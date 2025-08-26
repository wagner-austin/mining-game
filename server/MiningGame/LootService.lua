--!strict
-- LootService.server.lua
-- Deterministic loot generation based on cell coordinates

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("MiningGame")

local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Types = require(Shared:WaitForChild("Types"))
local RNG = require(Shared:WaitForChild("Utils"):WaitForChild("RNG"))

local LootService = {}

-- Cache for weighted tables
local rarityWeights = GameConfig.Loot.RARITIES
local itemDefinitions = GameConfig.Loot.ITEMS
local materialMultipliers = {}

-- Build material multiplier lookup
for _, material in ipairs(GameConfig.CubeMaterials) do
    materialMultipliers[material.id] = material.lootMultiplier
end

-- Build weighted loot table
local function buildWeightedTable(rarityBoost: number): {number}
    local weights = {}
    local totalWeight = 0
    
    for i, item in ipairs(itemDefinitions) do
        local rarity = item.rarity
        local baseWeight = rarityWeights[rarity].weight
        
        -- Apply rarity boost (higher boost = better items more likely)
        local adjustedWeight = baseWeight
        if rarityBoost > 1 then
            -- Increase weight of rarer items
            if rarity == "MYTHIC" then
                adjustedWeight = baseWeight * (rarityBoost ^ 3)
            elseif rarity == "LEGENDARY" then
                adjustedWeight = baseWeight * (rarityBoost ^ 2.5)
            elseif rarity == "EPIC" then
                adjustedWeight = baseWeight * (rarityBoost ^ 2)
            elseif rarity == "RARE" then
                adjustedWeight = baseWeight * (rarityBoost ^ 1.5)
            elseif rarity == "UNCOMMON" then
                adjustedWeight = baseWeight * rarityBoost
            end
        end
        
        weights[i] = math.max(0.0001, adjustedWeight)
        totalWeight = totalWeight + weights[i]
    end
    
    return weights
end

-- Pick item from weighted table
local function pickWeightedItem(rng: Random, weights: {number}): number
    local total = 0
    for _, w in ipairs(weights) do
        total = total + w
    end
    
    local roll = rng:NextNumber() * total
    local cumulative = 0
    
    for i, w in ipairs(weights) do
        cumulative = cumulative + w
        if roll <= cumulative then
            return i
        end
    end
    
    return #weights -- Fallback to last item
end

-- Roll for loot in a specific cell
function LootService:RollCell(
    materialId: string,
    cellX: number,
    cellY: number,
    cellZ: number,
    seed: number,
    luckMultiplier: number?
): Types.LootDrop?
    
    luckMultiplier = luckMultiplier or 1.0
    
    -- Get material multiplier
    local materialMult = materialMultipliers[materialId] or 1.0
    
    -- Combined rarity boost
    local rarityBoost = materialMult * luckMultiplier
    
    -- Create deterministic RNG for this cell
    local rng = RNG.fromCell(cellX, cellY, cellZ, seed)
    
    -- First check: does this cell have loot?
    local dropChance = GameConfig.Loot.BASE_DROP_CHANCE * math.min(2, luckMultiplier)
    if rng:NextNumber() > dropChance then
        return nil
    end
    
    -- Second roll: what item?
    local weights = buildWeightedTable(rarityBoost)
    local itemIndex = pickWeightedItem(rng, weights)
    local itemDef = itemDefinitions[itemIndex]
    
    if not itemDef then
        return nil
    end
    
    -- Create loot drop
    local loot: Types.LootDrop = {
        id = itemDef.id,
        name = itemDef.name,
        rarity = itemDef.rarity,
        type = itemDef.type,
        value = itemDef.value,
        stats = itemDef.stats,
        effect = itemDef.effect,
        duration = itemDef.duration,
    }
    
    return loot
end

-- Roll for multiple cells at once (batch operation)
function LootService:RollCells(
    materialId: string,
    cells: {{x: number, y: number, z: number}},
    seed: number,
    luckMultiplier: number?
): {Types.LootDrop}
    
    local drops = {}
    
    for _, cell in ipairs(cells) do
        local loot = self:RollCell(
            materialId,
            cell.x,
            cell.y,
            cell.z,
            seed,
            luckMultiplier
        )
        
        if loot then
            table.insert(drops, loot)
        end
    end
    
    return drops
end

-- Get item definition by ID
function LootService:GetItemDefinition(itemId: string)
    for _, item in ipairs(itemDefinitions) do
        if item.id == itemId then
            return item
        end
    end
    return nil
end

-- Get all items of a specific type
function LootService:GetItemsByType(itemType: string): {{}}
    local items = {}
    for _, item in ipairs(itemDefinitions) do
        if item.type == itemType then
            table.insert(items, item)
        end
    end
    return items
end

-- Get all items of a specific rarity
function LootService:GetItemsByRarity(rarity: string): {{}}
    local items = {}
    for _, item in ipairs(itemDefinitions) do
        if item.rarity == rarity then
            table.insert(items, item)
        end
    end
    return items
end

-- Calculate sell value for items
function LootService:CalculateSellValue(items: {[string]: number}): number
    local total = 0
    
    for itemId, count in pairs(items) do
        local itemDef = self:GetItemDefinition(itemId)
        if itemDef and itemDef.value then
            total = total + (itemDef.value * count)
        end
    end
    
    return total
end

-- Get rarity color
function LootService:GetRarityColor(rarity: string): Color3
    return rarityWeights[rarity] and rarityWeights[rarity].color or Color3.new(1, 1, 1)
end

-- Get rarity value multiplier
function LootService:GetRarityMultiplier(rarity: string): number
    return rarityWeights[rarity] and rarityWeights[rarity].value_mult or 1
end

print("[LootService] Initialized")

return LootService