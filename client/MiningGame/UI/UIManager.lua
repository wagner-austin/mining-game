--!strict
-- UIManager.lua
-- Core UI management system with scene-based architecture

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

-- Import Theme and UIUtils
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UIFolder = MiningGame:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))
local UIUtils = require(UIFolder:WaitForChild("UIUtils"))
local ThemeManager = require(UIFolder:WaitForChild("ThemeManager"))
local ThemeRefresher = require(UIFolder:WaitForChild("ThemeRefresher"))
local Logger = require(MiningGame:WaitForChild("Logger"))
local log = Logger.new("UIManager")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Use Theme colors
local UI_COLORS = Theme.colors  -- Will be updated in refreshTheme
local RARITY_COLORS = Theme.rarityColors

-- Types
type Scene = {
    name: string,
    frame: Frame?,
    init: (self: Scene, manager: any) -> (),
    show: (self: Scene) -> (),
    hide: (self: Scene) -> (),
    cleanup: ((self: Scene) -> ())?,
}

local UIManager = {}
UIManager.__index = UIManager

function UIManager.new()
    local self = setmetatable({}, UIManager)
    
    self.screenGui = nil :: ScreenGui?
    self.scenes = {} :: {[string]: Scene}
    self.activeScene = nil :: Scene?
    self.sceneStack = {} :: {Scene}  -- Track scene stack for proper back navigation
    self.mainHUD = nil :: Frame?
    self.isInitialized = false
    self._cons = {} :: {RBXScriptConnection}
    self._transitionUnlockAt = 0 :: number  -- Timestamp for transition cooldown
    self._watchdogNextCheckAt = 0 :: number  -- Next watchdog check time
    self._watchdogLastVisibleAt = 0 :: number  -- Last time UI was visible
    self._isRecovering = false :: boolean  -- Prevent re-entry during recovery
    
    -- Animation defaults from Theme
    self.tweenInfo = Theme.animations.Standard
    
    return self
end

function UIManager:init()
    if self.isInitialized then return end
    
    -- Create main screen GUI with full-bleed layout (still notch-safe)
    self.screenGui = Instance.new("ScreenGui")
    self.screenGui.Name = "MiningGameUI"
    self.screenGui.ResetOnSpawn = false
    self.screenGui.DisplayOrder = 1
    self.screenGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
    self.screenGui.ClipToDeviceSafeArea = true
    self.screenGui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
    self.screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    self.screenGui.IgnoreGuiInset = true
    self.screenGui.Parent = playerGui
    
    -- Container (unchanged)
    local container = Instance.new("Frame")
    container.Name = "Container"
    container.Size = UDim2.new(1, 0, 1, 0)
    container.BackgroundTransparency = 1
    container.Parent = self.screenGui
    
    -- Overlay GUI for modals only now (toasts moved to main container)
    self.overlayGui = Instance.new("ScreenGui")
    self.overlayGui.Name = "MiningGameUI_Overlay"
    self.overlayGui.ResetOnSpawn = false
    self.overlayGui.DisplayOrder = 100
    self.overlayGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
    self.overlayGui.ClipToDeviceSafeArea = true
    self.overlayGui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
    self.overlayGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    self.overlayGui.IgnoreGuiInset = true
    self.overlayGui.Parent = playerGui
    
    -- Bind the whole UI to ThemeRefresher so theme flips repaint everything
    ThemeRefresher.BindTree(self.screenGui)
    ThemeRefresher.BindTree(self.overlayGui)
    
    -- Removed UIScale - we want full screen UI without scaling
    
    -- Toast stack container (now inside main container, dynamically positioned)
    self.toastStack = Instance.new("Frame")
    self.toastStack.Name = "ToastStack"
    self.toastStack.BackgroundTransparency = 1
    self.toastStack.Parent = container  -- Now parented to main container
    
    local stackLayout = Instance.new("UIListLayout")
    stackLayout.FillDirection = Enum.FillDirection.Vertical
    stackLayout.Padding = UDim.new(0, Theme.toast.gap)
    stackLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    stackLayout.VerticalAlignment = Enum.VerticalAlignment.Top
    stackLayout.SortOrder = Enum.SortOrder.LayoutOrder
    stackLayout.Parent = self.toastStack
    self.toastLayout = stackLayout
    
    -- Function to update toast position dynamically
    self.updateToastPosition = function()
        local chipConfig = Theme.currencyChip
        local topPosition = 20 + chipConfig.height + 8  -- Below chips with 8px gap
        self.toastStack.Size = UDim2.new(0, Theme.toast.maxWidth, 0.5, 0)
        
        if Theme.toast.anchor == "topCenter" then
            stackLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
            self.toastStack.AnchorPoint = Vector2.new(0.5, 0)
            self.toastStack.Position = UDim2.new(0.5, 0, 0, topPosition)
        else -- default to topRight
            stackLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
            self.toastStack.AnchorPoint = Vector2.new(1, 0)
            self.toastStack.Position = UDim2.new(1, -20, 0, topPosition)
        end
    end
    
    -- React to runtime theme changes
    table.insert(self._cons, ThemeManager.Changed():Connect(function()
        -- Repaint all bound instances, then update frosted surfaces and do any layout tweaks
        ThemeRefresher.Refresh()
        UIUtils.refreshFrosting()
        if self.refreshTheme then self:refreshTheme() end
    end))
    
    -- Keep ScreenGuis attached to PlayerGui
    self:_bindAncestryGuard(self.screenGui)
    self:_bindAncestryGuard(self.overlayGui)
    
    -- Watchdog: scan ~2x/sec; recover if nothing visible for >1.5s
    self._watchdogLastVisibleAt = time()
    self._lastWatchdogLog = 0
    table.insert(self._cons, RunService.Heartbeat:Connect(function()
        local now = time()
        if now < self._watchdogNextCheckAt then return end
        self._watchdogNextCheckAt = now + 0.5
        
        local hasUI = self:_anyUIVisible()
        if hasUI then
            self._watchdogLastVisibleAt = now
            return
        end
        
        -- Log once per second when UI is missing
        if math.floor(now) ~= self._lastWatchdogLog then
            self._lastWatchdogLog = math.floor(now)
            log:debug("Watchdog: No UI visible, will recover in %.1fs", 
                 math.max(0, 1.5 - (now - self._watchdogLastVisibleAt)))
        end
        
        if (now - self._watchdogLastVisibleAt) > 1.5 then
            log:debug("Watchdog triggered recovery!")
            self:_showMainHUDNow()
            self._watchdogLastVisibleAt = now
        end
    end))
    
    -- Desktop hotkey escape hatch (F10 to recover)
    local UserInputService = game:GetService("UserInputService")
    if UserInputService.KeyboardEnabled then
        table.insert(self._cons, UserInputService.InputBegan:Connect(function(input, gp)
            if gp then return end
            if input.KeyCode == Enum.KeyCode.F10 then
                self:_showMainHUDNow()
                log:info("F10 triggered UI recovery")
            end
        end))
    end
    
    -- Apply initial theme + position
    if self.refreshTheme then 
        self:refreshTheme() 
    else 
        self.updateToastPosition() 
    end
    
    self.container = container
    self.isInitialized = true
    
    log:info("Initialized with mobile-safe settings")
end

-- UIScale removed - no longer needed

function UIManager:refreshLayout()
    -- Update toast stack position based on current theme values
    if self.updateToastPosition then
        self.updateToastPosition()
    end
end

function UIManager:refreshTheme()
    -- Update the global colors reference
    UI_COLORS = Theme.colors
    RARITY_COLORS = Theme.rarityColors
    
    -- 1) If themes change gap/width/anchor, update those:
    if self.toastLayout then
        self.toastLayout.Padding = UDim.new(0, Theme.toast.gap)
    end
    self.toastStack.Size = UDim2.new(0, Theme.toast.maxWidth, 0.5, 0)
    
    -- 2) Recompute exact position with chip height offset etc.
    if self.updateToastPosition then
        self.updateToastPosition()
    end
    
    -- 3) Refresh all active scenes to pick up new colors
    for _, scene in pairs(self.scenes) do
        if scene.frame and typeof(scene.refreshTheme) == "function" then
            scene:refreshTheme()
        end
    end
end

function UIManager:registerScene(scene: Scene)
    -- Validate scene interface
    UIUtils.validateScene(scene)
    
    self.scenes[scene.name] = scene
    log:debug("Registered scene: %s", scene.name)
end

-- Helper to get cooldown duration based on Theme animations
local function getCooldownSeconds()
    local t1 = Theme.animations.Standard.Time or 0.25
    local t2 = Theme.animations.Quick.Time or 0.15
    local t3 = Theme.animations.Smooth.Time or 0.35
    return math.max(t1, t2, t3) * 0.9  -- Slight under-shoot to keep UI snappy
end

function UIManager:showScene(sceneName: string, ...: any)
    local scene = self.scenes[sceneName]
    if not scene then
        log:warn("Scene not found: %s", sceneName)
        return
    end
    
    -- Allow immediate hide if the scene is already active (don't block closes)
    if self.activeScene == scene then
        self:hideScene(sceneName)
        return
    end
    
    -- Only guard opening during animation cooldown
    if time() < (self._transitionUnlockAt or 0) then
        return
    end
    self._transitionUnlockAt = time() + getCooldownSeconds()
    
    -- Initialize scene if needed - pass manager reference
    if not scene.frame then
        scene:init(self)
    end
    
    -- Remove target scene from stack if it's already there (prevents duplicates)
    for i = #self.sceneStack, 1, -1 do
        if self.sceneStack[i] == scene then
            table.remove(self.sceneStack, i)
            break
        end
    end
    
    -- Push current scene to stack and hide it
    if self.activeScene then
        table.insert(self.sceneStack, self.activeScene)
        self.activeScene:hide()
    end
    
    -- Show new scene
    scene:show(...)
    self.activeScene = scene
    
    log:info("Showing scene: %s", sceneName)
end

function UIManager:hideScene(sceneName: string)
    local scene = self.scenes[sceneName]
    if not scene then return end
    
    -- Never block hides - users can always close what's open
    scene:hide()
    
    -- If we hid the active scene, pop back to previous
    if self.activeScene == scene then
        self.activeScene = nil
        local prev = table.remove(self.sceneStack)
        if prev then
            prev:show()
            self.activeScene = prev
            log:info("Returning to scene: %s", prev.name)
        elseif self.scenes["MainHUD"] then
            -- Re-open MainHUD. We're hiding, so skip the open guard.
            local hud = self.scenes["MainHUD"]
            if not hud.frame then 
                hud:init(self) 
            end
            hud:show()
            self.activeScene = hud
        end
    else
        -- Remove from stack if it was there (to avoid stale refs)
        for i = #self.sceneStack, 1, -1 do
            if self.sceneStack[i] == scene then
                table.remove(self.sceneStack, i)
                break
            end
        end
    end
    
    -- Defensive check: if no UI is visible after hide, recover immediately
    task.defer(function()
        if not self:_anyUIVisible() then
            log:debug("No UI visible after hideScene, recovering immediately")
            self:_showMainHUDNow()
        end
    end)
end

function UIManager:hideAllScenes()
    for _, scene in pairs(self.scenes) do
        if scene.frame then
            scene:hide()
        end
    end
    self.sceneStack = {}  -- Clear the stack
    self.activeScene = nil
end

function UIManager:createButton(parent: GuiObject, text: string, position: UDim2?, size: UDim2?): TextButton
    local button = Instance.new("TextButton")
    button.Size = size or UDim2.new(0, 120, 0, 40)
    button.Position = position or UDim2.new(0, 0, 0, 0)
    button.BackgroundColor3 = UI_COLORS.Primary
    button.TextColor3 = UI_COLORS.Text
    button.Text = text
    button.Font = Enum.Font.SourceSansBold
    button.TextScaled = true
    button.AutoButtonColor = false
    button.Parent = parent
    
    -- Corner rounding
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = button
    
    -- Text size constraint for better readability
    local textConstraint = Instance.new("UITextSizeConstraint")
    textConstraint.MinTextSize = 12
    textConstraint.MaxTextSize = 18
    textConstraint.Parent = button
    
    -- Store original size and position for press effect
    local origSize = button.Size
    local origPos = button.Position
    
    -- Hover effects
    button.MouseEnter:Connect(function()
        TweenService:Create(button, self.tweenInfo, {
            BackgroundColor3 = UI_COLORS.Primary:Lerp(Color3.new(1, 1, 1), 0.2)
        }):Play()
    end)
    
    button.MouseLeave:Connect(function()
        TweenService:Create(button, self.tweenInfo, {
            BackgroundColor3 = UI_COLORS.Primary
        }):Play()
    end)
    
    -- Use Activated for cross-platform compatibility (mouse, touch, gamepad)
    button.Activated:Connect(function()
        self:pulse(button, 1.08)
    end)
    
    return button
end

function UIManager:createPanel(
    parent: GuiObject,
    position: UDim2,
    size: UDim2,
    opts: {variant: ("glass" | "solid")?, border: ("ink" | "subtle")?}?
): Frame
    opts = opts or {}
    local variant = opts.variant or "glass"
    local border = opts.border or "ink"

    local panel = Instance.new("Frame")
    panel.Size = size
    panel.Position = position
    panel.BackgroundColor3 = Theme.colors.Surface
    panel.BackgroundTransparency = (variant == "glass") and 0.15 or 0 -- semi-transparent
    panel.BorderSizePixel = 0
    panel.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, Theme.sizes.LargeCornerRadius)
    corner.Parent = panel

    -- Subtle vertical highlight for "glass" feel
    if variant == "glass" then
        local grad = Instance.new("UIGradient")
        grad.Rotation = 90
        grad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
            ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 255, 255)),
            ColorSequenceKeypoint.new(1, Theme.colors.Surface)
        })
        grad.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.6),
            NumberSequenceKeypoint.new(0.35, 0.8),
            NumberSequenceKeypoint.new(1, 0.9),
        })
        grad.Parent = panel
    end

    -- All panels use glass edge now
    UIUtils.applyGlassEdge(panel)

    return panel
end

function UIManager:pulse(gui: GuiObject, scaleUp: number?)
    UIUtils.pulse(gui, scaleUp)
end

function UIManager:animateIn(guiObject: GuiObject, animationType: string?)
    animationType = animationType or "fade"
    
    if animationType == "fade" then
        guiObject.Visible = true
        guiObject.BackgroundTransparency = 1
        TweenService:Create(guiObject, self.tweenInfo, {
            BackgroundTransparency = 0
        }):Play()
    elseif animationType == "slide" then
        local originalPosition = guiObject.Position
        guiObject.Position = UDim2.new(originalPosition.X.Scale, originalPosition.X.Offset,
                                       originalPosition.Y.Scale, originalPosition.Y.Offset + 100)
        guiObject.Visible = true
        TweenService:Create(guiObject, self.tweenInfo, {
            Position = originalPosition
        }):Play()
    elseif animationType == "scale" then
        -- Store final size first
        local finalSize = guiObject.Size
        guiObject.Size = UDim2.fromOffset(0, 0)
        guiObject.Visible = true
        TweenService:Create(guiObject, self.tweenInfo, {
            Size = finalSize
        }):Play()
    end
end

function UIManager:animateOut(guiObject: GuiObject, animationType: string?)
    animationType = animationType or "fade"
    
    local tween
    if animationType == "fade" then
        tween = TweenService:Create(guiObject, self.tweenInfo, {
            BackgroundTransparency = 1
        })
    elseif animationType == "slide" then
        tween = TweenService:Create(guiObject, self.tweenInfo, {
            Position = UDim2.new(guiObject.Position.X.Scale, guiObject.Position.X.Offset,
                                guiObject.Position.Y.Scale, guiObject.Position.Y.Offset + 100)
        })
    elseif animationType == "scale" then
        -- Store original size to restore later
        local originalSize = guiObject.Size
        tween = TweenService:Create(guiObject, self.tweenInfo, {
            Size = UDim2.fromOffset(0, 0)
        })
        tween.Completed:Connect(function()
            guiObject.Size = originalSize -- Restore size after hiding
        end)
    end
    
    if tween then
        tween:Play()
        tween.Completed:Connect(function()
            guiObject.Visible = false
        end)
    end
end

function UIManager:formatNumber(value: number): string
    return UIUtils.formatNumber(value)
end

-- createCurrencyDisplay removed - now using modular CurrencyChip component

function UIManager:showNotification(message: string, notificationType: string?)
    local tcfg = Theme.toast
    local colors = Theme.colors
    local kind = (notificationType == "success" or notificationType == "error") and notificationType or "info"
    local tint = tcfg.tint[kind]

    -- Toast root (auto height)
    local toast = Instance.new("Frame")
    toast.Name = "Toast"
    toast.BackgroundColor3 = colors.Surface
    toast.BackgroundTransparency = 0.2  -- frosted
    toast.Size = UDim2.new(1, 0, 0, 0)
    toast.AutomaticSize = Enum.AutomaticSize.Y
    toast.Parent = self.toastStack

    -- Glass edge border
    UIUtils.applyGlassEdge(toast)

    -- Rounding
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, Theme.sizes.LargeCornerRadius)
    corner.Parent = toast

    -- Soft highlight
    local grad = Instance.new("UIGradient")
    grad.Rotation = 90
    grad.Color = ColorSequence.new(Color3.new(1,1,1), Color3.new(1,1,1))
    grad.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.9),
        NumberSequenceKeypoint.new(1, 1.0),
    })
    grad.Parent = toast

    -- Left accent strip (tinted, subtle)
    local accent = Instance.new("Frame")
    accent.BackgroundColor3 = tint
    accent.BackgroundTransparency = 0.25
    accent.Size = UDim2.new(0, 4, 1, 0)
    accent.Parent = toast
    local accCorner = Instance.new("UICorner")
    accCorner.CornerRadius = corner.CornerRadius
    accCorner.Parent = accent

    -- Content row
    local content = Instance.new("Frame")
    content.BackgroundTransparency = 1
    content.Size = UDim2.new(1, -8, 0, 0)
    content.Position = UDim2.new(0, 8, 0, 0)
    content.AutomaticSize = Enum.AutomaticSize.Y
    content.Parent = toast

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.Padding = UDim.new(0, 8)
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.Parent = content

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, tcfg.padding)
    pad.PaddingBottom = UDim.new(0, tcfg.padding)
    pad.PaddingLeft = UDim.new(0, tcfg.padding)
    pad.PaddingRight = UDim.new(0, tcfg.padding)
    pad.Parent = content

    -- Icon (subtle)
    local icon = Instance.new("TextLabel")
    icon.BackgroundTransparency = 1
    icon.Size = UDim2.fromOffset(22, 22)
    icon.Text = tcfg.icon[kind]
    icon.TextScaled = true
    icon.Parent = content

    -- Message
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(1, -22, 0, 0)
    label.AutomaticSize = Enum.AutomaticSize.Y
    label.Text = message
    label.TextColor3 = colors.Text
    label.TextWrapped = true
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.Font = Theme.fonts.Primary  -- Back to primary for readability
    label.TextSize = 20  -- Comfortable reading size
    label.Parent = content

    -- Add padding for slide animation (UIListLayout ignores Position)
    local slidePad = Instance.new("UIPadding")
    slidePad.PaddingTop = UDim.new(0, -8) -- start slightly above
    slidePad.Parent = toast
    
    -- Subtle entrance animation + timed dismiss
    toast.BackgroundTransparency = 1
    toast.Visible = true

    TweenService:Create(toast, Theme.animations.Quick, {
        BackgroundTransparency = 0.2
    }):Play()
    TweenService:Create(slidePad, Theme.animations.Quick, {
        PaddingTop = UDim.new(0, 0)
    }):Play()

    task.delay(tcfg.duration, function()
        local out1 = TweenService:Create(toast, Theme.animations.Standard, {
            BackgroundTransparency = 1
        })
        local out2 = TweenService:Create(slidePad, Theme.animations.Standard, {
            PaddingTop = UDim.new(0, -8)
        })
        out1:Play()
        out2:Play()
        out1.Completed:Connect(function()
            toast:Destroy()
        end)
    end)

    -- Tap/click to dismiss early
    toast.InputBegan:Connect(function(input)
        local t = input.UserInputType
        if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
            toast:Destroy()
        end
    end)
end

function UIManager:getColors()
    return UI_COLORS
end

function UIManager:getRarityColor(rarity: string): Color3
    if typeof(rarity) ~= "string" then return UI_COLORS.Text end
    -- Normalize to title case for lookup
    local key = rarity:sub(1,1):upper() .. rarity:sub(2):lower()
    return RARITY_COLORS[key] or UI_COLORS.Text
end

-- Helper to bind ancestry guard to a GUI
function UIManager:_bindAncestryGuard(gui: Instance)
    table.insert(self._cons, gui.AncestryChanged:Connect(function(_, parent)
        if parent ~= playerGui then
            local ok = pcall(function() gui.Parent = playerGui end)
            if ok then
                log:info("Reparented UI GUI back to PlayerGui")
            end
        end
    end))
end

-- Is this GuiObject effectively visible? (self.Visible + all GuiObject parents Visible, and root ScreenGui Enabled)
local function _isEffectivelyVisible(inst: GuiObject, stopAt: Instance?)
    if not inst.Visible then return false end
    local p = inst.Parent
    while p and p ~= stopAt do
        if p:IsA("GuiObject") and (p.Visible == false) then return false end
        p = p.Parent
    end
    return true
end

-- A GuiObject is "visually meaningful" (not a transparent container / empty image/text)
local function _isMeaningfullyDrawn(inst: GuiObject): boolean
    -- Ignore explicit scrims/backdrops
    if inst:GetAttribute("isScrim") == true or inst.Name == "Scrim" then
        return false
    end
    
    local w, h = inst.AbsoluteSize.X, inst.AbsoluteSize.Y
    if w <= 2 or h <= 2 then return false end
    
    if inst:IsA("Frame") then
        -- Pure container? (nearly fully transparent)
        return (inst.BackgroundTransparency or 0) < 0.99
    elseif inst:IsA("TextLabel") or inst:IsA("TextButton") then
        local tt = inst.TextTransparency or 0
        local bt = inst.BackgroundTransparency or 0
        return (tt < 0.99) or (bt < 0.99)
    elseif inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
        local it = inst.ImageTransparency or 0
        local bt = inst.BackgroundTransparency or 0
        return (it < 0.99) or (bt < 0.99)
    else
        -- Other GuiObjects (ViewportFrame, etc.) – assume meaningful if not tiny
        return true
    end
end

local function _anyVisibleUnder(root: Instance?): boolean
    if not root then return false end
    for _, inst in ipairs(root:GetDescendants()) do
        if inst:IsA("GuiObject") then
            if _isEffectivelyVisible(inst, root) and _isMeaningfullyDrawn(inst) then
                return true
            end
        end
    end
    return false
end

-- Alias for cleanup
function UIManager:destroy()
    self:cleanup()
end

function UIManager:_anyUIVisible(): boolean
    -- ScreenGui must exist and be enabled
    if not self.screenGui or not self.screenGui.Parent then return false end
    if (self.screenGui.Enabled ~= nil) and (self.screenGui.Enabled == false) then return false end
    
    -- Special check: if MainHUD is active and its frame exists, consider UI visible
    -- (even if elements are still fading in)
    if self.activeScene and self.activeScene.name == "MainHUD" and self.activeScene.frame then
        return true
    end
    
    -- Overlay also must not be globally disabled (rare, but cheap to check)
    if self.overlayGui and (self.overlayGui.Enabled ~= nil) and (self.overlayGui.Enabled == false) then
        -- ignore overlay if disabled
        return _anyVisibleUnder(self.container)
    end
    
    -- Visible if container has content, or overlay has content that isn't just a scrim
    return _anyVisibleUnder(self.container) or _anyVisibleUnder(self.overlayGui)
end

function UIManager:_ensureRootsExist()
    -- Try to reparent screenGui first, only recreate if that fails
    if self.screenGui then
        local ok = pcall(function()
            if self.screenGui.Parent ~= playerGui then
                self.screenGui.Parent = playerGui
            end
        end)
        if not ok then
            self.screenGui = nil
        end
    end
    
    if not self.screenGui then
        self.screenGui = Instance.new("ScreenGui")
        self.screenGui.Name = "MiningGameUI"
        self.screenGui.ResetOnSpawn = false
        self.screenGui.DisplayOrder = 1
        self.screenGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
        self.screenGui.ClipToDeviceSafeArea = true
        self.screenGui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
        self.screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        self.screenGui.IgnoreGuiInset = true
        self.screenGui.Parent = playerGui
        
        ThemeRefresher.BindTree(self.screenGui)
        self:_bindAncestryGuard(self.screenGui)
    end
    
    -- Ensure container exists
    if not self.container or not self.container.Parent then
        local container = Instance.new("Frame")
        container.Name = "Container"
        container.Size = UDim2.new(1, 0, 1, 0)
        container.BackgroundTransparency = 1
        container.Parent = self.screenGui
        self.container = container
    end
    
    -- Try to reparent overlayGui first, only recreate if that fails
    if self.overlayGui then
        local ok = pcall(function()
            if self.overlayGui.Parent ~= playerGui then
                self.overlayGui.Parent = playerGui
            end
        end)
        if not ok then
            self.overlayGui = nil
        end
    end
    
    if not self.overlayGui then
        self.overlayGui = Instance.new("ScreenGui")
        self.overlayGui.Name = "MiningGameUI_Overlay"
        self.overlayGui.ResetOnSpawn = false
        self.overlayGui.DisplayOrder = 100
        self.overlayGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
        self.overlayGui.ClipToDeviceSafeArea = true
        self.overlayGui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
        self.overlayGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        self.overlayGui.IgnoreGuiInset = true
        self.overlayGui.Parent = playerGui
        
        ThemeRefresher.BindTree(self.overlayGui)
        self:_bindAncestryGuard(self.overlayGui)
    end
    
    -- Recreate toast stack if needed
    if not self.toastStack or not self.toastStack.Parent then
        self.toastStack = Instance.new("Frame")
        self.toastStack.Name = "ToastStack"
        self.toastStack.BackgroundTransparency = 1
        self.toastStack.Parent = self.container
        
        local stackLayout = Instance.new("UIListLayout")
        stackLayout.FillDirection = Enum.FillDirection.Vertical
        stackLayout.Padding = UDim.new(0, Theme.toast.gap)
        stackLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
        stackLayout.VerticalAlignment = Enum.VerticalAlignment.Top
        stackLayout.SortOrder = Enum.SortOrder.LayoutOrder
        stackLayout.Parent = self.toastStack
        self.toastLayout = stackLayout
        
        if self.updateToastPosition then
            self.updateToastPosition()
        end
    end
end

function UIManager:_showMainHUDNow()
    -- Prevent re-entry during recovery
    if self._isRecovering then return end
    self._isRecovering = true
    
    -- Ensure root elements exist
    self:_ensureRootsExist()
    
    -- Clear any modal/scrim leftovers
    if self.overlayGui then
        for _, child in ipairs(self.overlayGui:GetChildren()) do
            child:Destroy()
        end
    end
    
    -- Hide everything else (don't mutate stack with showScene/hideScene)
    for name, scene in pairs(self.scenes) do
        local s = scene
        if s and s.hide then
            pcall(function() s:hide() end)
        end
    end
    self.sceneStack = {}
    self.activeScene = nil
    
    local hud = self.scenes["MainHUD"]
    if hud then
        if not hud.frame then
            pcall(function() hud:init(self) end)
        end
        pcall(function() hud:show() end)
        self.activeScene = hud
        -- Let future opens proceed immediately
        self._transitionUnlockAt = 0
        -- Keep toasts in the right spot again
        if self.updateToastPosition then self.updateToastPosition() end
        
        -- Clean up any recovery buttons
        for _, child in ipairs(self.screenGui:GetChildren()) do
            if child:IsA("TextButton") and child.Text == "Tap to recover UI" then
                child:Destroy()
            end
        end
        
        -- Reset watchdog timer to give UI time to appear
        self._watchdogLastVisibleAt = time() + 2 -- Give 2 seconds for animations
        
        log:debug("Watchdog recovered UI by showing MainHUD")
    else
        -- As a last resort, show a tiny recovery prompt
        local btn = Instance.new("TextButton")
        btn.Text = "Tap to recover UI"
        btn.Size = UDim2.fromOffset(220, 48)
        btn.AnchorPoint = Vector2.new(0.5, 0.5)
        btn.Position = UDim2.fromScale(0.5, 0.5)
        btn.BackgroundColor3 = Theme.colors.Surface
        btn.TextColor3 = Theme.colors.Text
        btn.Font = Theme.fonts.Primary
        btn.TextSize = 20
        btn.Parent = self.screenGui
        btn.Activated:Connect(function()
            btn:Destroy()
            -- Try again (maybe MainHUD registered a moment later)
            self:_showMainHUDNow()
        end)
        log:warn("No MainHUD scene registered; showing recovery button")
    end
    
    -- Clear recovery flag after a frame
    task.defer(function() self._isRecovering = false end)
end

function UIManager:cleanup()
    -- Disconnect all connections (including theme listener)
    for _, c in ipairs(self._cons) do 
        if c.Connected then 
            c:Disconnect() 
        end 
    end
    self._cons = {}
    
    if self.screenGui then
        self.screenGui:Destroy()
        self.screenGui = nil
    end
    
    if self.overlayGui then
        self.overlayGui:Destroy()
        self.overlayGui = nil
    end
    
    for _, scene in pairs(self.scenes) do
        if scene.cleanup then
            scene:cleanup()
        end
    end
    
    self.scenes = {}
    self.activeScene = nil
    self.isInitialized = false
end

return UIManager
