--!strict
-- CubePositionService.server.lua
-- Single source of truth for cube positioning

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local CubePositionService = {}

-- Store manual overrides
local playerOrigins: {[Player]: CFrame} = {}

-- Get cube origin for a player
function CubePositionService:GetOrigin(player: Player): CFrame
    -- Check for manual override first
    if playerOrigins[player] then
        return playerOrigins[player]
    end
    
    -- Calculate default position in neighborhood grid
    local playerIndex = 0
    for i, p in ipairs(Players:GetPlayers()) do
        if p == player then
            playerIndex = i - 1
            break
        end
    end
    
    local spacing = GameConfig.Multiplayer.CUBE_SPACING
    local gridX = playerIndex % 3
    local gridZ = math.floor(playerIndex / 3)
    
    -- Raise cube by half its height so it sits ON the baseplate
    local cubeY = GameConfig.Grid.CUBE_SIZE_STUDS / 2
    
    return CFrame.new(gridX * spacing, cubeY, gridZ * spacing)
end

-- Set manual override for testing
function CubePositionService:SetOrigin(player: Player, origin: CFrame)
    playerOrigins[player] = origin
    print(string.format("[CubePositionService] Set origin for %s to %s", player.Name, tostring(origin.Position)))
end

-- Clear origin on player leave
Players.PlayerRemoving:Connect(function(player)
    playerOrigins[player] = nil
end)

print("[CubePositionService] Initialized")

return CubePositionService