--!strict
-- PostProcessingSettings.lua
-- Configuration settings for enabling/disabling post-processing features

local PostProcessingSettings = {}

-- Master switch for all post-processing effects
PostProcessingSettings.Enabled = false

-- Individual feature toggles
PostProcessingSettings.Features = {
	-- Environmental effects
	UnderwaterEffects = true,
	
	-- Theme-based atmospheric effects
	ThemeEffects = true,
	
	-- Gameplay effects (damage flash, heal, etc)
	GameplayEffects = true,
	
	-- Quality-based auto-adjustment
	QualityAutoAdjust = true,
	
	-- Day/Night effects (if implemented)
	DayNightEffects = false
}

-- Debug settings
PostProcessingSettings.Debug = {
	-- Log all effect changes
	VerboseLogging = false,
	
	-- Show on-screen debug panel
	ShowDebugPanel = false,
	
	-- Force quality level (nil = auto, "Low", "Medium", "High")
	ForceQualityLevel = nil
}

return PostProcessingSettings