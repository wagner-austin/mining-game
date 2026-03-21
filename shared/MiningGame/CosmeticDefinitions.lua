--!strict
-- CosmeticDefinitions.lua (modular loader)
-- Loads category modules under MiningGame/Cosmetics and merges into a single ITEMS table.

local CosmeticDefinitions = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")

CosmeticDefinitions.ITEMS = {}

local function merge(dst: { [string]: any }, src: { [string]: any }?)
	if type(src) ~= "table" then
		return
	end
	for k, v in pairs(src) do
		dst[k] = v
	end
end

-- Static, explicit requires for analyzer-friendly loading
do
	local root = MiningGame:WaitForChild("Cosmetics")
	local Auras = require(root:WaitForChild("Auras"))
	local Trails = require(root:WaitForChild("Trails"))
	local Wings = require(root:WaitForChild("Wings"))
	local Head = require(root:WaitForChild("Head"))
	local Hand = require(root:WaitForChild("Hand"))

	merge(CosmeticDefinitions.ITEMS, Auras)
	merge(CosmeticDefinitions.ITEMS, Trails)
	merge(CosmeticDefinitions.ITEMS, Wings)
	merge(CosmeticDefinitions.ITEMS, Head)
	merge(CosmeticDefinitions.ITEMS, Hand)
end

-- Public API (unchanged)
function CosmeticDefinitions.Get(id: string)
	return CosmeticDefinitions.ITEMS[id]
end

function CosmeticDefinitions.GetByCategory(category: string): { [string]: any }
	local items = {}
	for id, item in pairs(CosmeticDefinitions.ITEMS) do
		if item.slot == category then
			items[id] = item
		end
	end
	return items
end

function CosmeticDefinitions.GetByRarity(rarity: string): { [string]: any }
	local items = {}
	for id, item in pairs(CosmeticDefinitions.ITEMS) do
		if item.rarity == rarity then
			items[id] = item
		end
	end
	return items
end

function CosmeticDefinitions.GetByEffect(effect: string): { [string]: any }
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
	for id in pairs(items) do
		table.insert(keys, id)
	end
	if #keys > 0 then
		local idx = Random.new():NextInteger(1, #keys)
		return items[keys[idx]]
	end
	return nil
end

return CosmeticDefinitions
