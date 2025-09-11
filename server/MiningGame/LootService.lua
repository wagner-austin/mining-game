--!strict
--[[
    LootService.server.lua
    Deterministic loot generation system using cell coordinates as seeds.
    
    Features:
    - Deterministic drops based on cell position
    - Material-based loot multipliers
    - Luck stat integration
    - Weighted rarity system
    - Multi-cell batch processing
    - Composition-based drop modifiers
    - Exclusive item support
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(Shared:WaitForChild("Logger"))
local log = Logger.new("LootService")

local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Types = require(Shared:WaitForChild("Types"))
local RNG = require(Shared:WaitForChild("Utils"):WaitForChild("RNG"))
local CubeThemes = require(Shared:WaitForChild("CubeThemes"))
local CosmeticDefinitions = require(Shared:WaitForChild("CosmeticDefinitions"))

local ServiceValidator = require(Shared:WaitForChild("ServiceValidator"))

-- Services (injected via Init)
local CompositionService

local LootService = {}

type ItemDef = {
    id: string,
    name: string?,
    type: string,
    rarity: string?,
    value: number?,
    stats: {[string]: number}?,
    effect: string?,
    duration: number?,
    _adjustedWeight: number?,
}

type RollCellOpts = {
    chanceMult: number?,
    rarityBoost: number?,
    specificBoosts: {[string]: number}?,
    exclusiveSet: {[string]: boolean}?,
}

-- Initialize with DI container
function LootService:Init(container)
    -- Optional dependency - only used for drop modifiers
    CompositionService = ServiceValidator.tryGet(container, "CompositionService", {"GetActiveComposition"})
    log:info("Initialized with dependencies")
end

-- Cache for weighted tables  
local rarityWeights = GameConfig.Loot.RARITIES
local baseItems = GameConfig.Loot.ITEMS
local itemDefinitions: {ItemDef} = {}  -- Will contain base + cosmetics
local itemById: {[string]: ItemDef} = {}  -- O(1) lookup map
local materialMultipliers = {}

-- Helper to add item definition
local function addItemDef(def: ItemDef)
    if not def.id then return end
    table.insert(itemDefinitions, def)
    itemById[def.id] = def
end

-- Add base items from GameConfig
for _, def in ipairs(baseItems) do
    addItemDef(def)
end

-- Add cosmetic items from CosmeticDefinitions (with reduced weight, if enabled)
if GameConfig.Features.COSMETICS_ENABLED and GameConfig.Features.COSMETICS_IN_LOOT then
    local COSMETIC_WEIGHT_MULT = GameConfig.Features.DEBUG_HIGH_COSMETIC_RATE and 1.0 
        or (GameConfig.Features.COSMETIC_WEIGHT_MULT or 0.1)
    
    for id, def in pairs(CosmeticDefinitions.ITEMS) do
        def.id = def.id or id
        def.type = def.type or "cosmetic"
        -- Apply weight reduction for cosmetics
        if def.rarity and rarityWeights[def.rarity] then
            def._adjustedWeight = rarityWeights[def.rarity].weight * COSMETIC_WEIGHT_MULT
        end
        addItemDef(def)
    end
    
    -- Count cosmetics loaded
    local cosmeticCount = 0
    for _ in pairs(CosmeticDefinitions.ITEMS) do
        cosmeticCount = cosmeticCount + 1
    end
    log:info("Cosmetics loaded: %d items, weight multiplier: %.2f", 
        cosmeticCount, COSMETIC_WEIGHT_MULT)
end

-- Build material multiplier lookup
for _, material in ipairs(GameConfig.CubeMaterials) do
    materialMultipliers[material.id] = material.lootMultiplier
end

-- Build weighted loot table
local function buildWeightedTable(rarityBoost: number): {number}
    local weights = {}
    
    for i, item in ipairs(itemDefinitions) do
        local rarity = item.rarity
        -- Use item-specific weight if available (for cosmetics), otherwise use rarity weight
        local baseWeight = item._adjustedWeight 
            or (rarity and rarityWeights[rarity] and rarityWeights[rarity].weight)
            or 0.0001
        
        -- Apply rarity boost (higher boost = better items more likely)
        local adjustedWeight = baseWeight
        if rarityBoost > 1 and rarity then
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

--[[
    Roll for loot in a specific cell using deterministic RNG.
    Each cell has a consistent loot result based on its coordinates.
    
    @param materialId: string - The cube's material ID for multipliers
    @param cellX: number - Cell X coordinate
    @param cellY: number - Cell Y coordinate  
    @param cellZ: number - Cell Z coordinate
    @param seed: number - Additional seed value (usually player ID)
    @param luckMultiplier: number? - Player's luck stat multiplier
    @param opts: {chanceMult: number?, rarityBoost: number?, specificBoosts: {[string]: number}?, exclusiveSet: {[string]: boolean}?}? - Composition modifiers
    @return Types.LootDrop? - The loot drop if successful, nil otherwise
]]
function LootService:RollCell(
    materialId: string,
    cellX: number,
    cellY: number,
    cellZ: number,
    seed: number,
    luckMultiplier: number?,
    opts: {chanceMult: number?, rarityBoost: number?, specificBoosts: {[string]: number}?, exclusiveSet: {[string]: boolean}?}?
): Types.LootDrop?
    
    luckMultiplier = luckMultiplier or 1.0
    opts = opts or {}
    
    -- Get material multiplier
    local materialMult = materialMultipliers[materialId] or 1.0
    
    -- Combined rarity boost (use override from composition if present)
    local rarityBoost = (opts.rarityBoost or materialMult) * luckMultiplier
    
    -- Create deterministic RNG for this cell
    local rng = RNG.fromCell(cellX, cellY, cellZ, seed)
    
    -- First check: does this cell have loot?
    local baseChance = GameConfig.Loot.BASE_DROP_CHANCE
    local chanceMult = opts.chanceMult or 1.0
    local dropChance = baseChance * chanceMult * math.min(2, luckMultiplier)
    -- Clamp to avoid always-hit and keep RNG meaningful
    dropChance = math.clamp(dropChance, 0, 0.9999)
    
    if rng:NextNumber() > dropChance then
        return nil
    end
    
    -- DEBUG: Force rarity if configured
    if GameConfig.Features.DEBUG_FORCE_RARITY then
        local forcedRarity = GameConfig.Features.DEBUG_FORCE_RARITY
        
        -- Helper to check if item type is allowed
        local function isAllowed(def)
            if def.type == "cosmetic" and not GameConfig.Features.COSMETICS_IN_LOOT then 
                return false 
            end
            return true
        end
        
        local rarityItems = {}
        for i, def in ipairs(itemDefinitions) do
            if def.rarity == forcedRarity and isAllowed(def) then
                table.insert(rarityItems, i)
            end
        end
        
        if #rarityItems > 0 then
            local itemIndex = rarityItems[rng:NextInteger(1, #rarityItems)]
            local pickedItem = itemDefinitions[itemIndex]
            
            -- Return properly typed LootDrop
            local loot: Types.LootDrop = {
                id       = pickedItem.id,
                name     = pickedItem.name,
                rarity   = pickedItem.rarity,
                type     = pickedItem.type,
                value    = pickedItem.value,
                stats    = pickedItem.stats,
                effect   = pickedItem.effect,
                duration = pickedItem.duration,
                cellX    = cellX,
                cellY    = cellY,
                cellZ    = cellZ,
            }
            return loot
        end
    end
    
    -- Second roll: what item?
    local weights = buildWeightedTable(rarityBoost)
    
    -- Apply specific item boosts and enforce exclusive items
    for i, itemDef in ipairs(itemDefinitions) do
        -- Apply specific boosts
        if opts.specificBoosts and opts.specificBoosts[itemDef.id] then
            weights[i] = weights[i] * opts.specificBoosts[itemDef.id]
        end
        
        -- Hard gate exclusive items: only available if composition provides them
        if itemDef.exclusive and (not opts.exclusiveSet or not opts.exclusiveSet[itemDef.id]) then
            weights[i] = 0 -- Cannot drop unless composition includes it
        end
        
        -- Boost exclusive items when they are allowed
        if opts.exclusiveSet and opts.exclusiveSet[itemDef.id] then
            weights[i] = weights[i] * 2.0 -- Extra weight for exclusive drops
        end
    end
    
    -- Guard against zero-weight scenarios
    local totalWeight = 0
    for _, w in ipairs(weights) do 
        totalWeight = totalWeight + w 
    end
    if totalWeight <= 0 then 
        return nil 
    end
    
    local itemIndex = pickWeightedItem(rng, weights)
    local itemDef = itemDefinitions[itemIndex]
    
    if not itemDef then
        return nil
    end
    
    -- Create loot drop with cell position
    local loot: Types.LootDrop = {
        id = itemDef.id,
        name = itemDef.name,
        rarity = itemDef.rarity,
        type = itemDef.type,
        value = itemDef.value,
        stats = itemDef.stats,
        effect = itemDef.effect,
        duration = itemDef.duration,
        -- Store the cell that dropped this loot
        cellX = cellX,
        cellY = cellY,
        cellZ = cellZ,
    }
    
    return loot
end

--[[
    Roll for loot in multiple cells at once for efficiency.
    Processes batch operations with consistent deterministic results.
    
    @param materialId: string - The cube's material ID
    @param cells: {{x: number, y: number, z: number}} - Array of cell coordinates
    @param seed: number - Additional seed value
    @param luckMultiplier: number? - Player's luck stat multiplier
    @param compositionInfo: {miner: Player?, ownerId: number?, materialKey: string?, compositionId: string?}? - Composition context
    @return {Types.LootDrop} - Array of successful loot drops
]]
function LootService:RollCells(
    materialId: string,
    cells: {{x: number, y: number, z: number}},
    seed: number,
    luckMultiplier: number?,
    compositionInfo: {miner: Player?, ownerId: number?, materialKey: string?, compositionId: string?}?
): {Types.LootDrop}
    
    local drops = {}
    
    -- Build composition-driven options
    local chanceMult = 1.0
    local rarityBoostOverride = nil
    local specificBoosts = nil
    local exclusiveSet = nil
    
    -- Try preset compositions first
    local mods = nil
    if compositionInfo and compositionInfo.compositionId then
        -- Theme-based system: compositionId is actually themeId
        local theme = CubeThemes.GetTheme(compositionInfo.compositionId)
        if theme then
            -- Apply theme drop boost
            if theme.dropBoost then
                chanceMult = chanceMult * theme.dropBoost
            end
            
            -- Theme-based modifiers (simplified from old material system)
            mods = {
                rarityBoost = theme.dropBoost or 1.0
            }
            
            -- Apply co-op bonuses (themes could have shareBonus in future)
            if compositionInfo.miner and compositionInfo.ownerId then
                if compositionInfo.miner.UserId ~= compositionInfo.ownerId then
                    -- Co-op bonus could be added to themes later
                    -- if theme.shareBonus then
                    --     chanceMult = chanceMult * (1 + theme.shareBonus)
                    -- end
                    -- if theme.exclusive then
                    --     chanceMult = chanceMult * 0.75 -- Penalty for non-owners
                    -- end
                end
            end
        end
    end
    
    -- Fall back to custom mix modifiers if no preset composition found
    if (not mods) and compositionInfo and compositionInfo.ownerId and CompositionService then
        local owner = Players:GetPlayerByUserId(compositionInfo.ownerId)
        if owner then
            local active = CompositionService:GetActiveComposition(owner)
            if active and active.dropModifiers then
                mods = {
                    rarityBonus = active.dropModifiers.rarityBoost,
                    specificItems = active.dropModifiers.specificItems,
                    exclusiveItems = active.dropModifiers.exclusiveItems,
                }
            end
        end
    end
    
    -- Apply modifiers if found
    if mods then
        rarityBoostOverride = mods.rarityBonus
        
        -- Build specific item boost map
        if mods.specificItems then
            specificBoosts = {}
            for _, itemId in ipairs(mods.specificItems) do
                specificBoosts[itemId] = 1.5 -- 50% boost
            end
        end
        
        -- Build exclusive item set
        if mods.exclusiveItems then
            exclusiveSet = {}
            for _, itemId in ipairs(mods.exclusiveItems) do
                exclusiveSet[itemId] = true
            end
        end
    end
    
    -- Build opts to pass to RollCell
    local opts = {
        chanceMult = chanceMult,
        rarityBoost = rarityBoostOverride,
        specificBoosts = specificBoosts,
        exclusiveSet = exclusiveSet,
    }
    
    -- Roll each cell with the composed options
    for _, cell in ipairs(cells) do
        local loot = self:RollCell(
            materialId,
            cell.x,
            cell.y,
            cell.z,
            seed,
            luckMultiplier,
            opts
        )
        
        if loot then
            table.insert(drops, loot)
        end
    end
    
    return drops
end

-- Get item definition by ID (O(1) lookup)
function LootService:GetItemDefinition(itemId: string): ItemDef?
    return itemById[itemId]
end

-- Get all items of a specific type
function LootService:GetItemsByType(itemType: string): {ItemDef}
    local items = {}
    for _, item in ipairs(itemDefinitions) do
        if item.type == itemType then
            table.insert(items, item)
        end
    end
    return items
end

-- Get all items of a specific rarity
function LootService:GetItemsByRarity(rarity: string): {ItemDef}
    local items = {}
    for _, item in ipairs(itemDefinitions) do
        if item.rarity == rarity then
            table.insert(items, item)
        end
    end
    return items
end

-- Calculate sell value for items (O(1) lookup, excludes cosmetics)
function LootService:CalculateSellValue(items: {[string]: number}): number
    local total = 0
    
    for itemId, count in pairs(items) do
        local itemDef = itemById[itemId]  -- Direct O(1) lookup
        if itemDef and itemDef.value and itemDef.type ~= "cosmetic" then
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

log:info("Initialized")

return LootService
