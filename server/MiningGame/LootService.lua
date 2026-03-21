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
local DigPerformance = require(script.Parent.DigPerformance)

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
	stats: { [string]: number }?,
	effect: string?,
	duration: number?,
	jumps: number?,
	exclusive: boolean?,
	_adjustedWeight: number?,
}

type RollCellOpts = {
	chanceMult: number?,
	rarityBoost: number?,
	specificBoosts: { [string]: number }?,
	exclusiveSet: { [string]: boolean }?,
	terrainKey: string?,
}

-- Initialize with DI container
function LootService:Init(container)
	-- Optional dependency - only used for drop modifiers
	CompositionService = ServiceValidator.tryGet(container, "CompositionService", { "GetActiveComposition" })
	log:info("Initialized with dependencies")
end

-- Cache for weighted tables
local rarityWeights = GameConfig.Loot.RARITIES
local baseItems = GameConfig.Loot.ITEMS
local itemDefinitions: { ItemDef } = {} -- Will contain base + cosmetics
local itemById: { [string]: ItemDef } = {} -- O(1) lookup map
local materialMultipliers = {}
local terrainResourceMapByMaterialId = (
	GameConfig
	and GameConfig.Loot
	and GameConfig.Loot.TERRAIN_RESOURCE_MAP
	and GameConfig.Loot.TERRAIN_RESOURCE_MAP.byMaterialId
) or {}
local terrainResourceMapByTerrainKey = (
	GameConfig
	and GameConfig.Loot
	and GameConfig.Loot.TERRAIN_RESOURCE_MAP
	and GameConfig.Loot.TERRAIN_RESOURCE_MAP.byTerrainKey
) or {}

-- Helper to add item definition
local function addItemDef(def: ItemDef)
	if not def.id then
		return
	end
	table.insert(itemDefinitions, def)
	itemById[def.id] = def
end

-- Add base items from GameConfig
for _, def in ipairs(baseItems) do
	-- Allow per-item override via dropWeight on the definition
	local dw = (def :: any).dropWeight
	local entry: ItemDef = (table.clone(def) :: any) :: ItemDef
	if type(dw) == "number" then
		entry._adjustedWeight = dw
	end
	addItemDef(entry)
end

-- Add cosmetic items from CosmeticDefinitions (with reduced weight, if enabled)
if GameConfig.Features.COSMETICS_ENABLED and GameConfig.Features.COSMETICS_IN_LOOT then
	local COSMETIC_WEIGHT_MULT = GameConfig.Features.DEBUG_HIGH_COSMETIC_RATE and 1.0
		or (GameConfig.Features.COSMETIC_WEIGHT_MULT or 0.1)

	for id, def in pairs(CosmeticDefinitions.ITEMS) do
		local entry: ItemDef = (table.clone(def) :: any) :: ItemDef
		entry.id = entry.id or id
		entry.type = entry.type or "cosmetic"
		-- Per-item override takes precedence when present
		local dw = (def :: any).dropWeight :: any
		if type(dw) == "number" then
			entry._adjustedWeight = dw
		else
			-- Apply weight reduction for cosmetics
			if entry.rarity and rarityWeights[entry.rarity] then
				entry._adjustedWeight = rarityWeights[entry.rarity].weight * COSMETIC_WEIGHT_MULT
			end
		end
		addItemDef(entry)
	end

	-- Count cosmetics loaded
	local cosmeticCount = 0
	for _ in pairs(CosmeticDefinitions.ITEMS) do
		cosmeticCount = cosmeticCount + 1
	end
	log:info("Cosmetics loaded: %d items, weight multiplier: %.2f", cosmeticCount, COSMETIC_WEIGHT_MULT)
end

-- Build material multiplier lookup
for _, material in ipairs(GameConfig.CubeMaterials) do
	materialMultipliers[material.id] = material.lootMultiplier
end

-- Build weighted loot table
local function buildWeightedTable(rarityBoost: number): { number }
	local weights = {}
	local typeMult = (GameConfig and GameConfig.Loot and GameConfig.Loot.TYPE_MULTIPLIER) or {}

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

		-- Apply optional type multiplier to adjust overall share per type
		local t = tostring(item.type or "")
		local tm = typeMult[t] or 1.0
		weights[i] = math.max(0.0001, adjustedWeight * tm)
	end

	return weights
end

-- Pick item from weighted table
-- pickWeightedItem removed (unused); fast variant below is used

-- Fast picker using precomputed total
local function pickWeightedItemFast(rng: Random, weights: { number }, total: number): number
	if total <= 0 then
		return 0
	end
	local roll = rng:NextNumber() * total
	local cumulative = 0
	for i, w in ipairs(weights) do
		cumulative = cumulative + w
		if roll <= cumulative then
			return i
		end
	end
	return #weights
end

-- Build a per-dig weighted context once, applying the same adjustments the per-cell path does.
local function buildLootContext(
	materialId: string,
	luckMultiplier: number,
	opts: RollCellOpts
): (
	{ weights: { number }, total: number, aliasProb: { number }?, aliasAlias: { number }? }
)
	luckMultiplier = luckMultiplier or 1.0
	opts = opts or {}

	-- Combined rarity boost (use override from composition if present)
	local materialMult = materialMultipliers[materialId] or 1.0
	local rarityBoost = ((opts.rarityBoost or materialMult) or 1.0) * (luckMultiplier or 1.0)

	-- Start from base weighted table (already applies TYPE_MULTIPLIER)
	local weights = buildWeightedTable(rarityBoost)

	-- Resource gating: prefer terrain key (dominant voxel material) when provided
	do
		local mappedId = nil
		local tk = opts.terrainKey
		if tk and type(tk) == "string" and terrainResourceMapByTerrainKey and terrainResourceMapByTerrainKey[tk] then
			mappedId = terrainResourceMapByTerrainKey[tk]
		else
			mappedId = terrainResourceMapByMaterialId and terrainResourceMapByMaterialId[materialId]
		end
		if mappedId then
			for i, itemDef in ipairs(itemDefinitions) do
				if itemDef.type == "resource" and itemDef.id ~= mappedId then
					weights[i] = 0
				end
			end
		end
	end

	-- Apply specific item boosts and exclusive item rules
	for i, itemDef in ipairs(itemDefinitions) do
		if opts.specificBoosts and opts.specificBoosts[itemDef.id] then
			weights[i] = weights[i] * opts.specificBoosts[itemDef.id]
		end
		if itemDef.exclusive and (not opts.exclusiveSet or not opts.exclusiveSet[itemDef.id]) then
			weights[i] = 0
		end
		if opts.exclusiveSet and opts.exclusiveSet[itemDef.id] then
			weights[i] = weights[i] * 2.0
		end
	end

	local total = 0
	for _, w in ipairs(weights) do
		total += w
	end

	-- Build alias table for O(1) picks if we have any mass
	local n = #weights
	if total > 0 and n > 0 then
		local scaled: { number } = table.create(n, 0)
		local prob: { number } = table.create(n, 1)
		local alias: { number } = table.create(n, 1)
		local small: { number } = {}
		local large: { number } = {}
		local scale = n / total
		for i = 1, n do
			local v = (weights[i] or 0) * scale
			scaled[i] = v
			if v < 1 then
				table.insert(small, i)
			else
				table.insert(large, i)
			end
		end
		while #small > 0 and #large > 0 do
			local l = table.remove(small) :: number
			local g = table.remove(large) :: number
			prob[l] = scaled[l]
			alias[l] = g
			scaled[g] = (scaled[g] + scaled[l]) - 1
			if scaled[g] < 1 then
				table.insert(small, g)
			else
				table.insert(large, g)
			end
		end
		for _, i in ipairs(large) do
			prob[i] = 1
			alias[i] = i
		end
		for _, i in ipairs(small) do
			prob[i] = 1
			alias[i] = i
		end
		return { weights = weights, total = total, aliasProb = prob, aliasAlias = alias }
	end
	return { weights = weights, total = total }
end

-- Legacy per-cell RollCell removed; selection uses optimized per-dig context in RollCells

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
	cells: { { x: number, y: number, z: number } },
	seed: number,
	luckMultiplier: number?,
	compositionInfo: {
		miner: Player?,
		ownerId: number?,
		materialKey: string?,
		compositionId: string?,
		terrainKey: string?,
	}?
): { Types.LootDrop }
	local drops = {}

	-- Build composition-driven options
	local chanceMult = 1.0
	local rarityBoostOverride = nil
	local specificBoosts = nil
	local exclusiveSet = nil

	-- Try preset compositions first
	local mods: { rarityBoost: number?, specificItems: { string }?, exclusiveItems: { string }? }? = nil
	if compositionInfo and compositionInfo.compositionId then
		-- Theme-based system: compositionId is actually themeId
		local theme = CubeThemes.GetTheme(compositionInfo.compositionId)
		if theme then
			-- Apply theme drop boost
			if theme.dropBoost then
				chanceMult = chanceMult * theme.dropBoost
			end

			-- Theme-based modifiers (simplified from old material system)
			mods = { rarityBoost = theme.dropBoost or 1.0 }

			-- Apply co-op bonuses (themes could have shareBonus in future)
			-- Future: apply co-op modifiers when applicable
		end
	end

	-- Fall back to custom mix modifiers if no preset composition found
	if (not mods) and compositionInfo and compositionInfo.ownerId and CompositionService then
		local owner = Players:GetPlayerByUserId(compositionInfo.ownerId)
		if owner then
			local active = CompositionService:GetActiveComposition(owner)
			if active and active.dropModifiers then
				mods = {
					rarityBoost = active.dropModifiers.rarityBoost,
					specificItems = active.dropModifiers.specificItems,
					exclusiveItems = active.dropModifiers.exclusiveItems,
				}
			end
		end
	end

	-- Apply modifiers if found
	if mods then
		rarityBoostOverride = mods.rarityBoost

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

	-- Build opts to pass to RollCell / context builder
	local opts = {
		chanceMult = chanceMult,
		rarityBoost = rarityBoostOverride,
		specificBoosts = specificBoosts,
		exclusiveSet = exclusiveSet,
	}
	if compositionInfo and compositionInfo.terrainKey then
		opts.terrainKey = compositionInfo.terrainKey
	end

	local ctx
	DigPerformance.measureSection("LootContextBuild", function()
		ctx = buildLootContext(materialId, luckMultiplier or 1.0, opts)
	end)
	local baseChance = GameConfig.Loot.BASE_DROP_CHANCE
	local luck = math.max(0, luckMultiplier or 1.0)
	local cappedLuck = math.min(2, luck)
	local dropChance = math.clamp(baseChance * chanceMult * cappedLuck, 0, 0.9999)
	DigPerformance.measureSection("LootPickLoop", function()
		local useAlias = (ctx.aliasProb ~= nil and ctx.aliasAlias ~= nil)
		for _, cell in ipairs(cells) do
			local rng = RNG.fromCell(cell.x, cell.y, cell.z, seed)
			if rng:NextNumber() <= dropChance then
				local idx
				if useAlias then
					local ap = ctx.aliasProb :: { number }
					local al = ctx.aliasAlias :: { number }
					local n = #ap
					local col = rng:NextInteger(1, n)
					local coin = rng:NextNumber()
					if coin < ap[col] then
						idx = col
					else
						idx = al[col]
					end
				else
					idx = pickWeightedItemFast(rng, ctx.weights, ctx.total)
				end
				local itemDef = itemDefinitions[idx]
				if itemDef then
					local loot: Types.LootDrop = {
						id = itemDef.id,
						name = itemDef.name or itemDef.id,
						rarity = itemDef.rarity or "COMMON",
						type = itemDef.type,
						value = itemDef.value,
						stats = itemDef.stats,
						effect = itemDef.effect,
						duration = itemDef.duration,
						cellX = cell.x,
						cellY = cell.y,
						cellZ = cell.z,
					}
					table.insert(drops, loot)
				end
			end
		end
	end)

	return drops
end

-- Get item definition by ID (O(1) lookup)
function LootService:GetItemDefinition(itemId: string): ItemDef?
	return itemById[itemId]
end

-- Get all items of a specific type
function LootService:GetItemsByType(itemType: string): { ItemDef }
	local items = {}
	for _, item in ipairs(itemDefinitions) do
		if item.type == itemType then
			table.insert(items, item)
		end
	end
	return items
end

-- Get all items of a specific rarity
function LootService:GetItemsByRarity(rarity: string): { ItemDef }
	local items = {}
	for _, item in ipairs(itemDefinitions) do
		if item.rarity == rarity then
			table.insert(items, item)
		end
	end
	return items
end

-- Calculate sell value for items (O(1) lookup, excludes cosmetics)
function LootService:CalculateSellValue(items: { [string]: number }): number
	local total = 0

	for itemId, count in pairs(items) do
		local itemDef = itemById[itemId] -- Direct O(1) lookup
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
