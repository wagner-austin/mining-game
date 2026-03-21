--!strict
-- ItemInsights.lua
-- Single source of item detail insights for UI popups (drop info, rarity, enhancements)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MG = ReplicatedStorage:WaitForChild("MiningGame")
local GameConfig = require(MG:WaitForChild("GameConfig"))
local ItemDefinitions = require(MG:WaitForChild("ItemDefinitions"))
local MaterialDefinitions = require(MG:WaitForChild("MaterialDefinitions"))

export type Insight = {
	id: string,
	name: string,
	type: string,
	slot: string?,
	rarity: string?,
	value: number?,
	icon: string?,
	enhanced: boolean?,
	perks: { [string]: any }?,
	baseDropChance: number?,
	rarityWeight: number?,
	rarityColor: Color3?,
	materialMultipliers: { { id: string, name: string, lootMultiplier: number } }?,
	sources: { string },
}

local ItemInsights = {}

local function rarityData(r: string?): (number?, Color3?)
	if not r then
		return nil, nil
	end
	local rar = GameConfig and GameConfig.Loot and GameConfig.Loot.RARITIES and GameConfig.Loot.RARITIES[r]
	if not rar then
		return nil, nil
	end
	return rar.weight, rar.color
end

local function listMaterials(): { { id: string, name: string, lootMultiplier: number } }
	local list = {}
	local mats = (GameConfig and GameConfig.CubeMaterials) or {}
	for _, m in ipairs(mats) do
		table.insert(list, { id = m.id, name = m.name, lootMultiplier = m.lootMultiplier or 1.0 })
	end
	table.sort(list, function(a, b)
		return (a.lootMultiplier or 1) > (b.lootMultiplier or 1)
	end)
	return list
end

local function determineSources(item: any): { string }
	local out = {}
	if not item then
		return out
	end

	-- Prefer specific terrain source for resources using TERRAIN_RESOURCE_MAP
	if item.type == "resource" then
		local map = GameConfig and GameConfig.Loot and GameConfig.Loot.TERRAIN_RESOURCE_MAP
		local byKey = map and map.byTerrainKey or {}
		local terrains = {}
		for terrainKey, id in pairs(byKey) do
			if id == item.id then
				table.insert(terrains, terrainKey)
			end
		end
		table.sort(terrains)
		if #terrains > 0 then
			-- Use first terrain display name directly (the UI label already says "Source")
			local tk = terrains[1]
			local md = MaterialDefinitions.Materials[tk]
			local display = (md and md.displayName) or (tk:sub(1, 1):upper() .. tk:sub(2))
			table.insert(out, display)
			-- Include any additional terrains as secondary sources
			for i = 2, #terrains do
				local tk2 = terrains[i]
				local md2 = MaterialDefinitions.Materials[tk2]
				local disp2 = (md2 and md2.displayName) or (tk2:sub(1, 1):upper() .. tk2:sub(2))
				table.insert(out, disp2)
			end
			return out
		end

		-- Exclusive resources tied to compositions/themes
		local exclusive = (item.meta and item.meta.exclusive) or (item.tags and item.tags.exclusive)
		if exclusive then
			table.insert(out, "Exclusive: Theme-based drop")
			return out
		end

		-- Fallback for general resources in weighted mode
		table.insert(out, "Any terrain")
		return out
	end

	if item.type == "cosmetic" then
		if GameConfig.Features and GameConfig.Features.COSMETICS_IN_LOOT then
			table.insert(out, "Rare drop while digging")
		end
		table.insert(out, "Purchasable in Shop (coins)")
		return out
	end

	if item.type == "consumable" then
		table.insert(out, "Usable item: grants temporary boosts")
		return out
	end

	if item.type == "pickaxe" then
		table.insert(out, "Equip to change tool stats/appearance")
		return out
	end

	return out
end

function ItemInsights.get(itemId: string): Insight?
	local it = ItemDefinitions.get(itemId)
	if not it then
		return nil
	end
	local w, c = rarityData(it.rarity)
	local icon
	do
		local m = it.meta
		if m and typeof(m) == "table" then
			local v = m.icon
			if typeof(v) == "string" then
				icon = v
			end
		end
	end
	local enhancedFlag = false
	do
		local m = it.meta
		if m and typeof(m) == "table" then
			local v = m.enhanced
			if v == true then
				enhancedFlag = true
			end
		end
	end
	local perks
	do
		local m = it.meta
		if m and typeof(m) == "table" then
			local v = m.perks
			if typeof(v) == "table" then
				perks = v
			end
		end
	end
	local mats = listMaterials()
	local base = GameConfig and GameConfig.Loot and GameConfig.Loot.BASE_DROP_CHANCE or nil
	local insight: Insight = {
		id = it.id,
		name = it.name or it.id,
		type = it.type,
		slot = it.slot,
		rarity = it.rarity,
		value = it.value,
		icon = icon,
		enhanced = (enhancedFlag and true) or nil,
		perks = perks or nil,
		baseDropChance = base,
		rarityWeight = w,
		rarityColor = c,
		materialMultipliers = mats,
		sources = determineSources(it),
	}
	return insight
end

return ItemInsights
