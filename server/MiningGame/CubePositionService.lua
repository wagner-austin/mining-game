--!strict
-- CubePositionService.server.lua
-- Single source of truth for cube positioning

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(Shared:WaitForChild("Logger"))
local log = Logger.new("CubePositionService")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Strategies = require(script.Parent.SpawnStrategies)

local CubePositionService = {}

-- Store manual overrides (moved before Start method that uses them)
local playerOrigins: { [Player]: CFrame } = {}

-- Store simulated positions for testing (userId -> CFrame)
local simulatedOrigins: { [number]: CFrame } = {}

-- Initialize with DI container (no dependencies currently)
function CubePositionService:Init(_container)
	-- No dependencies needed currently
	log:info("Initialized")
end

-- Start method to connect events after all services are initialized
function CubePositionService:Start(_container)
	-- Clear origin on player leave
	Players.PlayerRemoving:Connect(function(player)
		playerOrigins[player] = nil
		-- Keep userOrdinals[player.UserId] so reconnects get same position
		-- Uncomment next line if you want reconnects to get a new position:
		-- userOrdinals[player.UserId] = nil
	end)

	log:info("Started with player connections")
end

-- Choose active strategy (uses SpawnStrategies dynamic getter which checks GameConfig)
local function strategyFor()
	local name = Strategies.GetCurrentStrategyName()
	local strategy = Strategies[name] or Strategies.grid
	log:debug("Using spawn strategy: %s (function=%s)", name, tostring(strategy))
	return strategy
end

-- Store assigned ordinals by userId for consistency across respawns
local userOrdinals: { [number]: number } = {}
local nextOrdinal = 1

-- Single source of truth for ordinal -> origin using selected strategy
function CubePositionService:ComputeDefaultOriginForOrdinal(ord: number): CFrame
	log:debug("ComputeDefaultOriginForOrdinal called for ordinal %d", ord)
	local cf = strategyFor()(ord, GameConfig)
	log:info("Computed origin for ordinal %d: %s", ord, tostring(cf.Position))
	return cf
end

-- Get cube origin for a player or simulated userId
function CubePositionService:GetOrigin(playerOrUserId: Player | number): CFrame?
	-- Check if it's a simulated position (number userId)
	if typeof(playerOrUserId) == "number" then
		local simOrigin = simulatedOrigins[playerOrUserId]
		if simOrigin then
			log:debug("Returning simulated origin for userId %d: %s", playerOrUserId, tostring(simOrigin.Position))
		end
		return simOrigin
	end

	local player = playerOrUserId :: Player
	-- Check for manual override first
	if playerOrigins[player] then
		log:debug("Returning manual override origin for %s: %s", player.Name, tostring(playerOrigins[player].Position))
		return playerOrigins[player]
	end

	-- Get or assign a persistent ordinal for this userId
	local userId = player.UserId
	local ord = userOrdinals[userId]
	if not ord then
		-- Assign new ordinal and store it
		ord = nextOrdinal
		userOrdinals[userId] = ord
		nextOrdinal = nextOrdinal + 1
		log:info("Assigned NEW ordinal %d to userId %d (%s)", ord, userId, player.Name)
	else
		log:debug("Using existing ordinal %d for userId %d (%s)", ord, userId, player.Name)
	end

	-- Return computed origin (SpawnService will freeze it via SetOrigin)
	return self:ComputeDefaultOriginForOrdinal(ord)
end

-- Set manual override for testing
function CubePositionService:SetOrigin(player: Player, origin: CFrame)
	playerOrigins[player] = origin
	log:info("Set origin for %s to %s", player.Name, tostring(origin.Position))
end

-- Register simulated position for testing
function CubePositionService:RegisterSimulatedPosition(userId: number, cf: CFrame)
	simulatedOrigins[userId] = cf
	log:debug("Registered simulated position for userId %d at %s", userId, tostring(cf.Position))
end

-- Unregister simulated position
function CubePositionService:UnregisterSimulatedPosition(userId: number)
	simulatedOrigins[userId] = nil
	log:debug("Unregistered simulated position for userId %d", userId)
end

-- Player events moved to Start method

log:info("Initialized")

return CubePositionService
