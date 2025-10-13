--!strict
-- RespawnPedestal.client.lua
-- Binds a proximity action to the player's Respawn pedestal using ProximityAction.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(MiningGame:WaitForChild("Logger"))
local ProximityAction = require(script.Parent:WaitForChild("ProximityAction"))
local ClientRF = require(MiningGame:WaitForChild("ClientRF"))
local GameConfig = require(MiningGame:WaitForChild("GameConfig"))
local Theme = require(MiningGame:WaitForChild("UI"):WaitForChild("Theme"))

local log = Logger.new("RespawnPedestalClient")

local player = Players.LocalPlayer

local function resolvePedestal(): Model?
    local bases = workspace:FindFirstChild("PlayerBases")
    if not bases then return nil end
    local baseModel = bases:FindFirstChild("PlayerBase_" .. tostring(player.UserId))
    if not baseModel or not baseModel:IsA("Model") then return nil end
    local pedestal = baseModel:FindFirstChild("RespawnPedestal_" .. tostring(player.UserId))
    if pedestal and pedestal:IsA("Model") then
        return pedestal
    end
    return nil
end

local binding = ProximityAction.bindMainHUD({
    id = "respawn_pedestal",
    resolveTarget = resolvePedestal,
    rangeStuds = 20,
    label = "Respawn Cube",
    icon = "⛏️",
    onActivate = function()
        -- Full reset + reseed with 95% remaining gate
        local data, err = ClientRF.call("Cube_ResetFull")
        if err then
            log:warn("Respawn RF error: %s", tostring(err))
            -- Show a player-facing toast with threshold and current progress
            local thresholdFrac = (GameConfig.Reset and GameConfig.Reset.MANUAL_RESET_MIN_MINED_FRAC) or 0.05
            local thresholdPct = math.floor(thresholdFrac * 100 + 0.5)
            -- Try to fetch current dug percentage
            local minedPctStr = nil
            local prof, perr = ClientRF.call("GetProfile")
            if prof and prof.cubeStats and prof.cubeStats.dugCells then
                local dug = prof.cubeStats.dugCells or 0
                local cellSize = GameConfig.Grid.CELL_SIZE_STUDS
                local cubeSide = math.floor((GameConfig.Grid.CUBE_SIZE_STUDS / cellSize) + 0.5)
                local totalCells = math.max(1, cubeSide * cubeSide * cubeSide)
                local minedFrac = math.clamp(dug / totalCells, 0, 1)
                minedPctStr = tostring(math.floor(minedFrac * 100 + 0.5)) .. "%"
            end
            local msg = string.format("Manual reset becomes available after at least %d%% mined%s", thresholdPct, minedPctStr and (" • You are at " .. minedPctStr) or "")
            if _G and _G.UIManager and _G.UIManager.showNotification then
                _G.UIManager:showNotification(msg, "error")
            end
        elseif not data or data.ok ~= true then
            log:warn("Respawn denied: %s", data and tostring(data.reason) or "unknown")
            local thresholdFrac = (GameConfig.Reset and GameConfig.Reset.MANUAL_RESET_MIN_MINED_FRAC) or 0.05
            local thresholdPct = math.floor(thresholdFrac * 100 + 0.5)
            local msg = string.format("Manual reset becomes available after at least %d%% mined", thresholdPct)
            if _G and _G.UIManager and _G.UIManager.showNotification then
                _G.UIManager:showNotification(msg, "error")
            end
        else
            log:info("Cube reset with new seed: %s", tostring(data.seed))
            if _G and _G.UIManager and _G.UIManager.showNotification then
                _G.UIManager:showNotification("Respawning your cube...", "info")
            end
        end
        end,
        widthPx = (Theme.homeButton.width + 90),
    })

