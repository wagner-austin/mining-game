--!strict
-- AchievementService.lua
-- Tracks and awards achievements based on gameplay events

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(Shared:WaitForChild("Logger"))
local log = Logger.new("AchievementService")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Types = require(Shared:WaitForChild("Types"))
local ServiceValidator = require(Shared:WaitForChild("ServiceValidator"))

-- Use EventBus instead of direct remotes
local EventBus = require(Shared:WaitForChild("EventBus"))
local EventNames = require(Shared:WaitForChild("EventNames"))
local Bus = EventBus.global()

-- Services (injected via Init)
local DataService
local CurrencyService

local AchievementService = {}
AchievementService.__index = AchievementService

type AchievementServiceT = {
    Init: (self: AchievementServiceT, container: any) -> (),
    RecordFirstDig: (player: Player) -> (),
    RecordFirstCosmeticEquip: (player: Player) -> (),
    RecordRarityFind: (player: Player, rarity: string) -> (),
    RecordCoinsEarned: (player: Player, delta: number) -> (),
    SetRewardItemCallback: (cb: (Player, string, number) -> ()) -> (),
}

-- Callback for item rewards (set by InventoryService to avoid circular dependency)
local rewardItemCallback: ((Player, string, number) -> ())?

-- Guard against duplicate event wiring
local coinsListenerBound = false

-- Initialize with DI container
function AchievementService:Init(container)
    DataService = ServiceValidator.get(container, "DataService", {"GetPlayerData", "QueueSave"})
    CurrencyService = ServiceValidator.get(container, "CurrencyService", {"add"})
    
    -- Track coin earnings via bus (no DI cycle)
    if not coinsListenerBound then
        Bus:on(EventNames.CURRENCY_CHANGED, function(msg)
            -- Expect shape: { to = { kind="player", player = <Player> }, payload = { currency, balance, delta } }
            local to, p = msg.to, msg.payload
            if to and to.kind == "player" and p and p.currency == "coins" then
                local delta = tonumber(p.delta) or 0
                if delta > 0 then
                    -- Use existing achievement logic
                    AchievementService.RecordCoinsEarned(to.player, delta)
                end
            end
        end)
        coinsListenerBound = true
    end
    
    log:info("Initialized with dependencies")
end

-- Achievement definitions
local ACHIEVEMENTS = {
    -- First-time achievements
    first_dig = {
        id = "first_dig",
        name = "Breaking Ground",
        desc = "Dig your first block",
        tier = "bronze",
        reward = { coins = 50 },
    },
    first_cosmetic = {
        id = "first_cosmetic",
        name = "Looking Good",
        desc = "Equip your first cosmetic item",
        tier = "bronze",
        reward = { coins = 100 },
    },
    first_rare = {
        id = "first_rare",
        name = "Rare Find",
        desc = "Find your first rare item",
        tier = "bronze",
        reward = { coins = 200 },
    },
    
    -- Rarity discoveries
    found_epic = {
        id = "found_epic",
        name = "Epic Discovery",
        desc = "Find an epic item",
        tier = "silver",
        reward = { coins = 500 },
    },
    found_legendary = {
        id = "found_legendary",
        name = "Legendary Find",
        desc = "Find a legendary item",
        tier = "gold",
        reward = { coins = 1000 },
    },
    found_mythic = {
        id = "found_mythic",
        name = "Mythic Moment",
        desc = "Find a mythic item",
        tier = "diamond",
        reward = { coins = 5000, gems = 10 },
    },
    
    -- Milestone achievements
    blocks_100 = {
        id = "blocks_100",
        name = "Novice Miner",
        desc = "Dig 100 blocks",
        tier = "bronze",
        reward = { coins = 100 },
        requirement = { type = "blocks_dug", value = 100 },
    },
    blocks_1000 = {
        id = "blocks_1000",
        name = "Experienced Miner",
        desc = "Dig 1,000 blocks",
        tier = "silver",
        reward = { coins = 500 },
        requirement = { type = "blocks_dug", value = 1000 },
    },
    blocks_10000 = {
        id = "blocks_10000",
        name = "Master Miner",
        desc = "Dig 10,000 blocks",
        tier = "gold",
        reward = { coins = 2000 },
        requirement = { type = "blocks_dug", value = 10000 },
    },
    blocks_100000 = {
        id = "blocks_100000",
        name = "Mining Legend",
        desc = "Dig 100,000 blocks",
        tier = "platinum",
        reward = { coins = 10000, gems = 50 },
        requirement = { type = "blocks_dug", value = 100000 },
    },
    
    -- Wealth milestones
    coins_1000 = {
        id = "coins_1000",
        name = "First Thousand",
        desc = "Earn 1,000 coins",
        tier = "bronze",
        reward = { coins = 100 },
        requirement = { type = "coins_earned", value = 1000 },
    },
    coins_10000 = {
        id = "coins_10000",
        name = "Wealthy",
        desc = "Earn 10,000 coins",
        tier = "silver",
        reward = { coins = 500 },
        requirement = { type = "coins_earned", value = 10000 },
    },
    coins_100000 = {
        id = "coins_100000",
        name = "Rich",
        desc = "Earn 100,000 coins",
        tier = "gold",
        reward = { coins = 2000 },
        requirement = { type = "coins_earned", value = 100000 },
    },
}

-- Set the reward item callback (called by InventoryService to avoid circular dep)
function AchievementService.SetRewardItemCallback(callback: (Player, string, number) -> ())
    rewardItemCallback = callback
end

-- Award achievement to player
local function awardAchievement(player: Player, achievementId: string)
    -- Check if achievements are enabled
    if not GameConfig.Features.ACHIEVEMENTS_ENABLED then
        return
    end
    
    local profile = DataService:GetPlayerData(player)
    if not profile then return end
    
    -- Check if already unlocked (unless debug mode)
    profile.achievements = profile.achievements or {}
    if profile.achievements[achievementId] and not GameConfig.Features.DEBUG_ALWAYS_ACHIEVEMENT then
        return -- Already has it
    end
    
    local achievement = ACHIEVEMENTS[achievementId]
    if not achievement then
        log:warn("Unknown achievement: %s", achievementId)
        return
    end
    
    -- Mark as unlocked
    profile.achievements[achievementId] = true
    
    -- Grant rewards
    if achievement.reward then
        if achievement.reward.coins then
            CurrencyService.add(player, "coins", achievement.reward.coins)
            log:debug("Granted %d coins for achievement %s", achievement.reward.coins, achievementId)
        end
        if achievement.reward.gems then
            CurrencyService.add(player, "gems", achievement.reward.gems)
            log:debug("Granted %d gems for achievement %s", achievement.reward.gems, achievementId)
        end
        if achievement.reward.itemId then
            if rewardItemCallback then
                rewardItemCallback(player, achievement.reward.itemId, 1)
            else
                log:warn("No rewardItemCallback set; skipping item reward %s", achievement.reward.itemId)
            end
        end
    end
    
    -- Save
    DataService:QueueSave(player)
    
    -- Fire client event (if notifications enabled)
    if GameConfig.Features.ACHIEVEMENT_NOTIFICATIONS then
        Bus:emit(EventNames.ACHIEVEMENT_UNLOCKED, {
            to = { kind = "player", player = player },
            payload = {
                achievementId = achievementId,
                reward = achievement.reward,
                playerName = player.Name,
            }
        })
    end
    
    -- Note: Rare item announcements are handled by AnnouncementService via ItemService
    -- to avoid duplicate banners
    
    log:info("Awarded achievement '%s' (%s) to %s", achievementId, achievement.tier, player.Name)
end

-- Check milestone achievements
local function checkMilestoneAchievements(player: Player)
    local profile = DataService:GetPlayerData(player)
    if not profile then return end
    
    profile.achievements = profile.achievements or {}
    
    -- Check block milestones
    local blocksDug = profile.totalBlocksDug or 0
    if blocksDug >= 100 and not profile.achievements.blocks_100 then
        awardAchievement(player, "blocks_100")
    end
    if blocksDug >= 1000 and not profile.achievements.blocks_1000 then
        awardAchievement(player, "blocks_1000")
    end
    if blocksDug >= 10000 and not profile.achievements.blocks_10000 then
        awardAchievement(player, "blocks_10000")
    end
    if blocksDug >= 100000 and not profile.achievements.blocks_100000 then
        awardAchievement(player, "blocks_100000")
    end
    
    -- Check coin milestones
    local coinsEarned = profile.totalCoinsEarned or 0
    if coinsEarned >= 1000 and not profile.achievements.coins_1000 then
        awardAchievement(player, "coins_1000")
    end
    if coinsEarned >= 10000 and not profile.achievements.coins_10000 then
        awardAchievement(player, "coins_10000")
    end
    if coinsEarned >= 100000 and not profile.achievements.coins_100000 then
        awardAchievement(player, "coins_100000")
    end
end

-- Public API

-- Record first dig
function AchievementService.RecordFirstDig(player: Player)
    local profile = DataService:GetPlayerData(player)
    if not profile then return end
    
    profile.achievements = profile.achievements or {}
    if not profile.achievements.first_dig then
        awardAchievement(player, "first_dig")
    end
    
    -- Check milestones
    checkMilestoneAchievements(player)
end

-- Record first cosmetic equip
function AchievementService.RecordFirstCosmeticEquip(player: Player)
    local profile = DataService:GetPlayerData(player)
    if not profile then return end
    
    profile.achievements = profile.achievements or {}
    if not profile.achievements.first_cosmetic then
        -- Update counter
        profile.statCounters = profile.statCounters or {}
        profile.statCounters.cosmetics_equipped = (profile.statCounters.cosmetics_equipped or 0) + 1
        
        awardAchievement(player, "first_cosmetic")
    end
end

-- Record rarity find
function AchievementService.RecordRarityFind(player: Player, rarity: string)
    local DigPerformance = require(script.Parent.DigPerformance)
    return DigPerformance.measureSection("Ach_RarityFind", function()
        local profile = DataService:GetPlayerData(player)
        if not profile then return end
        
        profile.achievements = profile.achievements or {}
        profile.statCounters = profile.statCounters or {}
        
        -- Update stat counters
        if rarity == "RARE" then
            profile.statCounters.rares_found = (profile.statCounters.rares_found or 0) + 1
            if not profile.achievements.first_rare then
                awardAchievement(player, "first_rare")
            end
        elseif rarity == "EPIC" then
            profile.statCounters.epics_found = (profile.statCounters.epics_found or 0) + 1
            if not profile.achievements.found_epic then
                awardAchievement(player, "found_epic")
            end
        elseif rarity == "LEGENDARY" then
            profile.statCounters.legendaries_found = (profile.statCounters.legendaries_found or 0) + 1
            if not profile.achievements.found_legendary then
                awardAchievement(player, "found_legendary")
            end
            log:event("legendary_found", {
                uid = player.UserId,
                total = profile.statCounters.legendaries_found
            })
        elseif rarity == "MYTHIC" then
            profile.statCounters.mythics_found = (profile.statCounters.mythics_found or 0) + 1
            if not profile.achievements.found_mythic then
                awardAchievement(player, "found_mythic")
            end
            log:event("mythic_found", {
                uid = player.UserId,
                total = profile.statCounters.mythics_found
            })
        end
    end)
end

-- Record blocks dug (called from DigService)
function AchievementService.RecordBlocksDug(player: Player, count: number)
    checkMilestoneAchievements(player)
end

-- Record coins earned (called from DataService)
function AchievementService.RecordCoinsEarned(player: Player, amount: number)
    checkMilestoneAchievements(player)
end

-- Get all achievements for a player
function AchievementService.GetPlayerAchievements(player: Player): {[string]: boolean}
    local profile = DataService:GetPlayerData(player)
    if not profile then return {} end
    
    return profile.achievements or {}
end

-- Get achievement definition
function AchievementService.GetAchievementDefinition(achievementId: string)
    return ACHIEVEMENTS[achievementId]
end

-- Get all achievement definitions
function AchievementService.GetAllAchievements()
    return ACHIEVEMENTS
end

log:info("AchievementService initialized")

return AchievementService
