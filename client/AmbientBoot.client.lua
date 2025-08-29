--!strict
-- AmbientBoot.client.lua
-- Bootstrap for proximity-based ambient sound system

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local AmbientController = require(MiningGame:WaitForChild("AmbientController"))
local MaterialManager = require(MiningGame:WaitForChild("MaterialManager"))

-- Initialize MaterialManager to handle palette-based lighting
MaterialManager.Initialize()

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