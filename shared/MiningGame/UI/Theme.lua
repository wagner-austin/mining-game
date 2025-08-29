--!strict
-- Theme.lua
-- Centralized theme configuration for consistent UI styling

local Theme = {}

-- Helper function to convert hex to Color3
local function hexToColor3(hex: string): Color3
    hex = hex:gsub("#", "")
    local r = tonumber(hex:sub(1, 2), 16) or 0
    local g = tonumber(hex:sub(3, 4), 16) or 0
    local b = tonumber(hex:sub(5, 6), 16) or 0
    return Color3.fromRGB(r, g, b)
end

-- Main color palette
Theme.colors = {
    Primary = hexToColor3("#6C63FF"),    -- Vibrant Purple - Main actions, buttons
    Secondary = hexToColor3("#FF6B9D"),  -- Bubblegum Pink - Highlights, special items
    Accent = hexToColor3("#FFD93D"),     -- Golden Yellow - Rewards, achievements
    Success = hexToColor3("#6BCF7F"),    -- Mint Green - Positive feedback, purchases
    Error = hexToColor3("#FF6B6B"),      -- Soft Red - Errors, warnings
    Background = hexToColor3("#1A1B2E"), -- Deep Navy - Main background
    Surface = hexToColor3("#0F2C4F"),    -- Card Blue - UI panels
    Text = hexToColor3("#FFFFFF"),       -- White - Primary text
    TextDim = hexToColor3("#B0B0B0"),    -- Gray - Secondary text
}

-- Rarity colors (consistent everywhere)
Theme.rarityColors = {
    Common = hexToColor3("#808080"),     -- Gray
    Uncommon = hexToColor3("#6BCF7F"),   -- Green
    Rare = hexToColor3("#4A90E2"),       -- Blue
    Epic = hexToColor3("#6C63FF"),       -- Purple
    Legendary = hexToColor3("#FFA500"),  -- Orange
    Mythic = hexToColor3("#FF6B6B"),     -- Red (will add rainbow animation)
}

-- UI size constants for mobile
Theme.sizes = {
    MinButtonHeight = 44,  -- Minimum touch target height
    TopBarHeight = 60,     -- Top bar container height
    BottomNavHeight = 56,  -- Bottom navigation height
    CornerRadius = 8,      -- Standard corner radius
    LargeCornerRadius = 12, -- Large panels
    TopMargin = 20,        -- Standard top margin for UI elements
}

-- Currency chip configuration
Theme.currencyChip = {
    width = 100,
    height = 36,
    iconSize = 28,
    iconPadding = 6,
    valuePadding = 38,  -- Space between left edge and value text
    gap = 8  -- Space between chips
}

-- Home button configuration
Theme.homeButton = {
    width = 100,  -- Match chip width exactly
    height = 36,  -- Match chip height exactly
    iconSize = 28,  -- Match chip icon size
    textWidth = 40,
    spacing = 4,  -- Gap between icon and text
    fontSize = {Min = 16, Max = 24}  -- Match Medium text size
}

-- Icon configuration
Theme.icons = {
    currency = {
        coins = "💰",  -- Money bag (more reliable)
        gems = "💎",
    },
    home = "🌀",  -- Spiral icon for teleport
    settings = "⚙",  -- Gear icon for settings
}

-- Settings button configuration (matching chip sizes)
Theme.settingsButton = {
    width = 36,
    height = 36,  -- Same height as currency chips
    iconSize = {Min = 24, Max = 32},
}

-- Base panel configuration
Theme.basePanel = {
    defaultSize = UDim2.new(0.8, 0, 0.9, 0),
    headerHeight = 60,
    contentPadding = 20,
    dividerThickness = 2,
}

-- Panel responsive sizing
Theme.panels = {
    margins = {
        phone = 0.12,    -- 12% margin top/bottom on phones
        tablet = 0.10,   -- 10% margin on tablets
        desktop = 0.10   -- 10% margin on desktop
    },
    widths = {
        phone = 0.90,    -- 90% width on phones
        tablet = 0.85,   -- 85% width on tablets
        desktop = 0.75   -- 75% width on desktop
    }
}

-- Close button configuration
Theme.closeButton = {
    size = {
        phone = 56,
        tablet = 56,
        desktop = 56
    },
    iconSize = {Min = 20, Max = 36},
    icon = "✖",  -- Clean X emoji
}

-- Font configurations
Theme.fonts = {
    Primary = Enum.Font.SourceSansBold,
    Secondary = Enum.Font.SourceSans,
    Display = Enum.Font.SourceSansSemibold,
}

-- Text size constraints for mobile readability
Theme.textSizes = {
    Small = {Min = 12, Max = 16},
    Medium = {Min = 16, Max = 24},  -- Increased for better visibility
    Large = {Min = 18, Max = 28},
    Display = {Min = 20, Max = 32},
}

-- Animation presets
Theme.animations = {
    Quick = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
    Standard = TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
    Smooth = TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.InOut),
    Bounce = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
}

-- Responsive breakpoints
Theme.breakpoints = {
    small = 520,
    medium = 640,
    large = 768
}

-- Z-index tiers for proper layering
Theme.z = {
    Base = 1,
    HUD = 10,
    Overlay = 20,
    Notification = 30,
    Modal = 40
}

-- Glass edge style (for all UI borders)
Theme.glassEdge = {
    thickness = 2,
    color = Color3.new(1, 1, 1),  -- White edge for glass effect
    transparency = 0.7,  -- Semi-transparent but more visible than background
    lineJoinMode = Enum.LineJoinMode.Round,
    applyStrokeMode = Enum.ApplyStrokeMode.Border
}

-- Toast presets (standardized, frosted, subtle)
Theme.toast = {
    anchor = "topRight",     -- "topRight" | "topCenter"
    maxWidth = 300,
    gap = 8,
    duration = 3.0,          -- seconds
    padding = 10,
    icon = { info = "🔔", success = "✅", error = "⚠️" },
    tint = {
        info    = Theme.colors.Primary,
        success = Theme.colors.Success,
        error   = Theme.colors.Error,
    },
}

-- Helper function to determine scale based on screen size
function Theme.scaleForMinDim(minDim: number): number
    if minDim < Theme.breakpoints.small then return 0.75 end
    if minDim < Theme.breakpoints.medium then return 0.82 end
    if minDim < Theme.breakpoints.large then return 0.9 end
    return 1
end

return Theme