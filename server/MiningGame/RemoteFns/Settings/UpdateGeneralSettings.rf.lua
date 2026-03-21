--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local ThemePacks = require(Shared:WaitForChild("UI"):WaitForChild("ThemePacks"))
local Types = require(Shared:WaitForChild("Types"))

return function(container)
	local DataService = container:Get("DataService")

	local _DEFAULT_THEME_SETTINGS = table.freeze({
		uiTheme = "default",
		soundPack = "default",
		musicVolume = 0.5,
		sfxVolume = 0.5,
	})

	local VALID_SETTINGS = {
		uiTheme = "string",
		soundPack = "string",
		musicVolume = "number",
		sfxVolume = "number",
	}

	local function normalize(s: Types.JsonValue): string?
		if type(s) ~= "string" then
			return nil
		end
		return (s:gsub("^%s*(.-)%s*$", "%1"))
	end

	local VALID_UI_THEMES = {}
	for themeName, _ in pairs(ThemePacks) do
		VALID_UI_THEMES[themeName] = true
	end

	local SoundPacksFolder = Shared:FindFirstChild("SoundPacks")
	local VALID_SOUND_PACKS = { default = true }
	if SoundPacksFolder then
		for _, m in ipairs(SoundPacksFolder:GetChildren()) do
			if m:IsA("ModuleScript") then
				VALID_SOUND_PACKS[string.lower(m.Name)] = true
			end
		end
	end

	local function validateSetting(key: string, value: Types.JsonValue): boolean
		local expectedType = VALID_SETTINGS[key]
		if not expectedType then
			return false
		end
		if type(value) ~= expectedType then
			return false
		end
		if key == "uiTheme" then
			-- Explicitly narrow to string so analyzer accepts indexing
			local v = value
			if type(v) ~= "string" then
				return false
			end
			return VALID_UI_THEMES[v] == true
		elseif key == "musicVolume" or key == "sfxVolume" then
			-- Explicitly narrow to number before range check
			local v = value
			if type(v) ~= "number" then
				return false
			end
			return v >= 0 and v <= 1
		end
		return true
	end

	local specs = {
		{
			name = "UpdateGeneralSettings",
			handler = function(ctx, ...)
				local updates = select(1, ...)
				local player = ctx.player
				if type(updates) ~= "table" then
					return { ok = false, success = false, err = "INVALID_BODY", reason = "" }
				end

				for key, value in pairs(updates) do
					if not validateSetting(key, value) then
						return {
							ok = false,
							success = false,
							err = "INVALID_SETTING",
							reason = string.format("Invalid setting: %s", key),
						}
					end
				end

				local themeUpdates = {}
				local skipped = {}
				if updates.uiTheme ~= nil then
					local themeName = normalize(updates.uiTheme)
					if themeName and VALID_UI_THEMES[themeName] then
						themeUpdates.uiTheme = themeName
					else
						skipped.uiTheme = "invalid"
					end
				end
				if updates.soundPack ~= nil then
					local pack = normalize(updates.soundPack)
					if pack and VALID_SOUND_PACKS[pack] then
						themeUpdates.soundPack = pack
					else
						skipped.soundPack = "invalid"
					end
				end
				if updates.musicVolume ~= nil then
					if type(updates.musicVolume) ~= "number" or updates.musicVolume < 0 or updates.musicVolume > 1 then
						skipped.musicVolume = "invalid"
					else
						themeUpdates.musicVolume = updates.musicVolume
					end
				end
				if updates.sfxVolume ~= nil then
					if type(updates.sfxVolume) ~= "number" or updates.sfxVolume < 0 or updates.sfxVolume > 1 then
						skipped.sfxVolume = "invalid"
					else
						themeUpdates.sfxVolume = updates.sfxVolume
					end
				end
				for key, _ in pairs(updates) do
					if themeUpdates[key] == nil and not skipped[key] then
						skipped[key] = "non-theme"
					end
				end

				if next(themeUpdates) == nil then
					return {
						ok = true,
						success = true,
						unchanged = true,
						skipped = next(skipped) and skipped or nil,
						err = "",
						reason = "",
					}
				end

				local success = DataService:SetThemeSettings(player, themeUpdates)
				if success then
					return {
						ok = true,
						success = true,
						updated = themeUpdates,
						skipped = next(skipped) and skipped or nil,
						err = "",
						reason = "",
					}
				end
				return { ok = false, success = false, err = "UPDATE_FAILED", reason = "Failed to update settings" }
			end,
			validate = function(updates)
				return type(updates) == "table"
			end,
			opts = { requireProfile = true, rateLimitSec = 0.2 },
		},
	}

	return specs
end
