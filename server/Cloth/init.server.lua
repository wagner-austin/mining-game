--!strict
-- server/Cloth/init.server.lua
-- Wires remotes to the ClothService and runs the simulation tick on the server.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MiningGame = RS:WaitForChild("MiningGame")
local Logger = require(MiningGame:WaitForChild("Logger"))
local log = Logger.new("ClothInit")

-- Using simplified cloth service
local ClothService = require(script:WaitForChild("ClothServiceSimple"))

-- Remote handlers are now managed by RFRegistry via ClothDebug.rf.lua
-- The RF handlers in RemoteFns/ClothDebug.rf.lua will call ClothService methods


-- Cleanup on leave
Players.PlayerRemoving:Connect(function(p)
    ClothService:destroyFor(p)
end)

-- Simulation tick
RunService.Heartbeat:Connect(function(dt)
    ClothService:step(dt)
end)

log:info("ClothService initialized")
