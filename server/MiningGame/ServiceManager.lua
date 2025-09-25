--!strict
-- ServiceManager.lua (new, thin wrapper over ServiceContainer)
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local ServiceContainer = require(script.Parent.ServiceContainer)
local Timeout = require(Shared:WaitForChild("Timeout"))
local LoadCfg = require(Shared:WaitForChild("LoadingConstants"))
local Logger = require(Shared:WaitForChild("Logger"))
local Time = require(Shared:WaitForChild("Time"))
local FallbackRegistry = require(script.Parent.FallbackRegistry)
local log = Logger.new("ServiceManager")

local ServiceManager = {}

-- Helper: require with timeout protection and timing diagnostics
local function requireWithTimeout(mod: ModuleScript)
    local t0 = Time.mono()
    local ok, resOrErr = Timeout.runWithRetry(function()
        return require(mod)
    end, LoadCfg.TIMEOUTS.ModuleRequire, LoadCfg.RETRY.ModuleRequire.attempts, LoadCfg.RETRY.ModuleRequire.backoff)
    
    local dt = Time.mono() - t0
    
    if not ok then
        log:error("Require timed out (%.2fs): %s", dt, mod:GetFullName())
        return nil, "TIMEOUT"
    end
    if resOrErr == nil then
        log:error("Module returned nil (%.2fs): %s", dt, mod:GetFullName())
        return nil, "MODULE_RETURNED_NIL"
    end
    
    -- Warn on slow requires (over 0.5s)
    if dt > 0.5 then
        log:warn("Slow require (%.2fs): %s", dt, mod:GetFullName())
    end
    
    return resOrErr
end

local function regReq(container, name: string, child: ModuleScript, deps: {string}?)
    assert(child and child:IsA("ModuleScript"), ("Missing/invalid service module: %s"):format(name))
    local modOrErr, err = requireWithTimeout(child)
    if not modOrErr then
        if FallbackRegistry.has(name) then
            log:warn("%s require failed (%s); registering fallback stub", name, tostring(err))
            container:register(name, FallbackRegistry.get(name), deps)
            return
        end
        error(("Failed to require %s: %s"):format(name, tostring(err)))
    end
    container:register(name, modOrErr, deps)
end

local function regOpt(container, name: string, child: ModuleScript?, deps: {string}?)
    if not child then return end
    assert(child:IsA("ModuleScript"), ("Invalid optional module: %s"):format(name))
    local modOrErr, err = requireWithTimeout(child)
    if not modOrErr then
        log:warn("Optional service %s failed to load: %s", name, tostring(err))
        -- TODO: Consider container:markDegraded(name) for tracking
        return -- Skip optional service on timeout
    end
    container:register(name, modOrErr, deps)
end

function ServiceManager.start()
    local c = ServiceContainer.new()
    local parent = script.Parent

    -- Infra first (required)
    regReq(c, "RemoteEventBridge", parent.RemoteEventBridge, {})
    regReq(c, "ErrorService",       parent.ErrorService,       {})

    -- Foundation (required)
    regReq(c, "DataService",     parent.DataService,     {})
    regReq(c, "SessionService",  parent.SessionService,  {"DataService"})
    
    -- MixedMaterialService (needed by GridService for theme application)
    regReq(c, "MixedMaterialService", parent.MixedMaterialService, {})
    
    regReq(c, "GridService",     parent.GridService,     {"ErrorService","MixedMaterialService"})
    
    -- RemoteManager (after DataService, optional RateLimitService)
    regReq(c, "RemoteManager", parent.RemoteManager, {"DataService"})
    
    -- Currency (early - many services depend on it)
    regReq(c, "CurrencyService", parent.CurrencyService, {"DataService"})
    
    -- Achievements (depends on Currency)
    regReq(c, "AchievementService",  parent.AchievementService,  {"DataService","CurrencyService"})
    
    -- Announcements (needed by ItemService)
    regReq(c, "AnnouncementService", parent.AnnouncementService, {})

    -- Core game (required)
    regReq(c, "LootService",         parent.LootService,         {"GridService"})
    regReq(c, "UpgradeService",      parent.UpgradeService,      {"DataService","CurrencyService"})
    regReq(c, "InventoryService",    parent.InventoryService,    {"DataService","LootService","AchievementService","CurrencyService"})
    regReq(c, "ItemService",         parent.ItemService,         {"InventoryService","LootService","DataService","UpgradeService","AchievementService","AnnouncementService"})

    -- Economy (required)
    regReq(c, "MonetizationService", parent.MonetizationService, {"DataService","InventoryService","UpgradeService","CurrencyService"})

    -- Customization (required)
    regReq(c, "ThemeSettingsService", parent.ThemeSettingsService, {"DataService"})
    regReq(c, "CubePositionService",  parent.CubePositionService,  {"GridService"})

    -- Move world generation earlier so the terrain baseplate exists before cubes spawn
    regOpt(c, "WorldGenerationService", parent:FindFirstChild("WorldGenerationService"), {"GridService", "CubePositionService"})
    regOpt(c, "TreeGenerationService", parent:FindFirstChild("TreeGenerationService"), {"CubePositionService"})
    regOpt(c, "RockGenerationService", parent:FindFirstChild("RockGenerationService"), {"CubePositionService"})
    regOpt(c, "FireflyGenerationService", parent:FindFirstChild("FireflyGenerationService"), {"CubePositionService"})
    regOpt(c, "FloatingIslandService", parent:FindFirstChild("FloatingIslandService"), {"GridService", "MixedMaterialService"})
    -- SimpleClothService removed; banners/clothes are client-driven now

    regReq(c, "CubeMaterialService",  parent.CubeMaterialService,  {"GridService","DataService"})
    regReq(c, "CompositionService",   parent.CompositionService,   {"MixedMaterialService","CubePositionService","DataService","CurrencyService"})

    -- Visual helpers
    regReq(c, "GlowBarService", parent.GlowBarService, {})

    -- Player base visuals (optional, safe fallback if absent)
    regOpt(c, "PlayerBaseService", parent:FindFirstChild("PlayerBaseService"), {})
    -- Scenic banners at player bases (spawns cloth + UIPanel + attributes for billboards)
    regOpt(c, "BannerService", parent:FindFirstChild("BannerService"), {"PlayerBaseService"})

    -- Gameplay (required)
    regReq(c, "DigService",              parent.DigService,              {"GridService","DataService","InventoryService","UpgradeService","LootService","AchievementService","ItemService","CubePositionService"})
    regReq(c, "SpawnService",            parent.SpawnService,            {"GridService","CubePositionService","DigService"})  -- SpawnService depends on DigService
    regReq(c, "CharacterStateManager",   parent.CharacterStateManager,   {"DataService"})

    -- Perk orchestrator (depends on CharacterStateManager)
    regReq(c, "PerkService", parent.PerkService, {"DataService","LootService","CharacterStateManager"})
    
    -- Cube manager (optional orchestration for spawn/despawn policies)
    regOpt(c, "CubeManager", parent:FindFirstChild("CubeManager"), {"DigService","CubePositionService"})
    
    -- Analytics (required)
    regReq(c, "UserMetricsService", parent.UserMetricsService, {"DataService","UpgradeService","GridService"})

    -- Optional/Studio-only services
    local RunService = game:GetService("RunService")
    if RunService:IsStudio() then
        regOpt(c, "SimAgents", parent:FindFirstChild("SimAgents"), {"DigService","GridService"})
    end
    
    regOpt(c, "RateLimitService", parent:FindFirstChild("RateLimitService"), {})

    -- Build & start
    c:build()
    c:start()
    return c
end

return ServiceManager
