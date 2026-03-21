--!strict
-- ClientCashShop.lua
-- Normalizes and centralizes cash shop item/category schemas and utilities

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Remotes = require(MiningGame:WaitForChild("Remotes"))
local ClientRF = require(MiningGame:WaitForChild("ClientRF"))
local ItemDefinitions = require(MiningGame:WaitForChild("ItemDefinitions"))
local GameConfig = require(MiningGame:WaitForChild("GameConfig"))
local UI = MiningGame:WaitForChild("UI")
local UIUtils = require(UI:WaitForChild("UIUtils"))
local TextUtils = require(MiningGame:WaitForChild("TextUtils"))
local ClientError = require(MiningGame:WaitForChild("ClientError"))

export type ShopItem = {
	id: string, -- Unique shop entry id (often same as itemId)
	itemId: string?, -- Underlying ItemDefinitions id, if applicable
	name: string,
	type: string, -- cosmetic | product | bundle | consumable
	slot: string?, -- for cosmetics
	rarity: string?,
	icon: string?, -- rbxassetid://... or http(s)
	price: { coins: number?, robux: number? }?,
	value: number?, -- legacy numeric price source
	meta: any?,
	owned: boolean?,
	ownedCount: number?,
}

local ClientCashShop = {}

local function hasRF(name: string): boolean
	if not Remotes or not Remotes.RF then
		return false
	end
	-- Use rawget to check presence without violating strict dict typing
	return rawget(Remotes.RF, name) ~= nil
end

-- Robust coin price extraction from various shapes
function ClientCashShop.getCoinPrice(entry: any): number
	if entry == nil then
		return 0
	end
	local t = typeof(entry)
	if t == "number" then
		return entry
	end
	if t == "string" then
		local n = tonumber(entry)
		return n or 0
	end
	if t == "table" then
		if typeof(entry.coins) == "number" then
			return entry.coins
		end
		if typeof(entry.price) == "number" then
			return entry.price
		end
		if typeof(entry.value) == "number" then
			return entry.value
		end
	end
	return 0
end

function ClientCashShop.getRobuxPrice(entry: any): number
	if entry == nil then
		return 0
	end
	local t = typeof(entry)
	if t == "number" then
		return entry
	end
	if t == "table" then
		if typeof(entry.robux) == "number" then
			return entry.robux
		end
		if typeof(entry.price) == "number" then
			return entry.price
		end
	end
	return 0
end

local function coalesceIcon(icon: any): string?
	if typeof(icon) == "string" and icon ~= "" then
		return icon
	end
	return nil
end

local function normalizeEntry(raw: any): ShopItem
	local id = tostring(raw.id or raw.itemId or raw.productId or raw.name or "")
	local itemId = raw.itemId or raw.id
	local icon = coalesceIcon(raw.icon)
	local name = tostring(raw.name or id)
	local rarity = raw.rarity
	local slot = raw.slot
	local typ =
		tostring(raw.type or raw.category or (raw.robux and "product") or (raw.price and "cosmetic") or "cosmetic")
	local priceCoins = ClientCashShop.getCoinPrice(raw.price)
	if priceCoins == 0 then
		priceCoins = ClientCashShop.getCoinPrice(raw.value)
	end
	local priceRobux = ClientCashShop.getRobuxPrice(raw.price)

	-- If we can find the underlying item, enrich fields
	if itemId then
		local base = ItemDefinitions.get(itemId)
		if base then
			name = base.name or name
			if not icon then
				local m = base.meta
				if m and typeof(m) == "table" and typeof(m.icon) == "string" then
					icon = m.icon
				end
			end
			rarity = rarity or base.rarity
			slot = slot or base.slot
			if not priceCoins or priceCoins == 0 then
				priceCoins = ClientCashShop.getCoinPrice(base.value)
			end
			typ = base.type or typ
		end
	end
	-- Clean up display name (prefer TextUtils for items)
	if name == id or string.find(name, "_") or string.find(name, "%-") then
		name = TextUtils.prettifyItemName(id, { id = id, name = name })
	end

	local out: ShopItem = {
		id = id,
		itemId = itemId,
		name = name,
		type = typ,
		slot = slot,
		rarity = if rarity then tostring(rarity) else nil,
		icon = icon,
		price = if (priceCoins and priceCoins > 0) or (priceRobux and priceRobux > 0)
			then { coins = priceCoins, robux = priceRobux }
			else nil,
		value = raw.value,
		meta = raw,
	}
	-- Bubble up owned flags from server response when available
	if raw and typeof(raw) == "table" then
		if raw.owned ~= nil then
			out.owned = raw.owned
		end
		if raw.ownedCount ~= nil then
			out.ownedCount = tonumber(raw.ownedCount)
		end
	end
	return out
end

-- Get normalized cosmetic entries for sale. If server provides, use it; otherwise fallback to ItemDefinitions.
function ClientCashShop.getCosmeticCatalog(): { ShopItem }
	local items: { any } = {}
	if not hasRF("GetShopCatalog") then
		return items
	end
	local ok, res = ClientError.try("ClientCashShop.GetShopCatalog", function()
		return ClientRF.call("GetShopCatalog")
	end)
	if not ok or not res or not res.items then
		return items
	end
	local list = res.items :: { any }
	for _, raw in ipairs(list) do
		table.insert(items, normalizeEntry(raw))
	end
	-- Sorting is already handled within ItemDefinitions for cosmetics; ensure stable name sort if equal
	table.sort(items, function(a, b)
		local sa = tostring(a.slot or "z")
		local sb = tostring(b.slot or "z")
		if sa ~= sb then
			return sa < sb
		end
		local ra = tostring(a.rarity or "")
		local rb = tostring(b.rarity or "")
		if ra ~= rb then
			return ra < rb
		end
		return tostring(a.name) < tostring(b.name)
	end)
	return items
end

-- Normalized Robux product list (for buying coins)
function ClientCashShop.getRobuxProducts(): { any }
	local out = {}
	if not hasRF("GetPrices") then
		return out
	end
	local ok, res = ClientError.try("ClientCashShop.GetPrices", function()
		return ClientRF.call("GetPrices")
	end)
	if not ok or not res or not res.prices then
		return out
	end
	local prices = res.prices :: { [string]: any }
	for id, prod in pairs(prices) do
		-- Only include configured developer products (server exposes only those in GameConfig)
		table.insert(out, {
			id = tostring(id),
			name = UIUtils.humanize(prod.name or tostring(id)),
			price = { robux = ClientCashShop.getRobuxPrice(prod) },
			icon = prod.icon, -- optional
			type = "product",
			slot = "coins",
		})
	end
	table.sort(out, function(a, b)
		return tostring(a.name) < tostring(b.name)
	end)
	return out
end

-- Is a developer product configured in GameConfig (has a non-zero productId)?
function ClientCashShop.isProductConfigured(id: string): boolean
	local list = (GameConfig.Monetization and GameConfig.Monetization.PRODUCTS) or {}
	for _, prod in ipairs(list) do
		if prod.id == id then
			return type(prod.productId) == "number" and prod.productId > 0
		end
	end
	return false
end

return ClientCashShop
