--!strict
-- Dig/AutoLoop.lua
-- Auto-dig loop (monetization). Encapsulates state and loop logic.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(Shared:WaitForChild("Logger"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Time = require(Shared:WaitForChild("Time"))

local log = Logger.new("AutoLoop")

local autoDigState: {[Player]: {active: boolean, version: number}} = {}
local autoDigVersion: {[Player]: number} = {}

local function runAutoDigLoop(service, player: Player)
    autoDigVersion[player] = (autoDigVersion[player] or 0) + 1
    local myVer = autoDigVersion[player]

    while autoDigState[player] and autoDigState[player].active and myVer == autoDigVersion[player] and player.Parent do
        local profile = service._container:Get("DataService"):GetPlayerData(player)
        if not profile or not profile.boosts or not profile.boosts.auto_dig or Time.unix() >= profile.boosts.auto_dig then
            log:debug("Auto-dig expired for {}", player.Name)
            break
        end

        local character = player.Character
        if character then
            local hrp = character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local digPos = hrp.Position - Vector3.new(0, 5, 0)
                local result = service:ProcessDigRequest(player, digPos)
                local sleepSec = 1.0
                if result and result.nextAllowedAt then
                    sleepSec = math.max(result.nextAllowedAt - Time.mono(), 0.5)
                else
                    sleepSec = 1.0
                end
                task.wait(math.max(sleepSec, 0.5))
            else
                task.wait(1)
            end
        else
            task.wait(1)
        end
    end

    if autoDigState[player] and autoDigState[player].version == myVer then
        autoDigState[player] = nil
    end
    log:info("Auto-dig stopped for {}", player.Name)
end

local AutoLoop = {}

function AutoLoop.Start(service, player: Player)
    local profile = service._container:Get("DataService"):GetPlayerData(player)
    if not profile or not profile.boosts or not profile.boosts.auto_dig or Time.unix() >= profile.boosts.auto_dig then
        log:debug("Cannot start auto-dig: no active boost for {}", player.Name)
        return false
    end
    AutoLoop.Stop(service, player)
    autoDigState[player] = { active = true, version = (autoDigVersion[player] or 0) + 1 }
    log:info("Starting auto-dig for {} (expires at {})", player.Name, profile.boosts.auto_dig)
    task.spawn(function() runAutoDigLoop(service, player) end)
    return true
end

function AutoLoop.Stop(service, player: Player)
    if autoDigState[player] then
        log:debug("Stopping auto-dig for {}", player.Name)
        autoDigState[player].active = false
    end
    autoDigVersion[player] = (autoDigVersion[player] or 0) + 1
end

function AutoLoop.CleanupOnRemoving(service, player: Player)
    autoDigState[player] = nil
    autoDigVersion[player] = nil
end

return AutoLoop

