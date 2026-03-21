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
type PostFXManagerI = typeof(PostProcessingManager.new())
local Logger = require(MiningGame:WaitForChild("Logger"))

local log = Logger.new("PostFXService")
local singleton: PostFXManagerI? = nil
local PostFXService = {}

-- Get the singleton instance of PostProcessingManager
function PostFXService.Get(): PostFXManagerI
	if not singleton then
		singleton = PostProcessingManager.new()
		log:debug("Created PostProcessingManager singleton")
	end
	local inst = singleton
	if inst then
		return inst
	end
	error("PostFXService: singleton not initialized")
end

-- Destroy the singleton (useful for testing)
function PostFXService.Destroy()
	local inst = singleton
	if inst then
		inst:destroy()
		singleton = nil
		log:info("Destroyed PostProcessingManager singleton")
	else
		log:debug("No singleton to destroy")
	end
end

return PostFXService
