--!strict
-- ThemePostFX.client.lua
-- Bridges the theme system with post-processing effects

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UI = MiningGame:WaitForChild("UI")
-- Strict Theme typing for this module
local PostProcessing = MiningGame:WaitForChild("PostProcessing")
local PostFXService = require(PostProcessing:WaitForChild("PostFXService"))
local PostProcessingConfig = require(PostProcessing:WaitForChild("PostProcessingConfig"))
type EffectComponents = PostProcessingConfig.EffectComponents
local Theme = require(UI:WaitForChild("Theme"))
local ThemeManager = require(UI:WaitForChild("ThemeManager"))
local PostProcessingSettings = require(PostProcessing:WaitForChild("PostProcessingSettings"))
local Logger = require(MiningGame:WaitForChild("Logger"))

local log = Logger.new("ThemePostFX")

-- Get the singleton post-processing manager
local manager0: any = PostFXService.Get()
type OverridesT = { components: EffectComponents }?
type PostFXPublic = {
	apply: (self: PostFXPublic, effectName: string, overrides: OverridesT) -> (),
	remove: (self: PostFXPublic, effectName: string) -> (),
	clearAll: (self: PostFXPublic) -> (),
	updateQuality: (self: PostFXPublic) -> (),
}
local manager: PostFXPublic = {
	apply = function(_, effectName: string, overrides: OverridesT)
		manager0.apply(manager0, effectName, overrides)
	end,
	remove = function(_, effectName: string)
		manager0.remove(manager0, effectName)
	end,
	clearAll = function(_)
		manager0.clearAll(manager0)
	end,
	updateQuality = function(_)
		manager0.updateQuality(manager0)
	end,
}

-- Helper to count dictionary size
local function dictSize(t: EffectComponents): number
	local n = 0
	for _ in pairs(t) do
		n += 1
	end
	return n
end

-- Apply theme post-processing effects
local function applyThemeFX(): ()
	-- Check if theme effects are enabled
	if not PostProcessingSettings.Enabled or not PostProcessingSettings.Features.ThemeEffects then
		log:debug("Theme effects disabled in settings")
		manager:remove("themeAtmosphere")
		return
	end

	-- Remove existing theme atmosphere
	manager:remove("themeAtmosphere")

	-- Build typed effect overrides from Theme.postProcessing (keys are optional)
	local overrides: OverridesT = nil
	local tp = Theme.postProcessing
	if tp then
		local eff: EffectComponents = {
			Atmosphere = rawget(tp, "Atmosphere"),
			SunRaysEffect = rawget(tp, "SunRaysEffect"),
			ColorCorrectionEffect = rawget(tp, "ColorCorrectionEffect"),
			DepthOfFieldEffect = rawget(tp, "DepthOfFieldEffect"),
			BloomEffect = rawget(tp, "BloomEffect"),
			BlurEffect = rawget(tp, "BlurEffect"),
		}
		-- If any entry present, pass overrides
		if
			eff.Atmosphere
			or eff.SunRaysEffect
			or eff.ColorCorrectionEffect
			or eff.DepthOfFieldEffect
			or eff.BloomEffect
			or eff.BlurEffect
		then
			overrides = { components = eff }
			log:debug("Applying theme post-processing with %d effect classes", dictSize(eff))
		end
	end

	-- Apply theme atmosphere with any theme overrides
	manager:apply("themeAtmosphere", overrides)

	log:debug("Theme post-processing applied for: %s", ThemeManager.ActiveName())
end

-- Connect to theme changes
ThemeManager.Changed():Connect(function(themeName)
	log:debug("Theme changed to: %s", themeName)
	applyThemeFX()
end)

-- Apply initial theme effects
applyThemeFX()

log:info("Theme post-processing bridge initialized")
