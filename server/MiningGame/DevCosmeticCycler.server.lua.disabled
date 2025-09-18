--!strict
-- DevCosmeticCycler.server.lua
-- Studio-only: Auto-cycles a set of head cosmetics for quick visual testing.

local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
    return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(MiningGame:WaitForChild("Logger"))
local log = Logger.new("DevCosmeticCycler")

local RATE_SEC = 1.0

local ITEMS_TO_CYCLE = {
    -- Kept items only
    "head_horns_neon",
    "head_halo_thick",
    "head_crown_gold",
    "head_speed_charm",
    "head_glasses_sunglasses",
}

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
    warn("[DevCosmeticCycler] InventoryService not available; skipping auto-cycle")
    return
end

local running: {[Player]: boolean} = {}

local function startCycle(player: Player)
    if running[player] then return end
    running[player] = true
    task.spawn(function()
        local i = 1
        log:info("Starting cosmetic cycle for %s", player.Name)
        while running[player] and player.Parent == Players do
            local id = ITEMS_TO_CYCLE[i]
            i = (i % #ITEMS_TO_CYCLE) + 1
            pcall(function()
                InventoryService:AddItem(player, id, 1)
                InventoryService:EquipItem(player, id)
            end)
            task.wait(RATE_SEC)
        end
        log:info("Stopped cosmetic cycle for %s", player.Name)
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
