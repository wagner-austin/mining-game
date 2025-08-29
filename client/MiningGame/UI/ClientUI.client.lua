--!strict
-- ClientUI.client.lua
-- Bootstrap for the mining game UI system

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Wait for MiningGame to load
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Remotes = require(MiningGame:WaitForChild("Remotes"))
local AccountDataProvider = require(script.Parent.Parent:WaitForChild("Data"):WaitForChild("AccountDataProvider"))

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

-- Create data providers
local accountDataProvider = AccountDataProvider.new(Remotes, UIUtils)

-- Create and register Settings Panel with provider
local settingsPanel = SettingsPanel.new({ accountDataProvider = accountDataProvider })
manager:registerScene(settingsPanel)

-- Track currency values locally to avoid re-fetching
local lastCoins = 0
local lastGems = 0

-- Load initial data and sync with HUD
local snapshot = accountDataProvider:getSnapshot()
if snapshot and snapshot.profile then
    lastCoins = snapshot.profile.coins or 0
    lastGems = snapshot.profile.gems or 0
    hud:SetCurrencies(lastCoins, lastGems)
    print("[ClientUI] Initial profile - Coins:", lastCoins, "Gems:", lastGems)
else
    hud:SetCurrencies(0, 0)
end

-- Subscribe to data changes from provider
accountDataProvider:onChanged():Connect(function(key, value, snapshot)
    if snapshot and snapshot.profile then
        local profile = snapshot.profile
        if profile.coins ~= lastCoins or profile.gems ~= lastGems then
            lastCoins = profile.coins or 0
            lastGems = profile.gems or 0
            hud:SetCurrencies(lastCoins, lastGems)
        end
    end
end)

-- Guard remote event lookups to prevent crashes
local RE = Remotes and Remotes.RE
if RE then
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