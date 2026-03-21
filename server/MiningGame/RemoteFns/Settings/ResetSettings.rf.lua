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
			name = "ResetSettings",
			handler = function(ctx, ...)
				local category: string? = select(1, ...)
				local player = ctx.player
				if not category or category == "all" then
					DataService:SetThemeSettings(player, table.clone(DEFAULT_THEME_SETTINGS))
					return { ok = true, success = true, reset = "all", err = "", reason = "" }
				elseif category == "theme" then
					DataService:SetThemeSettings(player, table.clone(DEFAULT_THEME_SETTINGS))
					return { ok = true, success = true, reset = "theme", err = "", reason = "" }
				else
					return {
						ok = false,
						success = false,
						reset = "",
						err = "INVALID_CATEGORY",
						reason = "Unknown category: " .. tostring(category),
					}
				end
			end,
			validate = function(category)
				return category == nil or type(category) == "string"
			end,
			opts = { requireProfile = true, rateLimitSec = 2.0 },
		},
	}

	return specs
end
