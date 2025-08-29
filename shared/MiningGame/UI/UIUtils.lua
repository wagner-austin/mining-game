--!strict
-- UIUtils.lua
-- Shared utilities for UI components to avoid duplication

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UI = MiningGame:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))

local UIUtils = {}

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
    return stroke
end

-- Get profile with retry logic
function UIUtils.getProfileWithRetry(remotes: any, maxAttempts: number?, delaySec: number?)
    maxAttempts = maxAttempts or 3
    delaySec = delaySec or 1
    
    local lastErr
    for i = 1, maxAttempts do
        local success, result = pcall(function()
            return remotes.RF.GetProfile:InvokeServer()
        end)
        
        if success and result then
            return result
        end
        
        if not success then lastErr = result end
        
        if i < maxAttempts then
            task.wait(delaySec)
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
    container.Parent = props.parent

    -- Background (this is what scales)
    local background = Instance.new("Frame")
    background.Name = "Background"
    background.Size = UDim2.fromScale(1, 1)
    background.AnchorPoint = Vector2.new(0.5, 0.5)
    background.Position = UDim2.fromScale(0.5, 0.5)
    background.BackgroundColor3 = (props.backgroundProps and props.backgroundProps.color) or Theme.colors.Surface
    background.BackgroundTransparency = (props.backgroundProps and props.backgroundProps.transparency) or 0.25
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
    
    if props.backgroundProps and props.backgroundProps.gradient then
        local gradient = Instance.new("UIGradient")
        gradient.Rotation = 90
        gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(1, 1, 1))
        gradient.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.85),
            NumberSequenceKeypoint.new(1, 1),
        })
        gradient.Parent = background
    end
    
    -- Noise texture for frosted glass effect
    if props.backgroundProps and props.backgroundProps.noise then
        local noise = Instance.new("ImageLabel")
        noise.BackgroundTransparency = 1
        noise.Image = "rbxasset://textures/ui/GuiImagePlaceholder.png"
        noise.ImageColor3 = Color3.new(1, 1, 1)
        noise.ImageTransparency = 0.92
        noise.ScaleType = Enum.ScaleType.Tile
        noise.TileSize = UDim2.fromOffset(64, 64)
        noise.Size = UDim2.fromScale(1, 1)
        noise.ZIndex = 1
        noise.Parent = background
    end

    -- Content (never scaled)
    local content = Instance.new("Frame")
    content.Name = "Content"
    content.Size = UDim2.fromScale(1, 1)
    content.AnchorPoint = Vector2.new(0.5, 0.5)
    content.Position = UDim2.fromScale(0.5, 0.5)
    content.BackgroundTransparency = 1
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
            TweenService:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Quad), { Scale = squish }):Play()
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

return UIUtils