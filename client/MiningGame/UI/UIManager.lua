--!strict
-- UIManager.lua
-- Core UI management system with scene-based architecture

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

-- Import Theme and UIUtils
local Theme = require(ReplicatedStorage:WaitForChild("MiningGame"):WaitForChild("UI"):WaitForChild("Theme"))
local UIUtils = require(ReplicatedStorage:WaitForChild("MiningGame"):WaitForChild("UI"):WaitForChild("UIUtils"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Use Theme colors
local UI_COLORS = Theme.colors
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
    
    -- Set initial position
    self.updateToastPosition()
    
    self.container = container
    self.isInitialized = true
    
    print("[UIManager] Initialized with mobile-safe settings")
end

-- UIScale removed - no longer needed

function UIManager:refreshLayout()
    -- Update toast stack position based on current theme values
    if self.updateToastPosition then
        self.updateToastPosition()
    end
end

function UIManager:registerScene(scene: Scene)
    -- Validate scene interface
    UIUtils.validateScene(scene)
    
    self.scenes[scene.name] = scene
    print(string.format("[UIManager] Registered scene: %s", scene.name))
end

function UIManager:showScene(sceneName: string, ...: any)
    local scene = self.scenes[sceneName]
    if not scene then
        warn(string.format("[UIManager] Scene not found: %s", sceneName))
        return
    end
    
    -- Toggle behavior: if scene is already active, hide it
    if self.activeScene == scene then
        self:hideScene(sceneName)
        return
    end
    
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
    
    print(string.format("[UIManager] Showing scene: %s", sceneName))
end

function UIManager:hideScene(sceneName: string)
    local scene = self.scenes[sceneName]
    if not scene then return end
    
    scene:hide()
    
    -- If we hid the active scene, pop back to previous
    if self.activeScene == scene then
        self.activeScene = nil
        local prev = table.remove(self.sceneStack)
        if prev then
            prev:show()
            self.activeScene = prev
            print(string.format("[UIManager] Returning to scene: %s", prev.name))
        elseif self.scenes["MainHUD"] then
            -- Fallback to MainHUD if no previous scene
            self:showScene("MainHUD")
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

function UIManager:cleanup()
    -- Disconnect all connections
    for _, c in ipairs(self._cons) do 
        if c.Disconnect then 
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