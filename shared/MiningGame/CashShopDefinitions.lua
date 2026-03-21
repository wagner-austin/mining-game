--!strict
-- CashShopDefinitions.lua
-- Curated, data-driven definitions for the Cash Shop catalog
-- Keep this lightweight: it references ItemDefinitions (via itemId) instead of duplicating item data

-- Schema:
-- COSMETICS: { { itemId: string, price: number?, icon: string?, featured: boolean?, limitedTime: boolean?, sort: number?, requireEnhanced: boolean?, tags: { [string]: boolean }? } }
--  - itemId: required. Must exist in ItemDefinitions/CosmeticDefinitions
--  - price: optional coin price override. If absent, falls back to item.value
--  - icon: optional override (rbxassetid://...)
--  - sort: optional sort priority (lower first)
--  - requireEnhanced: when true, only include if the underlying item is marked enhanced
--  - featured/limitedTime/tags: optional metadata for UI presentation

local CashShopDefinitions = {}

CashShopDefinitions.COSMETICS = {
	-- Enhanced cosmetics (feature gated): curated for launch
	{ itemId = "back_quad_wings", price = 3000, featured = true, requireEnhanced = true, sort = 10 },
	{ itemId = "head_speed_charm", price = 1500, featured = true, requireEnhanced = true, sort = 20 },
}

return CashShopDefinitions
