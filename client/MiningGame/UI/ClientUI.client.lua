--!strict
-- ClientUI.client.lua
-- Bootstrap for the mining game UI system

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Wait for MiningGame to load
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Ready = require(MiningGame:WaitForChild("Ready"))
local Remotes = require(MiningGame:WaitForChild("Remotes"))
local Logger = require(MiningGame:WaitForChild("Logger"))
local log = Logger.new("ClientUI")
local AccountDataProvider = require(script.Parent.Parent:WaitForChild("Data"):WaitForChild("AccountDataProvider"))
local SoundManager = require(MiningGame:WaitForChild("SoundManager"))

-- Use EventBus for event handling
local EventBus = require(MiningGame:WaitForChild("EventBus"))
local EventNames = require(MiningGame:WaitForChild("EventNames"))
local Bus = EventBus.global()

-- Store unsub functions for cleanup
local unsubs: {() -> ()} = {}

-- Load UI modules
local UIManager = require(script.Parent:WaitForChild("UIManager"))
local MainHUD = require(script.Parent:WaitForChild("MainHUD"))
local UIUtils = require(ReplicatedStorage:WaitForChild("MiningGame"):WaitForChild("UI"):WaitForChild("UIUtils"))
local SettingsPanel = require(script.Parent:WaitForChild("Panels"):WaitForChild("SettingsPanel"))
local InventoryPanel = require(script.Parent:WaitForChild("Panels"):WaitForChild("InventoryPanel"))
local CashShopPanel = require(script.Parent:WaitForChild("Panels"):WaitForChild("CashShopPanel"))
local ItemIndexPanel = require(script.Parent:WaitForChild("Panels"):WaitForChild("ItemIndexPanel"))
local UpgradesPanel = require(script.Parent:WaitForChild("Panels"):WaitForChild("UpgradesPanel"))
local BoostBar = require(script.Parent:WaitForChild("Components"):WaitForChild("BoostBar"))

log:info("Initializing UI system...")

-- Wait for server to be ready before making any API calls
if not Ready.wait(30) then
    log:warn("Server not ready after 30s - UI bootstrap aborted")
    return
end
log:info("Server ready, continuing UI initialization...")

-- Initialize UI Manager
local manager = UIManager.new()
manager:init()

-- Make UIManager globally accessible for other systems
_G.UIManager = manager

-- Create and register Main HUD
local hud = MainHUD.new()
manager:registerScene(hud)
manager:showScene("MainHUD")

-- Mount BoostBar in bottom-right on main HUD container
task.defer(function()
    if manager and manager.container then
        BoostBar.mount(manager.container)
    end
end)

-- Create data providers (now safe to make API calls)
local accountDataProvider = AccountDataProvider.new(Remotes, UIUtils)

-- Create and register Settings Panel with provider
local settingsPanel = SettingsPanel.new({ accountDataProvider = accountDataProvider })
manager:registerScene(settingsPanel)

-- Create and register Inventory panel (W2)
local inventoryPanel = InventoryPanel.new({ accountDataProvider = accountDataProvider })
manager:registerScene(inventoryPanel)

-- Create and register Upgrades panel (dedicated panel mounting existing UpgradeTab)
local upgradesPanel = UpgradesPanel.new({ accountDataProvider = accountDataProvider })
manager:registerScene(upgradesPanel)


-- Create and register Cash Shop + Item Index panels (W5)
local cashShopPanel = CashShopPanel.new({ accountDataProvider = accountDataProvider })
manager:registerScene(cashShopPanel)

local itemIndexPanel = ItemIndexPanel.new({ accountDataProvider = accountDataProvider })
manager:registerScene(itemIndexPanel)

-- Track currency values locally to avoid re-fetching
local lastCoins = 0
local lastGems = 0

-- Load initial data and sync with HUD
local snapshot = accountDataProvider:getSnapshot()
if snapshot and snapshot.profile then
    lastCoins = snapshot.profile.coins or 0
    lastGems = snapshot.profile.gems or 0
    hud:SetCurrencies(lastCoins, lastGems)
    log:info("Initial profile - Coins: %d Gems: %d", lastCoins, lastGems)
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

-- Listen for announcements via EventBus
table.insert(unsubs, Bus:on(EventNames.ANNOUNCEMENT_BROADCAST, function(payload)
    local kind = (payload.type or "info"):lower()
    
    if kind == "banner" and payload.color then
        -- Server announcements - show with proper formatting
        manager:showServerAnnouncement(payload.message, payload.color)
        return
    end
    
    manager:showNotification(payload.message, kind)
end))

-- Listen for notifications via EventBus
table.insert(unsubs, Bus:on(EventNames.NOTIFICATION_PUSH, function(payload)
    local kind = (payload.type or "info"):lower()
    
    if kind == "banner" and payload.color then
        -- Server announcements - show with proper formatting
        manager:showServerAnnouncement(payload.message, payload.color)
        return
    end
    
    manager:showNotification(payload.message, kind)
end))

-- Cleanup on script destroy
script.Destroying:Connect(function()
    for _, unsub in ipairs(unsubs) do 
        pcall(unsub) 
    end
    table.clear(unsubs)
end)

-- Future: Listen for extraction updates when ExtractionService is ready
-- Remotes.RE.OnExtractionUpdated.OnClientEvent:Connect(function(curr: number, quota: number, tierName: string?)
--     hud:SetExtraction(curr, quota, tierName)
-- end)

-- Start background music after UI is ready
task.defer(function()
    if not SoundManager.GetCurrentMusic() then
        SoundManager.PlayMusic("main")
        log:info("Background music started: main")
    end
end)

log:info("UI system ready!")
