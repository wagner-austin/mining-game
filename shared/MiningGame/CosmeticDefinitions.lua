--!strict
-- CosmeticDefinitions.lua (modular loader)
-- Loads category modules under MiningGame/Cosmetics and merges into a single ITEMS table.

local CosmeticDefinitions = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")

CosmeticDefinitions.ITEMS = {}

local function merge(dst: {[string]: any}, src: {[string]: any}?)
    if type(src) ~= "table" then return end
    for k, v in pairs(src) do dst[k] = v end
end

local function tryRequire(inst: Instance?): {[string]: any}?
    if not inst then return nil end
    local ok, mod = pcall(function()
        return require(inst)
    end)
    if ok and type(mod) == "table" then return mod end
    return nil
end

do
    local root = MiningGame:WaitForChild("Cosmetics")
    merge(CosmeticDefinitions.ITEMS, tryRequire(root:FindFirstChild("Auras")))
    merge(CosmeticDefinitions.ITEMS, tryRequire(root:FindFirstChild("Trails")))
    merge(CosmeticDefinitions.ITEMS, tryRequire(root:FindFirstChild("Wings")))
    merge(CosmeticDefinitions.ITEMS, tryRequire(root:FindFirstChild("Head")))
    merge(CosmeticDefinitions.ITEMS, tryRequire(root:FindFirstChild("Hand")))
end

-- Public API (unchanged)
function CosmeticDefinitions.Get(id: string)
    return CosmeticDefinitions.ITEMS[id]
end

function CosmeticDefinitions.GetByCategory(category: string): {[string]: any}
    local items = {}
    for id, item in pairs(CosmeticDefinitions.ITEMS) do
        if item.slot == category then
            items[id] = item
        end
    end
    return items
end

function CosmeticDefinitions.GetByRarity(rarity: string): {[string]: any}
    local items = {}
    for id, item in pairs(CosmeticDefinitions.ITEMS) do
        if item.rarity == rarity then
            items[id] = item
        end
    end
    return items
end

function CosmeticDefinitions.GetByEffect(effect: string): {[string]: any}
    local items = {}
    for id, item in pairs(CosmeticDefinitions.ITEMS) do
        if item.effect == effect then
            items[id] = item
        end
    end
    return items
end

function CosmeticDefinitions.GetTotalCount(): number
    local count = 0
    for _ in pairs(CosmeticDefinitions.ITEMS) do
        count += 1
    end
    return count
end

function CosmeticDefinitions.GetRandomOfRarity(rarity: string): any
    local items = CosmeticDefinitions.GetByRarity(rarity)
    local keys = {}
    for id in pairs(items) do table.insert(keys, id) end
    if #keys > 0 then
        local idx = Random.new():NextInteger(1, #keys)
        return items[keys[idx]]
    end
    return nil
end

return CosmeticDefinitions

