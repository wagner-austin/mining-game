--!strict
-- AccountTab.lua — modular account settings tab component

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UIFolder = MiningGame:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))

-- UIUtils is optional; guard in case the module doesn't exist
local uiUtilsModule = UIFolder:FindFirstChild("UIUtils")
local UIUtils = uiUtilsModule and require(uiUtilsModule) or nil

local AccountTab = {}
AccountTab.__index = AccountTab

type Props = {
    parent: GuiObject,
    position: UDim2?,
    size: UDim2?,
    dataProvider: any?, -- injected provider
}

function AccountTab.new(props: Props)
    local self = setmetatable({}, AccountTab)

    local colors = Theme.colors
    self._connections = {}
    self._dataProvider = props.dataProvider
    self._labels = {} :: {[string]: TextLabel}
    self._joinTime = os.time()
    self._baseLifetimeSeconds = 0

    -- Main container
    local container = Instance.new("Frame")
    container.Name = "AccountTab"
    container.Size = props.size or UDim2.new(1, 0, 0, 0)
    container.Position = props.position or UDim2.new(0, 0, 0, 0)
    container.AutomaticSize = Enum.AutomaticSize.Y
    container.BackgroundTransparency = 1
    container.Parent = props.parent
    self.container = container

    -- Stack sections vertically
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.Padding = UDim.new(0, 16)
    layout.Parent = container

    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 12)
    padding.PaddingBottom = UDim.new(0, 12)
    padding.PaddingLeft = UDim.new(0, 16)
    padding.PaddingRight = UDim.new(0, 16)
    padding.Parent = container

    -- Sections
    self:_createUserInfoSection()
    self:_createStatsSection()
    self:_createActionsSection()

    -- Hook provider if available
    if self._dataProvider then
        local snapshot = self._dataProvider:getSnapshot()
        self:_applySnapshot(snapshot)
        local conn = self._dataProvider:onChanged():Connect(function(_, _, snap)
            self:_applySnapshot(snap)
        end)
        table.insert(self._connections, conn)
    end

    -- Update playtime display once per second
    self._playtimeTick = true
    task.spawn(function()
        while self._playtimeTick do
            self:_updatePlaytime()
            task.wait(1)
        end
    end)

    return self
end

function AccountTab:_sectionCard(height: number?): Frame
    local colors = Theme.colors
    local card = Instance.new("Frame")
    card.Name = "Card"
    card.Size = height and UDim2.new(1, 0, 0, height) or UDim2.new(1, 0, 0, 0)
    card.AutomaticSize = height and Enum.AutomaticSize.None or Enum.AutomaticSize.Y
    card.BackgroundColor3 = colors.Surface
    card.BackgroundTransparency = 0.85
    card.Parent = self.container

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, Theme.sizes.CornerRadius)
    corner.Parent = card

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 12)
    pad.PaddingBottom = UDim.new(0, 12)
    pad.PaddingLeft = UDim.new(0, 16)
    pad.PaddingRight = UDim.new(0, 16)
    pad.Parent = card

    return card
end

function AccountTab:_createUserInfoSection()
    local colors = Theme.colors
    local player = Players.LocalPlayer

    local section = self:_sectionCard(100)

    -- Avatar
    local avatar = Instance.new("ImageLabel")
    avatar.Name = "Avatar"
    avatar.Size = UDim2.new(0, 80, 0, 80)
    avatar.BackgroundTransparency = 1
    avatar.Image = "rbxthumb://type=AvatarHeadShot&id=" .. player.UserId .. "&w=150&h=150"
    avatar.Parent = section

    local avatarCorner = Instance.new("UICorner")
    avatarCorner.CornerRadius = UDim.new(0.5, 0)
    avatarCorner.Parent = avatar

    -- Info text
    local info = Instance.new("TextLabel")
    info.Name = "Info"
    info.Size = UDim2.new(1, -100, 1, 0)
    info.Position = UDim2.new(0, 100, 0, 0)
    info.BackgroundTransparency = 1
    info.Text = string.format("%s\n@%s\nID: %d", player.DisplayName, player.Name, player.UserId)
    info.TextColor3 = colors.Text
    info.TextXAlignment = Enum.TextXAlignment.Left
    info.TextYAlignment = Enum.TextYAlignment.Top
    info.Font = Theme.fonts.Primary
    info.TextSize = 18
    info.Parent = section
end

function AccountTab:_createStatsSection()
    local colors = Theme.colors
    local section = self:_sectionCard()

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, 0, 0, 24)
    title.BackgroundTransparency = 1
    title.Text = "Account Statistics"
    title.TextColor3 = colors.TextDim
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Font = Theme.fonts.Primary
    title.TextSize = 16
    title.Parent = section

    local grid = Instance.new("Frame")
    grid.Name = "StatsGrid"
    grid.Size = UDim2.new(1, 0, 0, 0)
    grid.Position = UDim2.new(0, 0, 0, 28)
    grid.BackgroundTransparency = 1
    grid.Parent = section

    local gridLayout = Instance.new("UIGridLayout")
    gridLayout.CellSize = UDim2.new(0.5, -10, 0, 40) -- two columns
    gridLayout.CellPadding = UDim2.new(0, 10, 0, 10)
    gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
    gridLayout.Parent = grid

    -- Make the grid auto-height based on content
    local function updateGridHeight()
        grid.Size = UDim2.new(1, 0, 0, gridLayout.AbsoluteContentSize.Y)
    end
    gridLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateGridHeight)
    updateGridHeight()

    local stats = {
        { key = "playTime",   label = "Session Time",  value = "0m", icon = "⏱️" },
        { key = "lifetime",   label = "Total Playtime", value = "—", icon = "📈" },
        { key = "coins",      label = "Coins",         value = "0",  icon = "🪙" },
        { key = "blocksDug",  label = "Blocks Dug",    value = "0",  icon = "⛏️" },
    }

    for i, stat in ipairs(stats) do
        local item = Instance.new("Frame")
        item.Name = "Stat_" .. i
        item.BackgroundTransparency = 1
        item.Parent = grid

        local icon = Instance.new("TextLabel")
        icon.Size = UDim2.new(0, 24, 0, 24)
        icon.BackgroundTransparency = 1
        icon.Text = stat.icon
        icon.TextScaled = true
        icon.Font = Theme.fonts.Primary
        icon.Parent = item

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -34, 0, 16)
        label.Position = UDim2.new(0, 34, 0, 0)
        label.BackgroundTransparency = 1
        label.Text = stat.label
        label.TextColor3 = colors.TextDim
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Font = Theme.fonts.Primary
        label.TextSize = 14
        label.Parent = item

        local value = Instance.new("TextLabel")
        value.Size = UDim2.new(1, -34, 0, 16)
        value.Position = UDim2.new(0, 34, 0, 18)
        value.BackgroundTransparency = 1
        value.Text = stat.value
        value.TextColor3 = colors.Text
        value.TextXAlignment = Enum.TextXAlignment.Left
        value.Font = Theme.fonts.Primary
        value.TextSize = 16
        value.Parent = item

        if stat.key then
            self._labels[stat.key] = value
        end
    end

    self.statsGrid = grid
end

function AccountTab:_actionButton(parent: Instance, text: string, icon: string, color: Color3, onClick: () -> ())
    local colors = Theme.colors

    local btn = Instance.new("TextButton")
    btn.Name = "ActionButton"
    btn.Size = UDim2.new(1, 0, 0, 44)
    btn.BackgroundColor3 = colors.Surface
    btn.BackgroundTransparency = 0.85
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, Theme.sizes.CornerRadius)
    corner.Parent = btn

    local row = Instance.new("Frame")
    row.BackgroundTransparency = 1
    row.Size = UDim2.new(1, 0, 1, 0)
    row.Parent = btn

    local rowLayout = Instance.new("UIListLayout")
    rowLayout.FillDirection = Enum.FillDirection.Horizontal
    rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    rowLayout.Padding = UDim.new(0, 10)
    rowLayout.Parent = row

    local rowPad = Instance.new("UIPadding")
    rowPad.PaddingLeft = UDim.new(0, 14)
    rowPad.PaddingRight = UDim.new(0, 14)
    rowPad.Parent = row

    local i = Instance.new("TextLabel")
    i.Size = UDim2.new(0, 24, 0, 24)
    i.BackgroundTransparency = 1
    i.Text = icon
    i.TextScaled = true
    i.Font = Theme.fonts.Primary
    i.Parent = row

    local t = Instance.new("TextLabel")
    t.Size = UDim2.new(1, -28, 0, 24)
    t.BackgroundTransparency = 1
    t.Text = text
    t.TextColor3 = color
    t.TextXAlignment = Enum.TextXAlignment.Left
    t.Font = Theme.fonts.Primary
    t.TextSize = 16
    t.Parent = row

    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.15), { BackgroundTransparency = 0.7 }):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.15), { BackgroundTransparency = 0.85 }):Play()
    end)
    btn.Activated:Connect(function()
        local mg = ReplicatedStorage:FindFirstChild("MiningGame")
        local sm = mg and mg:FindFirstChild("SoundManager")
        if sm then 
            pcall(function() 
                require(sm).PlayUI("buttonclick") 
            end) 
        end
        onClick()
    end)

    if UIUtils and UIUtils.applyPressAnimation then
        UIUtils.applyPressAnimation(btn, 0.95)
    end

    return btn
end

function AccountTab:_createActionsSection()
    -- Removed placeholder actions - can add real actions later if needed
end

function AccountTab:updateStats(statsData: {[string]: any}?)
    if statsData and statsData.profile then
        self:_applySnapshot({ profile = statsData.profile, lastUpdated = os.time(), isLoading = false })
    elseif statsData then
        self:_applySnapshot({ profile = statsData, lastUpdated = os.time(), isLoading = false })
    end
end

function AccountTab:_applySnapshot(snapshot: {profile: {[string]: any}, cubeStats: any?, sessionStartTime: number?, lastUpdated: number?, isLoading: boolean?})
    local profile = snapshot.profile or {}
    
    -- Update coins
    if self._labels.coins then
        self._labels.coins.Text = UIUtils.formatNumber(profile.coins or 0)
    end
    
    -- Update blocks dug
    if self._labels.blocksDug then
        self._labels.blocksDug.Text = UIUtils.formatNumber(profile.totalBlocksDug or 0)
    end
    
    -- Update cubes dug (from cubeStats if available)  
    if self._labels.dugCells and snapshot.cubeStats then
        self._labels.dugCells.Text = UIUtils.formatNumber(snapshot.cubeStats.dugCells or 0)
    elseif self._labels.dugCells then
        self._labels.dugCells.Text = "0"
    end
    
    -- Session start time (prefer server-provided)
    self._joinTime = snapshot.sessionStartTime or profile.sessionStartTime or self._joinTime
    
    -- Lifetime base seconds (server-owned)
    if profile.playtime ~= nil then
        self._baseLifetimeSeconds = tonumber(profile.playtime) or self._baseLifetimeSeconds
    end
    
    -- Refresh both timers immediately
    self:_updatePlaytime()
end

function AccountTab:_updatePlaytime()
    local now = os.time()
    local sessionElapsed = math.max(0, now - (self._joinTime or now))
    
    -- Update session time
    if self._labels.playTime then
        self._labels.playTime.Text = self:_formatDuration(sessionElapsed)
    end
    
    -- Update lifetime playtime (base + current session)
    if self._labels.lifetime then
        local total = math.max(0, (self._baseLifetimeSeconds or 0) + sessionElapsed)
        self._labels.lifetime.Text = self:_formatDuration(total)
    end
end

function AccountTab:_formatDuration(seconds: number): string
    seconds = math.max(0, math.floor(seconds))
    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    
    if days > 0 then
        return string.format("%dd %dh", days, hours)
    elseif hours > 0 then
        return string.format("%dh %dm", hours, minutes)
    else
        return string.format("%dm", minutes)
    end
end

function AccountTab:destroy()
    self._playtimeTick = false
    if self._playtimeConnection then
        self._playtimeConnection:Disconnect()
    end
    
    for _, conn in ipairs(self._connections) do
        if conn then conn:Disconnect() end
    end
    self._connections = {}
    
    if self.container then
        self.container:Destroy()
        self.container = nil
    end
end

return AccountTab