--!strict
-- ItemDefinitions.lua
-- Unified, normalized item definitions for all item types (resources, cosmetics, consumables)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local GameConfig = require(MiningGame:WaitForChild("GameConfig"))
local CosmeticDefinitions = require(MiningGame:WaitForChild("CosmeticDefinitions"))

export type Item = {
    id: string,
    name: string,
    type: string, -- "resource" | "cosmetic" | "consumable" | ...
    slot: string?,
    rarity: string,
    value: number?,
    tags: {[string]: boolean}?,
    meta: {[string]: any}?,
}

local ItemDefinitions = {}

local _map: {[string]: Item} = {}
local _list: {Item} = {}
local _byType: {[string]: {Item}} = {}
local _rarityOrder: {[string]: number} = {}

-- Build rarity ordering map from GameConfig (higher weight = rarer; we sort by name/key as a stable fallback)
do
    local rarities = GameConfig and GameConfig.Loot and GameConfig.Loot.RARITIES or {}
    for k, def in pairs(rarities) do
        _rarityOrder[tostring(k)] = tonumber(def.weight) or 0
    end
end

local function _insert(item: Item)
    if _map[item.id] then
        warn(("[ItemDefinitions] Duplicate item id '%s' encountered; keeping first definition"):format(item.id))
        return
    end
    _map[item.id] = item
    table.insert(_list, item)
    local t = item.type or "other"
    _byType[t] = _byType[t] or {}
    table.insert(_byType[t], item)
end

-- Normalize inputs from GameConfig.Loot.ITEMS
local function _ingestGameConfig()
    local loot = GameConfig and GameConfig.Loot or nil
    if not loot or not loot.ITEMS then return end
    for _, def in ipairs(loot.ITEMS) do
        local item: Item = {
            id = def.id,
            name = def.name or def.id,
            type = def.type or "resource",
            slot = def.slot or def.type,
            rarity = tostring(def.rarity or ""),
            value = def.value,
            tags = def.exclusive and { exclusive = true } or nil,
            -- keep full def as meta so optional fields like icon are available
            meta = def,
        }
        _insert(item)
    end
end

-- Normalize inputs from CosmeticDefinitions.ITEMS (map)
local function _ingestCosmetics()
    local items = CosmeticDefinitions and CosmeticDefinitions.ITEMS or nil
    if not items then return end
    for id, def in pairs(items) do
        local item: Item = {
            id = id,
            name = def.name or id,
            type = "cosmetic",
            slot = def.slot,
            rarity = tostring(def.rarity or ""),
            value = def.value,
            meta = def,
        }
        _insert(item)
    end
end

-- Sort function: type, rarity (by weight then key), name
local function _typeRank(t: string): number
    -- Prefer the common order seen in UI: resources, cosmetics, consumables, then others
    local order = {
        resource = 1,
        cosmetic = 2,
        consumable = 3,
    }
    return order[t] or 99
end

local function _rarityRank(r: string): number
    -- Lower rank sorts earlier. Use raw weight so rarer (smaller weight) sorts first.
    local w = _rarityOrder[r] or 0
    return w
end

local function _slotRank(slot: string?): number
    local s = (slot or ""):lower()
    local order = {
        aura = 1,
        back = 2, wings = 2,
        head = 3,
        trail = 4,
        accessory = 5,
    }
    return order[s] or 99
end

local function _sortAll()
    table.sort(_list, function(a, b)
        if _typeRank(a.type) ~= _typeRank(b.type) then return _typeRank(a.type) < _typeRank(b.type) end
        if a.type == "cosmetic" and b.type == "cosmetic" then
            if _slotRank(a.slot) ~= _slotRank(b.slot) then return _slotRank(a.slot) < _slotRank(b.slot) end
        end
        if _rarityRank(a.rarity) ~= _rarityRank(b.rarity) then return _rarityRank(a.rarity) < _rarityRank(b.rarity) end
        return tostring(a.name) < tostring(b.name)
    end)
    for t, arr in pairs(_byType) do
        table.sort(arr, function(a, b)
            if t == "cosmetic" then
                if _slotRank(a.slot) ~= _slotRank(b.slot) then return _slotRank(a.slot) < _slotRank(b.slot) end
            end
            if _rarityRank(a.rarity) ~= _rarityRank(b.rarity) then return _rarityRank(a.rarity) < _rarityRank(b.rarity) end
            return tostring(a.name) < tostring(b.name)
        end)
    end
end

-- Build once
_ingestGameConfig()
_ingestCosmetics()
_sortAll()

-- Public API
function ItemDefinitions.get(id: string): Item?
    return _map[id]
end

function ItemDefinitions.map(): {[string]: Item}
    return _map
end

function ItemDefinitions.all(): {Item}
    return _list
end

function ItemDefinitions.byType(t: string): {Item}
    return _byType[t] or {}
end

function ItemDefinitions.ids(): {string}
    local out = {}
    for id, _ in pairs(_map) do table.insert(out, id) end
    table.sort(out)
    return out
end

function ItemDefinitions.rarities(): {string}
    local out = {}
    local rarities = GameConfig and GameConfig.Loot and GameConfig.Loot.RARITIES or {}
    for k, _ in pairs(rarities) do table.insert(out, tostring(k)) end
    table.sort(out)
    return out
end

return ItemDefinitions
