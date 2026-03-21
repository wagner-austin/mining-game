--!strict
-- Item.rf.lua
-- RemoteFunction specs for item pickup and testing
-- Contract: top-level { ok, success, ... }. Exceptions: GetServerUnix (scalar), Equipped maps (raw).

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

-- Return a factory function that accepts the DI container
return function(container)
	-- Resolve services from the container
	local ItemService = container:Get("ItemService")

	type RFSpec = {
		name: string,
		handler: (ctx: any, ...any) -> any,
		validate: ((...any) -> boolean)?,
		opts: { requireProfile: boolean?, rateLimitSec: number?, debugOnly: boolean? }?,
	}

	-- Helper
	local function isDev(_player: Player): boolean
		return RunService:IsStudio()
	end

	local specs: { RFSpec } = {
		{
			name = "PickupItem",
			handler = function(ctx, dropModel: Instance)
				-- Call the actual method name in ItemService
				local ok = ItemService:CollectDrop(dropModel, ctx.player)
				if ok then
					-- Return at top level to match client expectations
					return {
						ok = true,
						success = true,
					}
				end
				return {
					ok = false,
					success = false,
					err = "PICKUP_FAILED",
					reason = "Failed to pickup item",
				}
			end,
			validate = function(dropModel)
				if typeof(dropModel) ~= "Instance" or not dropModel:IsA("Model") then
					return false
				end
				-- Existence guard (handles deleted/queued models)
				if dropModel.Parent == nil then
					return false
				end
				-- Verify it's tagged as an ItemDrop (server-created drops only)
				if not CollectionService:HasTag(dropModel, "ItemDrop") then
					return false
				end
				-- Verify it's in workspace (drops should always be there)
				if not dropModel:IsDescendantOf(workspace) then
					return false
				end
				return true
			end,
			opts = { requireProfile = true, rateLimitSec = 0.2 },
		},

		{
			name = "SpawnTestItem",
			handler = function(ctx, itemId: string)
				if not isDev(ctx.player) then
					return {
						ok = false,
						success = false,
						err = "FORBIDDEN",
						reason = "Not authorized",
					}
				end
				local character = ctx.player.Character
				if not character or not character.PrimaryPart then
					return {
						ok = false,
						success = false,
						err = "NO_CHARACTER",
						reason = "Player has no character",
					}
				end
				local pos = character.PrimaryPart.Position + Vector3.new(0, 2, 0)
				local model = ItemService:SpawnStackedDrop(itemId, 1, pos, ctx.player)
				if model then
					-- Return at top level for consistency
					return {
						ok = true,
						success = true,
						itemId = itemId,
					}
				else
					return {
						ok = false,
						success = false,
						err = "SPAWN_FAILED",
						reason = "Failed to spawn test item",
					}
				end
			end,
			validate = function(itemId)
				return type(itemId) == "string" and #itemId > 0 and #itemId < 100
			end,
			opts = { requireProfile = false, rateLimitSec = 0.3, debugOnly = true },
		},
	}

	return specs
end -- End of factory function
