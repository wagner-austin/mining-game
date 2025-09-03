--!strict
-- DebugTab.lua
-- Debug controls for testing and development (Studio-only)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Theme = require(MiningGame:WaitForChild("UI"):WaitForChild("Theme"))
local Remotes = require(MiningGame:WaitForChild("Remotes"))
local Logger = require(MiningGame:WaitForChild("Logger"))
local log = Logger.new("DebugTab")

local DebugTab = {}
DebugTab.__index = DebugTab

type Config = {
    parent: Frame,
    position: UDim2?,
    size: UDim2?,
    portalParent: Frame?,
}

function DebugTab.new(config: Config)
    local self = setmetatable({}, DebugTab)
    
    -- Theme configuration (single source of truth)
    local theme = {
        colors = Theme.colors,
        fonts = Theme.fonts,
        sizes = Theme.sizes,
        -- Standardized text sizes
        titleSize = 20,
        buttonSize = 18,
        labelSize = 16,
        smallSize = 14,
    }
    
    -- Track connections for cleanup
    self._connections = {}
    self._resetConfirm = false
    
    -- Main container (matching MaterialsTab and AccountTab structure)
    local container = Instance.new("Frame")
    container.Name = "DebugTab"
    container.Size = config.size or UDim2.new(1, 0, 0, 0)
    container.Position = config.position or UDim2.new(0, 0, 0, 0)
    container.AutomaticSize = Enum.AutomaticSize.Y
    container.BackgroundTransparency = 1
    container.Parent = config.parent
    self.container = container
    
    -- Stack sections vertically (like AccountTab)
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.Padding = UDim.new(0, 16)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = container
    
    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 12)
    padding.PaddingBottom = UDim.new(0, 12)
    padding.PaddingLeft = UDim.new(0, 16)
    padding.PaddingRight = UDim.new(0, 16)
    padding.Parent = container
    
    -- Helper to create section card (consistent theme)
    local function createSectionCard(): Frame
        local card = Instance.new("Frame")
        card.Name = "Card"
        card.Size = UDim2.new(1, 0, 0, 0)
        card.AutomaticSize = Enum.AutomaticSize.Y
        card.BackgroundColor3 = theme.colors.Surface
        card.BackgroundTransparency = Theme.card.backgroundTransparency
        card.Parent = container
        
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, theme.sizes.CornerRadius)
        corner.Parent = card
        
        local pad = Instance.new("UIPadding")
        pad.PaddingTop = UDim.new(0, 12)
        pad.PaddingBottom = UDim.new(0, 12)
        pad.PaddingLeft = UDim.new(0, 16)
        pad.PaddingRight = UDim.new(0, 16)
        pad.Parent = card
        
        local cardLayout = Instance.new("UIListLayout")
        cardLayout.FillDirection = Enum.FillDirection.Vertical
        cardLayout.Padding = UDim.new(0, 8)
        cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
        cardLayout.Parent = card
        
        return card
    end
    
    -- Helper to create section title (consistent theme)
    local function createSectionTitle(parent: Frame, text: string)
        local title = Instance.new("TextLabel")
        title.Name = "Title"
        title.Size = UDim2.new(1, 0, 0, 24)
        title.BackgroundTransparency = 1
        title.Text = text
        title.TextColor3 = theme.colors.Text
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Font = theme.fonts.Primary
        title.TextSize = theme.titleSize
        title.LayoutOrder = 0
        title.Parent = parent
        return title
    end
    
    -- Helper to create label (consistent theme)
    local function createLabel(parent: Frame, text: string, isDim: boolean?)
        local label = Instance.new("TextLabel")
        label.Name = "Label"
        label.Size = UDim2.new(1, 0, 0, 0)
        label.AutomaticSize = Enum.AutomaticSize.Y
        label.BackgroundTransparency = 1
        label.Text = text
        label.TextColor3 = isDim and theme.colors.TextDim or theme.colors.Text
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Font = theme.fonts.Primary
        label.TextSize = theme.labelSize
        label.TextWrapped = true
        label.Parent = parent
        return label
    end
    
    -- Helper to create button (consistent theme)
    local function createButton(parent: Frame, text: string, onClick: () -> (), isDanger: boolean?)
        local button = Instance.new("TextButton")
        button.Name = text:gsub(" ", ""):gsub("[^%w]", "").."Button"
        button.Size = UDim2.new(1, 0, 0, theme.sizes.MinButtonHeight)
        button.BackgroundColor3 = isDanger and theme.colors.Error or theme.colors.Surface
        button.BackgroundTransparency = Theme.button.surfaceTransparency
        button.BorderSizePixel = 0
        button.Text = text
        button.TextColor3 = isDanger and theme.colors.Error or theme.colors.Text
        button.TextScaled = false
        button.TextSize = theme.buttonSize
        button.Font = theme.fonts.Primary
        button.AutoButtonColor = false
        button.Parent = parent
        
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, theme.sizes.CornerRadius)
        corner.Parent = button
        
        -- Hover effects
        button.MouseEnter:Connect(function()
            TweenService:Create(button, TweenInfo.new(0.15), {
                BackgroundTransparency = Theme.button.surfaceHoverTransparency
            }):Play()
        end)
        
        button.MouseLeave:Connect(function()
            TweenService:Create(button, TweenInfo.new(0.15), {
                BackgroundTransparency = Theme.button.surfaceTransparency
            }):Play()
        end)
        
        button.Activated:Connect(onClick)
        
        return button
    end
    
    -- Status feedback system
    local statusCard = createSectionCard()
    statusCard.Name = "StatusCard"
    statusCard.Visible = false
    statusCard.LayoutOrder = 0 -- Show at top
    
    local statusLabel = Instance.new("TextLabel")
    statusLabel.Name = "StatusLabel"
    statusLabel.Size = UDim2.new(1, 0, 0, 24)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Font = theme.fonts.Primary
    statusLabel.TextScaled = false
    statusLabel.TextSize = theme.labelSize
    statusLabel.TextXAlignment = Enum.TextXAlignment.Center
    statusLabel.Parent = statusCard
    
    local statusTimeout = nil
    local function showStatus(message: string, isError: boolean?)
        statusCard.Visible = true
        statusCard.BackgroundColor3 = isError and theme.colors.Error or theme.colors.Success
        statusLabel.Text = message
        statusLabel.TextColor3 = theme.colors.Text
        
        -- Cancel previous timeout
        if statusTimeout then
            task.cancel(statusTimeout)
        end
        
        -- Auto-hide after 3 seconds
        statusTimeout = task.delay(3, function()
            if statusCard and statusLabel.Text == message then
                statusCard.Visible = false
            end
            statusTimeout = nil
        end)
    end
    
    -- === CUBE CONTROLS SECTION ===
    local cubeSection = createSectionCard()
    cubeSection.LayoutOrder = 1
    createSectionTitle(cubeSection, "Cube Controls")
    
    -- Non-destructive respawn button (safe for all players)
    createButton(cubeSection, "Respawn Cube Model", function()
        local success, result = pcall(function()
            return Remotes.RF.RespawnCubeModel:InvokeServer()
        end)
        
        if success and result and result.success then
            showStatus("✓ " .. (result.message or "Cube respawned"), false)
        else
            local msg = result and result.reason or tostring(result)
            showStatus("✗ Failed: " .. msg, true)
        end
    end)
    
    -- Destructive reset button (Studio-only, danger styling)
    createButton(cubeSection, "Reset Cube (Wipes Progress!)", function()
        if self._resetConfirm then
            -- Second click - actually reset
            local success, result = pcall(function()
                return Remotes.RF.DebugResetCube:InvokeServer()
            end)
            
            self._resetConfirm = false
            
            if success and result and result.success then
                showStatus("✓ Cube reset to fresh state!", false)
            else
                local msg = result and result.reason or tostring(result)
                showStatus("✗ Failed: " .. msg, true)
            end
        else
            -- First click - ask for confirmation
            self._resetConfirm = true
            showStatus("⚠️ Click again to confirm WIPE", true)
            task.delay(3, function()
                self._resetConfirm = false
            end)
        end
    end, true) -- isDanger = true
    
    -- Teleport Home button
    createButton(cubeSection, "Teleport to Spawn", function()
        local success, result = pcall(function()
            return Remotes.RF.TeleportToHome:InvokeServer()
        end)
        
        if success and result and result.success then
            showStatus("✓ Teleported to spawn!", false)
        else
            local msg = result and result.reason or tostring(result)
            showStatus("✗ Failed: " .. msg, true)
        end
    end)
    
    -- === CURRENCY SECTION ===
    local currencySection = createSectionCard()
    currencySection.LayoutOrder = 2
    createSectionTitle(currencySection, "Currency Cheats")
    
    -- Add Coins button
    createButton(currencySection, "Add 1000 Coins", function()
        local success, result = pcall(function()
            return Remotes.RF.DebugAddCurrency:InvokeServer("coins", 1000)
        end)
        
        if success and result and result.success then
            showStatus("✓ Added 1000 coins!", false)
        else
            local msg = result and result.reason or tostring(result)
            showStatus("✗ Failed: " .. msg, true)
        end
    end)
    
    -- Add Gems button
    createButton(currencySection, "Add 100 Gems", function()
        local success, result = pcall(function()
            return Remotes.RF.DebugAddCurrency:InvokeServer("gems", 100)
        end)
        
        if success and result and result.success then
            showStatus("✓ Added 100 gems!", false)
        else
            local msg = result and result.reason or tostring(result)
            showStatus("✗ Failed: " .. msg, true)
        end
    end)
    
    -- === STATS SECTION ===
    local statsSection = createSectionCard()
    statsSection.LayoutOrder = 3
    createSectionTitle(statsSection, "Player Stats")
    
    -- Reset Stats button
    createButton(statsSection, "Reset All Stats", function()
        local success, result = pcall(function()
            return Remotes.RF.DebugResetStats:InvokeServer()
        end)
        
        if success and result and result.success then
            showStatus("✓ Stats reset successfully!", false)
        else
            local msg = result and result.reason or tostring(result)
            showStatus("✗ Failed: " .. msg, true)
        end
    end)
    
    -- === SIM AGENTS SECTION (Studio Only) ===
    local simSection = createSectionCard()
    simSection.LayoutOrder = 99
    createSectionTitle(simSection, "Sim Agents (Studio)")
    
    -- Store max count from server
    local maxAgentCount = 25
    
    -- Row with TextBox + Set button
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 32)
    row.BackgroundTransparency = 1
    row.Parent = simSection
    
    local rowLayout = Instance.new("UIListLayout")
    rowLayout.FillDirection = Enum.FillDirection.Horizontal
    rowLayout.Padding = UDim.new(0, 8)
    rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
    rowLayout.Parent = row
    
    -- Helper to create text box (consistent theme)
    local function createTextBox(parent: Frame, placeholder: string, defaultText: string?): TextBox
        local textBox = Instance.new("TextBox")
        textBox.Name = placeholder:gsub(" ", "").."Box"
        textBox.Size = UDim2.new(0, 80, 1, 0)
        textBox.ClearTextOnFocus = false
        textBox.Text = defaultText or ""
        textBox.PlaceholderText = placeholder
        textBox.Font = theme.fonts.Primary
        textBox.TextSize = theme.buttonSize
        textBox.TextColor3 = theme.colors.Text
        textBox.PlaceholderColor3 = theme.colors.TextDim
        textBox.BackgroundColor3 = theme.colors.Surface
        textBox.BackgroundTransparency = Theme.card.backgroundTransparency
        textBox.Parent = parent
        
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, theme.sizes.CornerRadius)
        corner.Parent = textBox
        
        return textBox
    end
    
    local countBox = createTextBox(row, "Count", "9")
    
    -- Helper to create inline button (for row layouts)
    local function createInlineButton(parent: Frame, text: string, width: number, onClick: () -> ()): TextButton
        local button = Instance.new("TextButton")
        button.Name = text:gsub(" ", ""):gsub("[^%w]", "").."Button"
        button.Size = UDim2.new(0, width, 1, 0)
        button.Text = text
        button.Font = theme.fonts.Primary
        button.TextSize = theme.buttonSize
        button.TextColor3 = theme.colors.Text
        button.BackgroundColor3 = theme.colors.Surface
        button.BackgroundTransparency = Theme.button.surfaceTransparency
        button.AutoButtonColor = false
        button.Parent = parent
        
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, theme.sizes.CornerRadius)
        corner.Parent = button
        
        -- Hover effects
        button.MouseEnter:Connect(function()
            TweenService:Create(button, TweenInfo.new(0.15), {
                BackgroundTransparency = Theme.button.surfaceHoverTransparency
            }):Play()
        end)
        
        button.MouseLeave:Connect(function()
            TweenService:Create(button, TweenInfo.new(0.15), {
                BackgroundTransparency = Theme.button.surfaceTransparency
            }):Play()
        end)
        
        button.Activated:Connect(onClick)
        
        return button
    end
    
    local setBtn = createInlineButton(row, "Set Agents", 120, function()
        local n = tonumber(countBox.Text) or 0
        local ok, success, count = pcall(function()
            return Remotes.RF.SimAgents_SetCount:InvokeServer(math.clamp(n, 0, maxAgentCount))
        end)
        if ok and success then
            showStatus("✓ SimAgents set to " .. tostring(count or n), false)
            countBox.Text = tostring(count or n)
        else
            showStatus("✗ Failed to set agents", true)
        end
    end)
    
    -- Spawn Strategy controls
    local strategies = {"grid", "grid_altitude_noise", "grid_terrain_snap", "pcg_probe"}
    local currentStrategy = "grid"
    local strategyLabel = createLabel(simSection, "Spawn Strategy: Loading...", true) -- isDim = true
    
    local function updateStrategyDisplay()
        strategyLabel.Text = "Spawn Strategy: " .. currentStrategy
    end
    
    -- Load current strategy
    task.spawn(function()
        local okList, list = pcall(function() return Remotes.RF.SpawnStrategy_List:InvokeServer() end)
        if okList and type(list) == "table" and #list > 0 then 
            strategies = list
            log:debug("Loaded spawn strategies: {}", table.concat(list, ", "))
        end
        
        local okGet, got = pcall(function() return Remotes.RF.SpawnStrategy_Get:InvokeServer() end)
        if okGet and type(got) == "string" then 
            currentStrategy = got
            log:debug("Current spawn strategy: {}", got)
        end
        
        updateStrategyDisplay()
    end)
    
    -- Change Strategy button (cycles through options)
    createButton(simSection, "Next Spawn Strategy", function()
        local idx = 1
        for i, s in ipairs(strategies) do
            if s == currentStrategy then
                idx = i
                break
            end
        end
        currentStrategy = strategies[(idx % #strategies) + 1]
        updateStrategyDisplay()
        
        -- Apply to server
        local ok, res = pcall(function() 
            return Remotes.RF.SpawnStrategy_Set:InvokeServer(currentStrategy) 
        end)
        
        if ok and res and res.success then
            showStatus("✓ Strategy: " .. tostring(res.strategy), false)
            
            -- Auto-respawn SimAgents if any exist
            task.spawn(function()
                local okStat, status = pcall(function()
                    return Remotes.RF.SimAgents_GetStatus:InvokeServer()
                end)
                if okStat and status and status.count > 0 then
                    pcall(function()
                        Remotes.RF.SimAgents_SetCount:InvokeServer(status.count)
                    end)
                end
            end)
        else
            local reason = (ok and res and res.reason) or "Unknown error"
            showStatus("✗ Strategy change failed: " .. reason, true)
            -- Revert display
            task.spawn(function()
                local okGet, got = pcall(function() 
                    return Remotes.RF.SpawnStrategy_Get:InvokeServer() 
                end)
                if okGet and type(got) == "string" then 
                    currentStrategy = got
                    updateStrategyDisplay()
                end
            end)
        end
    end)
    
    -- Respawn All button
    createButton(simSection, "Respawn All SimAgents", function()
        local ok, success = pcall(function()
            return Remotes.RF.SimAgents_RespawnAll:InvokeServer()
        end)
        if ok and success then
            showStatus("✓ Respawned all SimAgents", false)
        else
            showStatus("✗ Failed to respawn", true)
        end
    end)
    
    -- Clear button
    createButton(simSection, "Clear SimAgents", function()
        local ok, success = pcall(function()
            return Remotes.RF.SimAgents_Clear:InvokeServer()
        end)
        if ok and success then
            showStatus("✓ Cleared SimAgents", false)
            countBox.Text = "0"
        else
            showStatus("✗ Failed to clear", true)
        end
    end)
    
    -- Toggle terrain cubes button
    local toggleBtn = createButton(simSection, "Use Terrain Cubes: ...", function() end)
    toggleBtn.Activated:Connect(function()
        local ok, status = pcall(function()
            return Remotes.RF.SimAgents_GetStatus:InvokeServer()
        end)
        if ok and status then
            local want = not status.useTerrainCubes
            local ok2, success = pcall(function()
                return Remotes.RF.SimAgents_SetTerrainCubes:InvokeServer(want)
            end)
            if ok2 and success then
                toggleBtn.Text = "Use Terrain Cubes: " .. (want and "On" or "Off")
                showStatus("✓ Terrain cubes " .. (want and "enabled" or "disabled"), false)
            else
                showStatus("✗ Toggle failed", true)
            end
        else
            showStatus("✗ Status unavailable", true)
        end
    end)
    
    -- Initialize UI from server status
    task.spawn(function()
        local ok, status = pcall(function()
            return Remotes.RF.SimAgents_GetStatus:InvokeServer()
        end)
        if ok and status then
            maxAgentCount = status.maxCount or 25
            toggleBtn.Text = "Use Terrain Cubes: " .. (status.useTerrainCubes and "On" or "Off")
            countBox.Text = tostring(status.count)
            
            -- Display additional status info
            if status.playerCount then
                createLabel(simSection, "Real Players: " .. status.playerCount, true) -- isDim = true
            end
            -- Strategy is now shown in the spawn strategy controls above
            
            if not status.enabled then
                createLabel(simSection, "⚠️ SimAgents disabled (not in Studio)", false) -- warning, not dim
                simSection.Visible = false -- Hide the section outside Studio
            end
        else
            simSection.Visible = false -- Hide if we can't get status
        end
    end)
    
    -- Hotkeys for quick iteration (Studio only)
    local function bumpAgentCount(actionName, state, delta)
        if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
        
        local ok, status = pcall(function()
            return Remotes.RF.SimAgents_GetStatus:InvokeServer()
        end)
        if not ok or not status or not status.enabled then 
            return Enum.ContextActionResult.Pass
        end
        
        local currentCount = status.count or 0
        local newCount = math.clamp(currentCount + delta, 0, status.maxCount or 25)
        
        local ok2, success, count = pcall(function()
            return Remotes.RF.SimAgents_SetCount:InvokeServer(newCount)
        end)
        
        if ok2 and success then
            countBox.Text = tostring(count or newCount)
            showStatus("SimAgents: " .. tostring(count or newCount), false)
        end
        
        return Enum.ContextActionResult.Sink
    end
    
    -- Bind hotkeys: = and ] to increase, - and [ to decrease
    ContextActionService:BindAction(
        "SimAgentsIncrease",
        function(name, state, input)
            return bumpAgentCount(name, state, 1)
        end,
        false,
        Enum.KeyCode.Equals,
        Enum.KeyCode.RightBracket
    )
    
    ContextActionService:BindAction(
        "SimAgentsDecrease",
        function(name, state, input)
            return bumpAgentCount(name, state, -1)
        end,
        false,
        Enum.KeyCode.Minus,
        Enum.KeyCode.LeftBracket
    )
    
    -- Store connections for cleanup
    table.insert(self._connections, {
        Disconnect = function()
            ContextActionService:UnbindAction("SimAgentsIncrease")
            ContextActionService:UnbindAction("SimAgentsDecrease")
        end
    })
    
    return self
end

function DebugTab:destroy()
    -- Disconnect all connections
    for _, conn in ipairs(self._connections) do
        if conn then
            conn:Disconnect()
        end
    end
    self._connections = {}
    
    -- Destroy container
    if self.container then
        self.container:Destroy()
        self.container = nil
    end
end

return DebugTab