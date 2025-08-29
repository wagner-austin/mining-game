--!strict
-- AccountTab.lua — modular account settings tab component

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UIFolder = MiningGame:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))

-- UIUtils is optional; guard in case the module doesn't exist
local uiUtilsModule = UIFolder:FindFirstChild("UIUtils")
local UIUtils = uiUtilsModule and require(uiUtilsModule) or nil

local AccountTab = {}
AccountTab.__index = AccountTab

type Props = {
    parent: Instance,
    position: UDim2?,
    size: UDim2?,
}

function AccountTab.new(props: Props)
    local self = setmetatable({}, AccountTab)

    local colors = Theme.colors

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
        { label = "Play Time",  value = "0h 0m", icon = "⏱️" },
        { label = "Join Date",  value = "Today", icon = "📅" },
        { label = "Data Usage", value = "0 KB",  icon = "💾" },
        { label = "Server",     value = "Main",  icon = "🌐" },
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
        local SoundManager = require(ReplicatedStorage.MiningGame:WaitForChild("SoundManager"))
        SoundManager.PlayUI("buttonclick")
        onClick()
    end)

    if UIUtils and UIUtils.applyPressAnimation then
        UIUtils.applyPressAnimation(btn, 0.95)
    end

    return btn
end

function AccountTab:_createActionsSection()
    local colors = Theme.colors
    local section = Instance.new("Frame")
    section.Name = "Actions"
    section.Size = UDim2.new(1, 0, 0, 0)
    section.AutomaticSize = Enum.AutomaticSize.Y
    section.BackgroundTransparency = 1
    section.Parent = self.container

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.Padding = UDim.new(0, 8)
    layout.Parent = section

    self:_actionButton(section, "Reset Account Data", "🔄", colors.Error, function()
        print("Reset data clicked")
        -- TODO: Show confirm dialog + reset logic
    end)

    self:_actionButton(section, "Export Save Data", "💾", colors.Primary, function()
        print("Export data clicked")
        -- TODO: Implement export
    end)

    self:_actionButton(section, "Privacy Settings", "🔒", colors.Text, function()
        print("Privacy settings clicked")
        -- TODO: Open privacy panel/scene
    end)
end

function AccountTab:updateStats(statsData: {[string]: any}?)
    if not statsData then return end
    -- TODO: replace placeholder values by reading statsData and updating self.statsGrid children
end

function AccountTab:destroy()
    if self.container then
        self.container:Destroy()
        self.container = nil
    end
end

return AccountTab