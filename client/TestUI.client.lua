--!strict
-- TestUI.client.lua
-- Simple UI for testing the mining game backend

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

print("[TestUI] Starting UI test client...")

-- Wait for MiningGame
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame", 30)
assert(MiningGame, "MiningGame not found")
local Remotes = require(MiningGame:WaitForChild("Remotes"))

-- Create test UI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MiningTestUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- Stats display frame
local statsFrame = Instance.new("Frame")
statsFrame.Size = UDim2.new(0, 300, 0, 200)
statsFrame.Position = UDim2.new(0, 10, 0, 10)
statsFrame.BackgroundColor3 = Color3.new(0, 0, 0)
statsFrame.BackgroundTransparency = 0.3
statsFrame.BorderSizePixel = 0
statsFrame.Parent = screenGui

local statsLabel = Instance.new("TextLabel")
statsLabel.Size = UDim2.new(1, -10, 1, -10)
statsLabel.Position = UDim2.new(0, 5, 0, 5)
statsLabel.BackgroundTransparency = 1
statsLabel.TextColor3 = Color3.new(1, 1, 1)
statsLabel.TextScaled = false
statsLabel.TextSize = 14
statsLabel.TextXAlignment = Enum.TextXAlignment.Left
statsLabel.TextYAlignment = Enum.TextYAlignment.Top
statsLabel.Font = Enum.Font.Code
statsLabel.Text = "Loading stats..."
statsLabel.Parent = statsFrame

-- Button container
local buttonFrame = Instance.new("Frame")
buttonFrame.Size = UDim2.new(0, 150, 0, 320)
buttonFrame.Position = UDim2.new(1, -160, 0.5, -100)
buttonFrame.BackgroundColor3 = Color3.new(0, 0, 0)
buttonFrame.BackgroundTransparency = 0.3
buttonFrame.BorderSizePixel = 0
buttonFrame.Parent = screenGui

-- Helper to create buttons
local function createButton(text: string, position: number, callback: () -> ())
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(1, -10, 0, 40)
    button.Position = UDim2.new(0, 5, 0, 5 + (position * 45))
    button.BackgroundColor3 = Color3.new(0.2, 0.2, 0.2)
    button.TextColor3 = Color3.new(1, 1, 1)
    button.Text = text
    button.Font = Enum.Font.SourceSans
    button.TextSize = 16
    button.Parent = buttonFrame
    
    button.MouseButton1Click:Connect(callback)
    
    return button
end


-- Update stats display
local function updateStats()
    local profile = Remotes.RF.GetProfile:InvokeServer()
    
    if profile then
        local stats = {}
        table.insert(stats, "=== PLAYER STATS ===")
        table.insert(stats, string.format("Coins: %d", profile.profile.coins))
        table.insert(stats, string.format("Gems: %d", profile.profile.gems))
        table.insert(stats, string.format("Blocks Dug: %d", profile.profile.totalBlocksDug))
        table.insert(stats, "")
        table.insert(stats, "=== EFFECTIVE STATS ===")
        table.insert(stats, string.format("Dig Delay: %.2fs", profile.effectiveStats.delay))
        table.insert(stats, string.format("Dig Depth: %d", profile.effectiveStats.depth))
        table.insert(stats, string.format("Dig Radius: %d", profile.effectiveStats.radius))
        table.insert(stats, string.format("Luck: %.2fx", profile.effectiveStats.luck))
        
        if profile.profile.inventory then
            local itemCount = 0
            for _ in pairs(profile.profile.inventory) do
                itemCount = itemCount + 1
            end
            table.insert(stats, "")
            table.insert(stats, string.format("Items in inventory: %d", itemCount))
        end
        
        statsLabel.Text = table.concat(stats, "\n")
    else
        statsLabel.Text = "Failed to load profile"
    end
end

-- Other test buttons
createButton("Buy Speed Up", 0, function()
    local result = Remotes.RF.PurchaseUpgrade:InvokeServer("speed")
    if result.success then
        print("Speed upgraded to level", result.newLevel)
        updateStats()
    else
        print("Speed upgrade failed:", result.reason)
    end
end)

createButton("Buy Strength Up", 1, function()
    local result = Remotes.RF.PurchaseUpgrade:InvokeServer("strength")
    if result.success then
        print("Strength upgraded to level", result.newLevel)
        updateStats()
    else
        print("Strength upgrade failed:", result.reason)
    end
end)

createButton("Buy Radius Up", 2, function()
    local result = Remotes.RF.PurchaseUpgrade:InvokeServer("radius")
    if result.success then
        print("Radius upgraded to level", result.newLevel)
        updateStats()
    else
        print("Radius upgrade failed:", result.reason)
    end
end)

createButton("Sell All Items", 3, function()
    local profile = Remotes.RF.GetProfile:InvokeServer()
    if profile and profile.profile.inventory then
        local result = Remotes.RF.SellItems:InvokeServer(profile.profile.inventory)
        if result.success then
            print("Sold items for", result.coinsEarned, "coins")
            updateStats()
        else
            print("Sell failed:", result.reason)
        end
    else
        print("No items to sell")
    end
end)

-- Debug currency amount (easily modifiable)
local DEBUG_COIN_AMOUNT = 10000

createButton("Give " .. DEBUG_COIN_AMOUNT .. " Coins", 4, function()
    local result = Remotes.RF.DebugAddCurrency:InvokeServer("coins", DEBUG_COIN_AMOUNT)
    if result.success then
        print("Added " .. DEBUG_COIN_AMOUNT .. " coins!")
        updateStats()
    else
        print("Failed to add coins:", result.reason)
    end
end)

-- Reset Stats button (with space before it)
createButton("RESET Stats", 5, function()
    local result = Remotes.RF.DebugResetStats:InvokeServer()
    if result.success then
        print("Stats reset!")
        updateStats()
    else
        print("Reset failed:", result.reason)
    end
end)

-- Listen for events
Remotes.RE.OnNotification.OnClientEvent:Connect(function(notification)
    -- Just print notifications to console instead
    print("[Notification]", notification.message)
end)

Remotes.RE.OnLootDropped.OnClientEvent:Connect(function(data)
    print(string.format("Loot: %s (%s rarity)", data.item.id, data.item.rarity))
end)

Remotes.RE.OnInventoryChanged.OnClientEvent:Connect(function(change)
    print(string.format("Inventory: %s %s (count: %d)", change.action, change.itemId, change.count or 0))
    updateStats()
end)

-- Initial load
wait(2) -- Wait for data to load
updateStats()

print("[TestUI] UI ready! Use buttons to test backend.")