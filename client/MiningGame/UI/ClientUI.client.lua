--!strict
-- ClientUI.client.lua
-- Bootstrap for the mining game UI system

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Wait for MiningGame to load
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Remotes = require(MiningGame:WaitForChild("Remotes"))

-- Load UI modules
local UIManager = require(script.Parent:WaitForChild("UIManager"))
local MainHUD = require(script.Parent:WaitForChild("MainHUD"))
local UIUtils = require(ReplicatedStorage:WaitForChild("MiningGame"):WaitForChild("UI"):WaitForChild("UIUtils"))
local SettingsPanel = require(script.Parent:WaitForChild("Panels"):WaitForChild("SettingsPanel"))

print("[ClientUI] Initializing UI system...")

-- Initialize UI Manager
local manager = UIManager.new()
manager:init()

-- Create and register Main HUD
local hud = MainHUD.new()
manager:registerScene(hud)
manager:showScene("MainHUD")

-- Create and register Settings Panel
local settingsPanel = SettingsPanel.new()
manager:registerScene(settingsPanel)

-- Track currency values locally to avoid re-fetching
local lastCoins = 0
local lastGems = 0

-- Load initial data with retry
task.spawn(function()
    local profile = UIUtils.getProfileWithRetry(Remotes, 3, 1)
    if profile then
        lastCoins = profile.profile.coins or 0
        lastGems = profile.profile.gems or 0
        hud:SetCurrencies(lastCoins, lastGems)
        print("[ClientUI] Profile loaded - Coins:", lastCoins, "Gems:", lastGems)
    else
        print("[ClientUI] Failed to load profile after retries")
        hud:SetCurrencies(0, 0)
    end
end)

-- Guard remote event lookups to prevent crashes
local RE = Remotes and Remotes.RE
if RE then
    -- Currency changes (RE is a table, not an Instance)
    local onCurrency = RE.OnCurrencyChanged
    if onCurrency then
        pcall(function()
            onCurrency.OnClientEvent:Connect(function(currencyType: string, newValue: number)
                print("[ClientUI] Currency changed:", currencyType, newValue)
                if currencyType == "coins" then 
                    lastCoins = newValue
                elseif currencyType == "gems" then 
                    lastGems = newValue 
                end
                hud:SetCurrencies(lastCoins, lastGems)
            end)
        end)
    else
        print("[ClientUI] OnCurrencyChanged not found (ok for now)")
    end

    -- Notifications
    local onNotif = RE.OnNotification
    if onNotif then
        onNotif.OnClientEvent:Connect(function(notification)
            local notifType = notification.notificationType or "info"
            manager:showNotification(notification.message, notifType)
        end)
    else
        print("[ClientUI] OnNotification not found (using local test toasts)")
    end
else
    print("[ClientUI] Remote events not found - using test mode")
end

-- Future: Listen for extraction updates when ExtractionService is ready
-- Remotes.RE.OnExtractionUpdated.OnClientEvent:Connect(function(curr: number, quota: number, tierName: string?)
--     hud:SetExtraction(curr, quota, tierName)
-- end)

print("[ClientUI] UI system ready!")