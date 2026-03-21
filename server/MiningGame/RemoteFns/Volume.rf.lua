--!strict
-- Volume.rf.lua
-- RemoteFunction(s) for volume queries to support precise client previews

-- No ReplicatedStorage access needed

-- Export a factory that accepts the DI container and returns RF specs
return function(container)
	local DigService = container:Get("DigService")

	type RFSpec = {
		name: string,
		handler: (ctx: any, ...any) -> any,
		validate: ((...any) -> boolean)?,
		opts: { requireProfile: boolean?, rateLimitSec: number? }?,
	}

	local specs: { RFSpec } = {
		{
			name = "QueryVolumeAt",
			handler = function(ctx, position)
				local player: Player = ctx.player
				local vol = DigService:PickVolume(position, player)
				if not vol then
					return { ok = true, success = true, hit = false }
				end
				-- Return only what the client needs for preview/snapping
				return {
					ok = true,
					success = true,
					hit = true,
					id = vol.id,
					kind = vol.kind,
					origin = vol.origin,
					size = vol.sizeStuds,
					public = (vol.permissions and vol.permissions.public) == true,
				}
			end,
			validate = function(position)
				return typeof(position) == "Vector3"
			end,
			opts = { requireProfile = true, rateLimitSec = 0.1 },
		},
	}

	return specs
end
