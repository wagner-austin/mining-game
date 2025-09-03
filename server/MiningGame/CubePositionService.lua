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

-- Choose active strategy from config (fallback to "grid")
local function strategyFor(GameConfig)
    local name = (GameConfig.Multiplayer and GameConfig.Multiplayer.SPAWN_STRATEGY) or "grid"
    return Strategies[name] or Strategies.grid
end

-- Store manual overrides
local playerOrigins: {[Player]: CFrame} = {}

-- Store simulated positions for testing (userId -> CFrame)
local simulatedOrigins: {[number]: CFrame} = {}

-- Store assigned ordinals by userId for consistency across respawns
local userOrdinals: {[number]: number} = {}
local nextOrdinal = 1

-- Single source of truth for ordinal -> origin using selected strategy
function CubePositionService:ComputeDefaultOriginForOrdinal(ord: number): CFrame
    return strategyFor(GameConfig)(ord, GameConfig)
end

-- Get cube origin for a player or simulated userId
function CubePositionService:GetOrigin(playerOrUserId: Player | number): CFrame?
    -- Check if it's a simulated position (number userId)
    if typeof(playerOrUserId) == "number" then
        return simulatedOrigins[playerOrUserId]
    end
    
    local player = playerOrUserId :: Player
    -- Check for manual override first
    if playerOrigins[player] then
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
        log:debug("Assigned ordinal {} to userId {} ({})", ord, userId, player.Name)
    end
    
    return self:ComputeDefaultOriginForOrdinal(ord)
end

-- Set manual override for testing
function CubePositionService:SetOrigin(player: Player, origin: CFrame)
    playerOrigins[player] = origin
    log:info("Set origin for {} to {}", player.Name, tostring(origin.Position))
end

-- Register simulated position for testing
function CubePositionService:RegisterSimulatedPosition(userId: number, cf: CFrame)
    simulatedOrigins[userId] = cf
    log:debug("Registered simulated position for userId {} at {}", userId, tostring(cf.Position))
end

-- Unregister simulated position
function CubePositionService:UnregisterSimulatedPosition(userId: number)
    simulatedOrigins[userId] = nil
    log:debug("Unregistered simulated position for userId {}", userId)
end

-- Clear origin on player leave
Players.PlayerRemoving:Connect(function(player)
    playerOrigins[player] = nil
    -- Keep userOrdinals[player.UserId] so reconnects get same position
    -- Uncomment next line if you want reconnects to get a new position:
    -- userOrdinals[player.UserId] = nil
end)

log:info("Initialized")

return CubePositionService