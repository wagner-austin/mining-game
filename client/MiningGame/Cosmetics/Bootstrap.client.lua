--!strict
-- Bootstrap.client.lua
-- Initializes the cosmetic controller

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Ready = require(MiningGame:WaitForChild("Ready"))

local controller = require(script.Parent.CosmeticController)

-- Wait for server to be ready before initializing cosmetics
if not Ready.wait(10) then
    warn("[CosmeticBootstrap] Server not ready; initializing anyway to hook events")
    -- Still call init() to hook character events; RFs will work once server is ready
end

controller:init()

-- After init, perform one-time initial sync for local player only when readiness succeeds
if Ready.waitAll({ server = true, playerData = true, timeout = 20 }) then
    controller:initialSyncLocal()
end

-- Expose globally for testing/debugging (Studio only)
if RunService:IsStudio() then
    _G.CosmeticController = controller
end
