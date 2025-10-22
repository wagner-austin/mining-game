--!strict
-- AccountTab.lua — modular account settings tab component
-- Migrated to use BaseTabComponent for consistent UI patterns

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Time = require(MiningGame:WaitForChild("Time"))
local MathUtils = require(MiningGame:WaitForChild("MathUtils"))
local UIFolder = MiningGame:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))
local UIx = require(UIFolder:WaitForChild("UIConstants"))
local ClientRF = require(MiningGame:WaitForChild("ClientRF"))

-- UIUtils is optional; guard in case the module doesn't exist
local uiUtilsModule = UIFolder:FindFirstChild("UIUtils")
local UIUtils = uiUtilsModule and require(uiUtilsModule) or nil

local BaseTabComponent = require(script.Parent:WaitForChild("BaseTabComponent"))

local AccountTab = {}
AccountTab.__index = AccountTab
setmetatable(AccountTab, { __index = BaseTabComponent })

type Props = {
    parent: GuiObject,
    position: UDim2?,
    size: UDim2?,
    dataProvider: any?, -- injected provider
}

type AccountTabT = typeof(setmetatable({} :: any, AccountTab)) & {
    _joinTime: number,
    _baseLifetimeSeconds: number,
    statsGrid: Frame?,
    new: (props: Props) -> AccountTabT,
}

function AccountTab.new(props: Props): AccountTabT
    -- Initialize base component
    local self = setmetatable(BaseTabComponent.new({
        parent = props.parent,
        position = props.position,
        size = props.size,
        dataProvider = props.dataProvider,
        stacked = true,
        name = "AccountTab",
    }), AccountTab)
    
    -- Tab-specific state
    self._joinTime = Time.unix()
    self._baseLifetimeSeconds = 0
    
    -- Build UI sections
    self:_createUserInfoSection()
    self:_createStatsSection()
    self:_createActionsSection()
    
    -- Hook data provider if available (base handles this but we need custom apply)
    if props.dataProvider then
        self:connectDataProvider(props.dataProvider, function(snapshot)
            self:_applySnapshot(snapshot)
        end)
    end
    
    -- Start periodic playtime update (1 second interval)
    self:startPeriodicUpdate(1, function()
        self:_updatePlaytime()
    end)
    
    return self :: any
end

function AccountTab:_createUserInfoSection()
    local player = Players.LocalPlayer
    
    -- Create card with fixed height
    local section = self:createSectionCard(self.container, { 
        size = UIx.px(nil, UIx.Size.ACCOUNT_SECTION_HEIGHT),
        autoSize = false
    })
    
    -- Avatar
    local avatar = Instance.new("ImageLabel")
    avatar.Name = "Avatar"
    avatar.Size = UIx.avatar()
    avatar.BackgroundTransparency = 1
    avatar.Image = "rbxthumb://type=AvatarHeadShot&id=" .. player.UserId .. "&w=150&h=150"
    avatar.Parent = section
    
    local avatarCorner = Instance.new("UICorner")
    avatarCorner.CornerRadius = UDim.new(0.5, 0)
    avatarCorner.Parent = avatar
    
    -- Info text
    local info = self:createLabel(section, 
        string.format("%s\n@%s\nID: %d", player.DisplayName, player.Name, player.UserId), 
        {
            position = UDim2.new(0, UIx.Size.AVATAR_PX + UIx.Spacing.INPUT_MARGIN, 0, 0),
            size = UDim2.new(1, -(UIx.Size.AVATAR_PX + UIx.Spacing.INPUT_MARGIN), 1, 0),
            alignment = Enum.TextXAlignment.Left,
            textSize = UIx.Visual.TEXT_BODY + 2
        }
    )
    info.TextYAlignment = Enum.TextYAlignment.Top
end

function AccountTab:_createStatsSection()
    local section = self:createSectionCard(self.container)
    
    -- Title
    self:createSectionTitle(section, "Account Statistics")
    
    -- Stats grid container
    local grid = Instance.new("Frame")
    grid.Name = "StatsGrid"
    grid.Size = UDim2.new(1, 0, 0, 0)
    grid.BackgroundTransparency = 1
    grid.Parent = section
    
    local gridLayout = Instance.new("UIGridLayout")
    gridLayout.CellSize = UDim2.new(0.5, -UIx.Spacing.SECTION, 0, UIx.Size.ROW_LARGE) -- two columns
    gridLayout.CellPadding = UDim2.new(0, UIx.Spacing.SECTION, 0, UIx.Spacing.SECTION)
    gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
    gridLayout.Parent = grid
    
    -- Make the grid auto-height based on content
    local function updateGridHeight()
        grid.Size = UDim2.new(1, 0, 0, gridLayout.AbsoluteContentSize.Y)
    end
    local conn = gridLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateGridHeight)
    self:addConnection(conn)
    updateGridHeight()
    
    local stats = {
        { key = "playTime",   label = "Session Time",  value = "0m", icon = "⏱️" },
        { key = "lifetime",   label = "Total Playtime", value = "—", icon = "📈" },
        { key = "coins",      label = "Coins",         value = "0",  icon = "💰" },
        { key = "blocksDug",  label = "Blocks Dug",    value = "0",  icon = "⛏️" },
    }
    
    for i, stat in ipairs(stats) do
        local item = Instance.new("Frame")
        item.Name = "Stat_" .. i
        item.BackgroundTransparency = 1
        item.Parent = grid
        
        -- Icon
        local icon = Instance.new("TextLabel")
        icon.Size = UIx.square(UIx.Size.ICON_PX)
        icon.BackgroundTransparency = 1
        icon.Text = stat.icon
        icon.TextScaled = true
        icon.Font = self._theme.fonts.Primary
        icon.Parent = item
        
        -- Label
        local label = self:createLabel(item, stat.label, {
            position = UDim2.new(0, UIx.Size.ICON_PX + UIx.Spacing.SECTION, 0, 0),
            size = UDim2.new(1, -(UIx.Size.ICON_PX + UIx.Spacing.SECTION), 0, UIx.Size.ROW_TINY),
            alignment = Enum.TextXAlignment.Left
        })
        
        -- Value
        local value = self:createLabel(item, stat.value, {
            position = UDim2.new(0, UIx.Size.ICON_PX + UIx.Spacing.SECTION, 0, UIx.Size.ROW_TINY + UIx.Spacing.TINY / 2),
            size = UDim2.new(1, -(UIx.Size.ICON_PX + UIx.Spacing.SECTION), 0, UIx.Size.ROW_TINY),
            alignment = Enum.TextXAlignment.Left
        })
        
        if stat.key then
            self._labels[stat.key] = value
        end
    end
    
    self.statsGrid = grid
end

function AccountTab:_createActionsSection()
    local section = self:createSectionCard(self.container)
    self:createSectionTitle(section, "Gameplay")

    -- Auto-Dig toggle row
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, UIx.Size.BUTTON_MEDIUM_HEIGHT)
    row.BackgroundTransparency = 1
    row.Parent = section

    local label = self:createLabel(row, "Auto-Dig", {
        position = UDim2.new(0, 0, 0, 0),
        size = UDim2.new(0.6, -UIx.Spacing.XS, 1, 0),
        alignment = Enum.TextXAlignment.Left,
        textSize = UIx.Visual.TEXT_BODY,
    })

    local button = Instance.new("TextButton")
    button.Size = UDim2.new(0.4, 0, 1, 0)
    button.Position = UDim2.new(0.6, UIx.Spacing.XS, 0, 0)
    button.BackgroundColor3 = Theme.colors.Surface
    button.BackgroundTransparency = Theme.button.surfaceTransparency
    button.Text = "…"
    button.TextColor3 = Theme.colors.Text
    button.Font = Theme.fonts.Primary
    button.TextSize = UIx.Visual.TEXT_BODY
    button.AutoButtonColor = true
    button.Parent = row

    local function setBtnState(enabled: boolean)
        button.Text = enabled and "ON" or "OFF"
        button.TextColor3 = enabled and Theme.colors.Success or Theme.colors.Text
    end

    -- Load current preference
    task.spawn(function()
        local ok, res = pcall(function()
            return ClientRF.call("GetAllSettings")
        end)
        local enabled = true
        if ok and type(res) == "table" and res.ok then
            enabled = (res.autoDigEnabled ~= false)
        end
        setBtnState(enabled)
    end)

    button.Activated:Connect(function()
        local currOn = (button.Text == "ON")
        local nextOn = not currOn
        local ok, res = pcall(function()
            return ClientRF.call("UpdatePreferences", { autoDigEnabled = nextOn })
        end)
        if ok and res and res.success then
            setBtnState(nextOn)
            if _G.UIManager then
                _G.UIManager:showNotification("Auto-Dig " .. (nextOn and "enabled" or "disabled"), nextOn and "success" or "info")
            end
        else
            if _G.UIManager then _G.UIManager:showNotification("Failed to update Auto-Dig", "error") end
        end
    end)
end

function AccountTab:updateStats(statsData: {[string]: any}?)
    if statsData and statsData.profile then
        self:_applySnapshot({ profile = statsData.profile, lastUpdated = Time.unix(), isLoading = false })
    elseif statsData then
        self:_applySnapshot({ profile = statsData, lastUpdated = Time.unix(), isLoading = false })
    end
end

function AccountTab:_applySnapshot(snapshot: {profile: {[string]: any}, cubeStats: any?, sessionStartTime: number?, lastUpdated: number?, isLoading: boolean?})
    local profile = snapshot.profile or {}
    
    -- Helper for safe formatting
    local function fmt(n: number): string
        if UIUtils and UIUtils.formatNumber then
            return UIUtils.formatNumber(n)
        end
        return tostring(n)
    end
    
    -- Update coins
    if self._labels.coins then
        self._labels.coins.Text = fmt(profile.coins or 0)
    end
    
    -- Update blocks dug
    if self._labels.blocksDug then
        self._labels.blocksDug.Text = fmt(profile.totalBlocksDug or 0)
    end
    
    -- Update cubes dug (from cubeStats if available)  
    if self._labels.dugCells and snapshot.cubeStats then
        self._labels.dugCells.Text = fmt(snapshot.cubeStats.dugCells or 0)
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
    local now = Time.unix()
    local sessionElapsed = MathUtils.nonNegative(now - (self._joinTime or now))
    
    -- Update session time
    if self._labels.playTime then
        self._labels.playTime.Text = self:formatDuration(sessionElapsed)
    end
    
    -- Update lifetime playtime (base + current session)
    if self._labels.lifetime then
        local total = MathUtils.nonNegative((self._baseLifetimeSeconds or 0) + sessionElapsed)
        self._labels.lifetime.Text = self:formatDuration(total)
    end
end

-- Override destroy for tab-specific cleanup
function AccountTab:destroy()
    -- Clear tab-specific state
    self._joinTime = nil
    self._baseLifetimeSeconds = nil
    self.statsGrid = nil
    
    -- Call base destroy (handles periodic updates, connections, container)
    BaseTabComponent.destroy(self)
end

return AccountTab
