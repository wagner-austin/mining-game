--!strict
-- Sweeper.lua
-- Forced-claim safety and cleanup of invalid/expired drops

local Sweeper = {}

export type SweeperT = {
    handleForcedClaim: (self: SweeperT, dt: number) -> (),
}

function Sweeper.new(ctx): SweeperT
    local Time = ctx.Time
    local InventoryService = ctx.InventoryService
    local dropRegistry = ctx.dropRegistry

    local ITEM_LIFETIME: number = ctx.constants.ITEM_LIFETIME
    local DESPAWN_RETRY_DELAY: number = ctx.constants.DESPAWN_RETRY_DELAY

    local forcedClaimAccumulator = 0

    local function grantOwnerIfPresent(dropData)
        if dropData.owner and dropData.owner.Parent ~= nil then
            pcall(function()
                InventoryService:AddItem(dropData.owner, dropData.itemId, dropData.count)
            end)
            return true
        end
        return false
    end

    local function handleForcedClaim(dt: number)
        forcedClaimAccumulator += dt
        if forcedClaimAccumulator < 1.0 then return end
        forcedClaimAccumulator = 0

        local now = Time.mono()
        for dropModel, dropData in pairs(dropRegistry.state.activeDrops) do
            if dropData and not dropData.claimed then
                local invalid = (not dropModel.Parent) or (not dropModel.PrimaryPart)
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

