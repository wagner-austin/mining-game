--!strict
-- StatsResolver.lua
-- Centralized stats calculation combining upgrades, pets, gamepasses, and runtime effects

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Time = require(MiningGame:WaitForChild("Time"))
local ServiceValidator = require(MiningGame:WaitForChild("ServiceValidator"))
local Logger = require(MiningGame:WaitForChild("Logger"))
local log = Logger.new("StatsResolver")

-- Services (injected via Init)
local UpgradeService
local CharacterStateManager
local DataService

local StatsResolver = {}

-- Initialize with DI container
function StatsResolver:Init(container)
    UpgradeService = ServiceValidator.get(container, "UpgradeService", {"ComputeEffectiveStats"})
    CharacterStateManager = ServiceValidator.tryGet(container, "CharacterStateManager", {"GetActiveEffects"})
    DataService = ServiceValidator.get(container, "DataService", {"GetPlayerData"})
    log:info("Initialized with dependencies")
end

-- Stats type for clarity
type Stats = {
    delay: number,
    size: number,
    luck: number,
    hardness: number?,
}

-- Table-driven effect application to prevent double-application and typos
local EFFECT_MODIFIERS: {[string]: (Stats) -> ()} = {
    -- Delay modifiers (lower is faster)
    -- dynamic dig_speed@mult handled below
    
    -- Size modifiers (bigger dig area)
    size = function(s) s.size = s.size + 1 end,                -- +1 radius
    heavy_pickaxe = function(s) s.size = s.size + 1 end,       -- +1 radius
    
    -- Luck modifiers (better loot chances)
    luck = function(s) s.luck = s.luck * 1.2 end,              -- 20% more luck
    lucky_charm = function(s) s.luck = s.luck + 0.1 end,       -- +10% luck
    
    -- You can add more effects here as needed
    -- fortune = function(s) s.luck = s.luck * 1.5 end,
    -- swift = function(s) s.delay = s.delay * 0.7 end,
}

function StatsResolver:Get(player: Player): Stats?
    local profile = DataService:GetPlayerData(player)
    if not profile then return nil end

    -- Get base stats from upgrades, gamepasses, and pets
    local gamepasses = UpgradeService:GetPlayerGamepasses(player)
    local activePets = UpgradeService:GetActivePets(profile)
    local base = UpgradeService:ComputeEffectiveStats(profile, gamepasses, activePets)
    
    -- Ensure sensible defaults even if UpgradeService returns partial stats
    base.delay = base.delay or 0.25      -- Default 250ms
    base.size = base.size or 1           -- Default size 1
    base.luck = base.luck or 0           -- Default no bonus luck
    base.hardness = base.hardness or 1   -- Default hardness multiplier
    
    -- Apply runtime effects from CharacterStateManager
    local st = CharacterStateManager:Get(player)
    if st and st.effects then
        -- Apply each active effect using the table (guard against expired effects)
        local now = Time.unix()
        for effectId, expiry in pairs(st.effects) do
            if type(expiry) == "number" and expiry > now then
                local idStr = tostring(effectId)
                local baseId = idStr:gsub("#%d+$", "")
                local multStr = baseId:match("@([0-9%.]+)")
                local simpleBase = baseId:gsub("@([0-9%.]+)", "")
                local modifier = EFFECT_MODIFIERS[simpleBase]
                if modifier then
                    modifier(base)
                else
                    -- Dynamic dig speed and luck multipliers
                    local m = multStr and tonumber(multStr) or nil
                    if m then
                        if simpleBase == "dig_speed" then
                            base.delay = base.delay * m
                        elseif simpleBase == "cosmetic_luck" then
                            base.luck = base.luck * m
                        end
                    end
                end
            end
        end
    end
    
    -- Defensive clamps to prevent invalid values
    base.delay = math.max(0.01, base.delay)                    -- Never zero/negative (min 10ms)
    base.size = math.clamp(base.size, 1, 50)                   -- Reasonable size limits
    base.luck = math.clamp(base.luck, 0, 10)                   -- Reasonable luck range
    base.hardness = math.clamp(base.hardness or 1, 0.1, 10)   -- Hardness multiplier limits
    
    return base
end

return StatsResolver
