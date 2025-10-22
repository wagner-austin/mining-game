--!strict
-- CompositionService.lua
-- Orchestrates material composition unlocking, application, and persistence
-- Bridge between UI, MixedMaterialService, and data persistence

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(MiningGame:WaitForChild("Logger"))
local log = Logger.new("CompositionService")
local rng = Random.new() -- Replace math.random usages

local GameConfig = require(MiningGame:WaitForChild("GameConfig"))
local CubeThemes = require(MiningGame:WaitForChild("CubeThemes"))
local MaterialDefinitions = require(MiningGame:WaitForChild("MaterialDefinitions"))
local TerrainSurfaceDetector = require(MiningGame:WaitForChild("TerrainSurfaceDetector"))
local ServiceValidator = require(MiningGame:WaitForChild("ServiceValidator"))

-- Shared modules
local Remotes = require(MiningGame:WaitForChild("Remotes"))
local EventBus = require(MiningGame:WaitForChild("EventBus"))
local EventNames = require(MiningGame:WaitForChild("EventNames"))
local EventContracts = require(MiningGame:WaitForChild("EventContracts"))
local ErrorService = require(script.Parent.ErrorService)  -- Foundation service

-- Services (injected via Init)
local MixedMaterialService
local CubePositionService
local DataService
local CurrencyService
local RateLimitService
local Bus = EventBus.global()

local Service = {}
Service.__index = Service

type CompositionServiceT = {
    Init: (self: CompositionServiceT, container: any) -> (),
    ApplyComposition: (self: CompositionServiceT, player: Player, themeId: string, preserveAir: boolean?) -> (boolean, string?),
    RegenerateComposition: (self: CompositionServiceT, player: Player) -> (boolean, string?),
    GetActiveComposition: (self: CompositionServiceT, player: Player) -> any,
    ListCompositions: (self: CompositionServiceT, player: Player) -> any,
    ListThemes: (self: CompositionServiceT, player: Player) -> any,
}
-- Initialize with DI container
function Service:Init(container)
    MixedMaterialService = ServiceValidator.get(container, "MixedMaterialService")
    CubePositionService = ServiceValidator.get(container, "CubePositionService", {"GetOrigin"})
    DataService = ServiceValidator.get(container, "DataService", {"GetPlayerData", "QueueSave", "GetMaterialPrefs"})
    CurrencyService = ServiceValidator.get(container, "CurrencyService", {"add", "canAfford"})
    RateLimitService = ServiceValidator.tryGet(container, "RateLimitService")  -- Optional
    log:info("Initialized with dependencies")
end

-- Generate seed based on variation mode
local function generateSeed(mode: string?, oldSeed: number?, player: Player?): number
    mode = mode or "PER_REGEN"
    
    if mode == "FIXED" then
        -- Keep the same seed
        return oldSeed or rng:NextInteger(1, 1000000)
    elseif mode == "DAILY" then
        -- Deterministic seed that changes daily
        local dateStr = os.date("!%Y%m%d") -- UTC date
        local playerSeed = player and player.UserId or 0
        -- Mix date and player ID for unique daily seed per player
        local combined = tonumber(dateStr) + playerSeed
        return (combined * 1103515245 + 12345) % 1000000
    else -- PER_REGEN
        -- Generate new random seed
        return rng:NextInteger(1, 1000000)
    end
end

-- Get player's current tier from cube material
local function getPlayerTier(player: Player): number
    local state = DataService:GetCubeData(player)
    if not state then return 1 end
    
    local materialId = state.materialId or "tier1"
    local materialData = GameConfig.CubeMaterialsById[materialId]
    
    if materialData then
        -- Extract tier number from material ID (e.g., "tier3" -> 3)
        local tierNum = tonumber(string.match(materialId, "tier(%d+)"))
        return tierNum or 1
    end
    
    return 1
end

-- [REMOVED: ListMaterials and UnlockMaterial - system is theme-only, no material unlocking]

-- Apply a specific theme composition to a player's cube
function Service:ApplyComposition(
    player: Player, 
    themeId: string,
    preserveAir: boolean?
): (boolean, string?)
    -- Check if feature is enabled
    if not GameConfig.Features.ENABLE_COMPOSITIONS then
        return false, "Compositions are disabled"
    end
    
    -- Validate theme exists
    local theme = CubeThemes.GetTheme(themeId)
    if not theme then
        return false, "INVALID_THEME"
    end
    
    -- Check tier requirement
    local playerTier = getPlayerTier(player)
    if theme.minTier > playerTier then
        return false, "Requires tier " .. theme.minTier
    end
    
    -- Get cube origin
    local cubeOrigin = CubePositionService:GetOrigin(player)
    if not cubeOrigin then
        return false, "Could not find cube"
    end
    
    -- Generate new seed for this application
    local seed = rng:NextInteger(1, 1000000)
    
    -- Save preferences - theme-first, no variation mode
    DataService:UpdateMaterialPrefs(player, {
        mode = "composition",
        activeThemeId = themeId,
        compositionSeed = seed,
        -- Clean up legacy fields
        materialWeights = nil,
        unlockedMaterials = nil,
        variationMode = nil,
    })
    
    -- Build composition from the specified theme
    local components = CubeThemes.GetThemeComponents(themeId)
    if not components or #components == 0 then
        return false, "Theme has no components"
    end
    
    -- Convert components to swathes format for MixedMaterialService
    local swathes = {}
    for _, c in ipairs(components) do
        local matEnum = MaterialDefinitions.GetEnum(c.materialKey)
        if matEnum then
            table.insert(swathes, { 
                material = matEnum, 
                weight = c.weight, 
                scale = c.scale 
            })
        end
    end
    
    -- Create config with swathes
    local config = {
        seed = seed,
        blendMode = "hard",
        swathes = swathes,
    }
    
    -- Apply to terrain
    MixedMaterialService:ApplyMixedMaterials(
        cubeOrigin,
        GameConfig.Grid.CUBE_SIZE_STUDS,
        config,
        preserveAir
    )
    
    -- Clear surface detection cache after terrain changes
    TerrainSurfaceDetector.ClearCache()
    
    log:info("Applied theme '%s' to %s's cube with seed %d", themeId, player.Name, seed)
    
    return true, nil
end

-- Subscribe to composition apply requests from CubeMaterialService
Bus:on(EventNames.COMPOSITION_APPLY_REQUEST, function(evt)
    local pld = EventContracts.COMPOSITION_APPLY_REQUEST(evt.payload)
    local player = Players:GetPlayerByUserId(pld.userId)
    if not player then return end
    
    -- Rate limit to prevent spam
    if not RateLimitService.allow(
        pld.userId,
        "composition.apply",
        GameConfig.Timing.COMPOSITION_APPLY_RATE,
        GameConfig.Timing.COMPOSITION_APPLY_BURST
    ) then
        log:warn("Rate limited composition apply for user %d", pld.userId)
        return
    end
    
    ErrorService.safecall("CompositionService:ApplyComposition(request)", function()
        -- Get current theme from player prefs
        local prefs = DataService:GetMaterialPrefs(player) or {}
        local themeId = prefs.activeThemeId or "underwater_cave"
        Service:ApplyComposition(player, themeId, (pld.preserveAir ~= false))
    end, { uid = pld.userId, theme = pld.themeId or "current" })
end)

-- [REMOVED: SetSingleMaterialMode - system is composition-only]

-- Regenerate composition with new seed
function Service:RegenerateComposition(player: Player): (boolean, string?)
    -- Check if feature is enabled
    if not GameConfig.Features.ENABLE_COMPOSITIONS then
        return false, "Compositions are disabled"
    end
    
    local prefs = DataService:GetMaterialPrefs(player) or {}
    
    if prefs.mode ~= "composition" then
        return false, "Not in composition mode"
    end
    
    -- Always generate a fresh random seed now that variation is gone
    local newSeed = rng:NextInteger(1, 1000000)
    
    -- Update seed and normalize variation mode
    DataService:UpdateMaterialPrefs(player, { 
        compositionSeed = newSeed,
        variationMode = "PER_REGEN" -- normalize old prefs
    })
    
    -- Apply with new seed (preserving dug areas)
    local activeThemeId = prefs.activeThemeId or "underwater_cave"
    return self:ApplyComposition(player, activeThemeId, true)
end

-- Get composition details for drops/mining
function Service:GetActiveComposition(player: Player)
    local prefs = DataService:GetMaterialPrefs(player) or {}
    
    if prefs.mode ~= "composition" then
        return nil
    end
    
    local themeId = prefs.activeThemeId or "underwater_cave"
    local theme = CubeThemes.GetTheme(themeId)
    if not theme then
        theme = CubeThemes.GetTheme("underwater_cave")
        themeId = "underwater_cave"
    end
    
    local components = CubeThemes.GetThemeComponents(themeId)
    
    -- Theme-only modifiers
    local modifiers = {
        rarityBoost = theme.dropBoost or 1.0,
        -- Themes define their own drop characteristics
    }
    
    return {
        id = themeId,
        name = theme.name,
        components = components,
        dropModifiers = modifiers,
    }
end

-- List available theme-based compositions
function Service:ListCompositions(player: Player)
    local tier = getPlayerTier(player)
    local available = CubeThemes.GetAvailableForTier(tier)
    local list = {}
    
    for id, theme in pairs(available) do
        table.insert(list, {
            id = id,
            name = theme.name,
            description = theme.description,
            minTier = theme.minTier,
            components = CubeThemes.GetThemeComponents(id) -- [{materialKey, weight, scale}]
        })
    end
    
    table.sort(list, function(a,b) return a.name < b.name end)
    
    local prefs = DataService:GetMaterialPrefs(player) or {}
    return {
        compositions = list,  -- List of themes
        activeComposition = prefs.activeThemeId or "underwater_cave",
        mode = "composition"  -- Always composition mode
    }
end

-- List available themes for a player
function Service:ListThemes(player: Player)
    local tier = getPlayerTier(player)
    local available = CubeThemes.GetAvailableForTier(tier)
    local list = {}
    for id, t in pairs(available) do
        table.insert(list, {
            id = id,
            name = t.name,
            minTier = t.minTier,
            description = t.description,
            unlocked = true,  -- All themes are unlocked (no coin cost in theme system)
            unlockCost = 0
        })
    end
    table.sort(list, function(a,b) return a.name < b.name end)
    local prefs = DataService:GetMaterialPrefs(player) or {}
    local playerData = DataService:GetPlayerData(player)
    return { 
        themes = list,
        materials = list, -- Backward compat with old client
        activeTheme = prefs.activeThemeId or "underwater_cave",
        activeComposition = prefs.activeThemeId or "underwater_cave", -- Backward compat
        mode = "composition", -- Always composition mode now
        currentTier = tier, -- Backward compat
        playerCoins = playerData and playerData.coins or 0, -- Backward compat
        variationMode = "PER_REGEN" -- Normalize for legacy UIs
    }
end

-- Apply a specific theme to player's cube (wrapper for ApplyComposition)
function Service:ApplyTheme(player: Player, themeId: string, preserveAir: boolean?): (boolean, string?)
    -- Just delegate to ApplyComposition with the new signature
    return self:ApplyComposition(player, themeId, preserveAir)
end

-- [MIGRATED TO CompositionServiceRemotes.lua]
-- All remote handlers now use centralized RemoteManager pattern

log:info("Initialized")

return Service
