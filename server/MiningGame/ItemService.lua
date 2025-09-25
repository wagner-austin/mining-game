--!strict
-- ItemService.server.lua (modular orchestrator)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Time = require(Shared:WaitForChild("Time"))
local Logger = require(Shared:WaitForChild("Logger"))
local log = Logger.new("ItemService")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local MathUtils = require(Shared:WaitForChild("MathUtils"))
local ServiceValidator = require(Shared:WaitForChild("ServiceValidator"))
local ErrorService = require(script.Parent:WaitForChild("ErrorService"))

local SoundBroadcast = require(script.Parent.SoundBroadcast)
local ItemAnimations = require(script.Parent.ItemAnimations)
local DropModelFactory = require(script.Parent.Items.DropModelFactory)
local DigPerformance = require(script.Parent.DigPerformance)

local EventBus = require(Shared:WaitForChild("EventBus"))
local EventNames = require(Shared:WaitForChild("EventNames"))
local Bus = EventBus.global()

local DropRegistryMod = require(script.Parent.ItemServiceModules.DropRegistry)
local MagnetMod = require(script.Parent.ItemServiceModules.Magnet)
local CollectorMod = require(script.Parent.ItemServiceModules.Collector)
local AutoCollectorMod = require(script.Parent.ItemServiceModules.AutoCollector)
local SpawnerMod = require(script.Parent.ItemServiceModules.Spawner)
local SweeperMod = require(script.Parent.ItemServiceModules.Sweeper)

local InventoryService
local LootService
local DataService
local UpgradeService
local AchievementService
local AnnouncementService

local ITEM_PICKUP_RANGE = GameConfig.Loot.PICKUP_RANGE
local ITEM_MAGNET_RANGE = GameConfig.Loot.AUTO_COLLECT_RANGE
local ITEM_LIFETIME = GameConfig.Loot.ITEM_LIFETIME or 300
local DESPAWN_RETRY_DELAY = GameConfig.Loot.DESPAWN_RETRY_DELAY or 10
local OWNER_GRACE_SECONDS = GameConfig.Loot.OWNER_GRACE_SECONDS or 5
local FINAL_DESPAWN_AFTER = 120
local MAX_DROPS_PER_PLAYER = GameConfig.Loot.MAX_DROPS_PER_PLAYER
local ITEM_ROTATION_SPEED = GameConfig.Loot.ROTATION_SPEED

local LOOT_MAGNET_ENABLED = (GameConfig.Features and GameConfig.Features.LOOT_MAGNET_ENABLED)
if LOOT_MAGNET_ENABLED == nil then LOOT_MAGNET_ENABLED = true end
local FORCED_CLAIM_ENABLED = (GameConfig.Features and GameConfig.Features.FORCED_CLAIM_ENABLED)
if FORCED_CLAIM_ENABLED == nil then FORCED_CLAIM_ENABLED = true end

local MAGNET_START_DELAY = GameConfig.Loot.MAGNET_START_DELAY or 0.8
local MAGNET_START_RANGE = GameConfig.Loot.MAGNET_START_RANGE or 12
local MAGNET_MAX_RANGE = GameConfig.Loot.MAGNET_MAX_RANGE or 35
local MAGNET_GROWTH_SECONDS = GameConfig.Loot.MAGNET_GROWTH_SECONDS or 3
local AUTO_COLLECT_INTERVAL = 0.2

local dropRegistry
local magnet
local collector
local autoCollector
local spawner
local sweeper

local ItemService = {}
ItemService.__index = ItemService

function ItemService:Init(container)
    InventoryService = ServiceValidator.get(container, "InventoryService", {"AddItem", "AddItemsBulk"})
    LootService = ServiceValidator.get(container, "LootService", {"GetItemDefinition"})
    DataService = ServiceValidator.get(container, "DataService", {"GetPlayerData"})
    UpgradeService = ServiceValidator.get(container, "UpgradeService", {"ComputeEffectiveStats", "GetPlayerGamepasses"})
    AchievementService = ServiceValidator.get(container, "AchievementService", {"RecordRarityFind"})
    AnnouncementService = ServiceValidator.get(container, "AnnouncementService", {"AnnounceRareFind", "AnnounceRareDrop"})
    log:info("Initialized with dependencies")
end

local function updateItemRotations(dt: number)
    if not dropRegistry then return end
    ItemAnimations.updateRotations(dropRegistry.state.activeDrops, dt, ITEM_ROTATION_SPEED)
end

function ItemService:Start(_container)
    dropRegistry = DropRegistryMod.new({ ErrorService = ErrorService, MathUtils = MathUtils, LootService = LootService })
    magnet = MagnetMod.new({
        GameConfig = GameConfig,
        UpgradeService = UpgradeService,
        defaults = { ITEM_MAGNET_RANGE = ITEM_MAGNET_RANGE },
        constants = {
            ITEM_PICKUP_RANGE = ITEM_PICKUP_RANGE,
            LOOT_MAGNET_ENABLED = LOOT_MAGNET_ENABLED,
            MAGNET_START_DELAY = MAGNET_START_DELAY,
            MAGNET_START_RANGE = MAGNET_START_RANGE,
            MAGNET_MAX_RANGE = MAGNET_MAX_RANGE,
            MAGNET_GROWTH_SECONDS = MAGNET_GROWTH_SECONDS,
        }
    })
    spawner = SpawnerMod.new({
        Time = Time, Logger = Logger, GameConfig = GameConfig, MathUtils = MathUtils,
        DropModelFactory = DropModelFactory, ItemAnimations = ItemAnimations,
        LootService = LootService, InventoryService = InventoryService, dropRegistry = dropRegistry,
        constants = { ITEM_LIFETIME = ITEM_LIFETIME, DESPAWN_RETRY_DELAY = DESPAWN_RETRY_DELAY, MAX_DROPS_PER_PLAYER = MAX_DROPS_PER_PLAYER, FINAL_DESPAWN_AFTER = FINAL_DESPAWN_AFTER },
    })
    collector = CollectorMod.new({
        GameConfig = GameConfig, InventoryService = InventoryService, LootService = LootService,
        AchievementService = AchievementService, AnnouncementService = AnnouncementService,
        SoundBroadcast = SoundBroadcast, ItemAnimations = ItemAnimations,
        Bus = Bus, EventNames = EventNames, Time = Time, MathUtils = MathUtils,
        dropRegistry = dropRegistry, log = log, ErrorService = ErrorService,
        constants = { ITEM_PICKUP_RANGE = ITEM_PICKUP_RANGE },
        scheduleFinalHardDespawn = function(model) spawner.scheduleFinalHardDespawn(model) end,
    })
    spawner.setAutoCollectFn(function(model, owner) return collector.AutoCollectDrop(model, owner) end)
    autoCollector = AutoCollectorMod.new({
        Players = Players, Time = Time, LootService = LootService, InventoryService = InventoryService,
        AchievementService = AchievementService, AnnouncementService = AnnouncementService,
        ItemAnimations = ItemAnimations, dropRegistry = dropRegistry, Bus = Bus, EventNames = EventNames, Magnet = magnet, collector = collector,
        constants = { ITEM_PICKUP_RANGE = ITEM_PICKUP_RANGE, ITEM_MAGNET_RANGE = ITEM_MAGNET_RANGE, LOOT_MAGNET_ENABLED = LOOT_MAGNET_ENABLED,
            MAGNET_START_DELAY = MAGNET_START_DELAY, MAGNET_START_RANGE = MAGNET_START_RANGE, MAGNET_MAX_RANGE = MAGNET_MAX_RANGE,
            MAGNET_GROWTH_SECONDS = MAGNET_GROWTH_SECONDS, OWNER_GRACE_SECONDS = OWNER_GRACE_SECONDS, AUTO_COLLECT_INTERVAL = AUTO_COLLECT_INTERVAL },
    })
    sweeper = SweeperMod.new({ Time = Time, InventoryService = InventoryService, dropRegistry = dropRegistry, constants = { ITEM_LIFETIME = ITEM_LIFETIME, DESPAWN_RETRY_DELAY = DESPAWN_RETRY_DELAY } })

    Players.PlayerRemoving:Connect(function(player)
        local toRemove = {}
        for dropModel, data in pairs(dropRegistry.state.activeDrops) do
            if data.owner == player then table.insert(toRemove, dropModel) end
        end
        for _, m in ipairs(toRemove) do dropRegistry.removeDrop(m) end
        dropRegistry.state.playerDropCounts[player] = nil
        dropRegistry.state.playerPickupCooldowns[player] = nil
    end)

    RunService.Heartbeat:Connect(function(dt)
        DigPerformance.measureSection("IS_Rotations", function()
            updateItemRotations(dt)
        end)
        DigPerformance.measureSection("IS_AutoCollector", function()
            autoCollector.handleAutoCollection(dt)
        end)
        if FORCED_CLAIM_ENABLED then
            DigPerformance.measureSection("IS_Sweeper", function()
                sweeper.handleForcedClaim(dt)
            end)
        end
    end)

    if LOOT_MAGNET_ENABLED then
        log:info("Loot magnet enabled (start=%.2fs, range=%d->%d over %.2fs)", MAGNET_START_DELAY, MAGNET_START_RANGE, MAGNET_MAX_RANGE, MAGNET_GROWTH_SECONDS)
    end
    if FORCED_CLAIM_ENABLED then log:info("Forced-claim safety enabled") end
    log:info("Started with player connections and update loop")
end

function ItemService:SpawnLootFromDig(countsById: {[string]: number}, position: Vector3, owner: Player?): {Model}
    return spawner.SpawnLootFromDig(countsById, position, owner)
end

function ItemService:SpawnLootEntriesFromDig(entries: {{itemId: string, position: Vector3}}, owner: Player?): {Model}
    return spawner.SpawnLootEntriesFromDig(entries, owner)
end

function ItemService:SpawnStackedDrop(itemId: string, count: number, position: Vector3, owner: Player?): Model?
    return spawner.SpawnStackedDrop(itemId, count, position, owner)
end

function ItemService:AutoCollectDrop(dropModel: Model, collectorPlayer: Player): boolean
    return collector.AutoCollectDrop(dropModel, collectorPlayer)
end

function ItemService:CollectDrop(dropModel: Model, collectorPlayer: Player): boolean
    return collector.CollectDrop(dropModel, collectorPlayer)
end

function ItemService:RemoveDrop(dropModel: Model)
    return dropRegistry.removeDrop(dropModel)
end

function ItemService:GetNearbyDrops(position: Vector3, range: number): {Model}
    return dropRegistry.getNearbyDrops(position, range)
end

log:info("Initialized")

return ItemService
