--!strict
-- SimAgents.rf.lua
-- Debug-only RemoteFunction specs for sim agent testing
-- Contract: top-level { ok, success, ... }. Exceptions: GetServerUnix (scalar), Equipped maps (raw).

local RunService = game:GetService("RunService")

-- Return a factory function that accepts the DI container
return function(container)
	-- Resolve SimAgents from the container (optional, Studio-only)
	local SimAgents = container:tryGet("SimAgents")

	-- If SimAgents not available, return empty specs
	if not SimAgents then
		return {}
	end

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
			name = "SimAgents_SetCount",
			handler = function(ctx, count: number)
				if not isDev(ctx.player) then
					return {
						ok = false,
						success = false,
						err = "FORBIDDEN",
						reason = "Not authorized",
					}
				end
				local ok = SimAgents.SetCount(count)
				if ok then
					return {
						ok = true,
						success = true,
						count = count,
					}
				end
				return {
					ok = false,
					success = false,
					err = "SET_COUNT_FAILED",
					reason = "Failed to set agent count",
				}
			end,
			validate = function(count)
				return type(count) == "number" and count >= 0 and count == math.floor(count) and count <= 100
			end,
			opts = { requireProfile = false, rateLimitSec = 0.2, debugOnly = true },
		},

		{
			name = "SimAgents_GetStatus",
			handler = function(ctx)
				if not isDev(ctx.player) then
					return {
						ok = false,
						success = false,
						err = "FORBIDDEN",
						reason = "Not authorized",
					}
				end
				local status = SimAgents.GetStatus()
				return {
					ok = true,
					success = true,
					status = status,
				}
			end,
			opts = { requireProfile = false, rateLimitSec = 0.2, debugOnly = true },
		},

		{
			name = "SimAgents_RespawnAll",
			handler = function(ctx)
				if not isDev(ctx.player) then
					return {
						ok = false,
						success = false,
						err = "FORBIDDEN",
						reason = "Not authorized",
					}
				end
				SimAgents.RespawnAll()
				return {
					ok = true,
					success = true,
				}
			end,
			opts = { requireProfile = false, rateLimitSec = 0.2, debugOnly = true },
		},

		{
			name = "SimAgents_Clear",
			handler = function(ctx)
				if not isDev(ctx.player) then
					return {
						ok = false,
						success = false,
						err = "FORBIDDEN",
						reason = "Not authorized",
					}
				end
				SimAgents.Clear()
				return {
					ok = true,
					success = true,
				}
			end,
			opts = { requireProfile = false, rateLimitSec = 0.2, debugOnly = true },
		},

		{
			name = "SimAgents_SetTerrainCubes",
			handler = function(ctx, enabled: boolean)
				if not isDev(ctx.player) then
					return {
						ok = false,
						success = false,
						err = "FORBIDDEN",
						reason = "Not authorized",
					}
				end
				SimAgents.SetTerrainCubes(enabled == true)
				return {
					ok = true,
					success = true,
					enabled = enabled,
				}
			end,
			validate = function(enabled)
				return type(enabled) == "boolean"
			end,
			opts = { requireProfile = false, rateLimitSec = 0.2, debugOnly = true },
		},
	}

	return specs
end -- End of factory function
