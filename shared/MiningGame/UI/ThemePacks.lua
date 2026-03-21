--!strict
-- ThemePacks.lua
-- UI color theme definitions

local function hex(h: string): Color3
	h = h:gsub("#", "")
	return Color3.fromRGB(
		tonumber(h:sub(1, 2), 16) or 0,
		tonumber(h:sub(3, 4), 16) or 0,
		tonumber(h:sub(5, 6), 16) or 0
	)
end

return {
	Default = {}, -- no overrides, uses base Theme.lua values

	Light = {
		colors = {
			Background = hex("#F7F7F8"),
			Surface = hex("#FFFFFF"),
			Text = hex("#111111"),
			TextDim = hex("#666666"),
			Primary = hex("#3B82F6"),
			Accent = hex("#F59E0B"),
		},
	},

	Ocean = {
		colors = {
			Background = hex("#0D1B2A"), -- Deep ocean
			Surface = hex("#1B263B"), -- Navy surface
			Text = hex("#E0FBFC"), -- Pale cyan
			TextDim = hex("#B8D4E3"), -- Brighter light blue for better readability
			Primary = hex("#3D5A80"), -- Ocean blue
			Secondary = hex("#EE6C4D"), -- Coral
			Accent = hex("#FFD23F"), -- Sun yellow
			Success = hex("#6BCF7F"), -- Sea green
			Error = hex("#FF6B6B"), -- Red coral
		},
		postProcessing = {
			Atmosphere = {
				Density = 0.38,
				Color = Color3.fromRGB(78, 120, 170),
				Decay = Color3.fromRGB(100, 140, 180),
				Haze = 1,
			},
			SunRaysEffect = {
				Intensity = 0.28,
				Spread = 0.7,
			},
			ColorCorrectionEffect = {
				Saturation = 0.05,
				Brightness = -0.03,
			},
		},
	},

	Forest = {
		colors = {
			Background = hex("#1A1F16"), -- Dark forest
			Surface = hex("#2E342A"), -- Forest floor
			Text = hex("#F7F3E3"), -- Cream
			TextDim = hex("#C8C3A8"), -- Brighter khaki for better readability
			Primary = hex("#52734D"), -- Forest green
			Secondary = hex("#91C499"), -- Mint
			Accent = hex("#FDCA40"), -- Sunlight
			Success = hex("#6BCF7F"), -- Leaf green
			Error = hex("#DD6031"), -- Autumn orange
		},
		postProcessing = {
			Atmosphere = {
				Density = 0.45,
				Color = Color3.fromRGB(150, 180, 120),
				Decay = Color3.fromRGB(120, 140, 100),
				Glare = 0.1,
				Haze = 2,
			},
			SunRaysEffect = {
				Intensity = 0.35,
				Spread = 0.8,
			},
			ColorCorrectionEffect = {
				TintColor = Color3.fromRGB(255, 245, 220),
				Brightness = 0.05,
				Saturation = 0.15,
			},
		},
	},
}
