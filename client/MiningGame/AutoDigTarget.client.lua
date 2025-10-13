--!strict
-- AutoDigTarget.client.lua
-- Streams mouse world position at a modest rate so server auto-dig can follow aim

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Remotes = require(MiningGame:WaitForChild("Remotes"))

local localPlayer = Players.LocalPlayer
local mouse = localPlayer and localPlayer:GetMouse() or nil

-- Config
local SEND_INTERVAL = 0.1 -- 10 Hz
local DEADZONE_STUDS = 1.0 -- Only send if moved beyond this

local lastSentAt = 0.0
local lastPos: Vector3? = nil

-- Get target RemoteEvent safely (created by server during startup)
local function getRE(): RemoteEvent?
    local re = Remotes.RE["AutoDig_SetTarget"]
    if re then return re end
    -- Fallback: try to discover lazily (Remotes accessor watches additions)
    local folder = Remotes.Folder
    if folder then
        local inst = folder:FindFirstChild("AutoDig_SetTarget")
        if inst and inst:IsA("RemoteEvent") then
            return inst
        end
    end
    return nil
end

RunService.RenderStepped:Connect(function()
    -- Rate limit
    local now = os.clock()
    if (now - lastSentAt) < SEND_INTERVAL then return end
    if not mouse then return end

    -- Mouse.Hit is a CFrame; .p gives the position
    local hit = mouse.Hit
    if not hit then return end
    local pos = hit.p

    if lastPos and (pos - lastPos).Magnitude < DEADZONE_STUDS then
        return
    end

    local re = getRE()
    if re then
        lastSentAt = now
        lastPos = pos
        re:FireServer(pos)
    end
end)

