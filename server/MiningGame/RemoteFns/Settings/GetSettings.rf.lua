--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local _Shared = ReplicatedStorage:WaitForChild("MiningGame")

return function(container)
	local DataService = container:Get("DataService")
	local DEFAULT_THEME_SETTINGS = table.freeze({
		uiTheme = "default",
		soundPack = "default",
		musicVolume = 0.5,
		sfxVolume = 0.5,
	})

	local specs = {
		{
			name = "GetSettings",
			handler = function(ctx)
				local player = ctx.player
				local settings = DataService:GetThemeSettings(player)
				if settings then
					local out = table.clone(settings)
					out.ok = true
					out.success = true
					return out
				end
				local out = table.clone(DEFAULT_THEME_SETTINGS)
				out.ok = true
				out.success = true
				return out
			end,
			opts = { requireProfile = true, rateLimitSec = 0.5 },
		},
	}

	return specs
end
