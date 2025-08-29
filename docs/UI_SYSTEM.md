# Mining Game UI System Documentation

## Overview

The Mining Game UI system is a modular, component-based architecture built in Roblox Lua. It provides a flexible framework for creating responsive user interfaces with consistent theming, sound feedback, and state management.

## Architecture

### Core Components

```
client/MiningGame/
├── UI/
│   ├── ClientUI.client.lua      # Main UI bootstrap and initialization
│   ├── UIManager.lua             # Centralized UI state management
│   ├── MainHUD.lua               # Primary HUD container and layout
│   ├── Components/               # Reusable UI components
│   │   ├── BasePanel.lua         # Base class for all panels
│   │   ├── BaseChip.lua          # Base class for HUD chips
│   │   ├── CurrencyChip.lua      # Currency display component
│   │   ├── Dropdown.lua          # Dropdown select component
│   │   ├── HomeButton.lua        # Home/reset button
│   │   ├── SettingsButton.lua    # Settings toggle button
│   │   ├── TabContainer.lua      # Tab navigation component
│   │   ├── TabbedPanel.lua       # Panel with tab support
│   │   ├── AccountTab.lua        # Account settings tab (with real-time stats)
│   │   └── MaterialsTab.lua      # Material preferences tab
│   └── Panels/                   # Full-screen panels
│       └── SettingsPanel.lua     # Main settings panel
└── Data/
    └── AccountDataProvider.lua   # Reactive data management

shared/MiningGame/UI/
├── Theme.lua                     # Global theming and styling
└── UIUtils.lua                   # Utility functions (formatNumber, etc.)
```

## Component System

### Base Classes

#### BasePanel
The foundation for all modal panels in the game.

```lua
-- Example: Creating a custom panel
local BasePanel = require(UI.Components.BasePanel)

local MyPanel = {}
MyPanel.__index = MyPanel
setmetatable(MyPanel, BasePanel)

function MyPanel.new(screenGui)
    local self = BasePanel.new(screenGui)
    setmetatable(self, MyPanel)
    
    -- Custom initialization
    self.frame.Size = UDim2.new(0, 600, 0, 400)
    
    return self
end
```

**Key Features:**
- Automatic backdrop blur
- Close button with sound feedback
- Animated show/hide transitions
- Event cleanup on destruction

#### BaseChip
Base class for HUD status displays (coins, gems, stats).

```lua
-- Creating a custom chip
local BaseChip = require(UI.Components.BaseChip)

local StatsChip = {}
StatsChip.__index = StatsChip
setmetatable(StatsChip, BaseChip)

function StatsChip.new(parent, config)
    local self = BaseChip.new(parent, {
        size = config.size or UDim2.new(0, 150, 0, 50),
        position = config.position,
        icon = "rbxassetid://123456789",
        text = "0",
        color = Theme.colors.Primary
    })
    setmetatable(self, StatsChip)
    return self
end
```

### Modular Components

#### Dropdown Component
A fully-featured dropdown with portal rendering for proper layering.

```lua
local Dropdown = require(UI.Components.Dropdown)

local dropdown = Dropdown.new({
    parent = container,
    position = UDim2.new(0, 10, 0, 10),
    size = UDim2.new(1, -20, 0, 36),
    placeholder = "Select an option...",
    options = {
        {id = "opt1", label = "Option 1", color = Color3.new(1, 0, 0)},
        {id = "opt2", label = "Option 2"}
    },
    portalParent = screenGui,  -- Renders dropdown above other UI
    onSelect = function(option)
        print("Selected:", option.label)
    end
})

-- Programmatic control
dropdown:select(1)  -- Select first option
local value = dropdown:getValue()  -- Get current selection
dropdown:destroy()  -- Cleanup
```

#### TabContainer
Manages tabbed navigation within panels.

```lua
local TabContainer = require(UI.Components.TabContainer)

local tabs = TabContainer.new({
    parent = panel,
    tabs = {
        {id = "general", label = "General", icon = "⚙"},
        {id = "materials", label = "Materials", icon = "🎨"},
        {id = "account", label = "Account", icon = "👤"}
    },
    onTabChange = function(tabId)
        -- Handle tab switch
    end
})

tabs:selectTab("materials")  -- Switch to tab
tabs:setTabVisible("account", false)  -- Hide tab
```

## MainHUD System

The MainHUD manages the persistent UI elements visible during gameplay.

### Structure

```lua
MainHUD = {
    -- Currency displays
    coinsChip: CurrencyChip,
    gemsChip: CurrencyChip,
    
    -- Navigation
    homeButton: HomeButton,
    settingsButton: SettingsButton,
    
    -- Panels
    settingsPanel: SettingsPanel?,
    
    -- State
    isSettingsOpen: boolean
}
```

### Initialization Flow

1. **ClientUI.client.lua** bootstraps the UI system
2. **AccountDataProvider** is created for reactive data management
3. **UIManager** initializes and manages scene registration
4. **MainHUD** creates the screen GUI and container
5. Currency chips are positioned in top-left
6. Navigation buttons are positioned in top-right
7. Settings panel is created with data provider injection
8. Data providers connect to remote events for real-time updates

### Currency Updates

```lua
-- Using AccountDataProvider for reactive updates
local accountDataProvider = AccountDataProvider.new(Remotes, UIUtils)

-- Subscribe to changes
accountDataProvider:onChanged():Connect(function(key, value, snapshot)
    if snapshot and snapshot.profile then
        local profile = snapshot.profile
        hud:SetCurrencies(profile.coins or 0, profile.gems or 0)
    end
end)

-- Data automatically syncs when server updates profile
```

## Settings Management

### Settings Panel Architecture

The settings panel uses a modular tab system where each tab is a self-contained component.

```lua
SettingsPanel
├── TabContainer (navigation)
├── AccountTab (account statistics)
│   ├── User avatar and info
│   ├── Session time (real-time)
│   ├── Total playtime (lifetime + session)
│   ├── Coins display
│   └── Blocks dug counter
└── MaterialsTab (visual preferences)
    ├── Palette dropdown
    ├── Cube material dropdown
    └── Floor material dropdown
```

### Material Preferences System

Materials settings demonstrate the full settings flow:

1. **User Interaction**: User selects new material in dropdown
2. **Client Update**: Visual preview updates immediately
3. **Server Save**: Preference saved to DataService
4. **Persistence**: Loaded on next session

```lua
-- MaterialsTab.lua
function MaterialsTab:onPaletteSelect(option)
    if self._hydrating then return end  -- Prevent save during load
    
    -- Apply locally
    MaterialManager.SetPalette(option.id)
    
    -- Save to server
    Remotes.RF.SetPalettePreference:InvokeServer(option.id)
end
```

### Settings Hydration

Settings load after player data is ready:

```lua
task.spawn(function()
    -- Wait for server data
    if not player:GetAttribute("DataLoaded") then
        player:GetAttributeChangedSignal("DataLoaded"):Wait()
    end
    
    -- Load preferences
    local prefs = Remotes.RF.GetMaterialPreferences:InvokeServer()
    
    -- Hydrate UI (with guard to prevent re-save)
    self._hydrating = true
    self:setPalette(prefs.palette)
    self:setCubeMaterial(prefs.cubeMaterial)
    self:setFloorMaterial(prefs.floorMaterial)
    self._hydrating = false
end)
```

## Theme System

Global theming is centralized in `Theme.lua`:

```lua
Theme = {
    colors = {
        Background = Color3.fromRGB(30, 30, 35),
        Surface = Color3.fromRGB(40, 40, 50),
        Primary = Color3.fromRGB(88, 101, 242),
        Secondary = Color3.fromRGB(255, 121, 63),
        Text = Color3.fromRGB(230, 230, 230),
        TextDim = Color3.fromRGB(160, 160, 170),
        Success = Color3.fromRGB(87, 242, 135),
        Error = Color3.fromRGB(237, 66, 69)
    },
    fonts = {
        Primary = Enum.Font.GothamBold,
        Secondary = Enum.Font.Gotham,
        Mono = Enum.Font.RobotoMono
    },
    corners = {
        Small = UDim.new(0, 4),
        Medium = UDim.new(0, 8),
        Large = UDim.new(0, 12)
    }
}
```

## Sound Integration

UI components integrate with the SoundManager for feedback:

```lua
-- Button clicks with sound
button.Activated:Connect(function()
    local SoundManager = require(game.ReplicatedStorage.MiningGame.SoundManager)
    SoundManager.PlayUI("buttonclick")
    -- Perform action
end)

-- Panel open/close
SoundManager.PlayUI("whoosh")

-- Currency updates
SoundManager.PlayUI("coin")
```

## Data Provider Pattern

The UI system uses reactive data providers for state management:

### AccountDataProvider

```lua
-- Create provider
local provider = AccountDataProvider.new(Remotes, UIUtils)

-- Get current snapshot
local snapshot = provider:getSnapshot()
-- snapshot = {
--     profile = { coins, gems, playtime, sessionStartTime, ... },
--     cubeStats = { dugCells, ... },
--     lastUpdated = timestamp,
--     isLoading = false
-- }

-- Subscribe to changes
local connection = provider:onChanged():Connect(function(key, value, snapshot)
    -- React to data changes
    if key == "coins" then
        updateCoinDisplay(value)
    end
end)

-- Cleanup
connection:Disconnect()
```

### Benefits
- Single source of truth for account data
- Automatic synchronization with server
- Reactive updates (no polling)
- Type-safe data access
- Efficient change detection

## Best Practices

### 1. Component Lifecycle

Always implement proper cleanup:

```lua
function Component:destroy()
    -- Disconnect events
    for _, connection in ipairs(self.connections) do
        connection:Disconnect()
    end
    
    -- Destroy UI elements
    if self.frame then
        self.frame:Destroy()
    end
    
    -- Clear references
    self.connections = {}
end
```

### 2. State Management

Use UIManager for UI state and data providers for data state:

```lua
-- UI State (panels, visibility)
manager:registerScene(panel)
manager:showScene("MainHUD")
manager:togglePanel("Settings")

-- Data State (profile, stats)
local provider = AccountDataProvider.new(Remotes, UIUtils)
provider:onChanged():Connect(function(key, value, snapshot)
    -- React to data changes
end)

-- Dependency Injection
local settingsPanel = SettingsPanel.new({
    accountDataProvider = provider  -- Pass provider to components
})
```

### 3. Responsive Design

Use relative sizing and automatic layout:

```lua
-- Responsive container
container.Size = UDim2.new(1, -40, 1, -100)  -- Full size with padding

-- Use UIListLayout for automatic spacing
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 10)
layout.FillDirection = Enum.FillDirection.Vertical
layout.Parent = container
```

### 4. Performance

- Create panels lazily (only when first opened)
- Reuse components instead of destroying/recreating
- Use object pooling for frequently created elements
- Batch UI updates when possible

## Adding New Features

### Creating a New Panel

1. Create new file in `UI/Panels/`
2. Extend BasePanel
3. Register with UIManager
4. Add button/trigger in MainHUD

```lua
-- MyPanel.lua
local BasePanel = require(UI.Components.BasePanel)
local MyPanel = {}
MyPanel.__index = MyPanel
setmetatable(MyPanel, BasePanel)

function MyPanel.new(screenGui)
    local self = BasePanel.new(screenGui)
    setmetatable(self, MyPanel)
    
    self.frame.Size = UDim2.new(0, 500, 0, 400)
    self:setupContent()
    
    return self
end

function MyPanel:setupContent()
    -- Add your UI elements
end

return MyPanel
```

### Creating a New Tab

1. Create component in `UI/Components/`
2. Follow the tab interface pattern
3. Add to parent panel's TabContainer

```lua
-- MyTab.lua
local MyTab = {}
MyTab.__index = MyTab

function MyTab.new(config)
    local self = setmetatable({}, MyTab)
    
    self.container = Instance.new("Frame")
    self.container.Size = config.size or UDim2.new(1, 0, 1, 0)
    self.container.BackgroundTransparency = 1
    self.container.Parent = config.parent
    
    self:setupContent()
    return self
end

function MyTab:setEnabled(enabled)
    self.container.Visible = enabled
end

function MyTab:destroy()
    self.container:Destroy()
end

return MyTab
```

## Common Patterns

### Portal Rendering
Used for dropdowns and tooltips to render above other UI:

```lua
local portalParent = screenGui  -- Top-level container

local dropdown = Dropdown.new({
    parent = localContainer,
    portalParent = portalParent,  -- Dropdown renders here
    -- ...
})
```

### Hydration Pattern
Loading saved data without triggering save loops:

```lua
self._hydrating = true  -- Set guard
self:setValue(savedValue)  -- Update UI
self._hydrating = false  -- Clear guard

function self:onValueChange(value)
    if self._hydrating then return end  -- Skip during hydration
    -- Save to server
end
```

### Animation Helpers
Common animation patterns:

```lua
-- Fade in
local tween = TweenService:Create(
    frame,
    TweenInfo.new(0.3, Enum.EasingStyle.Quad),
    {BackgroundTransparency = 0}
)
tween:Play()

-- Slide in from right
frame.Position = UDim2.new(1, 0, 0.5, 0)
frame:TweenPosition(
    UDim2.new(0.5, 0, 0.5, 0),
    Enum.EasingDirection.Out,
    Enum.EasingStyle.Quad,
    0.3
)
```

## Debugging

### UI Hierarchy Inspector
```lua
-- In console
local function printHierarchy(instance, indent)
    indent = indent or ""
    print(indent .. instance.Name .. " (" .. instance.ClassName .. ")")
    for _, child in ipairs(instance:GetChildren()) do
        printHierarchy(child, indent .. "  ")
    end
end

printHierarchy(game.Players.LocalPlayer.PlayerGui)
```

### State Debugging
```lua
-- Add to UIManager
function UIManager:DebugState()
    print("=== UI State ===")
    for key, value in pairs(self.state) do
        print(key, ":", value)
    end
end
```

## Testing Checklist

- [ ] All panels open/close correctly
- [ ] Sound feedback plays on interactions (button clicks)
- [ ] Settings persist across sessions
- [ ] UI scales properly at different resolutions
- [ ] Memory is cleaned up properly (no leaks)
- [ ] Tab navigation works smoothly
- [ ] Dropdowns render above other UI elements
- [ ] Currency updates animate smoothly
- [ ] Theme is consistently applied
- [ ] Error states are handled gracefully
- [ ] Data providers update reactively
- [ ] Session time increments correctly
- [ ] Account stats display accurately
- [ ] Playtime tracking persists
- [ ] Data provider connections are cleaned up