--!strict
-- Shop.rf.lua
-- RemoteFunction specs for Cash Shop (coins + cosmetics)
-- Contract: top-level { ok, success, ... }

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local ItemDefinitions = require(Shared:WaitForChild("ItemDefinitions"))
local CosmeticDefinitions = require(Shared:WaitForChild("CosmeticDefinitions"))
local Logger = require(Shared:WaitForChild("Logger"))
local EventBus = require(Shared:WaitForChild("EventBus"))
local EventNames = require(Shared:WaitForChild("EventNames"))
local Contracts = require(Shared:WaitForChild("EventContracts"))
local CashShopDefinitions = require(Shared:WaitForChild("CashShopDefinitions"))

local log = Logger.new("ShopRF")
local Bus = EventBus.global()

-- Return a factory function that accepts the DI container
return function(container)
	-- Server gate: allow RFs to exist only when enabled
	if not (GameConfig.Features and GameConfig.Features.SHOP_ENABLED) then
		log:info("SHOP_ENABLED flag is off — RFs disabled")
		return {}
	end

	-- Resolve services from the container
	local DataService = container:Get("DataService")
	local InventoryService = container:Get("InventoryService")
	local CurrencyService = container:Get("CurrencyService")

	type RFSpec = {
		name: string,
		handler: (ctx: any, ...any) -> any,
		validate: ((...any) -> boolean)?,
		opts: { requireProfile: boolean?, rateLimitSec: number? }?,
	}

	-- Helpers
	local RARITY_RANK: { [string]: number } = {
		COMMON = 1,
		UNCOMMON = 2,
		RARE = 3,
		EPIC = 4,
		LEGENDARY = 5,
		MYTHIC = 6,
	}

	-- No legacy scanning; catalog is curated via CashShopDefinitions

	-- Build a fast lookup for curated cosmetics entries (id -> overrides)
	local curatedList = (CashShopDefinitions and CashShopDefinitions.COSMETICS) or {}
	local curatedById: { [string]: any } = {}
	for _, entry in ipairs(curatedList) do
		local id = tostring(entry.itemId or entry.id or "")
		if id ~= "" then
			curatedById[id] = entry
		end
	end

	local function isPurchasable(def: any): boolean
		-- Basic type/slot checks
		if not def or def.type ~= "cosmetic" then
			return false
		end
		if def.slot == "modelSwap" then
			return false
		end
		-- Enhanced cosmetics gated by feature flag
		local enhancedFlag = (def.enhanced == true) or (def.meta and def.meta.enhanced == true)
		if enhancedFlag and not (GameConfig.Features and GameConfig.Features.ENHANCED_COSMETICS_ENABLED) then
			return false
		end
		-- Must be explicitly curated for sale
		if not curatedById[def.id] then
			return false
		end
		return true
	end

	local function getOwnedCount(profile: any, itemId: string): number
		local inv = profile and profile.inventory
		if not inv then
			return 0
		end
		local n = inv[itemId]
		if type(n) == "number" then
			return n
		end
		return 0
	end

	local function shapeCatalogItem(def: any, ownedCount: number, overrides: any?)
		local priceOverride = overrides and overrides.price or nil
		local iconOverride = overrides and overrides.icon or nil
		local sort = overrides and overrides.sort or nil
		local featured = overrides and overrides.featured or false
		local limitedTime = overrides and overrides.limitedTime or false
		local enhancedFlag = ((def.meta and def.meta.enhanced) == true) or ((overrides and overrides.enhanced) == true)
		return {
			id = def.id,
			itemId = def.id,
			name = def.name or def.id,
			price = priceOverride or def.value,
			rarity = def.rarity,
			slot = def.slot,
			icon = iconOverride or def.icon or (def.meta and def.meta.icon),
			enhanced = enhancedFlag,
			owned = ownedCount > 0,
			ownedCount = ownedCount,
			sort = sort,
			featured = featured,
			limitedTime = limitedTime,
		}
	end

	local function collectCatalog(profile: any, category: string?, rarity: string?)
		local items = {}
		local curated = curatedList
		-- Curated list only: honor overrides and sorting; no legacy scan
		for _, entry in ipairs(curated) do
			local id = entry.itemId or entry.id
			local def = id and ItemDefinitions.get(id) or nil
			if def and def.type == "cosmetic" and def.slot ~= "modelSwap" then
				local enhancedFlag = ((def.meta and def.meta.enhanced) == true) or (entry.enhanced == true)
				local requireEnhanced = entry.requireEnhanced == true
				if
					(not category or def.slot == category)
					and (not rarity or def.rarity == rarity)
					and (not requireEnhanced or enhancedFlag)
				then
					local ownedCount = getOwnedCount(profile, id)
					table.insert(items, shapeCatalogItem(def, ownedCount, entry))
				end
			end
		end
		table.sort(items, function(a, b)
			-- notOwned first
			if a.owned ~= b.owned then
				return (a.owned == false)
			end
			-- rarity ascending per spec
			local ra = RARITY_RANK[(a.rarity or "")] or 999
			local rb = RARITY_RANK[(b.rarity or "")] or 999
			if ra ~= rb then
				return ra < rb
			end
			-- price ascending
			if a.price ~= b.price then
				return (a.price or 0) < (b.price or 0)
			end
			-- name ascending
			return tostring(a.name) < tostring(b.name)
		end)
		return items
	end

	local specs: { RFSpec } = {
		{
			name = "GetShopCatalog",
			handler = function(ctx, category: string?, rarity: string?)
				local player = ctx.player
				local profile = DataService:GetPlayerData(player)
				if not profile then
					return { ok = false, success = false, err = "NO_PROFILE", reason = "Profile not found" }
				end
				local items = collectCatalog(profile, category, rarity)
				return { ok = true, success = true, items = items }
			end,
			validate = function(category, rarity)
				if category ~= nil and type(category) ~= "string" then
					return false
				end
				if rarity ~= nil and type(rarity) ~= "string" then
					return false
				end
				return true
			end,
			opts = { requireProfile = true, rateLimitSec = 0.2 },
		},

		{
			name = "PurchaseItem",
			handler = function(ctx, itemId: string, quantity: number?)
				local player = ctx.player
				local profile = DataService:GetPlayerData(player)
				if not profile then
					return { ok = false, success = false, err = "NO_PROFILE", reason = "Profile not found" }
				end

				local q = quantity or 1
				if type(itemId) ~= "string" or #itemId == 0 or type(q) ~= "number" or q ~= 1 then
					return { ok = false, success = false, err = "INVALID_INPUT", reason = "quantity must be 1" }
				end

				local def = ItemDefinitions.get(itemId)
					or (CosmeticDefinitions and CosmeticDefinitions.ITEMS and CosmeticDefinitions.ITEMS[itemId])
				if not def then
					return { ok = false, success = false, err = "ITEM_NOT_FOUND", reason = "Unknown item" }
				end
				-- Ensure this item is curated and purchasable per flags
				if not isPurchasable(def) then
					return { ok = false, success = false, err = "NOT_AVAILABLE", reason = "Item not purchasable" }
				end

				-- Server-authoritative price: curated override wins; otherwise fallback to def.value
				local override = curatedById[def.id]
				local price = tonumber(override and override.price) or tonumber(def.value) or 0
				if price <= 0 then
					return { ok = false, success = false, err = "NOT_AVAILABLE", reason = "Invalid price" }
				end
				if not CurrencyService.canAfford(player, "coins", price) then
					return { ok = true, success = false, err = "INSUFFICIENT_FUNDS" }
				end

				-- Deduct then grant; rely on services for events/saves
				local deducted = CurrencyService.add(player, "coins", -price)
				if not deducted then
					return { ok = false, success = false, err = "PURCHASE_FAILED", reason = "Deduct failed" }
				end

				local granted = InventoryService:AddItem(player, itemId, 1)
				if not granted then
					return { ok = false, success = false, err = "PURCHASE_FAILED", reason = "Grant failed" }
				end

				-- Centralized auto-equip happens inside InventoryService on acquire
				-- Report whether it ended up equipped, and if we should suggest equip
				local equipped = false
				local equipSuggested = false
				if def.slot then
					local equippedMap = InventoryService:GetEquippedItems(player)
					local eq = equippedMap and equippedMap[def.slot]
					equipped = (eq == itemId)
					equipSuggested = not equipped
				end

				-- Informational toast
				Bus:emit(EventNames.NOTIFICATION_PUSH, {
					to = { kind = "player", player = player },
					payload = Contracts.NOTIFICATION_PUSH({
						type = "success",
						message = string.format("Purchased %s!", def.name or itemId),
						color = (
							GameConfig.Loot
							and GameConfig.Loot.RARITIES[def.rarity]
							and GameConfig.Loot.RARITIES[def.rarity].color
						) or Color3.new(1, 1, 1),
					}),
				})

				return {
					ok = true,
					success = true,
					purchased = itemId,
					quantity = 1,
					equipped = equipped,
					equipSuggested = equipSuggested,
				}
			end,
			validate = function(itemId, quantity)
				if type(itemId) ~= "string" or #itemId == 0 then
					return false
				end
				if quantity ~= nil then
					if type(quantity) ~= "number" or quantity ~= 1 then
						return false
					end
				end
				return true
			end,
			opts = { requireProfile = true, rateLimitSec = 0.2 },
		},
	}

	return specs
end -- factory
