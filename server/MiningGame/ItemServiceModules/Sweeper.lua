--!strict
-- Sweeper.lua
-- Forced-claim safety and cleanup of invalid/expired drops

local Sweeper = {}

export type SweeperT = {
	handleForcedClaim: (dt: number) -> (),
}

function Sweeper.new(ctx): SweeperT
	type Ctx = {
		Time: any,
		InventoryService: any,
		dropRegistry: any,
		ErrorService: any,
		constants: { ITEM_LIFETIME: number, DESPAWN_RETRY_DELAY: number },
	}
	ctx = ctx :: Ctx
	local Time = ctx.Time
	local InventoryService = ctx.InventoryService
	local dropRegistry = ctx.dropRegistry
	local ErrorService = ctx.ErrorService :: any

	local ITEM_LIFETIME: number = ctx.constants.ITEM_LIFETIME
	local DESPAWN_RETRY_DELAY: number = ctx.constants.DESPAWN_RETRY_DELAY

	local forcedClaimAccumulator = 0

	local function grantOwnerIfPresent(dropData)
		if dropData.owner and dropData.owner.Parent ~= nil then
			if ErrorService then
				ErrorService.safecall("Sweeper.GrantOwnerIfPresent", function()
					InventoryService:AddItem(dropData.owner :: Player, dropData.itemId, dropData.count)
				end)
			else
				InventoryService:AddItem(dropData.owner :: Player, dropData.itemId, dropData.count)
			end
			return true
		end
		return false
	end

	local function handleForcedClaim(dt: number)
		forcedClaimAccumulator += dt
		if forcedClaimAccumulator < 1.0 then
			return
		end
		forcedClaimAccumulator = 0

		local now: number = Time.mono()
		for dropModel, dropData in pairs(dropRegistry.state.activeDrops) do
			if dropData and not dropData.claimed then
				local invalid = (not dropModel.Parent) or not dropModel.PrimaryPart
				if invalid then
					grantOwnerIfPresent(dropData)
					dropData.claimed = true
					dropRegistry.removeDrop(dropModel)
				else
					local age = now - dropData.spawnTime
					if age > (ITEM_LIFETIME + DESPAWN_RETRY_DELAY) then
						grantOwnerIfPresent(dropData)
						dropData.claimed = true
						dropRegistry.removeDrop(dropModel)
					end
				end
			end
		end
	end

	return {
		handleForcedClaim = handleForcedClaim,
	}
end

return Sweeper
