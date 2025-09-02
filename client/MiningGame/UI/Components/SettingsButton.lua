--!strict
-- SettingsButton.lua
-- Minimal gear icon button with no background, just white icon

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage:WaitForChild("MiningGame"):WaitForChild("UI"):WaitForChild("Theme"))
local ThemeRefresher = require(ReplicatedStorage:WaitForChild("MiningGame"):WaitForChild("UI"):WaitForChild("ThemeRefresher"))

local SettingsButton = {}
SettingsButton.__index = SettingsButton

type Props = {
    parent: GuiObject,
    position: UDim2?,
    onClick: (() -> ())?
}

function SettingsButton.new(props: Props)
    local self = setmetatable({}, SettingsButton)
    
    local colors = Theme.colors
    local config = Theme.settingsButton
    
    -- Outer container that centers in parent
    local container = Instance.new("Frame")
    container.Name = "SettingsButton"
    container.Size = UDim2.new(0, config.width, 0, config.height)
    container.AnchorPoint = Vector2.new(0.5, 0.5)
    container.Position = UDim2.fromScale(0.5, 0.5)
    container.BackgroundTransparency = 1
    container.Parent = props.parent
    
    -- Inner frame for rotation (helps center the icon)
    local rotator = Instance.new("Frame")
    rotator.Name = "Rotator"
    rotator.Size = UDim2.fromScale(1, 1)
    rotator.BackgroundTransparency = 1
    rotator.AnchorPoint = Vector2.new(0.5, 0.5)
    rotator.Position = UDim2.new(0.5, 0, 0.5, -1)  -- Move rotation axis up 1 pixel
    rotator.Parent = container
    
    -- Button with the icon
    local button = Instance.new("TextButton")
    button.Name = "Icon"
    button.Size = UDim2.fromScale(1, 1)
    button.AnchorPoint = Vector2.new(0.5, 0.5)
    button.Position = UDim2.fromScale(0.5, 0.5)  -- Keep it perfectly centered
    button.BackgroundTransparency = 1
    button.Text = Theme.icons.settings -- Use Theme icon
    button.TextColor3 = colors.Text -- White
    button.TextScaled = true
    button.Font = Theme.fonts.Primary
    button.TextXAlignment = Enum.TextXAlignment.Center  -- Force center X
    button.TextYAlignment = Enum.TextYAlignment.Center  -- Force center Y
    button.AutoButtonColor = false
    button.Parent = rotator
    
    -- Bind to theme refresher for automatic color updates
    ThemeRefresher.Bind(button, {
        TextColor3 = "Text"
    })
    
    -- Text size constraint from Theme
    local textConstraint = Instance.new("UITextSizeConstraint")
    textConstraint.MinTextSize = config.iconSize.Min
    textConstraint.MaxTextSize = config.iconSize.Max
    textConstraint.Parent = button
    
    -- Store references
    self.container = container
    self.rotator = rotator
    self.button = button
    self.onClick = props.onClick
    self.spinConnection = nil
    self.targetSpeed = 0
    self.currentSpeed = 0
    self._clickCooldown = false
    
    -- Setup interactions
    self:setupInteractions()
    
    return self
end

function SettingsButton:setupInteractions()
    local button = self.button
    local rotator = self.rotator
    local RunService = game:GetService("RunService")
    
    -- Start continuous spin update loop
    local function startSpinLoop()
        if self.spinConnection then return end
        
        self.spinConnection = RunService.Heartbeat:Connect(function(dt)
            -- Smooth interpolation to target speed
            self.currentSpeed = self.currentSpeed + (self.targetSpeed - self.currentSpeed) * 0.1
            
            -- Apply rotation
            if math.abs(self.currentSpeed) > 0.01 then
                rotator.Rotation = rotator.Rotation + (self.currentSpeed * dt * 60) -- 60fps normalized
            elseif self.targetSpeed == 0 then
                -- Stop the loop when speed is near zero and not hovering
                if self.spinConnection then
                    self.spinConnection:Disconnect()
                    self.spinConnection = nil
                end
            end
        end)
    end
    
    -- Hover: start continuous spin
    button.MouseEnter:Connect(function()
        self.targetSpeed = 1.5 -- Slower: 90 degrees/second at 60fps
        startSpinLoop()
        
        -- Slight translucency for feedback
        TweenService:Create(button, Theme.animations.Quick, { TextTransparency = 0.1 }):Play()
    end)
    
    button.MouseLeave:Connect(function()
        self.targetSpeed = 0 -- Will falloff smoothly
        TweenService:Create(button, Theme.animations.Quick, { TextTransparency = 0 }):Play()
    end)
    
    -- Click: play sound and execute callback
    button.Activated:Connect(function()
        -- Simple click cooldown to prevent spamming
        if self._clickCooldown then return end
        self._clickCooldown = true
        task.delay(0.25, function() 
            self._clickCooldown = false 
        end)
        
        local SoundManager = require(ReplicatedStorage.MiningGame:WaitForChild("SoundManager"))
        SoundManager.PlayUI("buttonclick")
        if self.onClick then
            self.onClick()
        end
    end)
end

function SettingsButton:pulse()
    -- Quick pulse animation on the container
    local scale = Instance.new("UIScale")
    scale.Parent = self.container
    
    local tween = TweenService:Create(scale, Theme.animations.Quick, {Scale = 1.2})
    local tweenBack = TweenService:Create(scale, Theme.animations.Smooth, {Scale = 1})
    
    tween:Play()
    tween.Completed:Connect(function()
        tweenBack:Play()
        tweenBack.Completed:Connect(function()
            scale:Destroy()
        end)
    end)
end

function SettingsButton:destroy()
    if self.spinConnection then
        self.spinConnection:Disconnect()
        self.spinConnection = nil
    end
    if self.container then
        self.container:Destroy()
    end
end

return SettingsButton