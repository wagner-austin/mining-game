--!strict
-- UpgradeTab.lua — Profile upgrade panel component
-- Allows players to purchase upgrades using coins
-- Migrated to use BaseTabComponent for consistent UI patterns

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UIFolder = MiningGame:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))
local UIx = require(UIFolder:WaitForChild("UIConstants"))
local GameConfig = require(MiningGame:WaitForChild("GameConfig"))
local Logger = require(MiningGame:WaitForChild("Logger"))
local ClientRF = require(MiningGame:WaitForChild("ClientRF"))

-- Type definitions for RF responses
type UpgradeResponse = {success: boolean, reason: string?, newLevel: number?}
type TypedCaller<T> = (...any) -> (T?, string?)

-- Typed RF calls for upgrades
local Calls = {
    PurchaseUpgrade = ClientRF.typed("PurchaseUpgrade") :: TypedCaller<UpgradeResponse>,
    -- GetProfile removed - now using PlayerProfileGuard via AccountDataProvider
}

local BaseTabComponent = require(script.Parent:WaitForChild("BaseTabComponent"))

local log = Logger.new("UpgradeTab")

-- UIUtils is optional; guard in case the module doesn't exist
local uiUtilsModule = UIFolder:FindFirstChild("UIUtils")
local UIUtils = uiUtilsModule and require(uiUtilsModule) or nil

local UpgradeTab = {}
UpgradeTab.__index = UpgradeTab
setmetatable(UpgradeTab, { __index = BaseTabComponent })

type Props = {
    parent: GuiObject,
    position: UDim2?,
    size: UDim2?,
    dataProvider: any?, -- injected provider
}

type UpgradeTabT = typeof(setmetatable({} :: any, UpgradeTab)) & {
    _upgradeCards: {[string]: Frame},
    _upgradeButtons: {[string]: TextButton},
    _progressBars: {[string]: Frame},
    _valueFormatters: {[string]: (number) -> string},
    _pending: {[string]: boolean},
    _progressTweens: {[string]: any},
    new: (props: Props) -> UpgradeTabT,
}

function UpgradeTab.new(props: Props): UpgradeTabT
    -- Initialize base component with stacked=true for vertical sections
    local self = setmetatable(BaseTabComponent.new({
        parent = props.parent,
        position = props.position,
        size = props.size,
        dataProvider = props.dataProvider,
        stacked = true,
        name = "UpgradeTab",
    }), UpgradeTab)
    
    log:info("[UpgradeTab] Initializing with dataProvider: %s", tostring(props.dataProvider))
    
    -- Tab-specific state
    self._upgradeCards = {} :: {[string]: Frame}
    self._upgradeButtons = {} :: {[string]: TextButton}
    self._progressBars = {} :: {[string]: Frame}
    self._valueFormatters = {} :: {[string]: (number) -> string}
    self._pending = {} :: {[string]: boolean}
    self._progressTweens = {} :: {[string]: any}
    
    -- Build UI sections
    self:_createCurrencySection()
    self:_createSpeedUpgradeSection()
    self:_createSizeUpgradeSection()
    
    -- Hook data provider if available (base handles initial connection)
    if props.dataProvider then
        self:connectDataProvider(props.dataProvider, function(snapshot)
            self:_applySnapshot(snapshot)
        end)
    end
    
    return self :: any
end

function UpgradeTab:_sectionCard(height: number?): Frame
    -- Use base component's section card helper
    return self:createSectionCard(self.container, {
        size = height and UDim2.new(1, 0, 0, height) or nil,
        autoSize = not height
    })
end

function UpgradeTab:_createCurrencySection()
    local section = self:_sectionCard(UIx.Size.UPGRADE_COINS_HEIGHT)
    
    -- Title
    self:createSectionTitle(section, "Available Currency")
    
    -- Coins display
    local coinsFrame = Instance.new("Frame")
    coinsFrame.Size = UDim2.new(1, 0, 0, UIx.Size.ICON_LARGE_PX)
    coinsFrame.BackgroundTransparency = 1
    coinsFrame.LayoutOrder = 1
    coinsFrame.Parent = section
    
    local coinIcon = Instance.new("TextLabel")
    coinIcon.Size = UIx.square(UIx.Size.ICON_LARGE_PX)
    coinIcon.BackgroundTransparency = 1
    coinIcon.Text = "💰"
    coinIcon.TextScaled = true
    coinIcon.Font = self._theme.fonts.Primary
    coinIcon.Parent = coinsFrame
    
    local coinsLabel = self:createLabel(coinsFrame, "0", {
        position = UDim2.new(0, UIx.Size.ICON_LARGE_PX + UIx.Spacing.SECTION, 0, 0),
        size = UDim2.new(1, -(UIx.Size.ICON_LARGE_PX + UIx.Spacing.SECTION), 0, UIx.Size.ICON_LARGE_PX),
        alignment = Enum.TextXAlignment.Left,
        textSize = UIx.Visual.TEXT_TITLE
    })
    
    self._labels.coins = coinsLabel
end

function UpgradeTab:_createSpeedUpgradeSection()
    self:_createUpgradeSection("speed", {
        title = "Dig Speed",
        icon = "⚡",
        description = "Reduce delay between digs",
        getValueText = function(level: number): string
            local def = self:_getLevelDef("speed", level)
            if def then
                local delay = GameConfig.Digging.BASE_DIG_DELAY * def.multiplier
                return string.format("%.2fs delay", delay)
            end
            return "—"
        end
    })
end

function UpgradeTab:_createSizeUpgradeSection()
    self:_createUpgradeSection("size", {
        title = "Dig Size",
        icon = "📦",
        description = "Increase the area you dig",
        getValueText = function(level: number): string
            local def = self:_getLevelDef("size", level)
            if def then
                local size = def.size
                local diameter = size * 2 + 1
                local volume = diameter * diameter * diameter
                return string.format("%dx%dx%d (%d cells)", diameter, diameter, diameter, volume)
            end
            return "—"
        end
    })
end

function UpgradeTab:_createUpgradeSection(upgradeType: string, config: {
    title: string,
    icon: string,
    description: string,
    getValueText: (number) -> string
})
    local section = self:_sectionCard()
    self._upgradeCards[upgradeType] = section
    
    -- Title row container (contains icon, title, level)
    local titleRow = Instance.new("Frame")
    titleRow.Size = UDim2.new(1, 0, 0, UIx.Size.ICON_LARGE_PX + UIx.Size.ROW_TINY)
    titleRow.BackgroundTransparency = 1
    titleRow.LayoutOrder = 1
    titleRow.Parent = section
    
    local icon = Instance.new("TextLabel")
    icon.Size = UIx.square(UIx.Size.ICON_MEDIUM_PX)
    icon.Position = UDim2.new(0, 0, 0, UIx.Spacing.TINY / 2)
    icon.BackgroundTransparency = 1
    icon.Text = config.icon
    icon.TextScaled = true
    icon.Font = self._theme.fonts.Primary
    icon.Parent = titleRow
    
    local title = self:createLabel(titleRow, config.title, {
        position = UDim2.new(0, UIx.Size.ICON_MEDIUM_PX + UIx.Spacing.SECTION, 0, 0),
        size = UDim2.new(0.5, -(UIx.Size.ICON_MEDIUM_PX + UIx.Spacing.SECTION), 0, UIx.Size.ROW_STANDARD),
        alignment = Enum.TextXAlignment.Left,
        textSize = UIx.Visual.TEXT_HEADER
    })
    
    local levelLabel = self:createLabel(titleRow, "Level 0/15", {
        position = UDim2.new(0.5, 0, 0, 0),
        size = UDim2.new(0.5, 0, 0, UIx.Size.ROW_STANDARD),
        alignment = Enum.TextXAlignment.Right,
        textSize = UIx.Visual.TEXT_BODY,
        isDim = true
    })
    self._labels[upgradeType .. "_level"] = levelLabel
    
    -- Description (positioned below title within the same container)
    local desc = self:createLabel(titleRow, config.description, {
        position = UDim2.new(0, UIx.Size.ICON_MEDIUM_PX + UIx.Spacing.SECTION, 0, UIx.Size.ROW_STANDARD + UIx.Spacing.TINY / 2),
        size = UDim2.new(1, -(UIx.Size.ICON_MEDIUM_PX + UIx.Spacing.SECTION), 0, UIx.Size.ROW_TINY),
        alignment = Enum.TextXAlignment.Left,
        textSize = UIx.Visual.TEXT_SMALL,
        isDim = true
    })
    
    -- Progress bar
    local progressBg = Instance.new("Frame")
    progressBg.Size = UDim2.new(1, 0, 0, UIx.Size.PROGRESS_HEIGHT)
    progressBg.BackgroundColor3 = self._theme.colors.Surface
    progressBg.BackgroundTransparency = 0.5
    progressBg.LayoutOrder = 2
    progressBg.Parent = section
    
    self:bindToTheme(progressBg, { BackgroundColor3 = "Surface" })
    
    local progressCorner = Instance.new("UICorner")
    progressCorner.CornerRadius = UDim.new(0, UIx.Visual.CORNER_RADIUS_SMALL)
    progressCorner.Parent = progressBg
    
    local progressFill = Instance.new("Frame")
    progressFill.Size = UDim2.new(0, 0, 1, 0)
    progressFill.BackgroundColor3 = self._theme.colors.Primary
    progressFill.Parent = progressBg
    
    self:bindToTheme(progressFill, { BackgroundColor3 = "Primary" })
    
    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(0, UIx.Visual.CORNER_RADIUS_SMALL)
    fillCorner.Parent = progressFill
    
    self._progressBars[upgradeType] = progressFill
    
    -- Stats row
    local statsRow = Instance.new("Frame")
    statsRow.Size = UDim2.new(1, 0, 0, UIx.Size.ROW_STANDARD)
    statsRow.BackgroundTransparency = 1
    statsRow.LayoutOrder = 3
    statsRow.Parent = section
    
    local currentLabel = self:createLabel(statsRow, "Current: —", {
        position = UDim2.new(0, 0, 0, 0),
        size = UDim2.new(0.5, -UIx.Spacing.XS, 1, 0),
        alignment = Enum.TextXAlignment.Left,
        textSize = UIx.Visual.TEXT_SMALL,
        isDim = true
    })
    self._labels[upgradeType .. "_current"] = currentLabel
    
    local nextLabel = self:createLabel(statsRow, "Next: —", {
        position = UDim2.new(0.5, UIx.Spacing.XS, 0, 0),
        size = UDim2.new(0.5, -UIx.Spacing.XS, 1, 0),
        alignment = Enum.TextXAlignment.Right,
        textSize = UIx.Visual.TEXT_SMALL,
        isDim = false  -- Will be green text
    })
    self._labels[upgradeType .. "_next"] = nextLabel
    
    -- Cost and button row
    local buttonRow = Instance.new("Frame")
    buttonRow.Size = UDim2.new(1, 0, 0, UIx.Size.BUTTON_MEDIUM_HEIGHT)
    buttonRow.BackgroundTransparency = 1
    buttonRow.LayoutOrder = 4
    buttonRow.Parent = section
    
    local costLabel = self:createLabel(buttonRow, "Cost: —", {
        position = UDim2.new(0, 0, 0, 0),
        size = UDim2.new(0.5, -UIx.Spacing.XS, 1, 0),
        alignment = Enum.TextXAlignment.Left,
        textSize = UIx.Visual.TEXT_BODY,
        isDim = false
    })
    self._labels[upgradeType .. "_cost"] = costLabel
    
    -- Custom button since we need special states
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(0.5, -UIx.Spacing.XS, 1, 0)
    button.Position = UDim2.new(0.5, UIx.Spacing.XS, 0, 0)
    button.BackgroundColor3 = self._theme.colors.Primary
    button.Text = "UPGRADE"
    button.TextColor3 = self._theme.colors.OnPrimary
    button.Font = self._theme.fonts.Primary
    button.TextSize = UIx.Visual.TEXT_BODY
    button.AutoButtonColor = false
    button.Parent = buttonRow
    
    self:bindToTheme(button, { BackgroundColor3 = "Primary", TextColor3 = "OnPrimary" })
    
    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, self._theme.sizes.CornerRadius)
    btnCorner.Parent = button
    
    -- Re-apply non-bound props on theme change
    self:_addThemeUpdater(function()
        btnCorner.CornerRadius = UDim.new(0, Theme.sizes.CornerRadius)
    end)
    
    self:addConnection(button.MouseEnter:Connect(function()
        if button:GetAttribute("CanAfford") ~= false then
            TweenService:Create(button, TweenInfo.new(UIx.Anim.QUICK), {
                BackgroundTransparency = Theme.button.surfaceHoverTransparency or 0.5
            }):Play()
        end
    end))
    
    self:addConnection(button.MouseLeave:Connect(function()
        if button:GetAttribute("CanAfford") ~= false then
            TweenService:Create(button, TweenInfo.new(UIx.Anim.QUICK), {
                BackgroundTransparency = 0
            }):Play()
        end
    end))
    
    self:addConnection(button.Activated:Connect(function()
        self:_purchaseUpgrade(upgradeType)
    end))
    
    if UIUtils and UIUtils.applyPressAnimation then
        UIUtils.applyPressAnimation(button, 0.95)
    end
    
    self._upgradeButtons[upgradeType] = button
    
    -- Store formatter for value updates
    self._valueFormatters[upgradeType] = config.getValueText
    
    -- Adjust section height
    section.Size = UDim2.new(1, 0, 0, UIx.Size.UPGRADE_SECTION_HEIGHT)
end

function UpgradeTab:_getLevelDef(upgradeType: string, level: number)
    local levels = upgradeType == "speed" and GameConfig.Upgrades.SPEED_LEVELS or GameConfig.Upgrades.SIZE_LEVELS
    for _, def in ipairs(levels) do
        if def.level == level then
            return def
        end
    end
    return nil
end

function UpgradeTab:_purchaseUpgrade(upgradeType: string)
    log:info("[UpgradeTab] Purchase requested for: %s", upgradeType)
    
    -- Guard against spam clicks
    if self._pending[upgradeType] then 
        log:debug("[UpgradeTab] Purchase already pending for: %s", upgradeType)
        return 
    end
    
    -- Check if already at max level
    local snapshot = self._dataProvider and self._dataProvider:getSnapshot() or { profile = {} }
    local profile = snapshot.profile or {}
    local upgrades = profile.upgrades or {}
    local currentLevel = upgrades[upgradeType] or 0
    local levels = upgradeType == "speed" and GameConfig.Upgrades.SPEED_LEVELS or GameConfig.Upgrades.SIZE_LEVELS
    local maxLevel = #levels - 1
    
    log:debug("[UpgradeTab] Current level: %d, Max level: %d, Coins: %d", 
        currentLevel, maxLevel, profile.coins or 0)
    
    if currentLevel >= maxLevel then 
        log:info("[UpgradeTab] Already at max level for: %s", upgradeType)
        return 
    end
    
    -- Client-side affordability guard
    local button = self._upgradeButtons[upgradeType]
    if button and button:GetAttribute("CanAfford") == false then
        -- Quick feedback, no server roundtrip
        button.Text = "NOT ENOUGH"
        button.BackgroundColor3 = self._theme.colors.Error
        task.wait(UIx.Anim.SLOW + UIx.Anim.SMOOTH)  -- Wait for animation completion
        button.BackgroundColor3 = self._theme.colors.Surface
        button.TextColor3 = self._theme.colors.TextSecondary
        button.Text = "INSUFFICIENT"
        return
    end
    
    self._pending[upgradeType] = true
    if button then
        button.Text = "PURCHASING..."
        button.AutoButtonColor = false
    end
    
    -- Play click sound
    local sm = MiningGame:FindFirstChild("SoundManager")
    if sm then
        pcall(function()
            require(sm).PlayUI("buttonclick")
        end)
    end
    
    -- Call server remote
    log:info("[UpgradeTab] Calling server for upgrade: %s", upgradeType)
    local result, err = Calls.PurchaseUpgrade(upgradeType)
    
    log:debug("[UpgradeTab] Server response - error: %s, result: %s", 
        tostring(err), tostring(result))
    
    if err then
        -- Handle call failure
        if button then
            button.Text = "FAILED"
            button.BackgroundColor3 = self._theme.colors.Error
            self:setTimeout(1, function()
                if not button then return end
                button.BackgroundColor3 = self._theme.colors.Primary
                button.Text = "UPGRADE"
                button.AutoButtonColor = true
            end)
        end
        self._pending[upgradeType] = false
        log:error("[UpgradeTab] Purchase call failed for %s: %s", upgradeType, err)
        return
    end
    
    if not err and result and result.success then
        log:info("[UpgradeTab] Upgrade purchased: %s - level %s", upgradeType, tostring(result.newLevel or "unknown"))
        -- Visual feedback
        if button then
            button.Text = "SUCCESS!"
            button.BackgroundColor3 = self._theme.colors.Success
            self:setTimeout(1, function()
                if not button then return end
                button.BackgroundColor3 = self._theme.colors.Primary
                button.Text = "UPGRADE"
                button.AutoButtonColor = true
            end)
        end
    else
        local reason = err or (result and result.reason) or "Unknown reason"
        log:warn("[UpgradeTab] Upgrade failed: %s - reason: %s", upgradeType, reason)
        -- Error feedback
        if button then
            local originalText = "UPGRADE"
            if reason == "Insufficient coins" then
                button.Text = "NOT ENOUGH"
            else
                button.Text = reason or "FAILED"
            end
            button.BackgroundColor3 = self._theme.colors.Error
            self:setTimeout(1.5, function()
                if not button then return end
                button.BackgroundColor3 = self._theme.colors.Primary
                button.Text = originalText
                button.AutoButtonColor = true
            end)
        end
    end
    
    self._pending[upgradeType] = false
    
    -- Don't force refresh - provider will update via events
end

function UpgradeTab:_applySnapshot(snapshot: {profile: {[string]: any}, lastUpdated: number?, isLoading: boolean?})
    log:debug("[UpgradeTab] Applying snapshot")
    local profile = snapshot.profile or {}
    
    log:debug("[UpgradeTab] Profile data - coins: %s, speed upgrade: %s, size upgrade: %s",
        profile.coins or "nil",
        profile.upgrades and profile.upgrades.speed or "nil",
        profile.upgrades and profile.upgrades.size or "nil"
    )
    
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
    
    -- Update each upgrade
    self:_updateUpgrade("speed", profile)
    self:_updateUpgrade("size", profile)
end

function UpgradeTab:_updateUpgrade(upgradeType: string, profile: {[string]: any})
    log:debug("[UpgradeTab] Updating upgrade: %s", upgradeType)
    
    local upgrades = profile.upgrades or {}
    local currentLevel = upgrades[upgradeType] or 0
    local coins = profile.coins or 0
    
    log:debug("[UpgradeTab] %s - current level: %d, coins: %d", upgradeType, currentLevel, coins)
    
    -- Get level definitions
    local levels = upgradeType == "speed" and GameConfig.Upgrades.SPEED_LEVELS or GameConfig.Upgrades.SIZE_LEVELS
    local maxLevel = #levels - 1
    
    -- Get current and next definitions
    local currentDef = self:_getLevelDef(upgradeType, currentLevel)
    local nextDef = self:_getLevelDef(upgradeType, currentLevel + 1)
    
    -- Update level label
    local levelLabel = self._labels[upgradeType .. "_level"]
    if levelLabel then
        levelLabel.Text = string.format("Level %d/%d", currentLevel, maxLevel)
    end
    
    -- Update progress bar with de-duplication
    local progressBar = self._progressBars[upgradeType]
    if progressBar then
        local progress = maxLevel > 0 and (currentLevel / maxLevel) or 0
        
        -- Cancel previous tween if exists
        if self._progressTweens[upgradeType] then
            self._progressTweens[upgradeType]:Cancel()
        end
        
        -- Create and play new tween
        local tween = TweenService:Create(progressBar, TweenInfo.new(UIx.Anim.SMOOTH), {
            Size = UDim2.new(progress, 0, 1, 0)
        })
        self._progressTweens[upgradeType] = tween
        tween:Play()
    end
    
    -- Get value formatter from memory
    local getValueText = self._valueFormatters[upgradeType]
    
    -- Update current value
    local currentLabel = self._labels[upgradeType .. "_current"]
    if currentLabel and getValueText then
        currentLabel.Text = "Current: " .. getValueText(currentLevel)
    end
    
    -- Update next value
    local nextLabel = self._labels[upgradeType .. "_next"]
    if nextLabel and getValueText then
        if nextDef then
            nextLabel.Text = "Next: " .. getValueText(currentLevel + 1)
            nextLabel.TextColor3 = self._theme.colors.Success
        else
            nextLabel.Text = "MAX LEVEL"
            nextLabel.TextColor3 = self._theme.colors.Accent
        end
    end
    
    -- Update cost
    local costLabel = self._labels[upgradeType .. "_cost"]
    if costLabel then
        if nextDef then
            local cost = nextDef.cost
            costLabel.Text = string.format("Cost: %s 💰", self:_formatNumber(cost))
            costLabel.TextColor3 = coins >= cost and self._theme.colors.Success or self._theme.colors.Error
        else
            costLabel.Text = "MAX LEVEL"
            costLabel.TextColor3 = self._theme.colors.Accent
        end
    end
    
    -- Update button state
    local button = self._upgradeButtons[upgradeType]
    if button then
        if nextDef then
            local cost = nextDef.cost
            local canAfford = coins >= cost
            button:SetAttribute("CanAfford", canAfford)
            
            if canAfford then
                button.Text = "UPGRADE"
                button.BackgroundColor3 = self._theme.colors.Primary
                button.BackgroundTransparency = 0
                button.TextColor3 = self._theme.colors.OnPrimary
                button.AutoButtonColor = true
            else
                button.Text = "INSUFFICIENT"
                button.BackgroundColor3 = self._theme.colors.Surface
                button.BackgroundTransparency = 0
                button.TextColor3 = self._theme.colors.TextDim
                button.AutoButtonColor = false
            end
        else
            button:SetAttribute("CanAfford", false)
            button.Text = "MAX LEVEL"
            button.BackgroundColor3 = self._theme.colors.Surface
            button.BackgroundTransparency = 0
            button.TextColor3 = self._theme.colors.TextDim
            button.AutoButtonColor = false
        end
    end
end

function UpgradeTab:_formatNumber(n: number): string
    if UIUtils and UIUtils.formatNumber then
        return UIUtils.formatNumber(n)
    end
    -- Fallback formatting
    if n >= 1000000 then
        return string.format("%.1fM", n / 1000000)
    elseif n >= 1000 then
        return string.format("%.1fK", n / 1000)
    else
        return tostring(n)
    end
end

-- Override destroy for tab-specific cleanup
function UpgradeTab:destroy()
    -- Cancel any active progress tweens
    for _, tween in pairs(self._progressTweens) do
        if tween then
            tween:Cancel()
        end
    end
    
    -- Clear tab-specific state
    self._upgradeCards = nil
    self._upgradeButtons = nil
    self._progressBars = nil
    self._valueFormatters = nil
    self._pending = nil
    self._progressTweens = nil
    
    -- Call base destroy (handles connections, container, periodic updates)
    BaseTabComponent.destroy(self)
end

return UpgradeTab
