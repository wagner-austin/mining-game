--!strict
return function(_container)
	local specs = {
		{
			name = "UpdatePreferences",
			handler = function(ctx, ...)
				local updates = select(1, ...)
				local player = ctx.player
				if type(updates) ~= "table" then
					return { ok = false, success = false, err = "INVALID_BODY", reason = "" }
				end
				if updates.autoDigEnabled ~= nil and type(updates.autoDigEnabled) ~= "boolean" then
					return {
						ok = false,
						success = false,
						err = "INVALID_autodig",
						reason = "autoDigEnabled must be boolean",
					}
				end
				if updates.autoDigEnabled ~= nil then
					player:SetAttribute("AutoDigEnabled", updates.autoDigEnabled)
				end
				return {
					ok = true,
					success = true,
					updated = { autoDigEnabled = updates.autoDigEnabled },
					err = "",
					reason = "",
				}
			end,
			opts = { requireProfile = true, rateLimitSec = 0.2 },
		},
	}
	return specs
end
