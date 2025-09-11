--!strict
-- PostFXService.lua
-- Singleton accessor for the PostProcessingManager

local RunService = game:GetService("RunService")
if RunService:IsServer() then
	error("PostFXService must run on the client", 0)
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local PostProcessing = MiningGame:WaitForChild("PostProcessing")
local PostProcessingManager = require(PostProcessing:WaitForChild("PostProcessingManager"))
local Logger = require(MiningGame:WaitForChild("Logger"))

local log = Logger.new("PostFXService")
local singleton = nil
local PostFXService = {}

-- Get the singleton instance of PostProcessingManager
function PostFXService.Get()
	if not singleton then
		singleton = PostProcessingManager.new()
		log:debug("Created PostProcessingManager singleton")
	end
	return singleton
end

-- Destroy the singleton (useful for testing)
function PostFXService.Destroy()
	if singleton then
		singleton:destroy()
		singleton = nil
		log:info("Destroyed PostProcessingManager singleton")
	else
		log:debug("No singleton to destroy")
	end
end

return PostFXService