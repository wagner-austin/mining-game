--!strict
-- UpgradeService.server.lua
-- Handles player progression and upgrade calculations

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Types = require(Shared:WaitForChild("Types"))

local UpgradeService = {}

-- Cache upgrade definitions
local SPEED_LEVELS = GameConfig.Upgrades.SPEED_LEVELS
local STRENGTH_LEVELS = GameConfig.Upgrades.STRENGTH_LEVELS
local RADIUS_LEVELS = GameConfig.Upgrades.RADIUS_LEVELS

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
    local baseDepth = GameConfig.Digging.BASE_DIG_DEPTH_CELLS
    local baseRadius = GameConfig.Digging.BASE_DIG_RADIUS_CELLS
    local baseLuck = 1.0
    
    -- Get upgrade levels
    local speedLevel = profile.upgrades.speed or 0
    local strengthLevel = profile.upgrades.strength or 0
    local radiusLevel = profile.upgrades.radius or 0
    
    -- Apply upgrade multipliers
    local speedUpgrade = getUpgradeLevel(SPEED_LEVELS, speedLevel)
    local strengthUpgrade = getUpgradeLevel(STRENGTH_LEVELS, strengthLevel)
    local radiusUpgrade = getUpgradeLevel(RADIUS_LEVELS, radiusLevel)
    
    local delay = baseDelay * (speedUpgrade and speedUpgrade.multiplier or 1.0)
    local depth = strengthUpgrade and strengthUpgrade.depth or baseDepth
    local radius = radiusUpgrade and radiusUpgrade.radius or baseRadius
    local luck = baseLuck
    
    -- Apply boosts (time-limited)
    local now = os.time()
    for boostType, expiry in pairs(profile.boosts) do
        if expiry > now then
            if boostType == "speed" then
                delay = delay * 0.5 -- 50% faster
            elseif boostType == "luck" then
                luck = luck * 2.0 -- 2x luck
            elseif boostType == "strength" then
                depth = depth + 2 -- +2 depth
            end
        end
    end
    
    -- Apply gamepass bonuses
    if gamepasses["VIP"] then
        luck = luck * 2.0 -- VIP doubles luck
    end
    if gamepasses["MEGA_PICKAXE"] then
        radius = radius + 2 -- +2 radius
        depth = depth + 2 -- +2 depth
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
            depth = math.floor(depth * (pickaxeDef.stats.strength or 1.0))
            luck = luck * (pickaxeDef.stats.luck or 1.0)
            radius = math.floor(radius * (pickaxeDef.stats.radius or 1.0))
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
                    if petDef.buffs.strength then
                        depth = depth + math.floor(depth * petDef.buffs.strength * starMult)
                    end
                    if petDef.buffs.radius then
                        radius = radius + math.floor(radius * petDef.buffs.radius * starMult)
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
    depth = math.min(20, depth) -- Maximum 20 depth
    radius = math.min(15, radius) -- Maximum 15 radius
    luck = math.min(10, luck) -- Maximum 10x luck
    
    return {
        delay = delay,
        depth = depth,
        radius = radius,
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
    elseif upgradeType == "strength" then
        levels = STRENGTH_LEVELS
    elseif upgradeType == "radius" then
        levels = RADIUS_LEVELS
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
    profile.coins = profile.coins - nextLevel.cost
    profile.upgrades[upgradeType] = nextLevel.level
    
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
    local expiry = os.time() + duration
    profile.boosts[boostType] = expiry
end

-- Check gamepass ownership
function UpgradeService:GetPlayerGamepasses(player: Player): {[string]: boolean}
    local gamepasses = {}
    
    for _, gamepass in ipairs(GameConfig.Monetization.GAMEPASSES) do
        if gamepass.gamepassId > 0 then
            local success, owns = pcall(function()
                return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamepass.gamepassId)
            end)
            
            if success then
                gamepasses[gamepass.id] = owns
            else
                gamepasses[gamepass.id] = false
            end
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
function UpgradeService:CalculateDigVolume(radius: number, depth: number, shape: string): number
    if shape == "CUBE" then
        local diameter = radius * 2 + 1
        return diameter * diameter * depth
    elseif shape == "SPHERE" then
        -- Approximate sphere volume
        local volume = 0
        for d = 0, depth - 1 do
            local effectiveRadius = radius * (1 - d / depth) -- Taper with depth
            volume = volume + ((effectiveRadius * 2 + 1) ^ 2)
        end
        return math.floor(volume)
    end
    
    return 1
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
    
    -- Strength
    local strengthCurrent = profile.upgrades.strength or 0
    local strengthMax = #STRENGTH_LEVELS - 1
    progress.strength = {
        current = strengthCurrent,
        max = strengthMax,
        percent = strengthMax > 0 and (strengthCurrent / strengthMax) or 0,
    }
    
    -- Radius
    local radiusCurrent = profile.upgrades.radius or 0
    local radiusMax = #RADIUS_LEVELS - 1
    progress.radius = {
        current = radiusCurrent,
        max = radiusMax,
        percent = radiusMax > 0 and (radiusCurrent / radiusMax) or 0,
    }
    
    return progress
end

print("[UpgradeService] Initialized")

return UpgradeService