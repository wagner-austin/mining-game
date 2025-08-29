--[[
    Gravity Controller for Mining Game
    ===================================
    Sets the server-wide gravity based on configuration.
    This affects all players equally and creates a consistent physics environment.
    
    Location: ServerScriptService/MiningGame/Gravity.server.lua
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for Movement configuration to be available
local Movement = ReplicatedStorage:WaitForChild("Movement")
local Config = require(Movement:WaitForChild("Config"))

-- Default Roblox gravity is 196.2 studs/second²
local DEFAULT_GRAVITY = 196.2

-- Apply gravity multiplier from config
local gravityMult = Config.GRAVITY_MULT or 1.0

-- Clamp gravity to reasonable values to prevent physics issues
local newGravity = math.clamp(DEFAULT_GRAVITY * gravityMult, 50, 600)

-- Set workspace gravity
workspace.Gravity = newGravity

-- Log the gravity change
print(string.format("[Gravity] Set server gravity to %.1f (%.2fx normal)", newGravity, gravityMult))

-- Optional: Listen for gravity changes if we want dynamic gravity events later
-- This could be useful for special zones or events
workspace:GetPropertyChangedSignal("Gravity"):Connect(function()
    print(string.format("[Gravity] Gravity changed to %.1f", workspace.Gravity))
end)