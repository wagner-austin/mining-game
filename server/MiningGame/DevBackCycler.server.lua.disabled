--!strict
-- DevBackCycler.server.lua
-- Studio-only: Auto-cycles curated back (wings) cosmetics for quick visual verification.

local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
    return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(MiningGame:WaitForChild("Logger"))
local log = Logger.new("DevBackCycler")

local CosmeticDefinitions = require(MiningGame:WaitForChild("CosmeticDefinitions"))

local BACKS: {string} = {
    "back_angel",
    "back_demon",
    "back_void",
    "back_rainbow_wings",
    "back_quad_wings",
}

for _, id in ipairs(BACKS) do
    local def = CosmeticDefinitions.Get(id)
    if not def then
        warn(string.format("[DevBackCycler] Missing definition for %s", id))
    elseif def.slot ~= "back" then
        warn(string.format("[DevBackCycler] %s has unexpected slot %s", id, tostring(def.slot)))
    else
        log:info("Back OK: %s (%s)", id, tostring(def.asset or def.procedural or ""))
    end
end

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
    warn("[DevBackCycler] InventoryService not available; skipping auto-cycle")
    return
end

local running: {[Player]: boolean} = {}

local function startCycle(player: Player)
    if running[player] then return end
    running[player] = true
    task.spawn(function()
        local i = 1
        log:info("Starting back cycle for %s", player.Name)
        while running[player] and player.Parent == Players do
            local id = BACKS[i]
            i = (i % #BACKS) + 1
            pcall(function()
                InventoryService:AddItem(player, id, 1)
                InventoryService:EquipItem(player, id)
            end)
            task.wait(RATE_SEC)
        end
        log:info("Stopped back cycle for %s", player.Name)
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
