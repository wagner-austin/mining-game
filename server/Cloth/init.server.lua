--!strict
-- server/Cloth/init.server.lua
-- Wires remotes to the ClothService and runs the simulation tick on the server.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MiningGame = RS:WaitForChild("MiningGame")
local Logger = require(MiningGame:WaitForChild("Logger"))
local log = Logger.new("ClothInit")

local Remotes = require(MiningGame:WaitForChild("Remotes"))
local RF = Remotes.RF

-- Using simplified cloth service
local ClothService = require(script:WaitForChild("ClothServiceSimple"))

-- Remote handlers
RF.ClothSpawn.OnServerInvoke = function(player: Player, opts)
    local ok = ClothService:spawnFor(player)  -- Simple version doesn't use opts
    return { success = ok }
end

RF.ClothDestroy.OnServerInvoke = function(player: Player)
    ClothService:destroyFor(player)
    return { success = true }
end


-- Cleanup on leave
Players.PlayerRemoving:Connect(function(p)
    ClothService:destroyFor(p)
end)

-- Simulation tick
local last = tick()
RunService.Heartbeat:Connect(function(_dt)
    local now = tick()
    local dt = now - last
    last = now
    ClothService:step(dt)
end)

log:info("ClothService initialized")
