--!strict
-- ThemePostFX.client.lua
-- Bridges the theme system with post-processing effects

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UI = MiningGame:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local ThemeManager = require(UI:WaitForChild("ThemeManager"))
local PostProcessing = MiningGame:WaitForChild("PostProcessing")
local PostFXService = require(PostProcessing:WaitForChild("PostFXService"))
local PostProcessingSettings = require(PostProcessing:WaitForChild("PostProcessingSettings"))
local Logger = require(MiningGame:WaitForChild("Logger"))

local log = Logger.new("ThemePostFX")

-- Get the singleton post-processing manager
local manager = PostFXService.Get()

-- Helper to count dictionary size
local function dictSize(t: any): number
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
	
	-- Check if theme has post-processing overrides
	local overrides = nil
	if Theme.postProcessing and next(Theme.postProcessing) then
		overrides = {
			components = Theme.postProcessing
		}
		log:debug("Applying theme post-processing with %d effect classes", 
			dictSize(Theme.postProcessing))
	end
	
	-- Apply theme atmosphere with overrides
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
