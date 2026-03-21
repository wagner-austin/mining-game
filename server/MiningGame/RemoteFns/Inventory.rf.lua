--!strict
-- Inventory.rf.lua
-- RemoteFunction specs for inventory operations
-- Contract: top-level { ok, success, ... } for all user-facing RFs

local Players = game:GetService("Players")

-- Return a factory function that accepts the DI container
return function(container)
	-- Resolve services from the container
	local InventoryService = container:Get("InventoryService")

	type RFSpec = {
		name: string,
		handler: (ctx: any, ...any) -> any,
		validate: ((...any) -> boolean)?,
		opts: { requireProfile: boolean?, rateLimitSec: number? }?,
	}

	-- Constants
	local MAX_SELL_ITEMS = 100 -- Prevent spam/abuse

	local specs: { RFSpec } = {
		{
			name = "GetInventory",
			handler = function(ctx)
				local player = ctx.player
				local inventory = InventoryService:GetInventory(player)
				if inventory then
					-- Return at top level for consistency
					return {
						ok = true,
						success = true,
						inventory = inventory,
					}
				end
				return {
					ok = false,
					success = false,
					err = "NO_INVENTORY",
					reason = "Failed to get inventory",
				}
			end,
			opts = { requireProfile = true, rateLimitSec = 0.25 },
		},

		{
			name = "SellItems",
			handler = function(ctx, items: { [string]: number })
				local player = ctx.player
				local success, value = InventoryService:SellItems(player, items)
				if success then
					-- Return at top level to match client expectations
					return {
						ok = true,
						success = true,
						coins = value,
						sold = items,
					}
				end
				return {
					ok = false,
					success = false,
					err = "SELL_FAILED",
					reason = tostring(value) or "Unable to sell items",
				}
			end,
			validate = function(items)
				if type(items) ~= "table" then
					return false
				end

				local count = 0
				for itemId, quantity in pairs(items) do
					count += 1
					-- Hard cap to prevent abuse
					if count > MAX_SELL_ITEMS then
						return false
					end
					-- Validate types
					if type(itemId) ~= "string" then
						return false
					end
					if type(quantity) ~= "number" or quantity <= 0 then
						return false
					end
					-- Integers only
					if quantity ~= math.floor(quantity) then
						return false
					end
				end

				-- Must have at least one item
				return count > 0
			end,
			opts = { requireProfile = true, rateLimitSec = 0.5 },
		},

		{
			name = "EquipItem",
			handler = function(ctx, itemId: string, _slot: string?)
				local player = ctx.player
				local r = InventoryService:EquipItem(player, itemId)
				if not r or not r.success then
					return {
						ok = false,
						success = false,
						err = "EQUIP_FAILED",
						reason = (r and r.reason) or "Failed to equip item",
					}
				end
				-- Return at top level to match client expectations
				return {
					ok = true,
					success = true,
					equipped = itemId,
				}
			end,
			validate = function(itemId, slot)
				if type(itemId) ~= "string" or #itemId == 0 then
					return false
				end
				if slot ~= nil and type(slot) ~= "string" then
					return false
				end
				return true
			end,
			opts = { requireProfile = true, rateLimitSec = 0.2 },
		},

		{
			name = "UnequipItem",
			handler = function(ctx, slot: string)
				local player = ctx.player
				local r = InventoryService:UnequipItem(player, slot)
				if not r or not r.success then
					return {
						ok = false,
						success = false,
						err = "UNEQUIP_FAILED",
						reason = (r and r.reason) or "Failed to unequip item",
					}
				end
				-- Return at top level to match client expectations
				return {
					ok = true,
					success = true,
					unequipped = slot,
				}
			end,
			validate = function(slot)
				return type(slot) == "string" and #slot > 0 and #slot < 50
			end,
			opts = { requireProfile = true, rateLimitSec = 0.2 },
		},

		{
			name = "UseConsumable",
			handler = function(ctx, itemId: string, _count: number?)
				local player = ctx.player
				-- Service only supports single use, ignore count for now
				local r = InventoryService:UseConsumable(player, itemId)
				if not r or not r.success then
					return {
						ok = false,
						success = false,
						err = "USE_FAILED",
						reason = (r and r.reason) or "Failed to use consumable",
					}
				end
				-- Return at top level to match client expectations
				return {
					ok = true,
					success = true,
					used = 1,
				}
			end,
			validate = function(itemId, count)
				if type(itemId) ~= "string" or #itemId == 0 then
					return false
				end
				-- Accept count for future compatibility but ignore it for now
				if count ~= nil then
					if type(count) ~= "number" or count <= 0 then
						return false
					end
					if count ~= math.floor(count) then
						return false
					end
					if count > 10 then
						return false
					end -- Cap to reasonable value
				end
				return true
			end,
			opts = { requireProfile = true, rateLimitSec = 0.3 },
		},

		{
			-- Contract: Returns *raw* map for compatibility with CosmeticController
			-- This is an intentional exception to the top-level { ok, success, ... } convention
			name = "GetEquippedItems",
			handler = function(ctx)
				local player = ctx.player
				-- CosmeticController expects the raw equipped map (slot -> itemId)
				return InventoryService:GetEquippedItems(player) or {}
			end,
			opts = { requireProfile = true, rateLimitSec = 0.25 },
		},

		{
			-- Contract: Returns *raw* map for compatibility with CosmeticController
			-- This is an intentional exception to the top-level { ok, success, ... } convention
			name = "GetAllEquipped",
			handler = function(_ctx)
				-- Get all players' equipped items (for cosmetics sync)
				local allEquipped = {}

				for _, player in ipairs(Players:GetPlayers()) do
					local equipped = InventoryService:GetEquippedItems(player)
					if equipped then
						allEquipped[player.UserId] = equipped
					end
				end

				-- CosmeticController expects the raw userId -> (slot -> itemId) map
				return allEquipped
			end,
			opts = { requireProfile = false, rateLimitSec = 1.0 }, -- No profile needed for viewing others
		},
	}

	return specs
end -- End of factory function
