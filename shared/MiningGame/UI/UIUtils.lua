--!strict
-- UIUtils.lua
-- Shared utilities for UI components to avoid duplication

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UI = MiningGame:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local ThemeRefresher = require(UI:WaitForChild("ThemeRefresher"))

-- Try to get PlayerProfileGuard if available (client-side only)
local PlayerProfileGuard = nil
local okPPG, ppg = pcall(function() return require(MiningGame:FindFirstChild("PlayerProfileGuard")) end)
if okPPG then PlayerProfileGuard = ppg end

local UIUtils = {}

-- Tween helper: create+play a tween for simple property animations
function UIUtils.tweenProps(inst: Instance, goals: {[string]: any}, info: TweenInfo?)
    local tweenInfo = info or Theme.animations.Quick
    local tween = TweenService:Create(inst, tweenInfo, goals)
    tween:Play()
    return tween
end

-- Registry of frosted backgrounds for live theme refreshing
local _frosted = setmetatable({}, { __mode = "k" }) :: {[Frame]: { gradient: UIGradient?, noise: ImageLabel? }}

function UIUtils.registerFrosted(background: Frame, gradient: UIGradient?, noise: ImageLabel?)
    _frosted[background] = { gradient = gradient, noise = noise }
    background.AncestryChanged:Connect(function()
        if not background.Parent then
            _frosted[background] = nil
        end
    end)
end

function UIUtils.refreshFrosting()
    local frost = Theme.effects.frosted
    for background, parts in pairs(_frosted) do
        if background and background.Parent then
            background.BackgroundTransparency = frost.backgroundTransparency
            local grad = parts.gradient
            if grad and grad.Parent then
                grad.Transparency = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, frost.gradientTopT),
                    NumberSequenceKeypoint.new(1, frost.gradientBottomT),
                })
            end
            local noise = parts.noise
            if noise and noise.Parent then
                local base = Theme.colors[frost.noiseColorKey] or Theme.colors.Background
                local t = math.clamp(frost.noiseLighten or 0, 0, 1)
                local tinted = t > 0 and base:Lerp(Color3.new(1,1,1), t) or base
                noise.ImageColor3 = tinted
                noise.ImageTransparency = frost.noiseTransparency
            end
        else
            _frosted[background] = nil
        end
    end
end

-- Format number with K/M/B suffixes
function UIUtils.formatNumber(n: number): string
    local a = math.abs(n)
    if a >= 1e9 then 
        return (string.format("%.1fB", n/1e9)):gsub("%.0B", "B")
    elseif a >= 1e6 then 
        return (string.format("%.1fM", n/1e6)):gsub("%.0M", "M")
    elseif a >= 1e3 then 
        return (string.format("%.1fK", n/1e3)):gsub("%.0K", "K")
    else
        return tostring(n)
    end
end

-- Pulse animation for any GUI element
function UIUtils.pulse(gui: GuiObject, scaleUp: number?)
    local scale = gui:FindFirstChildOfClass("UIScale")
    if not scale then
        scale = Instance.new("UIScale")
        scale.Parent = gui
    end
    
    local up = TweenService:Create(scale, Theme.animations.Quick, {
        Scale = scaleUp or 1.06
    })
    local down = TweenService:Create(scale, Theme.animations.Smooth, {
        Scale = 1
    })
    
    up:Play()
    up.Completed:Connect(function() 
        down:Play() 
    end)
end

-- Apply consistent glass edge styling
function UIUtils.applyGlassEdge(parent: GuiObject): UIStroke
    local stroke = Instance.new("UIStroke")
    stroke.Thickness = Theme.glassEdge.thickness
    stroke.Color = Theme.glassEdge.color
    stroke.Transparency = Theme.glassEdge.transparency
    stroke.ApplyStrokeMode = Theme.glassEdge.applyStrokeMode
    stroke.LineJoinMode = Theme.glassEdge.lineJoinMode
    stroke.Parent = parent
    -- Bind to theme so glass edge updates on theme change
    ThemeRefresher.Bind(stroke, { Stroke = "glassEdge" })
    return stroke
end

-- Get profile with retry logic
function UIUtils.getProfileWithRetry(remotes: any, maxAttempts: number?, delaySec: number?)
    maxAttempts = maxAttempts or 3
    delaySec = delaySec or 1
    
    local lastErr
    for i = 1, maxAttempts do
        -- Guard-only approach
        if PlayerProfileGuard and type(PlayerProfileGuard.get) == "function" then
            local p, err = PlayerProfileGuard.get()
            if p then
                return p
            end
            lastErr = err
        else
            lastErr = "PlayerProfileGuard unavailable"
        end
        
        if i < maxAttempts then
            task.wait(delaySec or 1)
        end
    end
    
    return nil, lastErr
end

-- Validate scene interface
function UIUtils.validateScene(scene: any)
    assert(type(scene) == "table", "Scene must be a table")
    assert(type(scene.name) == "string", "Scene must have a name property")
    assert(type(scene.init) == "function", "Scene must have init method")
    assert(type(scene.show) == "function", "Scene must have show method")
    assert(type(scene.hide) == "function", "Scene must have hide method")
end

-- Create a button/chip with separated background and content layers
-- Background scales on interaction, content stays stable
function UIUtils.createLayeredButton(props: {
    parent: GuiObject,
    size: UDim2?,
    backgroundProps: {
        color: Color3?,
        transparency: number?,
        cornerRadius: UDim?,
        applyGlassEdge: boolean?,
        gradient: boolean?,
        noise: boolean?,
    }?
}): (Frame, Frame, Frame)
    local container = Instance.new("Frame")
    container.Name = "LayeredContainer"
    container.Size = props.size or UDim2.fromScale(1, 1)
    container.AnchorPoint = Vector2.new(0.5, 0.5)
    container.Position = UDim2.fromScale(0.5, 0.5)
    container.BackgroundTransparency = 1
    container.Selectable = false
    container.Parent = props.parent

    -- Background (this is what scales)
    local background = Instance.new("Frame")
    background.Name = "Background"
    background.Size = UDim2.fromScale(1, 1)
    background.AnchorPoint = Vector2.new(0.5, 0.5)
    background.Position = UDim2.fromScale(0.5, 0.5)
    background.BackgroundColor3 = (props.backgroundProps and props.backgroundProps.color) or Theme.colors.Surface
    background.BackgroundTransparency = (props.backgroundProps and props.backgroundProps.transparency) ~= nil
        and props.backgroundProps.transparency
        or Theme.effects.frosted.backgroundTransparency
    background.ClipsDescendants = true
    background.Parent = container

    if props.backgroundProps and props.backgroundProps.cornerRadius then
        local corner = Instance.new("UICorner")
        corner.CornerRadius = props.backgroundProps.cornerRadius
        corner.Parent = background
    end
    
    if props.backgroundProps and props.backgroundProps.applyGlassEdge then
        UIUtils.applyGlassEdge(background)
    end
    
    local gradient: UIGradient? = nil
    if props.backgroundProps and props.backgroundProps.gradient then
        gradient = Instance.new("UIGradient")
        gradient.Rotation = 90
        gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(1, 1, 1))
        local gt = Theme.effects.frosted.gradientTopT
        local gb = Theme.effects.frosted.gradientBottomT
        gradient.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, gt),
            NumberSequenceKeypoint.new(1, gb),
        })
        gradient.Parent = background
    end
    
    -- Noise texture for frosted glass effect
    local noise: ImageLabel? = nil
    if props.backgroundProps and props.backgroundProps.noise then
        noise = Instance.new("ImageLabel")
        noise.BackgroundTransparency = 1
        noise.Image = "rbxasset://textures/ui/GuiImagePlaceholder.png"
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
        noise.ZIndex = 1
        noise.Parent = background
    end

    -- Track frosted elements so we can refresh them on theme flips
    UIUtils.registerFrosted(background, gradient, noise)

    -- Content (never scaled)
    local content = Instance.new("Frame")
    content.Name = "Content"
    content.Size = UDim2.fromScale(1, 1)
    content.AnchorPoint = Vector2.new(0.5, 0.5)
    content.Position = UDim2.fromScale(0.5, 0.5)
    content.BackgroundTransparency = 1
    content.Selectable = false
    content.ZIndex = 2
    content.Parent = container

    -- scale lives on Background only
    local scale = Instance.new("UIScale")
    scale.Scale = 1
    scale.Parent = background

    return container, background, content
end

-- Press (squish) animation that scales the Background only
function UIUtils.applyPressAnimation(container: Frame, intensity: number?)
    -- Guard against double-binding
    if container:GetAttribute("PressBound") then return end
    container:SetAttribute("PressBound", true)
    
    local background = container:FindFirstChild("Background")
    if not background then return end

    local scale = background:FindFirstChildOfClass("UIScale")
    if not scale then
        scale = Instance.new("UIScale")
        scale.Scale = 1
        scale.Parent = background
    end

    local squish = intensity or 0.92
    local pressed = false
    
    -- Helper to reset scale
    local function resetScale()
        if pressed then
            pressed = false
            TweenService:Create(scale, Theme.animations.Bounce, { Scale = 1 }):Play()
        end
    end

    container.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            pressed = true
            TweenService:Create(scale, Theme.animations.Quick, { Scale = squish }):Play()
        end
    end)

    container.InputEnded:Connect(function(input)
        if (input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch) and pressed then
            resetScale()
        end
    end)
    
    -- Reset if mouse/touch leaves the element
    container.MouseLeave:Connect(function()
        resetScale()
    end)
    
    -- Also reset on global input end (in case pointer is released outside)
    local UserInputService = game:GetService("UserInputService")
    UserInputService.InputEnded:Connect(function(input)
        if (input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch) and pressed then
            resetScale()
        end
    end)
end

-- Pulse (affects Background only)
function UIUtils.pulseLayered(container: Frame, scaleUp: number?)
    local background = container:FindFirstChild("Background")
    if not background then
        UIUtils.pulse(container, scaleUp) -- fallback
        return
    end
    local scale = background:FindFirstChildOfClass("UIScale")
    if not scale then
        scale = Instance.new("UIScale")
        scale.Scale = 1
        scale.Parent = background
    end

    local up = TweenService:Create(scale, Theme.animations.Quick, { Scale = scaleUp or 1.06 })
    local down = TweenService:Create(scale, Theme.animations.Smooth, { Scale = 1 })

    up:Play()
    up.Completed:Connect(function() down:Play() end)
end

-- Convert programmer identifiers to human-readable strings
function UIUtils.humanize(s: string): string
    local str = tostring(s or "")
    -- Replace underscores and hyphens with spaces
    str = str:gsub("_", " ")
    str = str:gsub("%-", " ")
    -- Collapse whitespace and trim
    str = str:gsub("%s+", " ")
    str = str:gsub("^%s+", "")
    str = str:gsub("%s+$", "")
    return str
end

-- Optional TitleCase utility (not applied automatically)
function UIUtils.toTitleCase(s: string): string
    local str = UIUtils.humanize(s)
    str = string.gsub(str, "(%a)([%w_]*)", function(first, rest)
        return string.upper(first) .. string.lower(rest)
    end)
    return str
end

return UIUtils
