--!strict
-- AmbientBoot.client.lua
-- Bootstrap for proximity-based ambient sound system

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local AmbientController = require(MiningGame:WaitForChild("AmbientController"))
local MaterialManager = require(MiningGame:WaitForChild("MaterialManager"))
local ClientRF = require(MiningGame:WaitForChild("ClientRF"))
local Ready = require(MiningGame:WaitForChild("Ready"))

-- Initialize MaterialManager to handle palette-based lighting
MaterialManager.Initialize()

-- Load and apply saved palette preference AFTER player data is ready
task.spawn(function()
    if not player:GetAttribute("DataLoaded") then
        player:GetAttributeChangedSignal("DataLoaded"):Wait()
    end
    if not Ready.wait(10) then
        warn("[AmbientBoot] Server not ready; skipping initial palette fetch")
        return
    end
    -- Use ClientRF with retry for material preferences
    local prefs, err = ClientRF.callWithRetry("GetMaterialPreferences", 3)
    if not err and prefs and prefs.palette then
        local pal = string.lower(prefs.palette)
        print("[AmbientBoot] Applying saved palette:", pal)
        MaterialManager.SetPalette(pal)
    elseif err then
        print("[AmbientBoot] Failed to get material preferences:", err)
    end
end)

-- REMOVED palette and daytime providers - zones handle everything now with time rules!
-- The zone provider already checks SoundConfig.ShouldSoundPlay() which handles:
-- - Time-based filtering (birds only during day, crickets at night)
-- - Event-based variants (storm sounds, frozen water, etc.)
-- - All configured in SoundConfig.TimeRules - no code changes needed!

-- Use config-driven MaxConcurrent setting
local SoundConfig = require(MiningGame:WaitForChild("SoundConfig"))
AmbientController.SetMaxConcurrent(SoundConfig.AmbientSettings.MaxConcurrent or 2)
AmbientController.SetEnabled(true)
AmbientController.Start()

print("[AmbientBoot] Proximity ambient system started with palette + time-of-day providers")