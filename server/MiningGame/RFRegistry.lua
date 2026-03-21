--!strict
-- RFRegistry.lua
-- Single entry point to register ALL RemoteFunctions with RemoteManager.
-- Now accepts ServiceContainer for proper DI

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(MiningGame:WaitForChild("Logger"))
local Time = require(MiningGame:WaitForChild("Time"))
local Types = require(MiningGame:WaitForChild("Types"))
local log = Logger.new("RFRegistry")

local RemoteManager = require(script.Parent.RemoteManager)
local ErrorService = require(script.Parent.ErrorService)
local SafeRequire = require(script.Parent.Util.SafeRequire)

-- RFSpec type defined below to maintain consistent shapes without over-constraining

-- Recursively load specs from folders (supports nesting)
local function loadSpecsFrom(folder, serviceContainer, acc)
	local children = folder:GetChildren()
	table.sort(children, function(a: Instance, b: Instance)
		return a.Name < b.Name
	end) -- Deterministic order

	for _, item in ipairs(children) do
		if item:IsA("ModuleScript") then
			local ms = item :: ModuleScript
			local ok, specOrFactory = ErrorService.safecall("RFRegistry.require:\t" .. ms.Name, function()
				return SafeRequire(ms)
			end)
			if ok then
				-- Support both direct specs and factory functions
				local specs
				if type(specOrFactory) == "function" then
					-- Module exports a factory function that takes the container
					specs = specOrFactory(serviceContainer)
				else
					-- Legacy: Module exports specs directly
					specs = specOrFactory
				end
				if type(specs) == "table" then
					for _, spec in ipairs(specs) do
						table.insert(acc, spec)
					end
					log:debug("Loaded %d specs from %s", #specs, item:GetFullName())
				end
			else
				log:warn("Failed to load RF spec module %s: %s", item:GetFullName(), tostring(specOrFactory))
			end
		elseif item:IsA("Folder") then
			-- Recurse into subfolders for organization
			loadSpecsFrom(item, serviceContainer, acc)
		end
	end
end

-- Middleware wrapper with normalization and timing
local function wrap(spec: RFSpec, opts)
	local fn = spec.handler

	return function(ctx, ...)
		-- Capture varargs so inner closures can access them safely
		local args = table.pack(...)
		-- Debug-only check
		local o = opts
		if o and o.debugOnly and not RunService:IsStudio() then
			return { ok = false, success = false, err = "DEBUG_ONLY", time_ms = 0 }
		end

		-- Note: validation + requireProfile are enforced in RemoteManager
		-- We only handle debugOnly filtering here in the middleware

		-- Execute handler with timing
		local t0 = Time.mono()
		local ok, res = ErrorService.safecall("RFRegistry.wrap:" .. spec.name, function()
			return fn(ctx, table.unpack(args, 1, args.n))
		end)
		local dt = (Time.mono() - t0) * 1000 -- Convert to milliseconds

		if not ok then
			local msg = tostring(res)
			log:warn("RF %s failed after %.2fms: %s", spec.name, dt, msg)
			return { ok = false, success = false, err = msg, time_ms = dt }
		end

		-- Pass through the response as-is (RFs already return proper top-level shapes)
		-- Only add timing metadata if it's a Result-like table (has ok field)
		if type(res) == "table" and res.ok ~= nil then
			res.time_ms = res.time_ms or dt
			return res
		else
			-- Normalize non-result returns to a standard result envelope
			return { ok = true, success = true, err = "", data = res, time_ms = dt }
		end
	end
end

-- Main registration logic
type RFSpec = {
	name: string,
	handler: (ctx: { player: Player }, ...Types.JsonValue) -> Types.JsonValue,
	opts: { requireProfile: boolean?, rateLimitSec: number?, debugOnly: boolean? }?,
	validate: ((...Types.JsonValue) -> (boolean, string?))?,
}

local function registerAllRFs(serviceContainer): { registeredCount: number, skippedCount: number, names: { string } }
	local registeredCount = 0
	local skippedCount = 0
	local names = {} :: { [string]: boolean }
	local registeredNames = {} :: { string }

	-- Load all specs from RemoteFns folder
	local specsAll = {} :: { RFSpec }
	local root = script.Parent:FindFirstChild("RemoteFns")

	if root then
		log:info("Loading RF specs from %s/RemoteFns...", script.Parent.Name)
		loadSpecsFrom(root, serviceContainer, specsAll)
	else
		log:warn("RemoteFns folder not found - no RFs registered")
		return {
			registeredCount = 0,
			skippedCount = 0,
			names = {},
		}
	end

	-- Check for duplicate names
	for _, spec in ipairs(specsAll) do
		if names[spec.name] then
			error(("[RFRegistry] Duplicate RF name: %s"):format(spec.name))
		end
		names[spec.name] = true
	end

	-- Register each spec
	for _, spec in ipairs(specsAll) do
		-- Skip debug-only RFs in production
		if spec.opts and spec.opts.debugOnly and not RunService:IsStudio() then
			skippedCount += 1
			log:debug("Skipped debug-only RF: %s", spec.name)
			continue
		end

		-- Bridge spec.validate -> opts.schema (RemoteManager requires schema)
		-- Clone to avoid mutating the original spec
		local rawOpts = spec.opts or {}
		local opts = table.clone(rawOpts)

		if not opts.schema then
			if spec.validate then
				-- Convert validate function to schema format (with optional error message)
				opts.schema = function(...): (boolean, string?)
					local ok, msg = spec.validate(...)
					if ok then
						return true, nil
					end
					-- Ensure the second return is a string when not ok
					if msg ~= nil and typeof(msg) == "string" then
						return false, msg
					else
						return false, "INVALID_INPUT"
					end
				end
			else
				-- Permissive schema for handlers with no parameters
				opts.schema = function(...): (boolean, string?)
					local _ = ...
					return true, nil
				end
			end
		end

		-- Register with RemoteManager (pass opts to both wrap and registerRF)
		local success, err = ErrorService.safecall("RFRegistry.registerRF", function()
			local rmOpts: { schema: (...Types.JsonValue) -> (boolean, string?), rateLimitSec: number, requireProfile: boolean? } =
				{
					schema = opts.schema or function(...): (boolean, string?)
						local _ = ...
						return true, nil
					end,
					rateLimitSec = (opts.rateLimitSec or 0.5),
					requireProfile = opts.requireProfile,
				}
			RemoteManager.registerRF(spec.name, wrap(spec, opts), rmOpts)
		end)

		if success then
			registeredCount += 1
			table.insert(registeredNames, spec.name)
			if RunService:IsStudio() then
				log:debug("Registered RF: %s", spec.name)
			end
		else
			log:error("Failed to register RF %s: %s", spec.name, tostring(err))
		end
	end

	-- Sort names for consistent output
	table.sort(registeredNames)

	log:info("RF registration complete: %d registered, %d skipped", registeredCount, skippedCount)
	if RunService:IsStudio() and #registeredNames > 0 then
		log:debug("Registered RFs: %s", table.concat(registeredNames, ", "))
	end

	return {
		registeredCount = registeredCount,
		skippedCount = skippedCount,
		names = registeredNames,
	}
end

-- Export the registration function
local RFRegistry = {}

function RFRegistry.register(serviceContainer)
	return registerAllRFs(serviceContainer)
end

-- Fake container so RF factories can run without live services during precreate
local FakeContainer = {}
function FakeContainer:Get(_name)
	return {}
end
function FakeContainer:get(_name)
	return {}
end
function FakeContainer:tryGet(_name)
	return nil
end -- Return nil for optional services

function RFRegistry.precreate(remotesFolder: Instance)
	local created, existed = 0, 0
	local namesSeen: { [string]: boolean } = {}

	-- Load specs using fake container; we only need names here
	local specsAll = {} :: { RFSpec }
	local root = script.Parent:FindFirstChild("RemoteFns")
	if root then
		loadSpecsFrom(root, FakeContainer, specsAll)
	else
		log:warn("RemoteFns folder not found - no RFs to precreate")
		return { created = 0, existed = 0 }
	end

	for _, spec in ipairs(specsAll) do
		-- Skip duplicates and debug-only RFs in production
		if not namesSeen[spec.name] then
			namesSeen[spec.name] = true

			if not (spec.opts and spec.opts.debugOnly and not RunService:IsStudio()) then
				local inst = remotesFolder:FindFirstChild(spec.name)
				local rf: RemoteFunction
				if inst and inst:IsA("RemoteFunction") then
					rf = inst
					existed += 1
				else
					local newRf = Instance.new("RemoteFunction")
					newRf.Name = spec.name
					newRf.Parent = remotesFolder
					rf = newRf
					created += 1
				end
				-- Temporary handler that returns retryable result
				rf.OnServerInvoke = function(player, ...)
					local _ = player
					local __ = ...
					-- Return a structured, retryable result instead of throwing
					return { ok = false, retry = true, err = "INITIALIZING" }
				end
			end
		end
	end

	log:info("RF precreate complete: %d created, %d existed", created, existed)
	return { created = created, existed = existed }
end

return RFRegistry
