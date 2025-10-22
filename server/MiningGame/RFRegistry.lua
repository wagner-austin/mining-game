--!strict
-- RFRegistry.lua
-- Single entry point to register ALL RemoteFunctions with RemoteManager.
-- Now accepts ServiceContainer for proper DI

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(MiningGame:WaitForChild("Logger"))
local Time = require(MiningGame:WaitForChild("Time"))
local log = Logger.new("RFRegistry")

local RemoteManager = require(script.Parent.RemoteManager)

export type RFSpec = {
    name: string,
    handler: (ctx: any, ...any) -> any,
    validate: ((...any) -> boolean)?, -- Optional input validator
    opts: { 
        requireProfile: boolean?, 
        rateLimitSec: number?,
        debugOnly: boolean? -- Only register in Studio
    }?,
}

-- Recursively load specs from folders (supports nesting)
local function loadSpecsFrom(folder: Instance, serviceContainer: any, acc: {RFSpec})
    local children = folder:GetChildren()
    table.sort(children, function(a, b) return a.Name < b.Name end) -- Deterministic order
    
    for _, item in ipairs(children) do
        if item:IsA("ModuleScript") then
            local ok, specOrFactory = pcall(require, item)
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
                    for _, spec in ipairs(specs :: {RFSpec}) do
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
local function wrap(spec: RFSpec, opts: {requireProfile: boolean?, rateLimitSec: number?, debugOnly: boolean?, schema: any?}?)
    local fn = spec.handler
    opts = opts or {}
    
    return function(ctx, ...)
        -- Debug-only check
        if opts.debugOnly and not RunService:IsStudio() then
            return { ok = false, success = false, err = "DEBUG_ONLY", time_ms = 0 }
        end
        
        -- Note: validation + requireProfile are enforced in RemoteManager
        -- We only handle debugOnly filtering here in the middleware
        
        -- Execute handler with timing
        local t0 = Time.mono()
        local ok, res = pcall(fn, ctx, ...)
        local dt = (Time.mono() - t0) * 1000 -- Convert to milliseconds
        
        if not ok then
            local msg = tostring(res)
            -- Add stack trace in Studio for debugging
            if RunService:IsStudio() then
                msg = debug.traceback(msg, 2)
            end
            log:warn("RF %s failed after %.2fms: %s", spec.name, dt, msg)
            return { ok = false, success = false, err = msg, time_ms = dt }
        end
        
        -- Pass through the response as-is (RFs already return proper top-level shapes)
        -- Only add timing metadata if it's a Result-like table (has ok field)
        if type(res) == "table" and res.ok ~= nil then
            res.time_ms = res.time_ms or dt
            return res
        else
            -- For scalar returns or raw data maps (like GetAllEquipped), pass through unchanged
            return res
        end
    end
end

-- Main registration logic
local function registerAllRFs(serviceContainer: any): {registeredCount: number, skippedCount: number, names: {string}}
    local registeredCount = 0
    local skippedCount = 0
    local names = {} :: {[string]: boolean}
    local registeredNames = {} :: {string}
    
    -- Load all specs from RemoteFns folder
    local specsAll = {} :: {RFSpec}
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
                opts.schema = function(...)
                    local ok, msg = spec.validate(...)
                    if ok then return true, nil end
                    return false, type(msg) == "string" and msg or "INVALID_INPUT"
                end
            else
                -- Permissive schema for handlers with no parameters
                opts.schema = function(...) return true end
            end
        end
        
        -- Register with RemoteManager (pass opts to both wrap and registerRF)
        local success, err = pcall(function()
            RemoteManager.registerRF(spec.name, wrap(spec, opts), opts)
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

function RFRegistry.register(serviceContainer: any)
    return registerAllRFs(serviceContainer)
end

-- Fake container so RF factories can run without live services during precreate
local FakeContainer = {}
function FakeContainer:Get(_name) return {} end
function FakeContainer:get(_name) return {} end
function FakeContainer:tryGet(_name) return nil end  -- Return nil for optional services

function RFRegistry.precreate(remotesFolder: Instance)
    local created, existed = 0, 0
    local namesSeen: {[string]: boolean} = {}

    -- Load specs using fake container; we only need names here
    local specsAll = {} :: {RFSpec}
    local root = script.Parent:FindFirstChild("RemoteFns")
    if root then
        loadSpecsFrom(root, FakeContainer, specsAll)
    else
        log:warn("RemoteFns folder not found - no RFs to precreate")
        return {created = 0, existed = 0}
    end

    for _, spec in ipairs(specsAll) do
        -- Skip duplicates and debug-only RFs in production
        if not namesSeen[spec.name] then
            namesSeen[spec.name] = true

            if not (spec.opts and spec.opts.debugOnly and not RunService:IsStudio()) then
                local rf = remotesFolder:FindFirstChild(spec.name)
                if not rf then
                    rf = Instance.new("RemoteFunction")
                    rf.Name = spec.name
                    rf.Parent = remotesFolder
                    created += 1
                else
                    existed += 1
                end
                -- Temporary handler that returns retryable result
                (rf :: RemoteFunction).OnServerInvoke = function(player, ...)
                    -- Return a structured, retryable result instead of throwing
                    return { ok = false, retry = true, err = "INITIALIZING" }
                end
            end
        end
    end

    log:info("RF precreate complete: %d created, %d existed", created, existed)
    return {created = created, existed = existed}
end

return RFRegistry