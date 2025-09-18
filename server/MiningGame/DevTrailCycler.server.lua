--!strict
-- DevTrailCycler.server.lua
-- Studio-only: Auto-cycles all trail cosmetics for quick visual verification.

local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
    return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(MiningGame:WaitForChild("Logger"))
local log = Logger.new("DevTrailCycler")

local CosmeticDefinitions = require(MiningGame:WaitForChild("CosmeticDefinitions"))

-- Gather all trail IDs deterministically
local TRAILS: {string} = {}
do
    local trailMap = CosmeticDefinitions.GetByCategory("trail")
    for id in pairs(trailMap) do
        table.insert(TRAILS, id)
    end
    table.sort(TRAILS)
end

if #TRAILS == 0 then
    warn("[DevTrailCycler] No trail definitions found; skipping auto-cycle")
    return
end

-- 5-second cadence per item
local RATE_SEC = 5.0

local function getInventoryService()
    for _ = 1, 200 do -- ~20s
        local container = _G.MiningGameServices and _G.MiningGameServices.container
        if container then
            local ok, svc = pcall(function()
                return container:Get("InventoryService")
            end)
            if ok and svc then return svc end
        end
        task.wait(0.1)
    end
    return nil
end

local InventoryService = getInventoryService()
if not InventoryService then
    warn("[DevTrailCycler] InventoryService not available; skipping auto-cycle")
    return
end

local running: {[Player]: boolean} = {}

local function startCycle(player: Player)
    if running[player] then return end
    running[player] = true
    task.spawn(function()
        local i = 1
        log:info("Starting trail cycle for %s", player.Name)
        while running[player] and player.Parent == Players do
            local id = TRAILS[i]
            i = (i % #TRAILS) + 1
            pcall(function()
                InventoryService:AddItem(player, id, 1)
                InventoryService:EquipItem(player, id)
            end)
            task.wait(RATE_SEC)
        end
        log:info("Stopped trail cycle for %s", player.Name)
    end)
end

local function stopCycle(player: Player)
    running[player] = nil
end

Players.PlayerAdded:Connect(startCycle)
Players.PlayerRemoving:Connect(stopCycle)
for _, p in ipairs(Players:GetPlayers()) do
    startCycle(p)
end

