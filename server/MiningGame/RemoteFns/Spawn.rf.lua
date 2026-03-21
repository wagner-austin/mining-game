--!strict
-- Spawn.rf.lua
-- RemoteFunction spec(s) for spawn orchestration handshakes

-- No Shared modules needed here

-- Factory returns specs with access to DI container
return function(container)
	type RFSpec = {
		name: string,
		handler: (ctx: any, ...any) -> any,
		validate: ((...any) -> boolean)?,
		opts: { requireProfile: boolean?, rateLimitSec: number?, debugOnly: boolean? }?,
	}

	local SpawnService = container:Get("SpawnService")

	local specs: { RFSpec } = {
		{
			name = "SpawnClientReady",
			handler = function(ctx)
				-- Idempotent: ok to call multiple times
				if SpawnService and SpawnService.MarkClientReady then
					SpawnService:MarkClientReady(ctx.player)
				end
				return { ok = true, success = true }
			end,
			opts = { requireProfile = false, rateLimitSec = 1.0 },
		},
	}

	return specs
end
