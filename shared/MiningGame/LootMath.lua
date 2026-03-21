--!strict
-- LootMath.lua
-- Deterministic, client-safe reproduction of server loot math to compute per-dig drop rates.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MG = ReplicatedStorage:WaitForChild("MiningGame")
local GameConfig = require(MG:WaitForChild("GameConfig"))
local ItemDefinitions = require(MG:WaitForChild("ItemDefinitions"))
-- local CosmeticDefinitions = require(MG:WaitForChild("CosmeticDefinitions"))

export type Context = {
	materialId: string?,
	terrainKey: string?,
	luckMultiplier: number?, -- 1.0..2.0 typically; server caps at 2 in first roll
	chanceMult: number?, -- theme dropBoost influences this on server
	rarityBoostOverride: number?, -- theme rarity boost override (rarely used)
	specificBoosts: { [string]: number }?,
	exclusiveSet: { [string]: boolean }?,
	size: number?, -- dig radius half-extent in cells (1 => 3x3x3)
	cells: number?, -- override total cells per dig
}

local LootMath = {}
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

local function _materialMult(materialId: string?): number
	local mats = GameConfig and GameConfig.CubeMaterials or {}
	local id = materialId or (mats[1] and mats[1].id) or "tier1"
	for _, m in ipairs(mats) do
		if m.id == id then
			return m.lootMultiplier or 1.0
		end
	end
	return 1.0
end

local function _baseWeightFor(item: any): number
	local rarities = GameConfig and GameConfig.Loot and GameConfig.Loot.RARITIES or {}
	-- Per-item override from definitions
	if item and item.meta and type(item.meta.dropWeight) == "number" then
		return item.meta.dropWeight
	end
	-- Server applies a cosmetic weight multiplier when including cosmetics in loot
	if item and item.type == "cosmetic" then
		local w = (item.meta and item.meta._adjustedWeight) or nil
		if w then
			return w
		end
		local r = item.rarity and rarities[item.rarity]
		local mult = 1.0
		if GameConfig.Features.COSMETICS_ENABLED and GameConfig.Features.COSMETICS_IN_LOOT then
			mult = (GameConfig.Features.DEBUG_HIGH_COSMETIC_RATE and 1.0)
				or (GameConfig.Features.COSMETIC_WEIGHT_MULT or 0.1)
		end
		return ((r and r.weight) or 0.0001) * mult
	end
	local r = item and item.rarity and rarities[item.rarity]
	return (r and r.weight) or 0.0001
end

local function _applyRarityBoost(base: number, rarity: string?, rarityBoost: number): number
	if (rarityBoost or 1.0) <= 1 or not rarity then
		return base
	end
	if rarity == "MYTHIC" then
		return base * (rarityBoost ^ 3)
	elseif rarity == "LEGENDARY" then
		return base * (rarityBoost ^ 2.5)
	elseif rarity == "EPIC" then
		return base * (rarityBoost ^ 2)
	elseif rarity == "RARE" then
		return base * (rarityBoost ^ 1.5)
	elseif rarity == "UNCOMMON" then
		return base * rarityBoost
	end
	return base
end

local function _finalWeight(
	item: any,
	rarityBoost: number,
	specificBoosts: { [string]: number }?,
	exclusiveSet: { [string]: boolean }?
): number
	local w = _baseWeightFor(item)
	w = _applyRarityBoost(w, item.rarity, rarityBoost)
	w = math.max(0.0001, w)
	if specificBoosts and specificBoosts[item.id] then
		w = w * specificBoosts[item.id]
	end
	local exclusive = (item.meta and item.meta.exclusive) or (item.tags and item.tags.exclusive) or false
	if exclusive then
		if not (exclusiveSet and exclusiveSet[item.id]) then
			return 0 -- hard gate when not allowed
		else
			w = w * 2.0 -- boost when allowed
		end
	end
	-- Apply optional type multiplier for selection share balancing
	local typeMult = (GameConfig and GameConfig.Loot and GameConfig.Loot.TYPE_MULTIPLIER) or {}
	local tm = typeMult[tostring(item.type or "")] or 1.0
	w = w * tm
	return w
end

-- Compose the same item list the server uses for weights
local function _buildItemList(): { any }
	local items = {}
	for _, it in ipairs(ItemDefinitions.all()) do
		if it.type == "cosmetic" then
			if GameConfig.Features.COSMETICS_ENABLED and GameConfig.Features.COSMETICS_IN_LOOT then
				table.insert(items, it)
			end
		else
			table.insert(items, it)
		end
	end
	return items
end

-- Compute normalized pick probability given a rarity boost and modifiers
local function _pickProbabilityById(rarityBoost: number, ctx: Context): { [string]: number }
	local list = _buildItemList()
	local weights = {}
	local total = 0
	for _, it in ipairs(list) do
		local w = _finalWeight(it, rarityBoost, ctx.specificBoosts, ctx.exclusiveSet)
		-- Server gates resources to a single mapped id per terrain/material in all modes.
		if it.type == "resource" then
			local mappedId = nil
			local tk = tostring(ctx.terrainKey or "")
			if tk ~= "" and terrainResourceMapByTerrainKey[tk] then
				mappedId = terrainResourceMapByTerrainKey[tk]
			else
				local matId = tostring(ctx.materialId or "")
				mappedId = terrainResourceMapByMaterialId[matId]
			end
			if mappedId and it.id ~= mappedId then
				w = 0
			end
		end
		weights[it.id] = w
		total += w
	end
	local probs = {}
	if total <= 0 then
		return probs
	end
	for id, w in pairs(weights) do
		probs[id] = w / total
	end
	return probs
end

local function _dropChance(ctx: Context): number
	local baseChance = (GameConfig and GameConfig.Loot and GameConfig.Loot.BASE_DROP_CHANCE) or 0.0
	local chanceMult = ctx.chanceMult or 1.0
	local luck = math.max(0, ctx.luckMultiplier or 1.0)
	local cappedLuck = math.min(2, luck) -- server caps luck at 2.0 in first roll
	local p = baseChance * chanceMult * cappedLuck
	return math.clamp(p, 0, 0.9999)
end

-- Compute per-dig drop probability for a specific item id given a context
function LootMath.dropRatePerDig(itemId: string, ctx: Context?): number
	local c: Context = if ctx then ctx else {} :: Context
	local anyDrop = _dropChance(c)
	local luck = c.luckMultiplier or 1.0
	local matMult = _materialMult(c.materialId)
	local rarityBoost = (c.rarityBoostOverride or matMult) * luck
	local pickProbs = _pickProbabilityById(rarityBoost, c)
	local pick = pickProbs[itemId] or 0
	return anyDrop * pick
end

-- Compute per-dig drop probabilities for all items given a context
function LootMath.allDropRates(ctx: Context?): { [string]: number }
	local c: Context = if ctx then ctx else {} :: Context
	local anyDrop = _dropChance(c)
	local luck = c.luckMultiplier or 1.0
	local matMult = _materialMult(c.materialId)
	local rarityBoost = (c.rarityBoostOverride or matMult) * luck
	local pickProbs = _pickProbabilityById(rarityBoost, c)
	local out = {}
	for id, prob in pairs(pickProbs) do
		out[id] = anyDrop * prob
	end
	return out
end

local function _cellsPerDig(size: number?): number
	local s = math.max(0, math.floor(size or 1))
	local edge = (2 * s + 1)
	return edge * edge * edge
end

-- Per-dig probability (at least one) for a given item across multiple cells.
-- Exact independence formula: P(item ≥ 1) = 1 - (1 - p_cell)^cells
function LootMath.dropRatePerDigAction(itemId: string, ctx: Context?): number
	local c: Context = if ctx then ctx else {} :: Context
	local pCell = LootMath.dropRatePerDig(itemId, c) or 0
	local cells = c.cells or _cellsPerDig(c.size or 1)
	local none = (1 - pCell) ^ math.max(0, cells)
	return 1 - none
end

return LootMath
