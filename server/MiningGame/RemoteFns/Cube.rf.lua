--!strict
-- Cube.rf.lua
-- RemoteFunction spec(s) for cube-specific actions (manual respawn)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
-- Logger removed (unused)

return function(container)
	-- Unused service lookups removed; container is passed to CubeReset
	local CubeReset = require(script.Parent.Parent:WaitForChild("CubeReset"))
	local GameConfig = require(MiningGame:WaitForChild("GameConfig"))

	type RFSpec = {
		name: string,
		handler: (ctx: any, ...any) -> any,
		validate: ((...any) -> boolean)?,
		opts: { requireProfile: boolean?, rateLimitSec: number?, debugOnly: boolean? }?,
	}

	-- validateNoArgs helper inlined where needed

	local specs: { RFSpec } = {
		{
			name = "Cube_ResetFull",
			handler = function(ctx)
				local player: Player = ctx.player
				local minFrac = (
					GameConfig.Reset
					and (GameConfig.Reset.MANUAL_RESET_MIN_MINED_FRAC or GameConfig.Reset.MANUAL_RESET_MAX_MINED_FRAC)
				) or 0.05
				local res =
					CubeReset.resetPlayerCube(container, player, { gateAtLeastMinedFrac = minFrac, reseed = true })
				if res and res.ok then
					return { ok = true, success = true, reset = true }
				end
				if res and res.err == "NOT_ENOUGH_MINED" then
					local needPct = math.floor((minFrac * 100) + 0.5)
					res.reason = string.format("Mine at least %d%% to enable manual reset", needPct)
				end
				return res
			end,
			validate = function(...: any): boolean
				return select("#", ...) == 0
			end,
			opts = { requireProfile = true, rateLimitSec = 10.0 },
		},
	}

	return specs
end
