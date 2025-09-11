--!strict
-- Ready.lua — small utility to wait for server readiness
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
            conn:Disconnect()
            return false
        end
        task.wait(0.05)
    end
    conn:Disconnect()
    return true
end

return Ready