--!strict
-- UpgradeService.server.lua
-- Handles player progression and upgrade calculations

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Time = require(Shared:WaitForChild("Time"))
local Logger = require(Shared:WaitForChild("Logger"))
local log = Logger.new("UpgradeService")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Types = require(Shared:WaitForChild("Types"))
local ServiceValidator = require(Shared:WaitForChild("ServiceValidator"))
local ErrorService = require(script.Parent.ErrorService)  -- OK: ErrorService is a foundation service

-- Services (injected via Init)
local CurrencyService
local DataService

local UpgradeService = {}
UpgradeService.__index = UpgradeService

-- Initialize with DI container
function UpgradeService:Init(container)
    DataService = ServiceValidator.get(container, "DataService", {"GetPlayerData", "QueueSave"})
    CurrencyService = ServiceValidator.get(container, "CurrencyService", {"canAfford", "add"})
    log:info("Initialized with dependencies")
end

-- Cache upgrade definitions
local SPEED_LEVELS = GameConfig.Upgrades.SPEED_LEVELS
local SIZE_LEVELS = GameConfig.Upgrades.SIZE_LEVELS

-- Get upgrade definition by level
local function getUpgradeLevel(levels: {Types.UpgradeLevel}, level: number): Types.UpgradeLevel?
    for _, def in ipairs(levels) do
        if def.level == level then
            return def
        end
    end
    return nil
end

-- Calculate effective stats including all bonuses
function UpgradeService:ComputeEffectiveStats(
    profile: Types.PlayerStats,
    gamepasses: {[string]: boolean},
    activePets: {Types.PetData}?
): Types.EffectiveStats
    
    -- Base values
    local baseDelay = GameConfig.Digging.BASE_DIG_DELAY
    local baseSize = GameConfig.Digging.BASE_DIG_SIZE_CELLS or 0
    local baseLuck = 1.0
    
    -- Get upgrade levels
    local speedLevel = profile.upgrades.speed or 0
    local sizeLevel = profile.upgrades.size or 0
    
    -- Apply upgrade multipliers
    local speedUpgrade = getUpgradeLevel(SPEED_LEVELS, speedLevel)
    local sizeUpgrade = getUpgradeLevel(SIZE_LEVELS, sizeLevel)
    
    local delay = baseDelay * (speedUpgrade and speedUpgrade.multiplier or 1.0)
    local size = (sizeUpgrade and sizeUpgrade.size) or baseSize
    local luck = baseLuck
    
    -- Debug: Log the size calculation
    log:debug("Size calc: sizeLevel=%d, sizeUpgrade.size=%s, baseSize=%d, final size=%d", 
        sizeLevel, tostring(sizeUpgrade and sizeUpgrade.size or "nil"), baseSize, size)
    
    -- Apply boosts (time-limited)
    local now = Time.unix()
    for boostType, expiry in pairs(profile.boosts) do
        if expiry > now then
            if boostType == "speed" then
                delay = delay * 0.5 -- 50% faster
            elseif boostType == "luck" then
                luck = luck * 2.0 -- 2x luck
            elseif boostType == "size" then
                size = size + 2 -- +2 size
            end
        end
    end
    
    -- Apply gamepass bonuses
    if gamepasses["VIP"] then
        luck = luck * 2.0 -- VIP doubles luck
    end
    if gamepasses["MEGA_PICKAXE"] then
        size = size + 3 -- +3 size
    end
    
    -- Apply equipped pickaxe stats
    if profile.equipped.pickaxe then
        local pickaxeDef = nil
        for _, item in ipairs(GameConfig.Loot.ITEMS) do
            if item.id == profile.equipped.pickaxe and item.type == "pickaxe" then
                pickaxeDef = item
                break
            end
        end
        
        if pickaxeDef and pickaxeDef.stats then
            delay = delay / (pickaxeDef.stats.speed or 1.0)
            size = math.floor(size + (pickaxeDef.stats.size or 0))  -- Add pickaxe size bonus
            luck = luck * (pickaxeDef.stats.luck or 1.0)
        end
    end
    
    -- Apply pet bonuses
    if activePets then
        for _, petData in ipairs(activePets) do
            if petData.equipped then
                local petDef = nil
                for _, pet in ipairs(GameConfig.Pets.PETS) do
                    if pet.id == petData.id then
                        petDef = pet
                        break
                    end
                end
                
                if petDef and petDef.buffs then
                    -- Apply star multiplier
                    local starMult = GameConfig.Pets.STAR_MULTIPLIERS[petData.stars] or 1.0
                    
                    if petDef.buffs.speed then
                        delay = delay * (1 - petDef.buffs.speed * starMult)
                    end
                    if petDef.buffs.size then
                        local sizeBuff = petDef.buffs.size or 0
                        size = size + math.floor(size * sizeBuff * starMult)
                    end
                    if petDef.buffs.luck then
                        luck = luck * (1 + petDef.buffs.luck * starMult)
                    end
                end
            end
        end
    end
    
    -- Get material hardness
    local materialData = GameConfig.CubeMaterialsById[profile.materialId]
    local hardness = materialData and materialData.hardness or 1.0
    
    -- Apply hardness to delay
    delay = delay * hardness
    
    -- Clamp values to reasonable ranges
    delay = math.max(0.1, delay) -- Minimum 0.1 second delay
    size = math.min(20, size) -- Maximum 20 size
    luck = math.min(10, luck) -- Maximum 10x luck
    
    return {
        delay = delay,
        size = size,
        luck = luck,
        hardness = hardness,
    }
end

-- Purchase an upgrade
function UpgradeService:PurchaseUpgrade(
    player: Player,
    profile: Types.PlayerStats,
    upgradeType: string
): {success: boolean, newLevel: number?, costNext: number?, reason: string?}
    
    -- Get current level
    local currentLevel = profile.upgrades[upgradeType] or 0
    
    -- Get upgrade definitions
    local levels = nil
    if upgradeType == "speed" then
        levels = SPEED_LEVELS
    elseif upgradeType == "size" then
        levels = SIZE_LEVELS
    else
        return {success = false, reason = "Invalid upgrade type"}
    end
    
    -- Find next level
    local nextLevel = nil
    for _, level in ipairs(levels) do
        if level.level == currentLevel + 1 then
            nextLevel = level
            break
        end
    end
    
    if not nextLevel then
        return {success = false, reason = "Max level reached"}
    end
    
    -- Check if player can afford
    if profile.coins < nextLevel.cost then
        return {success = false, reason = "Insufficient coins"}
    end
    
    -- Deduct cost and apply upgrade
    CurrencyService.add(player, "coins", -nextLevel.cost)
    profile.upgrades[upgradeType] = nextLevel.level
    
    -- Emit profile update after upgrade is applied
    local EventBus = require(Shared:WaitForChild("EventBus"))
    local EventNames = require(Shared:WaitForChild("EventNames"))
    EventBus.global():emit(EventNames.PROFILE_UPDATED, {
        to = { kind = "player", player = player },
        payload = profile
    })
    
    -- Find cost of next level after this one
    local nextNextLevel = nil
    for _, level in ipairs(levels) do
        if level.level == nextLevel.level + 1 then
            nextNextLevel = level
            break
        end
    end
    
    return {
        success = true,
        newLevel = nextLevel.level,
        costNext = nextNextLevel and nextNextLevel.cost or nil,
    }
end

-- Apply a temporary boost
function UpgradeService:ApplyBoost(
    profile: Types.PlayerStats,
    boostType: string,
    duration: number
)
    local expiry = Time.unix() + duration
    profile.boosts[boostType] = expiry
end

-- Check gamepass ownership
function UpgradeService:GetPlayerGamepasses(player: Player): {[string]: boolean}
    local gamepasses = {}
    
    for _, gamepass in ipairs(GameConfig.Monetization.GAMEPASSES) do
        if gamepass.gamepassId > 0 then
            local ok, owns = ErrorService.safecall("UserOwnsGamePassAsync", function()
                return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamepass.gamepassId)
            end, { uid = player.UserId, gpid = gamepass.gamepassId })
            
            gamepasses[gamepass.id] = ok and owns or false
        end
    end
    
    return gamepasses
end

-- Get active pets for a player
function UpgradeService:GetActivePets(profile: Types.PlayerStats): {Types.PetData}
    local activePets = {}
    local equippedCount = 0
    local maxEquipped = GameConfig.Pets.MAX_EQUIPPED
    
    for _, petData in pairs(profile.pets) do
        if petData.equipped and equippedCount < maxEquipped then
            table.insert(activePets, petData)
            equippedCount = equippedCount + 1
        end
    end
    
    return activePets
end

-- Calculate total cells that will be dug
function UpgradeService:CalculateDigVolume(size: number): number
    -- Simple cube volume calculation
    local diameter = size * 2 + 1
    return diameter * diameter * diameter
end

-- Get upgrade progress
function UpgradeService:GetUpgradeProgress(profile: Types.PlayerStats): {[string]: {current: number, max: number, percent: number}}
    local progress = {}
    
    -- Speed
    local speedCurrent = profile.upgrades.speed or 0
    local speedMax = #SPEED_LEVELS - 1
    progress.speed = {
        current = speedCurrent,
        max = speedMax,
        percent = speedMax > 0 and (speedCurrent / speedMax) or 0,
    }
    
    -- Size
    local sizeCurrent = profile.upgrades.size or 0
    local sizeMax = #SIZE_LEVELS - 1
    progress.size = {
        current = sizeCurrent,
        max = sizeMax,
        percent = sizeMax > 0 and (sizeCurrent / sizeMax) or 0,
    }
    
    return progress
end

log:info("Initialized")

return UpgradeService