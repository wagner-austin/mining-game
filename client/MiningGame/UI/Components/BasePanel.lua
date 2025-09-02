--!strict
-- BasePanel.lua
-- Reusable frosted glass panel component with responsive scaling and proper UX

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Theme = require(MiningGame:WaitForChild("UI"):WaitForChild("Theme"))
local Logger = require(MiningGame:WaitForChild("Logger"))

local log = Logger.new(Logger.CAT.Panel)
local UIUtils = require(ReplicatedStorage:WaitForChild("MiningGame"):WaitForChild("UI"):WaitForChild("UIUtils"))
local ThemeRefresher = require(ReplicatedStorage:WaitForChild("MiningGame"):WaitForChild("UI"):WaitForChild("ThemeRefresher"))

local BasePanel = {}
BasePanel.__index = BasePanel

type Props = {
    parent: GuiObject,
    title: string,
    size: UDim2?,
    position: UDim2?,
    tintColor: Color3?,
    transition: ("left" | "down" | "scale")?,
    scrim: boolean?,
    closeOnEsc: boolean?,
    onClose: (() -> ())?
}

function BasePanel.new(props: Props)
    local self = setmetatable({}, BasePanel)
    
    local colors = Theme.colors
    local panelConfig = Theme.basePanel
    
    -- Connection management
    self._cons = {}
    local function bind(signal, fn)
        local c = signal:Connect(fn)
        table.insert(self._cons, c)
        return c
    end
    
    -- Responsive sizing based on viewport
    local camera = workspace.CurrentCamera
    local vp = camera.ViewportSize
    local isPhone = vp.X < Theme.breakpoints.medium
    local isTablet = vp.X < Theme.breakpoints.large
    
    local defaultSize = props.size
    if not defaultSize then
        -- Use Theme if present, otherwise safe defaults
        local panelMargins = (Theme.panels and Theme.panels.margins) or { phone = 0.10, tablet = 0.10, desktop = 0.10 }
        local panelWidths  = (Theme.panels and Theme.panels.widths)  or { phone = 0.90, tablet = 0.85, desktop = 0.75 }

        local margin = isPhone and panelMargins.phone or isTablet and panelMargins.tablet or panelMargins.desktop
        local width  = isPhone and panelWidths.phone  or isTablet and panelWidths.tablet  or panelWidths.desktop
        local height = 1 - (2 * margin)  -- vertical margins, top+bottom

        defaultSize = UDim2.new(width, 0, height, 0)
    end
    
    -- Remove scrim but add click-outside-to-close functionality
    -- This allows full camera controls while panel is open
    if props.scrim ~= false then
        -- Monitor clicks globally to detect outside clicks
        bind(UserInputService.InputBegan, function(input, gameProcessed)
            -- Only handle left clicks and touches
            if input.UserInputType == Enum.UserInputType.MouseButton1 or 
               input.UserInputType == Enum.UserInputType.Touch then
                -- Only check if panel is open and visible
                if self.isOpen and self.container and self.container.Visible then
                    local clickPos = input.Position
                    local panel = self.container
                    local absPos = panel.AbsolutePosition
                    local absSize = panel.AbsoluteSize
                    
                    -- Check if click is outside panel bounds
                    if clickPos.X < absPos.X or clickPos.X > absPos.X + absSize.X or
                       clickPos.Y < absPos.Y or clickPos.Y > absPos.Y + absSize.Y then
                        -- Small delay to prevent accidental closes
                        task.wait(0.05)
                        if self.isOpen then
                            self:close()
                        end
                    end
                end
            end
        end)
    end
    
    -- Main container (transparent, holds background and content layers)
    local container = Instance.new("Frame")
    container.Name = "BasePanel_" .. props.title
    container.Size = defaultSize
    container.Position = props.position or UDim2.new(0.5, 0, 0.5, 0)
    container.AnchorPoint = Vector2.new(0.5, 0.5)
    container.BackgroundTransparency = 1  -- Transparent container
    container.ZIndex = 2  -- Above scrim (which is now at ZIndex 1)
    container.Visible = false
    container.Active = true  -- Block clicks from going through the panel
    container.Parent = props.parent
    
    -- Background layer (this gets scaled for animations)
    local backgroundLayer = Instance.new("Frame")
    backgroundLayer.Name = "Background"  -- Match the name UIUtils expects
    backgroundLayer.Size = UDim2.fromScale(1, 1)
    backgroundLayer.AnchorPoint = Vector2.new(0.5, 0.5)
    backgroundLayer.Position = UDim2.fromScale(0.5, 0.5)
    backgroundLayer.BackgroundColor3 = props.tintColor or colors.Surface
    backgroundLayer.BackgroundTransparency = Theme.effects.frosted.backgroundTransparency  -- Slightly less transparent for better visibility
    backgroundLayer.ClipsDescendants = true
    backgroundLayer.ZIndex = 1
    backgroundLayer.Parent = container
    
    -- Content layer (never scaled, holds all actual content)
    local contentLayer = Instance.new("Frame")
    contentLayer.Name = "Content"  -- Match the name UIUtils expects
    contentLayer.Size = UDim2.fromScale(1, 1)
    contentLayer.AnchorPoint = Vector2.new(0.5, 0.5)
    contentLayer.Position = UDim2.fromScale(0.5, 0.5)
    contentLayer.BackgroundTransparency = 1
    contentLayer.ZIndex = 2
    contentLayer.Parent = container
    
    -- Only apply aspect ratio if explicitly requested (opt-in to prevent height issues)
    if props.useAspect and not isPhone then
        local widthScale = defaultSize.X.Scale
        local heightScale = defaultSize.Y.Scale
        local ar = widthScale / heightScale  -- Calculate aspect from the computed size
        
        local aspectRatio = Instance.new("UIAspectRatioConstraint")
        aspectRatio.AspectRatio = ar
        aspectRatio.DominantAxis = Enum.DominantAxis.Width  -- IMPORTANT: Width drives, height follows
        aspectRatio.Parent = container
    end
    
    -- Apply all visual effects to background layer
    -- Rounded corners
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, Theme.sizes.LargeCornerRadius)
    corner.Parent = backgroundLayer
    
    -- Glass edge
    UIUtils.applyGlassEdge(backgroundLayer)
    
    -- Frosted gradient (configurable via Theme.effects.frosted)
    local gradient = Instance.new("UIGradient")
    gradient.Rotation = 90
    gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(1, 1, 1))
    local frosted = Theme.effects.frosted
    gradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, frosted.gradientTopT),  -- More opaque at top
        NumberSequenceKeypoint.new(1, frosted.gradientBottomT)   -- Less transparent at bottom
    })
    gradient.Parent = backgroundLayer
    
    -- Noise texture for glass effect (configurable via Theme.effects.frosted)
    local noise = Instance.new("ImageLabel")
    noise.BackgroundTransparency = 1
    -- Tint the noise toward the active theme color for a colored frost
    local frost = Theme.effects.frosted
    local base = Theme.colors[frost.noiseColorKey] or Theme.colors.Background
    local t = math.clamp(frost.noiseLighten or 0, 0, 1)
    local tinted = t > 0 and base:Lerp(Color3.new(1, 1, 1), t) or base
    noise.ImageColor3 = tinted
    noise.ImageTransparency = frost.noiseTransparency
    noise.ScaleType = Enum.ScaleType.Tile
    noise.TileSize = UDim2.fromOffset(64, 64)
    noise.Size = UDim2.fromScale(1, 1)
    noise.ZIndex = 0
    noise.Parent = backgroundLayer

    -- Register this frosted surface for live theme refreshes
    UIUtils.registerFrosted(backgroundLayer, gradient, noise)
    
    -- Header bar (in content layer so text doesn't scale)
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, panelConfig.headerHeight)
    header.BackgroundTransparency = 1
    header.Parent = contentLayer
    
    -- Title (scale-based padding)
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, -80, 1, 0)
    title.Position = UDim2.new(0, panelConfig.contentPadding, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = props.title:upper()
    title.TextColor3 = colors.Text
    title.TextScaled = true
    title.Font = Theme.fonts.Display
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = header
    
    local titleConstraint = Instance.new("UITextSizeConstraint")
    titleConstraint.MinTextSize = Theme.textSizes.Large.Min
    titleConstraint.MaxTextSize = Theme.textSizes.Large.Max
    titleConstraint.Parent = title
    
    -- Close button (emoji, square, larger, white)
    local closeCfg = Theme.closeButton or {
        size = { phone = 56, tablet = 56, desktop = 56 },
        iconSize = { Min = 20, Max = 36 },
        icon = "X",  -- Regular X character
    }
    local cbSize = (isPhone and closeCfg.size.phone) or (isTablet and closeCfg.size.tablet) or closeCfg.size.desktop
    
    local closeButton = Instance.new("TextButton")
    closeButton.Name = "CloseButton"
    closeButton.Size = UDim2.fromOffset(cbSize, cbSize)
    closeButton.Position = UDim2.new(1, -(cbSize + 6), 0, 6)
    closeButton.BackgroundTransparency = 1  -- Clear background, chip-like
    closeButton.RichText = true
    closeButton.Text = string.format('<font color="rgb(255,59,48)">%s</font>', closeCfg.icon)
    closeButton.TextStrokeTransparency = 1  -- Avoid gray edging
    closeButton.TextScaled = true
    closeButton.Font = Theme.fonts.Primary
    closeButton.AutoButtonColor = false
    closeButton.Parent = header
    
    local closeConstraint = Instance.new("UITextSizeConstraint")
    closeConstraint.MinTextSize = closeCfg.iconSize.Min
    closeConstraint.MaxTextSize = closeCfg.iconSize.Max
    closeConstraint.Parent = closeButton
    
    -- Divider line
    local divider = Instance.new("Frame")
    divider.Name = "Divider"
    divider.Size = UDim2.new(1, -panelConfig.contentPadding*2, 0, panelConfig.dividerThickness)
    divider.Position = UDim2.new(0, panelConfig.contentPadding, 1, -panelConfig.dividerThickness)
    divider.BackgroundColor3 = colors.Text
    divider.BackgroundTransparency = Theme.ui.dividerTransparency
    divider.BorderSizePixel = 0
    divider.Parent = header
    
    -- Content area (scrollable, in content layer)
    local contentContainer = Instance.new("ScrollingFrame")
    contentContainer.Name = "Content"
    contentContainer.Size = UDim2.new(1, -panelConfig.contentPadding*2, 1, -(panelConfig.headerHeight + 20))
    contentContainer.Position = UDim2.new(0, panelConfig.contentPadding, 0, panelConfig.headerHeight + 10)
    contentContainer.BackgroundTransparency = 1
    contentContainer.BorderSizePixel = 0
    contentContainer.ScrollBarThickness = isPhone and 16 or 10  -- Wider for easier touch
    contentContainer.ScrollBarImageColor3 = colors.Text
    contentContainer.ScrollBarImageTransparency = 0.5
    contentContainer.CanvasSize = UDim2.new(0, 0, 0, 0)  -- Let AutomaticCanvasSize handle it
    contentContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
    contentContainer.ScrollingDirection = Enum.ScrollingDirection.Y
    contentContainer.ElasticBehavior = Enum.ElasticBehavior.Always  -- Bouncy scrolling
    contentContainer.Parent = contentLayer
    
    -- Add padding to prevent content from going under scrollbar (avoid duplicates)
    local contentPadding = contentContainer:FindFirstChildOfClass("UIPadding")
    if not contentPadding then
        contentPadding = Instance.new("UIPadding")
        contentPadding.Parent = contentContainer
    end
    contentPadding.PaddingRight = UDim.new(0, (contentContainer.ScrollBarThickness or 12) + 8)
    contentPadding.PaddingLeft = UDim.new(0, 4)
    contentPadding.PaddingTop = UDim.new(0, 4)
    contentPadding.PaddingBottom = UDim.new(0, 4)
    
    -- Interactive scale for animations (only on background layer)
    local scale = Instance.new("UIScale")
    scale.Scale = 1
    scale.Parent = backgroundLayer
    
    -- Apply press animation to the panel
    UIUtils.applyPressAnimation(container, 0.98)  -- Subtle press for large panels
    
    -- Store references
    self.container = container
    self.backgroundLayer = backgroundLayer
    self.contentLayer = contentLayer
    self.content = contentContainer
    self.scale = scale
    self.title = title
    self.divider = divider
    self.closeButton = closeButton
    self.onClose = props.onClose
    self.isOpen = false
    self.transition = props.transition or "scale"
    self._textReveal = nil  -- Track gradient reveal state
    self._closing = false
    self._revealBaseline = {}  -- Persistent baseline for element transparencies
    
    -- Bind to theme refresher for automatic updates
    ThemeRefresher.Bind(backgroundLayer, { BackgroundColor3 = "Surface" })
    ThemeRefresher.Bind(title, { TextColor3 = "Text" })
    ThemeRefresher.Bind(divider, { BackgroundColor3 = "Text" })
    
    -- Setup interactions
    bind(closeButton.Activated, function()
        local SoundManager = require(ReplicatedStorage.MiningGame:WaitForChild("SoundManager"))
        SoundManager.PlayUI("buttonclick")
        self:close()
    end)
    
    -- Close button hover
    bind(closeButton.MouseEnter, function()
        TweenService:Create(closeButton, Theme.animations.Quick, {
            TextTransparency = 0.3
        }):Play()
    end)
    
    bind(closeButton.MouseLeave, function()
        TweenService:Create(closeButton, Theme.animations.Quick, {
            TextTransparency = 0
        }):Play()
    end)
    
    -- ESC to close (if enabled)
    if props.closeOnEsc ~= false then
        bind(UserInputService.InputBegan, function(input, gameProcessed)
            if gameProcessed then return end
            if input.KeyCode == Enum.KeyCode.Escape and self.isOpen then
                self:close()
            end
        end)
    end
    
    -- Touch swipe down to close (mobile)
    local touchStartY = 0
    local swipeThreshold = 100
    
    bind(container.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            touchStartY = input.Position.Y
        end
    end)
    
    bind(container.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            local deltaY = input.Position.Y - touchStartY
            if deltaY > swipeThreshold then
                self:close()
            end
        end
    end)
    
    return self
end

-- Helper: Capture or maintain the baseline transparency values
function BasePanel:_refreshRevealBaseline()
    if not self._revealBaseline then self._revealBaseline = {} end
    local baseline = self._revealBaseline
    
    -- Prune dead instances
    for inst, _ in pairs(baseline) do
        if not inst:IsDescendantOf(self.contentLayer) then
            baseline[inst] = nil
        end
    end
    
    -- Add new elements that don't have a record yet
    for _, c in ipairs(self.contentLayer:GetDescendants()) do
        if c:IsA("GuiObject") and c.Visible and not c:IsA("UIConstraint") then
            if not baseline[c] then
                local rec = {}
                if c:IsA("TextLabel") or c:IsA("TextButton") or c:IsA("TextBox") then
                    rec.textOrig = c.TextTransparency
                    rec.strokeTextOrig = c.TextStrokeTransparency
                end
                rec.bgOrig = c.BackgroundTransparency
                if c:IsA("ImageLabel") or c:IsA("ImageButton") then
                    rec.imgOrig = c.ImageTransparency
                end
                if c:IsA("ScrollingFrame") then
                    rec.scrollBarOrig = c.ScrollBarImageTransparency
                end
                local uiStroke = c:FindFirstChildOfClass("UIStroke")
                if uiStroke then
                    rec.stroke = uiStroke
                    rec.strokeOrig = uiStroke.Transparency
                end
                baseline[c] = rec
            end
        end
    end
end

-- Helper: cancel any in-flight reveal cleanly
function BasePanel:_cancelTextReveal(setTo)
    log:debug("[_cancelTextReveal] Called with setTo: %s", tostring(setTo))
    local tr = self._textReveal
    if tr then
        log:debug("[_cancelTextReveal] Canceling existing reveal")
        if tr.tween then tr.tween:Cancel() end
        if tr.conn then tr.conn:Disconnect() end
        if tr.progress then tr.progress:Destroy() end
        self._textReveal = nil
    end
    if setTo ~= nil then
        for _, child in ipairs(self.contentLayer:GetDescendants()) do
            if child:IsA("GuiObject") then
                if child:IsA("TextLabel") or child:IsA("TextButton") or child:IsA("TextBox") then
                    child.TextTransparency = setTo
                    child.TextStrokeTransparency = setTo
                end
                child.BackgroundTransparency = setTo
                if child:IsA("ImageLabel") or child:IsA("ImageButton") then
                    child.ImageTransparency = setTo
                end
                local s = child:FindFirstChildOfClass("UIStroke")
                if s then s.Transparency = setTo end
            end
        end
    end
end

-- Helper: true top→bottom gradient reveal driven by one tween
function BasePanel:_startTextReveal(duration, delay, bandPx)
    log:debug("[_startTextReveal] Called, isOpen: %s, _closing: %s", tostring(self.isOpen), tostring(self._closing))
    
    -- Let layout/AbsolutePosition settle for one frame
    RunService.Heartbeat:Wait()
    
    -- Guard: don't animate if panel was closed while waiting
    if not self.isOpen then 
        log:debug("[_startTextReveal] Panel not open after heartbeat, returning")
        return 
    end
    
    -- Helper for smooth interpolation
    local function lerp(a, b, t) return a + (b - a) * t end
    
    -- Refresh baseline and use it
    self:_refreshRevealBaseline()
    local baseline = self._revealBaseline
    
    local elems = {}
    local minY, maxY = math.huge, -math.huge
    
    log:debug("[_startTextReveal] Using baseline for elements")
    local elementCount = 0
    
    for _, c in ipairs(self.contentLayer:GetDescendants()) do
        if c:IsA("GuiObject") and c.Visible and not c:IsA("UIConstraint") then
            local rec = baseline[c]
            if rec then
                local y = c.AbsolutePosition.Y + c.AbsoluteSize.Y * 0.5
                table.insert(elems, { el = c, y = y, rec = rec })
                elementCount = elementCount + 1
                if y < minY then minY = y end
                if y > maxY then maxY = y end
                
                -- Set current to hidden (start state)
                if rec.textOrig ~= nil then
                    c.TextTransparency = 1
                    c.TextStrokeTransparency = 1
                end
                if rec.bgOrig ~= nil and c.BackgroundTransparency < 0.99 then
                    c.BackgroundTransparency = 1
                end
                if rec.imgOrig ~= nil then
                    c.ImageTransparency = 1
                end
                if rec.stroke then
                    rec.stroke.Transparency = 1
                end
                if rec.scrollBarOrig ~= nil then
                    c.ScrollBarImageTransparency = 1
                end
            end
        end
    end
    
    log:debug("[_startTextReveal] Found %d elements, minY: %.1f, maxY: %.1f", elementCount, minY, maxY)
    
    if #elems == 0 or not (maxY > minY) then
        log:debug("[_startTextReveal] Fallback: no elements or invalid range, restoring from baseline")
        -- Fallback: restore from baseline
        for inst, rec in pairs(baseline) do
            if inst:IsDescendantOf(self.contentLayer) then
                if rec.textOrig ~= nil then
                    inst.TextTransparency = rec.textOrig
                    inst.TextStrokeTransparency = rec.strokeTextOrig or 1
                end
                if rec.imgOrig ~= nil then
                    inst.ImageTransparency = rec.imgOrig
                end
                if rec.bgOrig ~= nil then
                    inst.BackgroundTransparency = rec.bgOrig
                end
                if rec.stroke then
                    rec.stroke.Transparency = rec.strokeOrig or 0
                end
                if rec.scrollBarOrig ~= nil then
                    inst.ScrollBarImageTransparency = rec.scrollBarOrig
                end
            end
        end
        return
    end
    
    -- Cancel any previous reveal
    self:_cancelTextReveal()
    
    local progress = Instance.new("NumberValue")
    progress.Value = 0
    
    local range = maxY - minY
    -- Sharper adaptive band for snappier feel
    local band = bandPx or math.clamp(range * 0.06, 16, 72)
    
    local function update()
        -- The reveal "front" sweeps downward
        local front = minY + progress.Value * (range + band)
        log:debug("update progress=%.3f front=%.2f elements=%d", progress.Value, front, #elems)
        for _, d in ipairs(elems) do
            local rec = d.rec
            -- Map each element to [0..1] based on how far the front has passed its Y
            local t = math.clamp((front - d.y) / band, 0, 1)
            
            -- Animate all properties back to baseline values
            if rec.textOrig ~= nil then
                d.el.TextTransparency = lerp(1, rec.textOrig, t)
                d.el.TextStrokeTransparency = lerp(1, rec.strokeTextOrig or 1, t)
            end
            
            if rec.imgOrig ~= nil then
                d.el.ImageTransparency = lerp(1, rec.imgOrig, t)
            end
            
            if rec.bgOrig ~= nil then
                d.el.BackgroundTransparency = lerp(1, rec.bgOrig, t)
            end
            
            if rec.stroke then
                rec.stroke.Transparency = lerp(1, rec.strokeOrig or 0, t)
            end
            
            if rec.scrollBarOrig ~= nil then
                d.el.ScrollBarImageTransparency = lerp(1, rec.scrollBarOrig, t)
            end
        end
    end
    
    local tr = { progress = progress }
    self._textReveal = tr
    tr.conn = progress.Changed:Connect(update)
    
    task.delay(delay or 0.08, function()
        log:debug("[_startTextReveal] Delay finished, checking state - isOpen: %s, textReveal match: %s", tostring(self.isOpen), tostring(self._textReveal == tr))
        -- Canceled while we waited or panel closed?
        if not self.isOpen or self._textReveal ~= tr then
            log:debug("[_startTextReveal] Aborting tween - isOpen: %s, textReveal match: %s", tostring(self.isOpen), tostring(self._textReveal == tr))
            progress:Destroy()
            return
        end
        
        log:debug("[_startTextReveal] Creating and playing reveal tween")
        local tween = TweenService:Create(
            progress,
            TweenInfo.new(duration or 0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {Value = 1}
        )
        tr.tween = tween
        
        tween.Completed:Connect(function()
            log:debug("[_startTextReveal] Tween completed")
            update()
            if self._textReveal == tr then
                if tr.conn then tr.conn:Disconnect() end
                if tr.progress then tr.progress:Destroy() end
                self._textReveal = nil
            end
        end)
        
        tween:Play()
    end)
    
    update()
end

function BasePanel:show()
    log:debug("[show] isOpen=%s closing=%s", tostring(self.isOpen), tostring(self._closing))
    
    -- If currently closing, abort that and reset
    if self._closing then
        log:debug("[show] Aborting close animation")
        self._closing = false
        self:_cancelTextReveal()
    end
    
    if self.isOpen then 
        log:debug("[show] Already open, returning")
        return 
    end
    self.isOpen = true
    log:debug("[show] Setting isOpen = true")
    
    -- No scrim to show anymore (allows camera controls)
    
    -- Set initial position based on transition type
    if self.transition == "left" then
        self.container.Position = UDim2.new(-0.5, 0, 0.5, 0)
    elseif self.transition == "down" then
        self.container.Position = UDim2.new(0.5, 0, 1.5, 0)
    else -- scale
        self.scale.Scale = 0.95
    end
    
    self.container.Visible = true
    self.backgroundLayer.BackgroundTransparency = 1  -- Start transparent for fade-in
    
    -- Entrance animation
    if self.transition == "scale" then
        TweenService:Create(self.scale, Theme.animations.Bounce, {
            Scale = 1
        }):Play()
    else
        TweenService:Create(self.container, Theme.animations.Standard, {
            Position = UDim2.new(0.5, 0, 0.5, 0)
        }):Play()
    end
    
    TweenService:Create(self.backgroundLayer, Theme.animations.Standard, {
        BackgroundTransparency = Theme.effects.frosted.backgroundTransparency
    }):Play()
    
    -- Also restore the glass edge stroke visibility
    local bgStroke = self.backgroundLayer:FindFirstChildOfClass("UIStroke")
    if bgStroke then
        bgStroke.Transparency = 0  -- Instantly visible for crisp edge
    end
    
    -- Start the smooth gradient reveal
    log:debug("[show] Starting text reveal")
    task.spawn(function()
        self:_startTextReveal(0.42, 0.08, nil)  -- Faster duration, quicker start, adaptive band
    end)
end

function BasePanel:close()
    if not self.isOpen or self._closing then return end
    self:hide()
    if self.onClose then
        self.onClose()
    end
    -- Don't reset _closing here - hide() will handle it
end

function BasePanel:hide()
    log:debug("[hide] isOpen=%s closing=%s", tostring(self.isOpen), tostring(self._closing))
    if not self.isOpen then 
        log:debug("[hide] Not open, returning")
        return 
    end
    self.isOpen = false
    self._closing = true  -- Mark as closing here
    log:debug("[hide] Setting isOpen = false, _closing = true")
    
    -- Stop the gradient tween safely
    log:debug("[hide] Canceling text reveal")
    self:_cancelTextReveal()
    
    -- Don't call _cancelTextReveal(1) here - it breaks the next show!
    
    -- Quick fade out all elements
    for _, child in ipairs(self.contentLayer:GetDescendants()) do
        if child:IsA("GuiObject") then
            local goals = {}
            if child:IsA("TextLabel") or child:IsA("TextButton") or child:IsA("TextBox") then
                goals.TextTransparency = 1
                goals.TextStrokeTransparency = 1
            end
            -- Only fade out backgrounds that are currently visible
            if child.BackgroundTransparency < 0.99 then
                goals.BackgroundTransparency = 1
            end
            if child:IsA("ImageLabel") or child:IsA("ImageButton") then
                goals.ImageTransparency = 1
            end
            -- Fade scrollbar
            if child:IsA("ScrollingFrame") then
                goals.ScrollBarImageTransparency = 1
            end
            if next(goals) then -- Only tween if there are properties to change
                TweenService:Create(child, Theme.animations.Quick, goals):Play()
            end
            
            local stroke = child:FindFirstChildOfClass("UIStroke")
            if stroke then
                TweenService:Create(stroke, Theme.animations.Quick, { Transparency = 1 }):Play()
            end
        end
    end
    
    -- No scrim to hide anymore
    
    -- Exit animation
    local endPos = self.container.Position
    if self.transition == "left" then
        endPos = UDim2.new(-0.5, 0, 0.5, 0)
    elseif self.transition == "down" then
        endPos = UDim2.new(0.5, 0, 1.5, 0)
    end
    
    local moveTween = nil
    if self.transition == "scale" then
        moveTween = TweenService:Create(self.scale, Theme.animations.Standard, {
            Scale = 0.95
        })
    else
        moveTween = TweenService:Create(self.container, Theme.animations.Standard, {
            Position = endPos
        })
    end
    
    local fadeTween = TweenService:Create(self.backgroundLayer, Theme.animations.Quick, {
        BackgroundTransparency = 1
    })
    
    -- Also fade the glass edge stroke on the background layer
    local bgStroke = self.backgroundLayer:FindFirstChildOfClass("UIStroke")
    if bgStroke then
        TweenService:Create(bgStroke, Theme.animations.Quick, { Transparency = 1 }):Play()
    end
    
    -- Simpler completion handling
    local function finishHide()
        log:debug("[hide] finishHide called, resetting _closing")
        self.container.Visible = false
        self._closing = false  -- Reset here after animations complete
        log:debug("[hide] _closing reset to false")
    end
    
    if moveTween then 
        moveTween:Play() 
    end
    
    fadeTween:Play()
    
    -- Use the longer of the two animations
    log:debug("[hide] Waiting for animations to complete")
    task.wait(Theme.animations.Standard.Time or 0.2)
    finishHide()
end

function BasePanel:setTitle(newTitle: string)
    self.title.Text = newTitle:upper()
end

function BasePanel:getContent(): ScrollingFrame
    return self.content
end

function BasePanel:destroy()
    -- Disconnect all connections
    for _, c in ipairs(self._cons) do
        if c and c.Disconnect then
            c:Disconnect()
        end
    end
    self._cons = {}
    
    -- Destroy UI elements
    if self.container then
        self.container:Destroy()
    end
end

return BasePanel
