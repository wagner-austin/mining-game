--!strict
-- Neighborhood.rf.lua
-- Stub RemoteFunction specs for future neighborhood/multiplayer system

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

-- Return a factory function that accepts the DI container
return function(_container)
	-- No services needed yet for this stub

	type RFSpec = {
		name: string,
		handler: (ctx: any, ...any) -> any,
		validate: ((...any) -> boolean)?,
		opts: { requireProfile: boolean?, rateLimitSec: number?, debugOnly: boolean? }?,
	}

	-- Feature flag check (disabled for now)
	local NEIGHBORHOODS_ENABLED = (GameConfig.Features ~= nil)
		and (rawget(GameConfig.Features, "NEIGHBORHOODS") == true)
	local IS_STUDIO = RunService:IsStudio()

	-- Stub handlers for future implementation
	local specs: { RFSpec } = {
		{
			name = "VisitNeighbor",
			handler = function(ctx, userId: number)
				if not NEIGHBORHOODS_ENABLED and not IS_STUDIO then
					return {
						ok = false,
						success = false,
						err = "NOT_IMPLEMENTED",
						reason = "Neighborhood system coming soon",
					}
				end
				-- Prevent self-visits
				if userId == ctx.player.UserId then
					return {
						ok = false,
						success = false,
						err = "INVALID_TARGET",
						reason = "Cannot visit yourself",
					}
				end
				-- TODO: Implement when multiplayer is ready
				return {
					ok = false,
					success = false,
					err = "NOT_IMPLEMENTED",
					reason = "Neighborhood system coming soon",
				}
			end,
			validate = function(userId)
				if type(userId) ~= "number" then
					return false
				end
				if userId ~= math.floor(userId) then
					return false
				end -- integer only
				if userId <= 0 or userId >= 2 ^ 53 then
					return false
				end -- JS-safe bound
				return true
			end,
			opts = { requireProfile = true, rateLimitSec = 1.0 },
		},

		{
			name = "ReturnHome",
			handler = function(_ctx)
				if not NEIGHBORHOODS_ENABLED and not IS_STUDIO then
					return {
						ok = false,
						success = false,
						err = "NOT_IMPLEMENTED",
						reason = "Neighborhood system coming soon",
					}
				end
				-- TODO: Implement when multiplayer is ready
				return {
					ok = false,
					success = false,
					err = "NOT_IMPLEMENTED",
					reason = "Neighborhood system coming soon",
				}
			end,
			opts = { requireProfile = true, rateLimitSec = 0.5 },
		},

		{
			name = "GetNeighborhood",
			handler = function(_ctx)
				if not NEIGHBORHOODS_ENABLED and not IS_STUDIO then
					return {
						ok = false,
						success = false,
						err = "NOT_IMPLEMENTED",
						reason = "Neighborhood system coming soon",
					}
				end
				-- TODO: Implement when multiplayer is ready
				-- Will return list of nearby players/friends
				return {
					ok = true,
					success = true,
					neighbors = {},
				}
			end,
			opts = { requireProfile = true, rateLimitSec = 2.0 },
		},
	}

	return specs
end -- End of factory function
