# Mining Game UI System Documentation

## Overview

The Mining Game UI system is a modular, component-based architecture built in Roblox Lua. It provides a flexible framework for creating responsive user interfaces with consistent theming, sound feedback, state management, and comprehensive developer tools.

## Architecture

### Core Components

```
client/MiningGame/
├── UI/
│   ├── ClientUI.client.lua      # Main UI bootstrap and initialization
│   ├── UIManager.lua             # Centralized UI state management
│   ├── MainHUD.lua               # Primary HUD container and layout
│   ├── ThemeBootstrap.client.lua # Early theme initialization 🆕
│   ├── Components/               # Reusable UI components
│   │   ├── BasePanel.lua         # Base class for all panels
│   │   ├── BaseChip.lua          # Base class for HUD chips
│   │   ├── CurrencyChip.lua      # Currency display component
│   │   ├── Dropdown.lua          # Dropdown select component
│   │   ├── HomeButton.lua        # Home/reset button
│   │   ├── SettingsButton.lua    # Settings toggle button
│   │   ├── TabContainer.lua      # Tab navigation component
│   │   ├── TabbedPanel.lua       # Panel with tab support
│   │   ├── AccountTab.lua        # Account settings tab
│   │   ├── MaterialsTab.lua      # Material preferences tab
│   │   ├── ThemeTab.lua          # Theme & sound pack selection 🆕
│   │   ├── MetricsTab.lua        # User metrics dashboard (Studio) 🆕
│   │   └── DebugTab.lua          # Debug controls (Studio) 🆕
│   └── Panels/                   # Full-screen panels
│       └── SettingsPanel.lua     # Main settings panel
└── Data/
    └── AccountDataProvider.lua   # Reactive data management

shared/MiningGame/UI/
├── Theme.lua                     # Global theming and styling
├── ThemeManager.lua              # Hot-swappable theme system 🆕
├── ThemePacks.lua                # Available UI themes 🆕
└── UIUtils.lua                   # Utility functions
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
setmetatable(MyPanel, {__index = BasePanel})

function MyPanel.new(config)
    local self = BasePanel.new(config)
    setmetatable(self, MyPanel)
    
    -- Add custom UI elements
    self:_setupContent()
    
    return self
end
```

**Features:**
- Consistent theming
- Animation support
- Portal rendering (for dropdowns/popovers)
- Event management
- Automatic cleanup

#### BaseChip
Foundation for HUD elements (currency displays, status indicators).

```lua
local BaseChip = require(UI.Components.BaseChip)

local StatusChip = {}
StatusChip.__index = StatusChip
setmetatable(StatusChip, {__index = BaseChip})

function StatusChip.new(config)
    local self = BaseChip.new(config)
    setmetatable(self, StatusChip)
    
    -- Custom chip logic
    return self
end
```

### NEW Components

#### ThemeTab 🆕
User interface for theme customization.

```lua
-- Located at: client/MiningGame/UI/Components/ThemeTab.lua
local ThemeTab = require(UI.Components.ThemeTab)

local themeTab = ThemeTab.new({
    parent = container,
    portalParent = settingsPanel.portal
})
```

**Features:**
- UI theme selection (default, light, highContrast, ocean, forest)
- Sound pack selection (dynamically loaded)
- Real-time preview
- Server persistence
- Hydration system to prevent unnecessary saves

#### MetricsTab 🆕
Real-time metrics dashboard (Studio only).

```lua
-- Located at: client/MiningGame/UI/Components/MetricsTab.lua
local MetricsTab = require(UI.Components.MetricsTab)

local metricsTab = MetricsTab.new({
    parent = container
})
```

**Features:**
- Auto-refresh every 2 seconds
- Categorized metrics display
- Server metrics integration
- Smart value formatting
- Manual refresh option

**Categories:**
- Gameplay (blocks dug, accuracy, streaks)
- Economy (coins, gems, net worth)
- Session (playtime, session count)
- Lifecycle (first played, account age)
- Progression (upgrades, materials)
- Monetization (purchases, revenue)

#### DebugTab 🆕
Developer tools and debug controls (Studio only).

```lua
-- Located at: client/MiningGame/UI/Components/DebugTab.lua
local DebugTab = require(UI.Components.DebugTab)

local debugTab = DebugTab.new({
    parent = container
})
```

**Features:**
- **Cube Controls**: Respawn, reset, teleport
- **Currency Cheats**: Add coins/gems
- **Player Stats**: Reset functionality
- **SimAgents**: Agent count, spawn strategy, terrain cubes
- **Hotkeys**: Quick agent adjustment (=/-, ]/[)
- **Confirmation**: Safety for destructive operations

### Component Properties

All components support these standard properties:

```lua
{
    parent = Instance,           -- Parent GUI object
    position = UDim2?,          -- Optional position
    size = UDim2?,              -- Optional size  
    visible = boolean?,         -- Initial visibility
    zIndex = number?,           -- Layer order
    portalParent = Frame?,      -- For dropdown/popover rendering
}
```

## Theme System

### ThemeManager 🆕
Hot-swappable theme system with table identity preservation.

```lua
-- Located at: shared/MiningGame/UI/ThemeManager.lua
local ThemeManager = require(UI.ThemeManager)

-- Switch theme
ThemeManager.SetTheme("ocean")

-- Listen for changes
ThemeManager.Changed:Connect(function(newTheme)
    -- UI automatically updates via Theme reference
end)
```

**Features:**
- In-place table mutation (preserves references)
- Event-driven updates
- Deep cloning for complex properties
- Performance optimized

### Available Themes

```lua
-- Located at: shared/MiningGame/UI/ThemePacks.lua
{
    default = {       -- Dark theme with blue accents
        colors = {
            Primary = Color3.fromHex("#3B82F6"),
            Background = Color3.fromHex("#111827"),
            Surface = Color3.fromHex("#1F2937"),
            Text = Color3.fromHex("#F9FAFB")
        }
    },
    light = {         -- Light theme with blue accents
        colors = {
            Primary = Color3.fromHex("#2563EB"),
            Background = Color3.fromHex("#FFFFFF"),
            Surface = Color3.fromHex("#F3F4F6"),
            Text = Color3.fromHex("#111827")
        }
    },
    highContrast = {  -- Accessibility theme
        colors = {
            Primary = Color3.fromHex("#FFFF00"),
            Background = Color3.fromHex("#000000"),
            Surface = Color3.fromHex("#1A1A1A"),
            Text = Color3.fromHex("#FFFFFF")
        }
    },
    ocean = {         -- Ocean-inspired theme
        colors = {
            Primary = Color3.fromHex("#06B6D4"),
            Background = Color3.fromHex("#0C4A6E"),
            Surface = Color3.fromHex("#075985"),
            Text = Color3.fromHex("#E0F2FE")
        }
    },
    forest = {        -- Forest-inspired theme
        colors = {
            Primary = Color3.fromHex("#10B981"),
            Background = Color3.fromHex("#14532D"),
            Surface = Color3.fromHex("#166534"),
            Text = Color3.fromHex("#DCFCE7")
        }
    }
}
```

### Theme Bootstrap 🆕
Early initialization system for seamless theme loading.

```lua
-- Located at: client/MiningGame/UI/ThemeBootstrap.client.lua
-- Automatically runs before UI creation
```

**Process:**
1. Loads saved theme settings from server
2. Applies UI theme before MainHUD appears
3. Applies sound pack for consistent audio
4. Handles missing/invalid themes gracefully

## State Management

### UIManager
Central state and scene management.

```lua
local UIManager = require(UI.UIManager)

-- Scene management
UIManager:TransitionToScene("settings")
UIManager:CloseCurrentScene()

-- Panel management
UIManager:RegisterPanel("inventory", inventoryPanel)
UIManager:ShowPanel("inventory")

-- Toast notifications
UIManager:ShowToast("Achievement unlocked!", {
    duration = 3,
    type = "success"
})
```

**Features:**
- Scene transitions with animations
- Panel lifecycle management
- Toast notification system
- Theme refresh propagation
- Watchdog recovery system (F10 key)

### Data Providers

#### AccountDataProvider
Reactive data management for player stats.

```lua
local AccountDataProvider = require(Data.AccountDataProvider)

-- Subscribe to changes
local connection = AccountDataProvider.Subscribe("coins", function(value)
    coinLabel.Text = tostring(value)
end)

-- Get current value
local coins = AccountDataProvider.GetValue("coins")

-- Clean up
connection:Disconnect()
```

**Tracked Values:**
- Currency (coins, gems)
- Stats (playtime, blocks dug, join date)
- Progression (upgrades, materials)
- Computed values (net worth, efficiency)

## Responsive Design

### Mobile Optimization

```lua
-- Theme provides mobile-aware sizing
local buttonHeight = Theme.sizes.MinButtonHeight -- 48px on mobile, 36px on desktop
local touchTarget = Theme.sizes.MinTouchTarget   -- 48px minimum
```

### Breakpoints

```lua
if viewport.X < Theme.breakpoints.mobile then
    -- Mobile layout
elseif viewport.X < Theme.breakpoints.tablet then
    -- Tablet layout
else
    -- Desktop layout
end
```

## Best Practices

### 1. Component Creation
Always extend base classes for consistency:

```lua
local MyComponent = {}
MyComponent.__index = MyComponent
setmetatable(MyComponent, {__index = BasePanel})

function MyComponent.new(config)
    local self = BasePanel.new(config)
    setmetatable(self, MyComponent)
    -- Custom initialization
    return self
end
```

### 2. Theme Usage
Reference Theme for all styling:

```lua
-- Good
label.TextColor3 = Theme.colors.Text
button.Size = UDim2.new(1, 0, 0, Theme.sizes.MinButtonHeight)

-- Bad
label.TextColor3 = Color3.new(1, 1, 1)
button.Size = UDim2.new(1, 0, 0, 36)
```

### 3. Event Management
Store and clean up connections:

```lua
function Component:_setupEvents()
    self._connections = {}
    
    table.insert(self._connections, 
        button.Activated:Connect(function()
            self:_handleClick()
        end)
    )
end

function Component:Destroy()
    for _, conn in ipairs(self._connections) do
        conn:Disconnect()
    end
end
```

### 4. Portal Usage
Use portals for overlays:

```lua
local dropdown = Dropdown.new({
    parent = container,
    portalParent = self.portal, -- Renders above panel
    options = {"Option 1", "Option 2"}
})
```

## Testing

### Studio Testing
1. Use MetricsTab to monitor performance
2. Use DebugTab for rapid iteration
3. Test all themes with ThemeTab
4. Verify mobile sizing with device emulator

### Common Issues

**Issue**: Dropdown appears behind panel
**Solution**: Pass `portalParent` to render in portal layer

**Issue**: Theme changes don't apply
**Solution**: Use Theme reference directly, not cached colors

**Issue**: Memory leaks from events
**Solution**: Store connections and disconnect in Destroy()

## Performance

### Optimization Tips
1. Use `AutomaticSize` sparingly
2. Cache Theme references in component init
3. Batch UI updates in single frame
4. Use object pooling for frequently created elements
5. Minimize deep nesting of GUI objects

### Monitoring
- Use MetricsTab to track UI update frequency
- Monitor memory usage in Developer Console
- Profile with MicroProfiler for frame timing

## Future Enhancements

### Planned Features
- Drag and drop support
- Animation library
- Custom cursor system
- Notification queue
- Keyboard navigation
- Gamepad support

### Extension Points
- Custom theme packs
- Plugin system for tabs
- Widget framework
- Layout presets
- Accessibility features