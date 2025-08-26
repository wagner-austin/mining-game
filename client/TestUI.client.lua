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
buttonFrame.Size = UDim2.new(0, 150, 0, 400)
buttonFrame.Position = UDim2.new(1, -160, 0.5, -200)
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

-- Track dig cooldown
local lastDigTime = 0
local digCooldown = 1

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
        
        -- Update dig cooldown
        if profile.effectiveStats then
            digCooldown = profile.effectiveStats.delay
        end
    else
        statsLabel.Text = "Failed to load profile"
    end
end

-- Dig button functionality
local digButton
digButton = createButton("DIG", 0, function()
    local now = tick()
    if now - lastDigTime < digCooldown then
        local remaining = digCooldown - (now - lastDigTime)
        if digButton and digButton.Parent then
            digButton.Text = string.format("Cooldown: %.1fs", remaining)
        end
        return
    end
    
    -- Get player position and dig below
    local character = player.Character
    if character and character:FindFirstChild("HumanoidRootPart") then
        local position = character.HumanoidRootPart.Position + Vector3.new(0, -10, 0)
        
        if digButton and digButton.Parent then
            digButton.Text = "Digging..."
        end
        local result = Remotes.RF.RequestDig:InvokeServer(position)
        
        if result.ok then
            if digButton and digButton.Parent then
                digButton.Text = string.format("Dug %d cells!", result.cellsDug or 0)
            end
            lastDigTime = now
            
            -- Update stats after successful dig
            wait(0.5)
            updateStats()
            
            -- Reset button text after delay
            wait(1)
            if digButton and digButton.Parent then
                digButton.Text = "DIG"
            end
        else
            if digButton and digButton.Parent then
                digButton.Text = result.reason or "Failed"
            end
            wait(1)
            if digButton and digButton.Parent then
                digButton.Text = "DIG"
            end
        end
    else
        if digButton and digButton.Parent then
            digButton.Text = "No character"
        end
        wait(1)
        if digButton and digButton.Parent then
            digButton.Text = "DIG"
        end
    end
end)

-- Other test buttons
createButton("Refresh Stats", 1, updateStats)

createButton("Buy Speed Up", 2, function()
    local result = Remotes.RF.PurchaseUpgrade:InvokeServer("speed")
    if result.success then
        print("Speed upgraded to level", result.newLevel)
        updateStats()
    else
        print("Speed upgrade failed:", result.reason)
    end
end)

createButton("Buy Strength Up", 3, function()
    local result = Remotes.RF.PurchaseUpgrade:InvokeServer("strength")
    if result.success then
        print("Strength upgraded to level", result.newLevel)
        updateStats()
    else
        print("Strength upgrade failed:", result.reason)
    end
end)

createButton("Buy Radius Up", 4, function()
    local result = Remotes.RF.PurchaseUpgrade:InvokeServer("radius")
    if result.success then
        print("Radius upgraded to level", result.newLevel)
        updateStats()
    else
        print("Radius upgrade failed:", result.reason)
    end
end)

createButton("Sell All Items", 5, function()
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

createButton("Give 1000 Coins", 6, function()
    print("Use console command: _G.MiningGameServices.DataService:AddCurrency(game.Players.LocalPlayer, 'coins', 1000)")
end)

-- Notification display
local notificationLabel = Instance.new("TextLabel")
notificationLabel.Size = UDim2.new(0, 400, 0, 50)
notificationLabel.Position = UDim2.new(0.5, -200, 0, 220)
notificationLabel.BackgroundColor3 = Color3.new(0, 0, 0)
notificationLabel.BackgroundTransparency = 0.3
notificationLabel.TextColor3 = Color3.new(1, 1, 1)
notificationLabel.TextScaled = false
notificationLabel.TextSize = 18
notificationLabel.Font = Enum.Font.SourceSans
notificationLabel.Text = ""
notificationLabel.Parent = screenGui

-- Listen for events
Remotes.RE.OnNotification.OnClientEvent:Connect(function(notification)
    notificationLabel.Text = notification.message
    notificationLabel.TextColor3 = notification.color or Color3.new(1, 1, 1)
    wait(3)
    notificationLabel.Text = ""
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