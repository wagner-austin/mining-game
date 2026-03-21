--!strict
-- RemoteManager.lua
-- Centralized remote handling with complete type safety

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Logger = require(Shared:WaitForChild("Logger"))
local DigPerformance = require(script.Parent.DigPerformance)
local ResultMod = require(Shared:WaitForChild("Result"))
local ErrorService = require(script.Parent.ErrorService)
local Types = require(Shared:WaitForChild("Types"))

local log = Logger.new("RemoteManager")
local ServiceValidatorMod = require(Shared:WaitForChild("ServiceValidator"))

-- Services (injected via Init)
local DataService
local RateLimitService

-- Type definitions
export type Context = {
	player: Player,
	profile: Types.PlayerStats?,
}

export type SchemaValidator = (...any) -> (boolean, string?)

export type RegisterOptions = {
	requireProfile: boolean?, -- Default true
	rateLimitSec: number, -- REQUIRED
	schema: SchemaValidator, -- REQUIRED
}

export type HandlerResult<T> = T | ResultMod.Result<T>

-- Rate limiting handled by RateLimitService

-- Registry tracking
type RemoteMetadata = {
	schema: SchemaValidator,
	rateLimitSec: number,
	requireProfile: boolean,
}
local registeredRF: { [string]: RemoteMetadata } = {}
local registeredRE: { [string]: RemoteMetadata } = {}

local RemoteManager = {}

-- Initialize with DI container
function RemoteManager:Init(container)
	DataService = ServiceValidatorMod.get(container, "DataService", { "EnsureLoaded", "GetPlayerData" })
	-- Rate limiting is nice-to-have; keep server usable if it's absent
	RateLimitService = ServiceValidatorMod.tryGet(container, "RateLimitService", { "allow", "reset" })
	log:info("Initialized with dependencies")
end

-- Start method to connect events after all services are initialized
function RemoteManager:Start(container)
	-- Cleanup on player leave
	Players.PlayerRemoving:Connect(function(player: Player)
		if RateLimitService then
			RateLimitService.reset(player.UserId)
		end
	end)

	log:info("Started with player connections")

	-- Register admin/debug RFs for generation service defaults
	local function okSchemaZeroArgs(...: any): (boolean, string?)
		return select("#", ...) == 0, "no args expected"
	end
	-- use modules defined at top scope; avoid shadowing

	-- Tree defaults
	RemoteManager.registerRF("GetTreeDefaults", function(_ctx)
		local svc = ServiceValidatorMod.tryGet(container, "TreeGenerationService")
		if not svc or type(svc.GetDefaults) ~= "function" then
			return ResultMod.err("UNAVAILABLE", "TreeGenerationService not available")
		end
		return svc:GetDefaults()
	end, { schema = okSchemaZeroArgs, rateLimitSec = 0.5, requireProfile = false })

	-- Rock defaults
	RemoteManager.registerRF("GetRockDefaults", function(_ctx)
		local svc = ServiceValidatorMod.tryGet(container, "RockGenerationService")
		if not svc or type(svc.GetDefaults) ~= "function" then
			return ResultMod.err("UNAVAILABLE", "RockGenerationService not available")
		end
		return svc:GetDefaults()
	end, { schema = okSchemaZeroArgs, rateLimitSec = 0.5, requireProfile = false })

	-- Firefly defaults
	RemoteManager.registerRF("GetFireflyDefaults", function(_ctx)
		local svc = ServiceValidatorMod.tryGet(container, "FireflyGenerationService")
		if not svc or type(svc.GetDefaults) ~= "function" then
			return ResultMod.err("UNAVAILABLE", "FireflyGenerationService not available")
		end
		return svc:GetDefaults()
	end, { schema = okSchemaZeroArgs, rateLimitSec = 0.5, requireProfile = false })

	-- Floating island defaults
	RemoteManager.registerRF("GetIslandDefaults", function(_ctx)
		local svc = ServiceValidatorMod.tryGet(container, "FloatingIslandService")
		if not svc or type(svc.GetDefaults) ~= "function" then
			return ResultMod.err("UNAVAILABLE", "FloatingIslandService not available")
		end
		return svc:GetDefaults()
	end, { schema = okSchemaZeroArgs, rateLimitSec = 0.5, requireProfile = false })

	-- Aggregate: all generation defaults
	RemoteManager.registerRF("GetAllGenDefaults", function(_ctx)
		local out = {}
		local treeSvc = ServiceValidatorMod.tryGet(container, "TreeGenerationService")
		if treeSvc and type(treeSvc.GetDefaults) == "function" then
			out.trees = treeSvc:GetDefaults()
		end
		local rockSvc = ServiceValidatorMod.tryGet(container, "RockGenerationService")
		if rockSvc and type(rockSvc.GetDefaults) == "function" then
			out.rocks = rockSvc:GetDefaults()
		end
		local flySvc = ServiceValidatorMod.tryGet(container, "FireflyGenerationService")
		if flySvc and type(flySvc.GetDefaults) == "function" then
			out.fireflies = flySvc:GetDefaults()
		end
		local islSvc = ServiceValidatorMod.tryGet(container, "FloatingIslandService")
		if islSvc and type(islSvc.GetDefaults) == "function" then
			out.islands = islSvc:GetDefaults()
		end
		return out
	end, { schema = okSchemaZeroArgs, rateLimitSec = 0.5, requireProfile = false })

	-- Aggregate: all generation status
	RemoteManager.registerRF("GetAllGenStatus", function(_ctx)
		local out = {}
		local treeSvc = ServiceValidatorMod.tryGet(container, "TreeGenerationService")
		if treeSvc and type(treeSvc.GetStats) == "function" then
			out.trees = treeSvc:GetStats()
		end
		local rockSvc = ServiceValidatorMod.tryGet(container, "RockGenerationService")
		if rockSvc and type(rockSvc.GetStats) == "function" then
			out.rocks = rockSvc:GetStats()
		end
		local flySvc = ServiceValidatorMod.tryGet(container, "FireflyGenerationService")
		if flySvc and type(flySvc.GetStats) == "function" then
			out.fireflies = flySvc:GetStats()
		end
		local islSvc = ServiceValidatorMod.tryGet(container, "FloatingIslandService")
		if islSvc and type(islSvc.GetStats) == "function" then
			out.islands = islSvc:GetStats()
		end
		return out
	end, { schema = okSchemaZeroArgs, rateLimitSec = 0.5, requireProfile = false })
end

-- Register a RemoteFunction with full type safety
function RemoteManager.registerRF<T>(
	name: string,
	handler: (Context, ...any) -> HandlerResult<T>,
	opts: RegisterOptions?
): ()
	-- STRICT: require explicit schema + rateLimitSec
	assert(opts ~= nil, ("RemoteFunction '%s' missing options"):format(name))
	local optsTbl = opts :: RegisterOptions
	assert(optsTbl.schema ~= nil, ("RemoteFunction '%s' missing schema validator"):format(name))
	assert(optsTbl.rateLimitSec ~= nil, ("RemoteFunction '%s' missing rateLimitSec"):format(name))
	assert(not registeredRF[name], ("RemoteFunction '%s' already registered"):format(name))

	-- Get or create the RemoteFunction
	local rfExisting = Remotes.RF[name]
	local rfFinal: RemoteFunction
	if rfExisting then
		rfFinal = rfExisting
	else
		-- Ensure folder exists (defensive)
		local f: Folder = Remotes.Folder
		if f.Parent == nil then
			local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
			local found = MiningGame:FindFirstChild("Remotes")
			if not (found and found:IsA("Folder")) then
				local created = Instance.new("Folder")
				created.Name = "Remotes"
				created.Parent = MiningGame
				found = created
			end
			f = found :: Folder
			Remotes.Folder = f
		end

		-- Create the RemoteFunction
		local newRf = Instance.new("RemoteFunction")
		newRf.Name = name
		newRf.Parent = f
		-- Update the RF table so clients can discover it
		Remotes.RF[name] = newRf
		rfFinal = newRf
		log:debug("Created RemoteFunction: %s", name)
	end

	-- Bind locals for clarity
	local schema = optsTbl.schema :: SchemaValidator
	local rateLimitSec = optsTbl.rateLimitSec :: number
	local requireProfile = if optsTbl.requireProfile == nil then true else optsTbl.requireProfile

	rfFinal.OnServerInvoke = function(player: Player, ...: any): ResultMod.Result<T>
		-- Capture varargs safely (preserve nils)
		local args = table.pack(...)

		-- Rate limiting (1 token per rateLimitSec, burst 1)
		local rate = (rateLimitSec and rateLimitSec > 0) and (1 / rateLimitSec) or math.huge
		if
			(rate ~= math.huge)
			and RateLimitService
			and not RateLimitService.allow(player.UserId, "rf:" .. name, rate, 1)
		then
			if name == "RequestDig" or name == "StartContinuousDig" then
				log:info("RF rate-limited: %s for %s", name, player.Name)
			else
				log:debug("Rate limited %s for %s", name, player.Name)
			end
			return ResultMod.err("RATE_LIMIT", "Too many requests")
		end

		-- Schema validation (always required now)
		local valid: boolean, err: string? = schema(table.unpack(args, 1, args.n))
		if not valid then
			if name == "RequestDig" or name == "StartContinuousDig" then
				log:info("RF invalid input: %s from %s (%s)", name, player.Name, err or "Invalid input")
			else
				log:debug("Schema validation failed for %s: %s", name, err or "Invalid input")
			end
			return ResultMod.err("INVALID_INPUT", err or "Invalid input")
		end

		-- Build context with proper typing
		local ctx: Context = {
			player = player,
			profile = nil,
		}

		-- Profile loading (default true)
		if requireProfile then
			if not DataService:EnsureLoaded(player) then
				if name == "RequestDig" or name == "StartContinuousDig" then
					log:info("RF no profile: %s for %s", name, player.Name)
				end
				return ResultMod.err("NO_PROFILE", "Profile not loaded")
			end

			local profile = DataService:GetPlayerData(player)
			if not profile then
				if name == "RequestDig" or name == "StartContinuousDig" then
					log:info("RF profile unavailable: %s for %s", name, player.Name)
				end
				return ResultMod.err("NO_PROFILE", "Profile unavailable")
			end
			ctx.profile = profile
		end

		-- Execute handler with error catching

		local ok, result = ErrorService.safecall("RemoteManager.invoke:" .. name, function()
			return DigPerformance.measureSection("RF_Invoke", function()
				return handler(ctx, table.unpack(args, 1, args.n))
			end)
		end)

		if not ok then
			log:error("RF %s error for %s: %s", name, player.Name, tostring(result))
			return ResultMod.err("INTERNAL", "Something went wrong")
		end

		-- Pass through Result objects unchanged
		if ResultMod.isResult(result) then
			return result :: ResultMod.Result<T>
		end

		-- Pass through top-level shapes unchanged
		-- (any table with ok, err, or success fields is assumed to be a top-level shape)
		if type(result) == "table" and (result.ok ~= nil or ResultMod.err ~= nil or result.success ~= nil) then
			return result
		end

		-- For everything else (raw maps, scalars), wrap in Result.ok so ClientRF unwraps to value
		-- This handles: GetServerUnix (scalar), GetEquippedItems/GetAllEquipped (raw maps)
		return ResultMod.ok(result :: T)
	end

	registeredRF[name] = {
		schema = schema,
		rateLimitSec = rateLimitSec,
		requireProfile = requireProfile,
	}

	log:debug("Registered RF: %s", name)
end

-- Register a RemoteEvent handler with type safety
function RemoteManager.registerRE(name: string, handler: (Context, ...any) -> (), opts: RegisterOptions?): ()
	-- STRICT: require explicit schema + rateLimitSec for RE too
	assert(opts ~= nil, ("RemoteEvent '%s' missing options"):format(name))
	local optsTbl = opts :: RegisterOptions
	assert(optsTbl.schema ~= nil, ("RemoteEvent '%s' missing schema validator"):format(name))
	assert(optsTbl.rateLimitSec ~= nil, ("RemoteEvent '%s' missing rateLimitSec"):format(name))
	assert(not registeredRE[name], ("RemoteEvent '%s' already registered"):format(name))

	-- Get or create the RemoteEvent (though we prefer EventBus for events)
	local reExisting = Remotes.RE[name]
	local reFinal: RemoteEvent
	if not reExisting then
		-- Ensure folder exists (defensive)
		local f: Folder = Remotes.Folder
		if f.Parent == nil then
			local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
			local found = MiningGame:FindFirstChild("Remotes")
			if not (found and found:IsA("Folder")) then
				local created = Instance.new("Folder")
				created.Name = "Remotes"
				created.Parent = MiningGame
				found = created
			end
			f = found :: Folder
			Remotes.Folder = f
		end

		-- Create the RemoteEvent
		local newRe = Instance.new("RemoteEvent")
		newRe.Name = name
		newRe.Parent = f
		-- Update the RE table so clients can discover it
		Remotes.RE[name] = newRe
		reFinal = newRe
		log:debug("Created RemoteEvent: %s", name)
	else
		reFinal = reExisting
	end

	-- Bind locals for clarity
	local schema = optsTbl.schema :: SchemaValidator
	local rateLimitSec = optsTbl.rateLimitSec :: number
	local requireProfile = if optsTbl.requireProfile == nil then true else optsTbl.requireProfile

	reFinal.OnServerEvent:Connect(function(player: Player, ...: any)
		-- Capture varargs safely (preserve nils)
		local args = table.pack(...)

		-- Rate limiting (1 token per rateLimitSec, burst 1)
		local rate = (rateLimitSec and rateLimitSec > 0) and (1 / rateLimitSec) or math.huge
		if
			(rate ~= math.huge)
			and RateLimitService
			and not RateLimitService.allow(player.UserId, "re:" .. name, rate, 1)
		then
			log:debug("Rate limited %s for %s", name, player.Name)
			return
		end

		-- Schema validation (always required now)
		local valid: boolean, err: string? = schema(table.unpack(args, 1, args.n))
		if not valid then
			log:debug("Schema validation failed for %s: %s", name, err or "Invalid input")
			return
		end

		-- Build context
		local ctx: Context = {
			player = player,
			profile = nil,
		}

		-- Profile loading
		if requireProfile then
			if not DataService:EnsureLoaded(player) then
				log:debug("No profile for %s, skipping RE %s", player.Name, name)
				return
			end

			local profile = DataService:GetPlayerData(player)
			if not profile then
				return
			end
			ctx.profile = profile
		end

		-- Execute handler
		local ok: boolean, ex: any = xpcall(function()
			handler(ctx, table.unpack(args, 1, args.n))
		end, debug.traceback)

		if not ok then
			log:error("RE %s error for %s: %s", name, player.Name, tostring(ex))
		end
	end)

	registeredRE[name] = {
		schema = schema,
		rateLimitSec = rateLimitSec,
		requireProfile = requireProfile,
	}

	log:debug("Registered RE: %s", name)
end

-- Player events moved to Start method

function RemoteManager.getRegisteredRF()
	return table.freeze(table.clone(registeredRF))
end

function RemoteManager.getRegisteredRE()
	return table.freeze(table.clone(registeredRE))
end

return RemoteManager
