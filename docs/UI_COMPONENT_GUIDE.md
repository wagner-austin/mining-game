# UI Component Creation Guide

## Overview

This guide provides step-by-step instructions for creating new UI components in the Mining Game. Components follow a consistent pattern for maintainability and reusability.

## Component Types

### 1. Base Components
Reusable UI elements (buttons, chips, dropdowns)

### 2. Panels
Full-screen or modal interfaces (settings, inventory, shop)

### 3. Tabs
Content sections within panels

### 4. HUD Elements
Always-visible gameplay UI (currency, stats, minimap)

## Step-by-Step Component Creation

### Step 1: Plan Your Component

Before coding, define:
- **Purpose**: What does this component do?
- **Parent**: Where will it be displayed?
- **State**: What data does it manage?
- **Events**: What interactions does it handle?
- **Dependencies**: What other components does it need?

### Step 2: Create the Component File

Create your component in the appropriate directory:
```
client/MiningGame/UI/
├── Components/       # Reusable components
├── Panels/          # Full panels
└── HUD/            # HUD elements
```

### Step 3: Basic Component Structure

```lua
--!strict
-- MyComponent.lua
-- Description of what this component does

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Dependencies
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Theme = require(script.Parent.Parent:WaitForChild("Theme"))
local SoundManager = require(MiningGame:WaitForChild("SoundManager"))

-- Component definition
local MyComponent = {}
MyComponent.__index = MyComponent

-- Type definition (optional but recommended)
export type MyComponentConfig = {
    parent: Instance,
    position: UDim2?,
    size: UDim2?,
    onAction: ((any) -> ())?
}

function MyComponent.new(config: MyComponentConfig)
    local self = setmetatable({}, MyComponent)
    
    -- Store config
    self.parent = config.parent
    self.connections = {}
    
    -- Create UI
    self:createUI(config)
    
    -- Setup interactions
    self:setupInteractions()
    
    return self
end

function MyComponent:createUI(config)
    -- Create main container
    self.frame = Instance.new("Frame")
    self.frame.Size = config.size or UDim2.new(0, 200, 0, 50)
    self.frame.Position = config.position or UDim2.new(0, 0, 0, 0)
    self.frame.BackgroundColor3 = Theme.colors.Surface
    self.frame.Parent = self.parent
    
    -- Add corner rounding
    local corner = Instance.new("UICorner")
    corner.CornerRadius = Theme.corners.Medium
    corner.Parent = self.frame
    
    -- Add other UI elements...
end

function MyComponent:setupInteractions()
    -- Connect events
    local connection = self.frame.MouseButton1Click:Connect(function()
        self:onClick()
    end)
    table.insert(self.connections, connection)
end

function MyComponent:onClick()
    -- Play sound
    SoundManager.PlayUI("click")
    
    -- Handle click
    if self.onAction then
        self.onAction()
    end
end

-- Public methods
function MyComponent:setValue(value: any)
    -- Update display
end

function MyComponent:setEnabled(enabled: boolean)
    self.frame.Visible = enabled
end

-- Cleanup
function MyComponent:destroy()
    -- Disconnect events
    for _, connection in ipairs(self.connections) do
        connection:Disconnect()
    end
    
    -- Destroy UI
    if self.frame then
        self.frame:Destroy()
    end
    
    -- Clear references
    self.connections = {}
end

return MyComponent
```

## Creating Specific Component Types

### Creating a Button Component

```lua
-- ActionButton.lua
local BaseButton = {}
BaseButton.__index = BaseButton

function BaseButton.new(config)
    local self = setmetatable({}, BaseButton)
    
    -- Create button
    self.button = Instance.new("TextButton")
    self.button.Size = config.size or UDim2.new(0, 100, 0, 36)
    self.button.Position = config.position
    self.button.Text = config.text or "Button"
    self.button.TextColor3 = Theme.colors.Text
    self.button.BackgroundColor3 = Theme.colors.Primary
    self.button.Font = Theme.fonts.Primary
    self.button.TextSize = 16
    self.button.AutoButtonColor = false
    self.button.Parent = config.parent
    
    -- Hover effect
    self.button.MouseEnter:Connect(function()
        self:setHovered(true)
    end)
    
    self.button.MouseLeave:Connect(function()
        self:setHovered(false)
    end)
    
    -- Click handler
    self.button.Activated:Connect(function()
        SoundManager.PlayUI("click")
        if config.onClick then
            config.onClick()
        end
    end)
    
    return self
end

function BaseButton:setHovered(hovered: boolean)
    local targetColor = hovered 
        and Theme.colors.Primary:Lerp(Color3.new(1,1,1), 0.1)
        or Theme.colors.Primary
    
    game:GetService("TweenService"):Create(
        self.button,
        TweenInfo.new(0.1),
        {BackgroundColor3 = targetColor}
    ):Play()
end

return BaseButton
```

### Creating a Panel Component

```lua
-- ShopPanel.lua
local BasePanel = require(script.Parent.Parent.Components.BasePanel)

local ShopPanel = {}
ShopPanel.__index = ShopPanel
setmetatable(ShopPanel, BasePanel)

function ShopPanel.new(screenGui)
    local self = BasePanel.new(screenGui)
    setmetatable(self, ShopPanel)
    
    -- Customize panel
    self.frame.Size = UDim2.new(0, 600, 0, 500)
    self.titleLabel.Text = "Shop"
    
    -- Add content
    self:createShopContent()
    
    return self
end

function ShopPanel:createShopContent()
    -- Create scroll frame
    local scrollFrame = Instance.new("ScrollingFrame")
    scrollFrame.Size = UDim2.new(1, -20, 1, -60)
    scrollFrame.Position = UDim2.new(0, 10, 0, 50)
    scrollFrame.BackgroundTransparency = 1
    scrollFrame.ScrollBarThickness = 4
    scrollFrame.Parent = self.frame
    
    -- Add items...
end

return ShopPanel
```

### Creating a HUD Element

```lua
-- HealthBar.lua
local HealthBar = {}
HealthBar.__index = HealthBar

function HealthBar.new(config)
    local self = setmetatable({}, HealthBar)
    
    -- Container
    self.container = Instance.new("Frame")
    self.container.Size = UDim2.new(0, 200, 0, 24)
    self.container.Position = config.position
    self.container.BackgroundColor3 = Theme.colors.Surface
    self.container.Parent = config.parent
    
    -- Background bar
    self.bgBar = Instance.new("Frame")
    self.bgBar.Size = UDim2.new(1, -4, 1, -4)
    self.bgBar.Position = UDim2.new(0, 2, 0, 2)
    self.bgBar.BackgroundColor3 = Color3.new(0.2, 0.2, 0.2)
    self.bgBar.Parent = self.container
    
    -- Fill bar
    self.fillBar = Instance.new("Frame")
    self.fillBar.Size = UDim2.new(1, 0, 1, 0)
    self.fillBar.BackgroundColor3 = Theme.colors.Success
    self.fillBar.Parent = self.bgBar
    
    -- Label
    self.label = Instance.new("TextLabel")
    self.label.Size = UDim2.new(1, 0, 1, 0)
    self.label.BackgroundTransparency = 1
    self.label.Text = "100/100"
    self.label.TextColor3 = Theme.colors.Text
    self.label.Font = Theme.fonts.Primary
    self.label.TextSize = 14
    self.label.Parent = self.container
    
    self.maxValue = 100
    self.currentValue = 100
    
    return self
end

function HealthBar:setValue(current: number, max: number?)
    self.currentValue = current
    if max then self.maxValue = max end
    
    local percentage = math.clamp(current / self.maxValue, 0, 1)
    
    -- Animate bar
    game:GetService("TweenService"):Create(
        self.fillBar,
        TweenInfo.new(0.3, Enum.EasingStyle.Quad),
        {Size = UDim2.new(percentage, 0, 1, 0)}
    ):Play()
    
    -- Update text
    self.label.Text = string.format("%d/%d", current, self.maxValue)
    
    -- Change color based on percentage
    if percentage < 0.25 then
        self.fillBar.BackgroundColor3 = Theme.colors.Error
    elseif percentage < 0.5 then
        self.fillBar.BackgroundColor3 = Theme.colors.Secondary
    else
        self.fillBar.BackgroundColor3 = Theme.colors.Success
    end
end

return HealthBar
```

## Integration Patterns

### Adding to MainHUD

```lua
-- In MainHUD.lua
local MyComponent = require(script.Parent.Components.MyComponent)

function MainHUD:initialize()
    -- ... existing code ...
    
    -- Add new component
    self.myComponent = MyComponent.new({
        parent = self.container,
        position = UDim2.new(0, 10, 0, 100),
        onAction = function()
            self:handleMyComponentAction()
        end
    })
end

function MainHUD:handleMyComponentAction()
    -- Handle the action
end
```

### Adding to Settings Panel

```lua
-- In SettingsPanel.lua
local MyTab = require(script.Parent.Components.MyTab)

function SettingsPanel:setupTabs()
    self.tabs = {
        {id = "general", label = "General"},
        {id = "my_new_tab", label = "My Feature"}  -- Add new tab
    }
    
    -- Create tab container
    self.tabContainer = TabContainer.new({
        parent = self.frame,
        tabs = self.tabs,
        onTabChange = function(tabId)
            if tabId == "my_new_tab" then
                self:showMyTab()
            end
        end
    })
end

function SettingsPanel:showMyTab()
    if not self.myTab then
        self.myTab = MyTab.new({
            parent = self.contentFrame
        })
    end
    self.myTab:setEnabled(true)
end
```

## State Management

### Local State

```lua
function MyComponent.new(config)
    local self = setmetatable({}, MyComponent)
    
    -- Local state
    self.isEnabled = true
    self.currentValue = 0
    self.items = {}
    
    return self
end
```

### Shared State via UIManager

```lua
-- Setting global state
UIManager:SetState("shopOpen", true)

-- Reading global state
local isShopOpen = UIManager:GetState("shopOpen")

-- Subscribing to state changes
UIManager:OnStateChange("shopOpen", function(isOpen)
    self:updateVisibility(isOpen)
end)
```

### Server State Sync

```lua
-- Request data from server
local function loadData()
    local success, data = pcall(function()
        return Remotes.RF.GetPlayerData:InvokeServer()
    end)
    
    if success and data then
        self:updateDisplay(data)
    end
end

-- Listen for server updates
Remotes.RE.OnDataUpdate.OnClientEvent:Connect(function(data)
    self:updateDisplay(data)
end)
```

## Animation Patterns

### Fade In/Out

```lua
function Component:fadeIn()
    self.frame.Transparency = 1
    self.frame.Visible = true
    
    TweenService:Create(
        self.frame,
        TweenInfo.new(0.3, Enum.EasingStyle.Quad),
        {Transparency = 0}
    ):Play()
end
```

### Slide Animation

```lua
function Component:slideIn()
    local startPos = UDim2.new(1, 0, 0.5, 0)  -- Off-screen right
    local endPos = UDim2.new(0.5, 0, 0.5, 0)  -- Center
    
    self.frame.Position = startPos
    self.frame:TweenPosition(
        endPos,
        Enum.EasingDirection.Out,
        Enum.EasingStyle.Back,
        0.4,
        true
    )
end
```

### Pop Effect

```lua
function Component:pop()
    local originalSize = self.frame.Size
    local popSize = UDim2.new(
        originalSize.X.Scale * 1.1,
        originalSize.X.Offset * 1.1,
        originalSize.Y.Scale * 1.1,
        originalSize.Y.Offset * 1.1
    )
    
    TweenService:Create(
        self.frame,
        TweenInfo.new(0.1, Enum.EasingStyle.Quad),
        {Size = popSize}
    ):Play()
    
    task.wait(0.1)
    
    TweenService:Create(
        self.frame,
        TweenInfo.new(0.1, Enum.EasingStyle.Quad),
        {Size = originalSize}
    ):Play()
end
```

## Common Patterns

### Lazy Initialization

```lua
function Panel:getSettings()
    if not self.settingsFrame then
        self.settingsFrame = self:createSettingsFrame()
    end
    return self.settingsFrame
end
```

### Event Cleanup

```lua
function Component:destroy()
    -- Always clean up connections
    for _, conn in ipairs(self.connections) do
        conn:Disconnect()
    end
    self.connections = {}
    
    -- Destroy UI
    if self.frame then
        self.frame:Destroy()
        self.frame = nil
    end
end
```

### Input Validation

```lua
function Component:setValue(value)
    -- Validate input
    if type(value) ~= "number" then
        warn("Invalid value type:", type(value))
        return
    end
    
    -- Clamp to valid range
    value = math.clamp(value, self.minValue, self.maxValue)
    
    -- Apply value
    self.currentValue = value
    self:updateDisplay()
end
```

## Testing Your Component

### Manual Testing Checklist

- [ ] Component renders correctly
- [ ] All interactions work as expected
- [ ] Sound feedback plays
- [ ] Animations are smooth
- [ ] Component cleans up properly
- [ ] Works at different screen sizes
- [ ] Handles edge cases gracefully

### Debug Helpers

```lua
-- Add debug mode to component
function Component.new(config)
    local self = setmetatable({}, Component)
    
    -- Debug mode
    if config.debug then
        self:enableDebug()
    end
    
    return self
end

function Component:enableDebug()
    -- Add debug border
    local border = Instance.new("UIStroke")
    border.Color = Color3.new(1, 0, 0)
    border.Thickness = 2
    border.Parent = self.frame
    
    -- Log interactions
    self.debug = true
end

function Component:log(...)
    if self.debug then
        print("[" .. self.__index .. "]", ...)
    end
end
```

## Performance Tips

1. **Reuse Components**: Don't destroy and recreate, hide and show instead
2. **Batch Updates**: Update multiple properties at once
3. **Debounce Events**: Prevent rapid repeated calls
4. **Use Object Pooling**: For frequently created elements
5. **Lazy Load**: Only create what's visible

```lua
-- Debouncing example
local lastClick = 0
function Component:onClick()
    local now = Time.mono()
    if now - lastClick < 0.5 then return end
    lastClick = now
    
    -- Handle click
end
```

## Common Pitfalls

1. **Memory Leaks**: Always disconnect events in destroy()
2. **Missing Theme**: Always use Theme colors, never hardcode
3. **No Sound**: Add sound feedback for all interactions
4. **Poor Scaling**: Use relative sizes (Scale) not just Offset
5. **Missing Types**: Add type annotations for better IDE support

## Next Steps

1. Study existing components for patterns
2. Start with simple components
3. Test thoroughly
4. Document your component's API
5. Consider reusability for future features