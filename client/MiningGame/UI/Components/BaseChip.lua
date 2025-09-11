--!strict
-- BaseChip.lua
-- Reusable base chip component that all chips should extend from
-- Ensures consistent behavior, sizing, and animations across all chip types

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage:WaitForChild("MiningGame"):WaitForChild("UI"):WaitForChild("Theme"))
local UIx = require(ReplicatedStorage:WaitForChild("MiningGame"):WaitForChild("UI"):WaitForChild("UIConstants"))
local UIUtils = require(ReplicatedStorage:WaitForChild("MiningGame"):WaitForChild("UI"):WaitForChild("UIUtils"))
local ThemeRefresher = require(ReplicatedStorage:WaitForChild("MiningGame"):WaitForChild("UI"):WaitForChild("ThemeRefresher"))

local BaseChip = {}
BaseChip.__index = BaseChip

export type ChipProps = {
    parent: GuiObject,
    size: UDim2?,
    position: UDim2?,
    
    -- Content configuration
    icon: string?,
    iconSize: number?,
    text: string?,
    value: (string | number)?,
    
    -- Style configuration
    backgroundColor: Color3?,
    backgroundTransparency: number?,
    textColor: Color3?,
    
    -- Behavior
    onClick: (() -> ())?,
    onHover: ((hovering: boolean) -> ())?,
    pulseOnUpdate: boolean?,
    squishIntensity: number?,
}

function BaseChip.new(props: ChipProps)
    local self = setmetatable({}, BaseChip)
    
    local colors = Theme.colors
    local chipConfig = Theme.currencyChip -- Use as default sizing
    
    -- Create layered container for proper animation
    local container, background, content = UIUtils.createLayeredButton({
        parent = props.parent,
        size = props.size or UDim2.new(0, chipConfig.width, 0, chipConfig.height),
        backgroundProps = {
            color = props.backgroundColor or colors.Background,
            transparency = (props.backgroundTransparency ~= nil) and props.backgroundTransparency or Theme.effects.frosted.backgroundTransparency,
            cornerRadius = UDim.new(0, Theme.sizes.CornerRadius),
            applyGlassEdge = true,
            gradient = true,
            noise = true,
        }
    })
    
    -- Bind background to theme refresher for automatic updates (only if not custom)
    if not props.backgroundColor then
        ThemeRefresher.Bind(background, {
            BackgroundColor3 = "Surface"
        })
    end

    -- Bind glass edge stroke to theme refresher
    local stroke = background:FindFirstChildOfClass("UIStroke")
    if stroke then
        ThemeRefresher.Bind(stroke, {
            Stroke = "glassEdge"
        })
    end

    -- Make container block click-through
    container.Active = true
    
    -- Apply position if provided
    if props.position then
        container.Position = props.position
    end
    
    -- Create content layout
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.Padding = UDim.new(0, UIx.Spacing.CHIP_INNER)
    layout.Parent = content
    
    -- Icon (optional)
    local iconLabel
    if props.icon then
        iconLabel = Instance.new("TextLabel")
        iconLabel.Name = "Icon"
        iconLabel.BackgroundTransparency = 1
        iconLabel.Size = UDim2.new(0, props.iconSize or chipConfig.iconSize, 0, props.iconSize or chipConfig.iconSize)
        iconLabel.Text = props.icon
        iconLabel.TextColor3 = props.textColor or colors.Text
        iconLabel.TextScaled = true
        iconLabel.Font = Theme.fonts.Primary
        iconLabel.LayoutOrder = 1
        iconLabel.Parent = content
        
        -- Bind to theme refresher for automatic updates (only if not custom)
        if not props.textColor then
            ThemeRefresher.Bind(iconLabel, {
                TextColor3 = "Text"
            })
        end
        
        local iconConstraint = Instance.new("UITextSizeConstraint")
        iconConstraint.MinTextSize = Theme.textSizes.Medium.Min
        iconConstraint.MaxTextSize = Theme.textSizes.Medium.Max
        iconConstraint.Parent = iconLabel
    end
    
    -- Text/Value label (optional)
    local textLabel
    if props.text or props.value then
        textLabel = Instance.new("TextLabel")
        textLabel.Name = "Text"
        textLabel.BackgroundTransparency = 1
        textLabel.AutomaticSize = Enum.AutomaticSize.X
        textLabel.Size = UDim2.new(0, 0, 0, chipConfig.iconSize)
        
        if props.value then
            textLabel.Text = typeof(props.value) == "number" and UIUtils.formatNumber(props.value) or tostring(props.value)
        else
            textLabel.Text = props.text or ""
        end
        
        textLabel.TextColor3 = props.textColor or colors.Text
        textLabel.TextScaled = true
        textLabel.Font = Theme.fonts.Primary
        textLabel.TextXAlignment = Enum.TextXAlignment.Center
        textLabel.LayoutOrder = 2
        textLabel.Parent = content
        
        -- Bind to theme refresher for automatic updates (only if not custom)
        if not props.textColor then
            ThemeRefresher.Bind(textLabel, {
                TextColor3 = "Text"
            })
        end
        
        local textConstraint = Instance.new("UITextSizeConstraint")
        textConstraint.MinTextSize = Theme.textSizes.Medium.Min
        textConstraint.MaxTextSize = Theme.textSizes.Medium.Max
        textConstraint.Parent = textLabel
        
        -- Add padding for text
        local padding = Instance.new("UIPadding")
        padding.PaddingLeft = UDim.new(0, UIx.Spacing.TINY)
        padding.PaddingRight = UDim.new(0, UIx.Spacing.SM)
        padding.Parent = textLabel
    end
    
    -- Store references
    self.container = container
    self.background = background
    self.content = content
    self.iconLabel = iconLabel
    self.textLabel = textLabel
    self.props = props
    self._lastValue = props.value
    
    -- Apply interactions
    if props.onClick or props.squishIntensity then
        UIUtils.applyPressAnimation(container, props.squishIntensity or 0.92)
    end
    
    if props.onClick then
        container.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or
               input.UserInputType == Enum.UserInputType.Touch then
                local SoundManager = require(ReplicatedStorage.MiningGame:WaitForChild("SoundManager"))
                SoundManager.PlayUI("buttonclick")
                props.onClick()
            end
        end)
    end
    
    if props.onHover then
        container.MouseEnter:Connect(function()
            props.onHover(true)
        end)
        
        container.MouseLeave:Connect(function()
            props.onHover(false)
        end)
    end
    
    return self
end

-- Update chip text/value
function BaseChip:setText(text: string)
    if self.textLabel then
        self.textLabel.Text = text
    end
end

function BaseChip:setValue(value: string | number)
    if self.textLabel then
        local newText = typeof(value) == "number" and UIUtils.formatNumber(value) or tostring(value)
        self.textLabel.Text = newText
        
        -- Pulse on increase (for numeric values)
        if self.props.pulseOnUpdate and typeof(value) == "number" and typeof(self._lastValue) == "number" then
            if value > self._lastValue then
                self:pulse()
            end
        end
        
        self._lastValue = value
    end
end

function BaseChip:setIcon(icon: string)
    if self.iconLabel then
        self.iconLabel.Text = icon
    end
end

-- Animations
function BaseChip:pulse(intensity: number?)
    UIUtils.pulseLayered(self.container, intensity or 1.06)
end

function BaseChip:show()
    self.container.Visible = true
end

function BaseChip:hide()
    self.container.Visible = false
end

-- Styling updates
function BaseChip:setBackgroundColor(color: Color3)
    self.background.BackgroundColor3 = color
end

function BaseChip:setTextColor(color: Color3)
    if self.iconLabel then
        self.iconLabel.TextColor3 = color
    end
    if self.textLabel then
        self.textLabel.TextColor3 = color
    end
end

-- Cleanup
function BaseChip:destroy()
    if self.container then
        self.container:Destroy()
    end
end

return BaseChip
