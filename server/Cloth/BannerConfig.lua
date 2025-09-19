--!strict
-- BannerConfig.lua
-- Central config for base banner placement/orientation/colors with simple setters

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(MiningGame:WaitForChild("Logger"))
local log = Logger.new("BannerConfig")

local Config = {}

Config.TUNE = {
    -- DO NOT TOUCH in normal use: PITCH_X_DEG tilts the banner. +90 hangs upright; 0 makes it flat.
    PITCH_X_DEG = 90,   -- X axis (pitch)
    -- DO NOT TOUCH in normal use: YAW_Y_DEG "spins the sign" like a sign spinner (rotates around vertical).
    YAW_Y_DEG = 0,      -- Y axis (yaw)
    -- Preferred control for facing: ROLL_Z_DEG "rotates the face" (0/90/180/270) without affecting hang/spin.
    ROLL_Z_DEG = 90,    -- Z axis (roll)
    LIFT_Y = 24,
    INWARD_X_T = 0.05,  -- 0..1 left->right
    INSIDE_Z = -4.0,    -- additive after along-edge
    ALONG_Z_T = 0.625,  -- 0..1 front->back
    COLOR = Color3.fromRGB(10, 30, 170),
    MATCH_GLOW_TO_BANNER = true,
    -- Optional multi‑spawn slots (normalized positions). If nil, spawns one banner using ALONG_Z_T/INWARD_X_T.
    -- Each slot: { alongZT = 0..1, inwardXT = 0..1 }
    -- Spawn three banners: first at current T, next two slightly higher along the Z edge.
    SLOTS = {
        { alongZT = 0.625, inwardXT = 0.05, color = Color3.fromRGB(10, 30, 170) }, -- dark blue
        { alongZT = 0.700, inwardXT = 0.05, color = Color3.fromRGB(170, 120, 0) },  -- dark yellow
        { alongZT = 0.775, inwardXT = 0.05, color = Color3.fromRGB(0, 120, 40) },   -- dark green
        { alongZT = 0.850, inwardXT = 0.05, color = Color3.fromRGB(100, 0, 160) },  -- dark purple
    },
}

function Config.update(partial: {[string]: any})
    for k, v in pairs(partial) do
        if Config.TUNE[k] ~= nil then
            Config.TUNE[k] = v
        else
            log:warn("Ignoring unknown banner config key: %s", tostring(k))
        end
    end
    return Config.TUNE
end

function Config.get()
    return Config.TUNE
end

return Config
