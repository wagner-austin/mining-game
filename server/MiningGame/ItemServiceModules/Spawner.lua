--!strict
-- Spawner.lua
-- Item drop spawning, per-dig capping, and despawn scheduling

local Spawner = {}

export type SpawnerT = {
    SpawnStackedDrop: (self: SpawnerT, itemId: string, count: number, position: Vector3, owner: Player?) -> Model?,
    SpawnLootEntriesFromDig: (self: SpawnerT, entries: {{itemId: string, position: Vector3}}, owner: Player?) -> {Model},
    SpawnLootFromDig: (self: SpawnerT, countsById: {[string]: number}, position: Vector3, owner: Player?) -> {Model},
    scheduleFinalHardDespawn: (self: SpawnerT, model: Model) -> (),
    setAutoCollectFn: (self: SpawnerT, fn: ((Model, Player) -> boolean)?) -> (),
}

function Spawner.new(ctx): SpawnerT
    local workspace = game:GetService("Workspace")

    local Time = ctx.Time
    local Logger = ctx.Logger
    local log = Logger.new("ItemService.Spawner")

    local GameConfig = ctx.GameConfig
    local MathUtils = ctx.MathUtils
    local DropModelFactory = ctx.DropModelFactory
    local ItemAnimations = ctx.ItemAnimations
    local LootService = ctx.LootService
    local InventoryService = ctx.InventoryService
    local dropRegistry = ctx.dropRegistry
    local Bus = ctx.Bus
    local EventNames = ctx.EventNames

    local ITEM_LIFETIME: number = ctx.constants.ITEM_LIFETIME
    local DESPAWN_RETRY_DELAY: number = ctx.constants.DESPAWN_RETRY_DELAY
    local MAX_DROPS_PER_PLAYER: number = ctx.constants.MAX_DROPS_PER_PLAYER

    local function getDropsFolder(): Folder
        local folder = workspace:FindFirstChild("ItemDrops")
        if not folder then
            folder = Instance.new("Folder")
            folder.Name = "ItemDrops"
            folder.Parent = workspace
        end
        return folder
    end

    local function createItemModel(itemDef: any, position: Vector3, count: number): Model
        return DropModelFactory.create(itemDef, position, count)
    end

    local autoCollectFn: ((Model, Player) -> boolean)? = nil
    local function setAutoCollectFn(fn)
        autoCollectFn = fn
    end

    local function scheduleFinalHardDespawn(model: Model)
        local thisModel = model
        task.delay((ctx.constants.FINAL_DESPAWN_AFTER or 120), function()
            local d = dropRegistry.state.activeDrops[thisModel]
            if d and not d.claimed and d.owner == nil then
                dropRegistry.removeDrop(thisModel)
                log:debug("Hard-despawned orphaned drop: %s", d.itemId)
            end
        end)
    end

    local function SpawnStackedDrop(itemId: string, count: number, position: Vector3, owner: Player?): Model?
        log:debug("SpawnStackedDrop called - itemId: %s, count: %d, position: (%.1f, %.1f, %.1f)", itemId, count, position.X, position.Y, position.Z)

        local itemDef = LootService:GetItemDefinition(itemId)
        if not itemDef then
            log:warn("Unknown item: {}", itemId)
            return nil
        end

        if owner then
            local dropCount = dropRegistry.state.playerDropCounts[owner] or 0
            log:debug("Player drop count: %d / %d", dropCount, MAX_DROPS_PER_PLAYER)
            if dropCount >= MAX_DROPS_PER_PLAYER then
                local oldestDrop, oldestTime = nil, math.huge
                for drop, data in pairs(dropRegistry.state.activeDrops) do
                    if data.owner == owner and not data.claimed and data.spawnTime < oldestTime then
                        oldestDrop = drop
                        oldestTime = data.spawnTime
                    end
                end
                if oldestDrop then
                    log:debug("Removing oldest drop to make room for new drop")
                    if autoCollectFn then
                        autoCollectFn(oldestDrop, owner)
                    else
                        -- Fallback: grant directly and remove
                        local d = dropRegistry.state.activeDrops[oldestDrop]
                        if d then
                            InventoryService:AddItemsBulk(owner, {[d.itemId] = d.count})
                            d.claimed = true
                            dropRegistry.removeDrop(oldestDrop)
                        end
                    end
                end
            end
        end

        local model = createItemModel(itemDef, position, count)
        model.Parent = getDropsFolder()

        if model.PrimaryPart then
            log:debug("Drop spawned at actual position: (%.1f, %.1f, %.1f)", model.PrimaryPart.Position.X, model.PrimaryPart.Position.Y, model.PrimaryPart.Position.Z)
        end

        if model.PrimaryPart then
            local hoverTween = ItemAnimations.createHoverAnimation(model.PrimaryPart)
            dropRegistry.state.hoverTweens[model] = hoverTween
        end

        dropRegistry.registerDrop(model, {
            owner = owner,
            itemId = itemId,
            count = count,
            rarity = itemDef.rarity,
            value = itemDef.value,
            spawnTime = Time.mono(),
            claimed = false,
        })

        local activeCount = 0
        for _ in pairs(dropRegistry.state.activeDrops) do activeCount += 1 end
        log:debug("Drop registered in activeDrops. Total active drops: %d", activeCount)

        if owner then
            log:event("item_dropped", { uid = owner.UserId, itemId = itemId, count = count, rarity = itemDef.rarity, position = tostring(position) })
        end

        task.delay(ITEM_LIFETIME, function()
            if model and model.Parent and dropRegistry.state.activeDrops[model] then
                local data = dropRegistry.state.activeDrops[model]
                if not data.claimed then
                    if owner and owner.Parent then
                        local ok = false
                        if autoCollectFn then ok = autoCollectFn(model, owner) end
                        if not ok then
                            task.delay(DESPAWN_RETRY_DELAY, function()
                                local d = dropRegistry.state.activeDrops[model]
                                if d and not d.claimed then
                                    if d.owner then
                                        dropRegistry.state.playerDropCounts[d.owner] = MathUtils.saturatingSub((dropRegistry.state.playerDropCounts[d.owner] or 0), 1)
                                    end
                                    d.owner = nil
                                    log:debug("Drop made public after failed collection: %s", d.itemId)
                                    scheduleFinalHardDespawn(model)
                                end
                            end)
                        end
                    else
                        if data.owner then
                            dropRegistry.state.playerDropCounts[data.owner] = MathUtils.saturatingSub((dropRegistry.state.playerDropCounts[data.owner] or 0), 1)
                        end
                        data.owner = nil
                        log:debug("Drop made public - owner disconnected: %s", data.itemId)
                        scheduleFinalHardDespawn(model)
                    end
                else
                    -- already claimed: no-op
                end
            end
        end)

        log:debug("Spawned stacked drop %s x%d at (%.1f, %.1f, %.1f)", itemId, count, position.X, position.Y, position.Z)
        return model
    end

    local function spawnCapped(entries: {{itemId: string, position: Vector3}}, owner: Player?): {Model}
        local drops = {}
        local toInventory: {[string]: number} = {}
        local typed = {}
        local spawnedCounts: {[string]: number} = {}

        for _, e in ipairs(entries) do
            local def = LootService:GetItemDefinition(e.itemId)
            if def then
                local w = (GameConfig.Loot.RARITIES[def.rarity] and GameConfig.Loot.RARITIES[def.rarity].weight) or 1e9
                table.insert(typed, { id = e.itemId, pos = e.position, weight = w })
            end
        end
        table.sort(typed, function(a, b) return a.weight < b.weight end)

        local cap = GameConfig.Loot.MAX_DROPS_PER_DIG or 5
        local spawned = 0
        for _, t in ipairs(typed) do
            if spawned < cap then
                local m = SpawnStackedDrop(t.id, 1, t.pos, owner)
                if m then table.insert(drops, m) end
                spawnedCounts[t.id] = (spawnedCounts[t.id] or 0) + 1
                spawned += 1
            else
                toInventory[t.id] = (toInventory[t.id] or 0) + 1
            end
        end

        if owner and next(toInventory) ~= nil then
            InventoryService:AddItemsBulk(owner, toInventory)
        end

        -- Emit a LOOT_DROPPED event (per dig) with counts and approximate center position
        if owner and Bus and EventNames and next(spawnedCounts) ~= nil then
            local cx, cy, cz, n = 0, 0, 0, 0
            for _, t in ipairs(typed) do
                if spawnedCounts[t.id] and spawnedCounts[t.id] > 0 and t.pos then
                    cx += t.pos.X; cy += t.pos.Y; cz += t.pos.Z; n += 1
                end
            end
            local center = nil
            if n > 0 then center = Vector3.new(cx / n, cy / n, cz / n) end
            Bus:emit(EventNames.LOOT_DROPPED, {
                to = { kind = "player", player = owner },
                payload = {
                    counts = spawnedCounts,
                    granted = next(toInventory) and toInventory or nil,
                    position = center,
                }
            })
        end
        return drops
    end

    local function SpawnLootEntriesFromDig(entries: {{itemId: string, position: Vector3}}, owner: Player?): {Model}
        if GameConfig.Loot.SPAWN_MODE == "ring" and #entries > 0 then
            local cx, cy, cz = 0, 0, 0
            for _, e in ipairs(entries) do cx += e.position.X; cy += e.position.Y; cz += e.position.Z end
            cx /= #entries; cy /= #entries; cz /= #entries
            local center = Vector3.new(cx, cy + (GameConfig.Loot.RING_VERTICAL_OFFSET or 0), cz)
            local radius = GameConfig.Loot.RING_RADIUS or 6
            local jitter = GameConfig.Loot.RING_JITTER or 1.5
            local golden = math.pi * (3 - math.sqrt(5))
            local ring = {}
            for i, e in ipairs(entries) do
                local r = radius + (math.random() * 2 - 1) * jitter
                local a = i * golden
                local pos = center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
                table.insert(ring, { itemId = e.itemId, position = pos })
            end
            return spawnCapped(ring, owner)
        end
        return spawnCapped(entries, owner)
    end

    local function SpawnLootFromDig(countsById: {[string]: number}, position: Vector3, owner: Player?): {Model}
        local entries = {}
        for itemId, count in pairs(countsById) do
            for _ = 1, math.max(0, count) do
                table.insert(entries, { itemId = itemId, position = position })
            end
        end
        return spawnCapped(entries, owner)
    end

    return {
        SpawnStackedDrop = SpawnStackedDrop,
        SpawnLootEntriesFromDig = SpawnLootEntriesFromDig,
        SpawnLootFromDig = SpawnLootFromDig,
        scheduleFinalHardDespawn = scheduleFinalHardDespawn,
        setAutoCollectFn = setAutoCollectFn,
    }
end

return Spawner
