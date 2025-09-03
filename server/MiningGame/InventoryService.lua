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

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Shared modules
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(Shared:WaitForChild("Logger"))
local log = Logger.new("InventoryService")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Types = require(Shared:WaitForChild("Types"))

-- Server siblings
local DataService = require(script.Parent.DataService)
local LootService = require(script.Parent.LootService)

-- Shared remotes accessor
local Remotes = require(ReplicatedStorage.MiningGame.Remotes)

local InventoryService = {}

-- Maximum stack sizes by item type
local MAX_STACK_SIZE = {
    resource = 9999,
    consumable = 999,
    pickaxe = 1,
    cosmetic = 1,
}

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
        log:warn("Unknown item: {}", itemId)
        return false
    end
    
    -- Get max stack size
    local maxStack = MAX_STACK_SIZE[itemDef.type] or 1
    
    -- Calculate how much we can actually add
    local currentCount = profile.inventory[itemId] or 0
    local addable = math.max(0, math.min(count, maxStack - currentCount))
    
    -- Skip if nothing to add (already at cap)
    if addable <= 0 then
        return false
    end
    
    -- Add to inventory
    local newCount = currentCount + addable
    profile.inventory[itemId] = newCount
    
    -- Queue save
    DataService:QueueSave(player)
    
    -- Notify client
    Remotes.RE.OnInventoryChanged:FireClient(player, {
        action = "add",
        itemId = itemId,
        count = addable,
        total = newCount,
    })
    
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
            local addable = math.max(0, math.min(count, maxStack - currentCount))
            
            if addable > 0 then
                profile.inventory[itemId] = currentCount + addable
                actuallyAdded[itemId] = addable
                needsSave = true
                
                -- Send individual inventory change events
                Remotes.RE.OnInventoryChanged:FireClient(player, {
                    action = "add",
                    itemId = itemId,
                    count = addable,
                    total = profile.inventory[itemId],
                })
            end
        end
    end
    
    -- Queue save only once if anything was added
    if needsSave then
        DataService:QueueSave(player)
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
    
    -- Notify client
    Remotes.RE.OnInventoryChanged:FireClient(player, {
        action = "remove",
        itemId = itemId,
        count = count,
        total = newCount,
    })
    
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
function InventoryService:SellItems(player: Player, items: {[string]: number}): {success: boolean, coinsEarned: number?, reason: string?}
    local profile = DataService:GetPlayerData(player)
    if not profile then
        return {success = false, reason = "No profile"}
    end
    
    -- Check if player has all items
    for itemId, count in pairs(items) do
        if not self:HasItem(player, itemId, count) then
            return {success = false, reason = "Insufficient items"}
        end
    end
    
    -- Calculate total value
    local totalValue = LootService:CalculateSellValue(items)
    
    -- Remove items and add coins
    for itemId, count in pairs(items) do
        self:RemoveItem(player, itemId, count)
    end
    
    DataService:AddCurrency(player, "coins", totalValue)
    
    -- Notify client
    Remotes.RE.OnNotification:FireClient(player, {
        type = "sell",
        message = string.format("Sold items for %d coins!", totalValue),
        color = Color3.new(1, 0.8, 0),
    })
    
    return {success = true, coinsEarned = totalValue}
end

-- Equip an item
function InventoryService:EquipItem(player: Player, itemId: string): {success: boolean, reason: string?}
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
    
    -- Determine slot
    local slot = nil
    if itemDef.type == "pickaxe" then
        slot = "pickaxe"
    elseif itemDef.type == "cosmetic" then
        slot = itemDef.slot
    else
        return {success = false, reason = "Item cannot be equipped"}
    end
    
    if not slot then
        return {success = false, reason = "No equipment slot"}
    end
    
    -- Unequip current item in slot
    local currentEquipped = profile.equipped[slot]
    if currentEquipped then
        -- Item stays in inventory, just unequipped
    end
    
    -- Equip new item
    profile.equipped[slot] = itemId
    
    -- Queue save
    DataService:QueueSave(player)
    
    -- Notify client
    Remotes.RE.OnInventoryChanged:FireClient(player, {
        action = "equip",
        itemId = itemId,
        slot = slot,
    })
    
    return {success = true}
end

-- Unequip an item
function InventoryService:UnequipItem(player: Player, slot: string): {success: boolean, reason: string?}
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
    Remotes.RE.OnInventoryChanged:FireClient(player, {
        action = "unequip",
        slot = slot,
        itemId = itemId,
    })
    
    return {success = true}
end

-- Use a consumable
function InventoryService:UseConsumable(player: Player, itemId: string): {success: boolean, reason: string?}
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
    if not itemDef or itemDef.type ~= "consumable" then
        return {success = false, reason = "Not a consumable"}
    end
    
    -- Remove item
    self:RemoveItem(player, itemId, 1)
    
    -- Apply effect
    if itemDef.effect == "speed" then
        profile.boosts.speed = os.time() + (itemDef.duration or 300)
    elseif itemDef.effect == "size" then
        profile.boosts.size = os.time() + (itemDef.duration or 300)
    elseif itemDef.effect == "luck" then
        profile.boosts.luck = os.time() + (itemDef.duration or 300)
    elseif itemDef.effect == "all" then
        -- Mega potion affects multiple stats
        local duration = itemDef.duration or 900
        profile.boosts.speed = os.time() + duration
        profile.boosts.size = os.time() + duration
        profile.boosts.luck = os.time() + duration
    end
    
    -- Queue save
    DataService:QueueSave(player)
    
    -- Notify client
    Remotes.RE.OnBoostsChanged:FireClient(player, profile.boosts)
    
    Remotes.RE.OnNotification:FireClient(player, {
        type = "consumable",
        message = string.format("Used %s!", itemDef.name),
        color = LootService:GetRarityColor(itemDef.rarity),
    })
    
    return {success = true}
end

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

-- Setup remote handlers
local function setupRemotes()
    -- Sell items
    Remotes.RF.SellItems.OnServerInvoke = function(player: Player, items: {[string]: number})
        if not DataService:EnsureLoaded(player) then
            return {success = false, reason = "No profile"}
        end
        return InventoryService:SellItems(player, items)
    end
    
    -- Equip item
    Remotes.RF.EquipItem.OnServerInvoke = function(player: Player, itemId: string)
        return InventoryService:EquipItem(player, itemId)
    end
    
    -- Unequip item
    Remotes.RF.UnequipItem.OnServerInvoke = function(player: Player, slot: string)
        return InventoryService:UnequipItem(player, slot)
    end
    
    -- Use consumable
    Remotes.RF.UseConsumable.OnServerInvoke = function(player: Player, itemId: string)
        return InventoryService:UseConsumable(player, itemId)
    end
end

-- Initialize
setupRemotes()

log:info("Initialized")

return InventoryService