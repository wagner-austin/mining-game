--!strict
-- PostProcessingDebug.client.lua
-- Debug commands for testing post-processing features

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local PostProcessing = MiningGame:WaitForChild("PostProcessing")
local PostProcessingSettings = require(PostProcessing:WaitForChild("PostProcessingSettings"))
local PostFXService = require(PostProcessing:WaitForChild("PostFXService"))
local Logger = require(MiningGame:WaitForChild("Logger"))

local log = Logger.new("PostProcessingDebug")
local player = Players.LocalPlayer

-- Chat commands for testing
player.Chatted:Connect(function(message)
	local msg = message:lower()
	
	-- Master toggle
	if msg == "/fx on" then
		PostProcessingSettings.Enabled = true
		log:info("Post-processing ENABLED")
		player:SetAttribute("PostFXEnabled", true)
		
	elseif msg == "/fx off" then
		PostProcessingSettings.Enabled = false
		-- Clear all effects
		local manager = PostFXService.Get()
		manager:clearAll()
		log:info("Post-processing DISABLED")
		player:SetAttribute("PostFXEnabled", false)
		
	-- Feature toggles
	elseif msg == "/fx underwater on" then
		PostProcessingSettings.Features.UnderwaterEffects = true
		log:info("Underwater effects ENABLED")
		
	elseif msg == "/fx underwater off" then
		PostProcessingSettings.Features.UnderwaterEffects = false
		log:info("Underwater effects DISABLED")
		
	elseif msg == "/fx theme on" then
		PostProcessingSettings.Features.ThemeEffects = true
		log:info("Theme effects ENABLED - rejoin or change theme to apply")
		
	elseif msg == "/fx theme off" then
		PostProcessingSettings.Features.ThemeEffects = false
		local manager = PostFXService.Get()
		manager:remove("themeAtmosphere")
		log:info("Theme effects DISABLED")
		
	-- Debug toggles
	elseif msg == "/fx verbose on" then
		PostProcessingSettings.Debug.VerboseLogging = true
		log:info("Verbose logging ENABLED")
		
	elseif msg == "/fx verbose off" then
		PostProcessingSettings.Debug.VerboseLogging = false
		log:info("Verbose logging DISABLED")
		
	-- Quality overrides
	elseif msg == "/fx quality low" then
		PostProcessingSettings.Debug.ForceQualityLevel = "Low"
		local manager = PostFXService.Get()
		manager:updateQuality()
		log:info("Forced quality level: LOW")
		
	elseif msg == "/fx quality medium" then
		PostProcessingSettings.Debug.ForceQualityLevel = "Medium"
		local manager = PostFXService.Get()
		manager:updateQuality()
		log:info("Forced quality level: MEDIUM")
		
	elseif msg == "/fx quality high" then
		PostProcessingSettings.Debug.ForceQualityLevel = "High"
		local manager = PostFXService.Get()
		manager:updateQuality()
		log:info("Forced quality level: HIGH")
		
	elseif msg == "/fx quality auto" then
		PostProcessingSettings.Debug.ForceQualityLevel = nil
		local manager = PostFXService.Get()
		manager:updateQuality()
		log:info("Quality level: AUTO")
		
	-- Test effects
	elseif msg == "/fx test damage" then
		local manager = PostFXService.Get()
		manager:apply("damageFlash")
		task.wait(0.5)
		manager:remove("damageFlash")
		log:info("Tested damage flash effect")
		
	elseif msg == "/fx test heal" then
		local manager = PostFXService.Get()
		manager:apply("healEffect")
		task.wait(1)
		manager:remove("healEffect")
		log:info("Tested heal effect")
		
	-- Status
	elseif msg == "/fx status" then
		log:info("=== Post-Processing Status ===")
		log:info("System: %s", PostProcessingSettings.Enabled and "ENABLED" or "DISABLED")
		log:info("Underwater: %s", PostProcessingSettings.Features.UnderwaterEffects and "ON" or "OFF")
		log:info("Theme: %s", PostProcessingSettings.Features.ThemeEffects and "ON" or "OFF")
		log:info("Quality: %s", PostProcessingSettings.Debug.ForceQualityLevel or "AUTO")
		log:info("Verbose: %s", PostProcessingSettings.Debug.VerboseLogging and "ON" or "OFF")
		
	-- Help
	elseif msg == "/fx help" or msg == "/fx" then
		log:info("=== Post-Processing Commands ===")
		log:info("/fx on|off - Master toggle")
		log:info("/fx underwater on|off - Toggle underwater effects")
		log:info("/fx theme on|off - Toggle theme effects")
		log:info("/fx quality low|medium|high|auto - Force quality level")
		log:info("/fx verbose on|off - Toggle verbose logging")
		log:info("/fx test damage|heal - Test effects")
		log:info("/fx status - Show current settings")
	end
end)

log:info("Debug commands loaded. Type '/fx help' for commands")