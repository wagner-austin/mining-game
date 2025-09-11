--!strict
-- Bootstrap.client.lua
-- Initializes the cosmetic controller

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Ready = require(MiningGame:WaitForChild("Ready"))

local controller = require(script.Parent.CosmeticController)

-- Wait for server to be ready before initializing cosmetics
if not Ready.wait(10) then
    warn("[CosmeticBootstrap] Server not ready; initializing anyway to hook events")
    -- Still call init() to hook character events; RFs will work once server is ready
end

controller:init()

-- Expose globally for testing/debugging
_G.CosmeticController = controller