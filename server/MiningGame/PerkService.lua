--!strict
-- PerkService.server.lua
-- Central orchestrator for movement-related perks and effects.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(Shared:WaitForChild("Logger"))
local ServiceValidator = require(Shared:WaitForChild("ServiceValidator"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Time = require(Shared:WaitForChild("Time"))

local log = Logger.new("PerkService")

-- Services (via DI)
local DataService
local LootService
local CharacterStateManager

local PerkService = {}
PerkService.__index = PerkService

-- Wait for profile and character-state readiness before applying effects
function PerkService:WaitReady(player: Player, timeoutSec: number?): boolean
    timeoutSec = timeoutSec or 10
    local deadline = Time.mono() + timeoutSec

    -- Wait for profile
    while Time.mono() < deadline do
        if DataService:GetPlayerData(player) then break end
        task.wait(0.1)
    end
    if not DataService:GetPlayerData(player) then
        return false
    end

    -- Wait for CharacterStateManager player state
    while Time.mono() < deadline do
        if CharacterStateManager and type(CharacterStateManager.Get) == "function" then
            local st = CharacterStateManager:Get(player)
            if st then return true end
        end
        task.wait(0.1)
    end
    return false
end

-- Internal: compute cosmetic perks from equipped items
-- New: compute and apply stacked cosmetic effects with per-item granularity
local function applyCosmeticStacks(player: Player, profile)
    local features = (GameConfig and GameConfig.Features) or {}
    if not features.ENHANCED_PERKS_ENABLED then
        return
    end
    if not profile or not profile.equipped then
        return
    end

    -- Clear previous cosmetic stacks (any suffixed variants)
    if CharacterStateManager and CharacterStateManager.Get then
        local st = CharacterStateManager:Get(player)
        if st and st.effects then
            for id, _ in pairs(st.effects) do
                local s = tostring(id)
                if string.find(s, "^cosmetic_speed_")
                    or string.find(s, "^cosmetic_luck_")
                    or string.find(s, "^cosmetic_extra_jumps_")
                    or string.find(s, "^cosmetic_speed@")
                    or string.find(s, "^cosmetic_luck@")
                    or string.find(s, "^dig_speed@") then
                    CharacterStateManager:RemoveEffect(player, (id :: any))
                end
            end
        end
    end

    local totalExtraJumps = 0
    local speedIdx = 0
    local luckIdx = 0
    local digIdx = 0

    for _, itemId in pairs(profile.equipped) do
        if type(itemId) == "string" then
            local def = LootService:GetItemDefinition(itemId)
            if def and def.type == "cosmetic" and def.enhanced == true and type(def.perks) == "table" then
                local perks = def.perks
                local sm = tonumber(perks.speedMult)
                if sm and sm > 1.0 then
                    speedIdx += 1
                    local id = string.format("cosmetic_speed@%.4f#%d", sm, speedIdx)
                    CharacterStateManager:ApplyTimedEffect(player, (id :: any), 31536000)
                end
                if type(perks.extraJumps) == "number" then
                    local ej = math.max(0, math.floor(perks.extraJumps))
                    totalExtraJumps += ej
                end
                if type(perks.luckMult) == "number" then
                    local lm = tonumber(perks.luckMult)
                    if lm and lm > 1.0 then
                        luckIdx += 1
                        local id = string.format("cosmetic_luck@%.4f#%d", lm, luckIdx)
                        CharacterStateManager:ApplyTimedEffect(player, (id :: any), 31536000)
                    end
                end
                -- Dig speed perks (cosmetic, server-auth) as stackable
                if type(perks.digSpeedTier) == "number" then
                    local tier = math.clamp(math.floor(perks.digSpeedTier), 0, 2)
                    local mult = (tier >= 2) and 0.80 or (tier >= 1) and 0.90 or nil
                    if mult then
                        digIdx += 1
                        local id = string.format("dig_speed@%.4f#%d", mult, digIdx)
                        CharacterStateManager:ApplyTimedEffect(player, (id :: any), 31536000)
                    end
                elseif type(perks.digSpeedMult) == "number" then
                    local mult = tonumber(perks.digSpeedMult)
                    if mult and mult < 1.0 then
                        digIdx += 1
                        local id = string.format("dig_speed@%.4f#%d", mult, digIdx)
                        CharacterStateManager:ApplyTimedEffect(player, (id :: any), 31536000)
                    end
                elseif perks.digSpeed == true then
                    digIdx += 1
                    local id = string.format("dig_speed@%.4f#%d", 0.90, digIdx)
                    CharacterStateManager:ApplyTimedEffect(player, (id :: any), 31536000)
                end
            end
        end
    end

    -- Extra jumps: add N stacks of +1 jump (shows visually as multiple chips)
    -- No cap on extra jumps; each +1 applies as a separate stack
    for i = 1, totalExtraJumps do
        local id = "cosmetic_extra_jumps_1#" .. tostring(i)
        CharacterStateManager:ApplyTimedEffect(player, (id :: any), 31536000)
    end

end

-- Public: recompute and apply all movement-related cosmetic effects
function PerkService:Recompute(player: Player)
    if not self:WaitReady(player, 10) then
        log:warn("Recompute skipped (not ready) for %s", player.Name)
        return
    end
    local profile = DataService:GetPlayerData(player)
    applyCosmeticStacks(player, profile)
end

-- Optional helper: normalize potion tiers (stack/refresh) — future work
function PerkService:ApplyPotionTier(player: Player, newTier: number, durationSec: number)
    local profile = DataService:GetPlayerData(player)
    if not profile then return false end
    newTier = math.max(1, math.floor(newTier))
    -- Clear all existing potion tiers (any number)
    for key, _ in pairs(profile.boosts) do
        if tostring(key):match("^potion_speed_tier_%d+$") then
            profile.boosts[key] = nil
        end
    end
    profile.boosts["potion_speed_tier_"..tostring(newTier)] = Time.unix() + math.max(1, durationSec)
    if CharacterStateManager and CharacterStateManager.SyncProfileBoosts then
        CharacterStateManager:SyncProfileBoosts(player)
    end
    return true
end

function PerkService:Init(container)
    DataService = ServiceValidator.get(container, "DataService", {"GetPlayerData"})
    LootService = ServiceValidator.get(container, "LootService", {"GetItemDefinition"})
    CharacterStateManager = ServiceValidator.get(container, "CharacterStateManager", {"ApplyTimedEffect", "RemoveEffect", "Get"})
    log:info("Initialized with dependencies")
end

function PerkService:Start(container)
    -- Initialize enhanced cosmetic effects on join
    local function onJoin(p: Player)
        self:Recompute(p)
        -- Also sync profile-based boosts into runtime snapshot (movement potions/products) if present
        if CharacterStateManager and CharacterStateManager.SyncProfileBoosts then
            CharacterStateManager:SyncProfileBoosts(p)
        end
    end
    Players.PlayerAdded:Connect(onJoin)
    for _, p in ipairs(Players:GetPlayers()) do onJoin(p) end
end

return PerkService
