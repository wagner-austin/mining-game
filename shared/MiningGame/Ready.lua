--!strict
-- Ready.lua – small utility to wait for server and data readiness
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Time = require(MiningGame:WaitForChild("Time"))

local Ready = {}

-- Wait until MiningGame:GetAttribute("ServerReady") is true, with optional timeout.
function Ready.wait(timeoutSec: number?): boolean
    timeoutSec = timeoutSec or 10
    if MiningGame:GetAttribute("ServerReady") then
        return true
    end
    local done = false
    local conn = MiningGame:GetAttributeChangedSignal("ServerReady"):Connect(function()
        if MiningGame:GetAttribute("ServerReady") then
            done = true
        end
    end)
    local t0 = Time.mono()
    while not done do
        if Time.mono() - t0 >= timeoutSec then
            if conn then conn:Disconnect() end
            return false
        end
        task.wait(0.05)
        if MiningGame:GetAttribute("ServerReady") then done = true end
    end
    if conn then conn:Disconnect() end
    return true
end

-- Alias for clarity
function Ready.waitServer(timeoutSec: number?): boolean
    return Ready.wait(timeoutSec)
end

-- Wait for an Instance attribute to become truthy
function Ready.waitAttribute(inst: Instance, attrName: string, timeoutSec: number?): boolean
    timeoutSec = timeoutSec or 10
    local t0 = Time.mono()
    local current = inst:GetAttribute(attrName)
    if current then return true end
    local done = false
    local conn = inst:GetAttributeChangedSignal(attrName):Connect(function()
        local val = inst:GetAttribute(attrName)
        if val then done = true end
    end)
    while not done do
        if Time.mono() - t0 >= timeoutSec then
            if conn then conn:Disconnect() end
            return false
        end
        task.wait(0.05)
        local val3 = inst:GetAttribute(attrName)
        if val3 then done = true end
    end
    if conn then conn:Disconnect() end
    return true
end

-- Composite wait: server and/or player data readiness
function Ready.waitAll(opts: { server: boolean?, playerData: boolean?, timeout: number?, player: Player? }): boolean
    opts = opts or {} :: any
    local needServer = (opts.server ~= false)
    local needPlayerData = (opts.playerData == true)
    local budget = opts.timeout or 10

    local deadline = Time.mono() + budget
    if needServer then
        local remaining = math.max(0, deadline - Time.mono())
        if not Ready.wait(remaining) then return false end
    end
    if needPlayerData then
        local player = opts.player or Players.LocalPlayer
        if player then
            local remaining = math.max(0, deadline - Time.mono())
            if not Ready.waitAttribute(player, "DataLoaded", remaining) then return false end
        end
    end
    return true
end

return Ready
