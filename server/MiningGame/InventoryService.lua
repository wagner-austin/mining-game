--!strict
--[[
    InventoryService.server.lua
    Manages player inventory, equipment, and item transactions.
    
    Features:
    - Stack management with per-type limits
    - Equipment system for cosmetics and tools
    - Bulk operations for efficiency
    - Auto-selling resources
    - Inventory change notifications
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Shared modules
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Time = require(Shared:WaitForChild("Time"))
local Logger = require(Shared:WaitForChild("Logger"))
local log = Logger.new("InventoryService")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Types = require(Shared:WaitForChild("Types"))
local MathUtils = require(Shared:WaitForChild("MathUtils"))
local Guard = require(Shared:WaitForChild("Guard"))
local ServiceValidator = require(Shared:WaitForChild("ServiceValidator"))

-- Server siblings - resolved via DI
local DataService
local LootService
local AchievementService
local CurrencyService
local CompositionService  -- Optional for terrain theme equipment
local ErrorService = require(script.Parent.ErrorService)  -- Foundation service
local Schema = require(script.Parent.SchemaValidators)  -- Not a service
local CharacterStateManager -- Injected via container
local PerkService -- Orchestrator

-- Shared remotes accessor
local Remotes = require(ReplicatedStorage.MiningGame.Remotes)

-- Event Bus for decoupled communication
local EventBus = require(Shared:WaitForChild("EventBus"))
local EventNames = require(Shared:WaitForChild("EventNames"))
local Contracts = require(Shared:WaitForChild("EventContracts"))
local Bus = EventBus.global()

local InventoryService = {}

-- Player debounce tracking (moved before Start method to avoid forward reference)
local paletteDebounce: {[Player]: number} = {}
-- Per-player lock to serialize consumable use and avoid double-consume
local useConsumableBusy: {[Player]: boolean} = {}
-- Short per-item rate limit (server-side) to coalesce accidental double taps
local lastUseAt: {[Player]: {[string]: number}} = {}

-- Initialize with dependency injection
function InventoryService:Init(container)
    -- Hard dependencies
    DataService = ServiceValidator.get(container, "DataService", {"GetPlayerData", "QueueSave"})
    LootService = ServiceValidator.get(container, "LootService", {"GetItemDefinition", "CalculateSellValue", "GetRarityColor"})
    AchievementService = ServiceValidator.get(container, "AchievementService", {"SetRewardItemCallback", "RecordFirstCosmeticEquip"})
    CurrencyService = ServiceValidator.get(container, "CurrencyService", {"add"})
    
    -- Optional dependency for terrain theme equipment
    CompositionService = ServiceValidator.tryGet(container, "CompositionService", {"ApplyComposition"})

    -- Character state manager for server-authored movement effects
    -- Use tryGet here because CharacterStateManager is registered later in ServiceManager
    CharacterStateManager = ServiceValidator.tryGet(container, "CharacterStateManager", {"ApplyTimedEffect", "RemoveEffect", "SyncProfileBoosts"})
    -- Perk orchestrator (registered after CharacterStateManager)
    PerkService = ServiceValidator.tryGet(container, "PerkService", {"Recompute"})
    
    -- Register callback with AchievementService now that deps are wired
    AchievementService.SetRewardItemCallback(function(player: Player, itemId: string, count: number)
        InventoryService:AddItem(player, itemId, count)
    end)
    
    log:info("Initialized with dependencies")
end

-- Start method to connect events after all services are initialized
function InventoryService:Start(container)
    -- Clean up debounce on player leave
    Players.PlayerRemoving:Connect(function(player)
        paletteDebounce[player] = nil
    end)
    
    -- Resolve CharacterStateManager now that all services are built
    CharacterStateManager = CharacterStateManager or ServiceValidator.tryGet(container, "CharacterStateManager", {"ApplyTimedEffect", "RemoveEffect", "SyncProfileBoosts"})
    PerkService = PerkService or ServiceValidator.tryGet(container, "PerkService", {"Recompute"})

    log:info("Started with player connections")

    -- Helper that waits for DataService profile and CharacterStateManager state, then recomputes perks
    local function initPerksFor(player: Player)
        task.defer(function()
            if PerkService and PerkService.Recompute then
                PerkService:Recompute(player)
            else
                log:warn("PerkService not available; perks not applied for %s", player.Name)
            end
            if CharacterStateManager and CharacterStateManager.SyncProfileBoosts then
                CharacterStateManager:SyncProfileBoosts(player)
            end
        end)
    end

    -- Initialize cosmetic perk effects when players join (after services and profile/state are ready)
    Players.PlayerAdded:Connect(initPerksFor)

    -- Also initialize for any players already present (Studio safety / mid-session reloads)
    for _, p in ipairs(Players:GetPlayers()) do
        initPerksFor(p)
    end
end

-- Helper to preserve : method syntax with Guard wrappers
local function asMethod(wrapped)
    return function(self, ...) return wrapped(self, ...) end
end

-- Helper to emit inventory snapshot consistently
local function emitInventorySnapshot(player: Player, profile: Types.PlayerStats)
    Bus:emit(EventNames.INVENTORY_CHANGED, {
        to = { kind = "player", player = player },
        payload = Contracts.INVENTORY_CHANGED(profile.inventory),
    })
    -- Also send full profile update so UI has both inventory and equipped data
    Bus:emit(EventNames.PROFILE_UPDATED, {
        to = { kind = "player", player = player },
        payload = profile
    })
end

-- Emit only deltas for lightweight updates
local function emitInventoryDelta(player: Player, delta: {[string]: number})
    if not delta or next(delta) == nil then return end
    Bus:emit(EventNames.INVENTORY_DELTA, {
        to = { kind = "player", player = player },
        payload = Contracts.INVENTORY_DELTA(delta),
    })
end

-- Debounce for palette refreshes (per-player) - already declared at top
local PALETTE_DEBOUNCE_TIME = 0.5 -- seconds

-- Maximum stack sizes by item type
local limits = GameConfig and GameConfig.Limits or {}
local MAX_STACK_SIZE = {
    resource = limits.MAX_RESOURCE_STACK or 99999,
    consumable = limits.MAX_CONSUMABLE_STACK or 99999,
    cosmetic = limits.MAX_COSMETIC_STACK or 99999,  -- Config-driven cap for cosmetics (including hand tools)
}

-- Centralized helper: auto-equip cosmetic into empty slot on acquire (opt-in via Feature flag)
local function autoEquipIfEmpty(self, player: Player, itemId: string, wasFirstObtain: boolean?)
    local features = GameConfig and GameConfig.Features or {}
    if not (features.COSMETICS_ENABLED and features.AUTO_EQUIP_COSMETICS_ON_ACQUIRE) then
        return
    end
    -- Only first obtain by default to avoid surprising replaces from duplicates
    if wasFirstObtain == false then
        return
    end
    local itemDef = LootService:GetItemDefinition(itemId)
    if not itemDef or itemDef.type ~= "cosmetic" then return end
    local slot = itemDef.slot
    if not slot or slot == "modelSwap" then return end
    -- Only when slot is empty
    local equippedMap = self:GetEquippedItems(player)
    if equippedMap and equippedMap[slot] then return end
    -- Best-effort equip (uses canonical EquipItem path for events/saves)
    pcall(function()
        self:EquipItem(player, itemId)
    end)
end


--[[
    Add an item to the player's inventory with stack limit checking.
    
    @param player: Player - The player receiving the item
    @param itemId: string - The item identifier
    @param count: number - Number of items to add
    @return boolean - True if any items were added
]]
function InventoryService:AddItem(player: Player, itemId: string, count: number): boolean
    local profile = DataService:GetPlayerData(player)
    if not profile then
        return false
    end
    
    -- Get item definition
    local itemDef = LootService:GetItemDefinition(itemId)
    if not itemDef then
        log:warn("Unknown item: %s", itemId)
        return false
    end
    
    -- Get max stack size
    local maxStack = MAX_STACK_SIZE[itemDef.type] or 1
    
    -- Calculate how much we can actually add
    local currentCount = profile.inventory[itemId] or 0
    local addable = MathUtils.nonNegative(math.min(count, maxStack - currentCount))
    
    -- Skip if nothing to add (already at cap)
    if addable <= 0 then
        return false
    end
    
    -- Add to inventory
    local newCount = currentCount + addable
    profile.inventory[itemId] = newCount
    -- Record first obtained timestamp
    local obtainedAt = (profile :: any).inventoryObtainedAt
    if obtainedAt and not obtainedAt[itemId] then
        obtainedAt[itemId] = DateTime.now().UnixTimestamp
    end
    
    -- Queue save
    DataService:QueueSave(player)

    -- Notify client with delta for this single add
    emitInventoryDelta(player, {[itemId] = addable})
    
    -- Auto-equip on first obtain if slot is empty
    local wasFirstObtain = (currentCount == 0) and (addable > 0)
    autoEquipIfEmpty(self, player, itemId, wasFirstObtain)

    return true
end

--[[
    Add multiple items in a single operation for better performance.
    Useful for processing multi-cell dig results.
    
    @param player: Player - The player receiving items
    @param countsById: {[string]: number} - Map of itemId to count
    @return {[string]: number} - Map of items actually added
]]
function InventoryService:AddItemsBulk(player: Player, countsById: {[string]: number}): {[string]: number}
    local profile = DataService:GetPlayerData(player)
    if not profile then
        return {}
    end

    local actuallyAdded = {}
    local needsSave = false

    for itemId, count in pairs(countsById) do
        local itemDef = LootService:GetItemDefinition(itemId)
        if itemDef then
            local maxStack = MAX_STACK_SIZE[itemDef.type] or 1
            local currentCount = profile.inventory[itemId] or 0
            local addable = MathUtils.nonNegative(math.min(count, maxStack - currentCount))

            if addable > 0 then
                profile.inventory[itemId] = currentCount + addable
                -- Record first obtained in bulk path
                local obtainedAt = (profile :: any).inventoryObtainedAt
                if obtainedAt and not obtainedAt[itemId] then
                    obtainedAt[itemId] = DateTime.now().UnixTimestamp
                end
                actuallyAdded[itemId] = addable
                needsSave = true

                -- Track that we need to emit inventory change
                -- (Will emit once after all items processed)

                -- Auto-equip this cosmetic if first obtain and slot empty
                local wasFirstObtain = (currentCount == 0)
                autoEquipIfEmpty(self, player, itemId, wasFirstObtain)
            end
        end
    end

    -- Queue save and emit inventory change once if anything was added
    if needsSave then
        DataService:QueueSave(player)
        -- Emit only deltas for efficiency; profile snapshots are
        -- still sent by higher-level flows (e.g., equip/unequip, login)
        emitInventoryDelta(player, actuallyAdded)
    end

    return actuallyAdded
end

-- Remove item from inventory
function InventoryService:RemoveItem(player: Player, itemId: string, count: number): boolean
    local profile = DataService:GetPlayerData(player)
    if not profile then
        return false
    end
    
    local currentCount = profile.inventory[itemId] or 0
    if currentCount < count then
        return false -- Not enough items
    end
    
    local newCount = currentCount - count
    if newCount <= 0 then
        profile.inventory[itemId] = nil
    else
        profile.inventory[itemId] = newCount
    end
    
    -- Queue save
    DataService:QueueSave(player)
    
    -- Notify client with negative delta for removal
    local removed = math.min(count, currentCount)
    emitInventoryDelta(player, {[itemId] = -removed})
    
    return true
end

-- Check if player has item
function InventoryService:HasItem(player: Player, itemId: string, count: number): boolean
    local profile = DataService:GetPlayerData(player)
    if not profile then
        return false
    end
    
    local currentCount = profile.inventory[itemId] or 0
    return currentCount >= count
end

-- Get item count
function InventoryService:GetItemCount(player: Player, itemId: string): number
    local profile = DataService:GetPlayerData(player)
    if not profile then
        return 0
    end
    
    return profile.inventory[itemId] or 0
end

--[[
    Sell items from inventory for coins based on rarity values.
    
    @param player: Player - The player selling items
    @param items: {[string]: number} - Map of itemId to quantity to sell
    @return {success: boolean, coinsEarned: number?, reason: string?} - Sale result
]]
InventoryService.SellItems = asMethod(Guard.args(
    { Schema.Table, Schema.InstanceIsA("Player"), Schema.ItemCounts },
    function(self, player: Player, items: {[string]: number}): {success: boolean, coinsEarned: number?, reason: string?}
    local profile = DataService:GetPlayerData(player)
    if not profile then
        return {success = false, reason = "No profile"}
    end
    
    -- Filter out unsellable items (cosmetics, pickaxes, valueless items)
    local sellable: {[string]: number} = {}
    for itemId, count in pairs(items) do
        local def = LootService:GetItemDefinition(itemId)
        -- Only allow selling resources and consumables with value > 0
        local isSellable = def 
            and def.type ~= "cosmetic" 
            and def.type ~= "pickaxe" 
            and def.value 
            and def.value > 0
        
        if isSellable then
            -- Also verify player has the items
            if not self:HasItem(player, itemId, count) then
                return {success = false, reason = "Insufficient items"}
            end
            sellable[itemId] = count
        end
    end
    
    -- Nothing sellable? Bail gracefully with clear message
    if next(sellable) == nil then
        return {success = false, reason = "Only resources and consumables can be sold"}
    end
    
    -- Calculate total value using only the filtered sellable items
    local totalValue = LootService:CalculateSellValue(sellable)
    
    -- Remove only the sellable items (cosmetics stay in inventory!)
    for itemId, count in pairs(sellable) do
        self:RemoveItem(player, itemId, count)
    end
    
    CurrencyService.add(player, "coins", totalValue)
    
    -- Notify client
    Bus:emit(EventNames.NOTIFICATION_PUSH, {
        to = { kind = "player", player = player },
        payload = Contracts.NOTIFICATION_PUSH({
            type = "success",
            message = string.format("Sold items for %d coins!", totalValue),
            color = Color3.new(1, 0.8, 0),
        })
    })
    
    return {success = true, coinsEarned = totalValue}
    end
))

-- Equip an item
InventoryService.EquipItem = asMethod(Guard.args(
    { Schema.Table, Schema.InstanceIsA("Player"), Schema.String },
    function(self, player: Player, itemId: string): {success: boolean, reason: string?}
    local profile = DataService:GetPlayerData(player)
    if not profile then
        return {success = false, reason = "No profile"}
    end
    
    -- Check if player has the item
    if not self:HasItem(player, itemId, 1) then
        return {success = false, reason = "Item not owned"}
    end
    
    -- Get item definition
    local itemDef = LootService:GetItemDefinition(itemId)
    if not itemDef then
        return {success = false, reason = "Unknown item"}
    end
    
    -- Check if cosmetics are enabled
    if itemDef.type == "cosmetic" and not GameConfig.Features.COSMETICS_ENABLED then
        return {success = false, reason = "Cosmetics are disabled"}
    end
    
    -- Determine slot
    local slot = nil
    if itemDef.type == "pickaxe" then
        slot = "pickaxe"
    elseif itemDef.type == "cosmetic" then
        slot = itemDef.slot
        if slot == "modelSwap" then
            return {success = false, reason = "Model swaps are not available"}
        end
    else
        return {success = false, reason = "Item cannot be equipped"}
    end
    
    if not slot then
        return {success = false, reason = "No equipment slot"}
    end
    
    -- Guard: Skip if already equipped in same slot
    local currentEquipped = profile.equipped[slot]
    if currentEquipped == itemId then
        log:debug("Item %s already equipped in slot %s for %s", itemId, slot, player.Name)
        return {success = true, reason = "Already equipped"}
    end
    
    -- Equip new item
    profile.equipped[slot] = itemId
    
    log:info("Equipped %s in slot %s for %s", itemId, slot, player.Name)
    
    -- Special handling for terrain theme -> mirror to palette preference
    if slot == "terrainTheme" then
        local palette = itemDef.palette
        if palette then
            profile.materialPreferences = profile.materialPreferences or {}
            profile.materialPreferences.palette = palette
            
            -- Apply the palette immediately if player has an active composition
            if profile.materialPreferences.compositionId then
                -- Check debounce to prevent paint storms
                local now = Time.mono()
                local lastRefresh = paletteDebounce[player] or 0
                
                if now - lastRefresh >= PALETTE_DEBOUNCE_TIME then
                    paletteDebounce[player] = now
                    
                    local compId = profile.materialPreferences.compositionId
                    local mode = profile.materialPreferences.variationMode
                    
                    -- Defer and protect the heavy repaint operation
                    task.defer(function()
                        -- Check player is still in game
                        if player.Parent == nil then 
                            log:debug("Player %s left before palette apply", player.Name)
                            return 
                        end
                        
                        -- Use DI'd CompositionService if available
                        if CompositionService then
                            local ok = ErrorService.safecall("CompositionService:ApplyComposition(equip)", function()
                                CompositionService:ApplyComposition(player, compId, mode, true)
                            end, { uid = player.UserId, compId = compId, mode = mode })
                            if ok then
                                log:info("Applied terrain theme palette for %s", player.Name)
                            else
                                log:warn("Failed to apply terrain theme for %s", player.Name)
                            end
                        else
                            log:debug("CompositionService not available for terrain theme")
                        end
                    end)
                end
            end
            
            -- Notify client about theme change
            Bus:emit(EventNames.NOTIFICATION_PUSH, {
                to = { kind = "player", player = player },
                payload = Contracts.NOTIFICATION_PUSH({
                    type = "info",
                    message = string.format("Applied terrain theme: %s", itemDef.name or palette),
                    color = Color3.new(0.4, 0.8, 1),
                })
            })
        end
    end
    
    -- Queue save
    DataService:QueueSave(player)
    
    -- Track cosmetic achievements
    if itemDef.type == "cosmetic" then
        AchievementService.RecordFirstCosmeticEquip(player)
    end
    
    -- Notify client with full inventory snapshot
    emitInventorySnapshot(player, profile)
    
    -- Broadcast to all clients for cosmetic rendering
    Bus:emit(EventNames.EQUIPMENT_CHANGED, {
        to = { kind = "all" },
        payload = Contracts.EQUIPMENT_CHANGED({
            playerUserId = player.UserId,
            slot = slot,
            itemId = itemId,
        })
    })

    -- Recompute cosmetic perks via orchestrator
    if PerkService and PerkService.Recompute then PerkService:Recompute(player) end

    return {success = true}
    end
))

-- Unequip an item
InventoryService.UnequipItem = asMethod(Guard.args(
    { Schema.Table, Schema.InstanceIsA("Player"), Schema.EquipmentSlot },
    function(self, player: Player, slot: string): {success: boolean, reason: string?}
    local profile = DataService:GetPlayerData(player)
    if not profile then
        return {success = false, reason = "No profile"}
    end
    
    local itemId = profile.equipped[slot]
    if not itemId then
        return {success = false, reason = "Nothing equipped"}
    end
    
    -- Unequip
    profile.equipped[slot] = nil
    
    -- Queue save
    DataService:QueueSave(player)
    
    -- Notify client
    -- Emit full inventory snapshot
    emitInventorySnapshot(player, profile)
    
    -- Broadcast to all clients for cosmetic rendering
    Bus:emit(EventNames.EQUIPMENT_CHANGED, {
        to = { kind = "all" },
        payload = Contracts.EQUIPMENT_CHANGED({
            playerUserId = player.UserId,
            slot = slot,
            itemId = nil,  -- nil = unequipped
        })
    })

    -- Recompute cosmetic perks via orchestrator
    if PerkService and PerkService.Recompute then PerkService:Recompute(player) end

    return {success = true}
    end
))

-- Use a consumable
InventoryService.UseConsumable = asMethod(Guard.args(
    { Schema.Table, Schema.InstanceIsA("Player"), Schema.String },
    function(self, player: Player, itemId: string): {success: boolean, reason: string?}
    -- Serialize per-player to prevent concurrent double-consume (race on profile.boosts)
    if useConsumableBusy[player] then
        return {success = true, reason = "DEDUPED_BUSY"}
    end
    useConsumableBusy[player] = true
    local function clearBusy()
        useConsumableBusy[player] = nil
    end
    
    -- Lightweight per-item debounce (server-authoritative)
    local nowMono = Time.mono()
    lastUseAt[player] = lastUseAt[player] or {}
    local last = lastUseAt[player][itemId] or 0
    if (nowMono - last) < 0.25 then
        clearBusy()
        return {success = true, reason = "DEDUPED_RATELIMIT"}
    end
    lastUseAt[player][itemId] = nowMono

    local profile = DataService:GetPlayerData(player)
    if not profile then
        clearBusy()
        return {success = false, reason = "No profile"}
    end
    
    -- Check if player has the item
    if not self:HasItem(player, itemId, 1) then
        clearBusy()
        return {success = false, reason = "Item not owned"}
    end
    
    -- Get item definition
    local itemDef = LootService:GetItemDefinition(itemId)
    if not itemDef or itemDef.type ~= "consumable" then
        clearBusy()
        return {success = false, reason = "Not a consumable"}
    end
    
    -- Apply effect then remove item (after effect computation) to reduce risk of consuming without effect in edge cases
    if itemDef.effect == "speed" then
        -- Movement-only speed potion (stacking)
        local MB = GameConfig.MovementBoosts and GameConfig.MovementBoosts.SpeedPotion
        local stackMax = (MB and MB.STACK_MAX) or 3
        local duration = itemDef.duration or (MB and MB.DURATION_SEC) or 300
        -- Read existing tier
        local now = Time.unix()
        local currentTier = 0
        -- Find any existing potion_speed_tier_* and clear them
        for key, exp in pairs(profile.boosts) do
            local n = tostring(key):match("^potion_speed_tier_(%d+)$")
            if n then
                local tier = tonumber(n) or 0
                if type(exp) == "number" and exp > now and tier > currentTier then
                    currentTier = tier
                end
                profile.boosts[key] = nil
            end
        end
        local newTier = currentTier + 1
        local newKey = "potion_speed_tier_"..tostring(newTier)
        profile.boosts[newKey] = now + duration
    elseif itemDef.effect == "size" then
        profile.boosts.size = Time.unix() + (itemDef.duration or 300)
    elseif itemDef.effect == "luck" then
        profile.boosts.luck = Time.unix() + (itemDef.duration or 300)
    elseif itemDef.effect == "jumps" then
        -- Jump potion: grants +N extra jumps temporarily using cosmetic_extra_jumps_1 stacks
        local duration = itemDef.duration or 900
        local now = Time.unix()
        local n = tonumber((itemDef :: any).jumps) or 4
        -- Clear existing extra jump stacks
        for key, _ in pairs(profile.boosts) do
            if tostring(key):match("^cosmetic_extra_jumps_1") then
                profile.boosts[key] = nil
            end
        end
        -- Apply N stacked entries as #1..#N
        for i = 1, math.max(0, n) do
            local k = string.format("cosmetic_extra_jumps_1#%d", i)
            profile.boosts[k] = now + duration
        end
    end
    
    -- Remove item (consume exactly once per accepted call)
    self:RemoveItem(player, itemId, 1)
    
    -- Queue save
    DataService:QueueSave(player)
    
    -- Notify client
    Bus:emit(EventNames.BOOSTS_CHANGED, {
        to = { kind = "player", player = player },
        payload = Contracts.BOOSTS_CHANGED(profile.boosts)
    })
    
    -- Update runtime effects snapshot immediately so movement/stats update without relog
    if CharacterStateManager and CharacterStateManager.SyncProfileBoosts then
        CharacterStateManager:SyncProfileBoosts(player)
    end
    
    Bus:emit(EventNames.NOTIFICATION_PUSH, {
        to = { kind = "player", player = player },
        payload = Contracts.NOTIFICATION_PUSH({
            type = "success",
            message = string.format("Used %s!", itemDef.name),
            color = LootService:GetRarityColor(itemDef.rarity),
        })
    })
    
    clearBusy()
    return {success = true}
    end
))

-- Get inventory value
function InventoryService:GetInventoryValue(player: Player): number
    local profile = DataService:GetPlayerData(player)
    if not profile then
        return 0
    end
    
    return LootService:CalculateSellValue(profile.inventory)
end

-- Get equipped items
function InventoryService:GetEquippedItems(player: Player): Types.EquippedItems
    local profile = DataService:GetPlayerData(player)
    if not profile then
        return {}
    end
    
    return profile.equipped
end

-- Remote handlers moved to RemoteFns/Inventory.rf.lua via RFRegistry

-- Initialize (remotes now handled by InventoryServiceRemotes.lua)
-- setupRemotes()  -- LEGACY: Moved to RemoteManager pattern

-- Player events moved to Start method

log:info("Initialized")

return InventoryService

