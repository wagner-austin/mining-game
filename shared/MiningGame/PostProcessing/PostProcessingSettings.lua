--!strict
-- PostProcessingSettings.lua
-- Configuration settings for enabling/disabling post-processing features

local PostProcessingSettings: {
	Enabled: boolean,
	Features: {
		UnderwaterEffects: boolean,
		ThemeEffects: boolean,
		GameplayEffects: boolean,
		QualityAutoAdjust: boolean,
		DayNightEffects: boolean,
	},
	Debug: {
		VerboseLogging: boolean,
		ShowDebugPanel: boolean,
		ForceQualityLevel: string?,
	},
} =
	{
		Enabled = false,
		Features = {
			UnderwaterEffects = true,
			ThemeEffects = true,
			GameplayEffects = true,
			QualityAutoAdjust = true,
			DayNightEffects = false,
		},
		Debug = {
			VerboseLogging = false,
			ShowDebugPanel = false,
			ForceQualityLevel = nil,
		},
	}

return PostProcessingSettings
