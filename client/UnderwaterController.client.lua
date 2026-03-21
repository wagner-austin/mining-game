--!strict
-- UnderwaterController.client.lua
-- Applies underwater post-processing effects when player is swimming

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local PostProcessing = MiningGame:WaitForChild("PostProcessing")
local PostFXService = require(PostProcessing:WaitForChild("PostFXService"))
local PostProcessingSettings = require(PostProcessing:WaitForChild("PostProcessingSettings"))
local Logger = require(MiningGame:WaitForChild("Logger"))
local Time = require(MiningGame:WaitForChild("Time"))

local log = Logger.new("UnderwaterController")

-- Debounce settings to prevent flickering in shallow water
local DEBOUNCE_TIME = 0.15 -- seconds

local function onCharacter(character: Model)
	-- Check if underwater effects are enabled
	if not PostProcessingSettings.Enabled or not PostProcessingSettings.Features.UnderwaterEffects then
		log:debug("Underwater effects disabled in settings")
		return
	end

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local manager: any = PostFXService.Get()

	local wasSwimming = false
	local lastStateChange = 0

	humanoid.StateChanged:Connect(function(_, newState)
		local now = Time.mono()

		-- Debounce rapid state changes
		if now - lastStateChange < DEBOUNCE_TIME then
			return
		end

		local isSwimming = (newState == Enum.HumanoidStateType.Swimming)

		if isSwimming and not wasSwimming then
			-- Enter water
			manager.apply(manager, "underwater")
			wasSwimming = true
			lastStateChange = now
			log:debug("Entered water - applying underwater effects")
		elseif wasSwimming and not isSwimming then
			-- Exit water
			manager.remove(manager, "underwater")
			wasSwimming = false
			lastStateChange = now
			log:debug("Exited water - removing underwater effects")
		end
	end)

	log:debug("Monitoring swimming state for character")
end

-- Connect to player's character
local player = Players.LocalPlayer
player.CharacterAdded:Connect(onCharacter)

-- Handle existing character
if player.Character then
	onCharacter(player.Character)
end

log:info("Underwater controller initialized")
