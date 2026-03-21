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
	Primary = hexToColor3("#6C63FF"), -- Vibrant Purple - Main actions, buttons
	OnPrimary = hexToColor3("#FFFFFF"), -- White - Text on Primary buttons
	Secondary = hexToColor3("#FF6B9D"), -- Bubblegum Pink - Highlights, special items
	Accent = hexToColor3("#FFD93D"), -- Golden Yellow - Rewards, achievements
	Success = hexToColor3("#6BCF7F"), -- Mint Green - Positive feedback, purchases
	Error = hexToColor3("#FF6B6B"), -- Soft Red - Errors, warnings
	Background = hexToColor3("#1A1B2E"), -- Deep Navy - Main background
	Surface = hexToColor3("#0F2C4F"), -- Card Blue - UI panels
	Text = hexToColor3("#FFFFFF"), -- White - Primary text
	TextDim = hexToColor3("#B0B0B0"), -- Gray - Secondary text
	TextSecondary = hexToColor3("#808080"), -- Darker Gray - Used for sliders/tracks
}

-- Rarity colors (consistent everywhere)
Theme.rarityColors = {
	Common = hexToColor3("#808080"), -- Gray
	Uncommon = hexToColor3("#6BCF7F"), -- Green
	Rare = hexToColor3("#4A90E2"), -- Blue
	Epic = hexToColor3("#6C63FF"), -- Purple
	Legendary = hexToColor3("#FFA500"), -- Orange
	Mythic = hexToColor3("#FF6B6B"), -- Red (will add rainbow animation)
}

-- UI size constants for mobile
Theme.sizes = {
	MinButtonHeight = 44, -- Minimum touch target height
	TopBarHeight = 60, -- Top bar container height
	BottomNavHeight = 56, -- Bottom navigation height
	CornerRadius = 8, -- Standard corner radius
	LargeCornerRadius = 12, -- Large panels
	TopMargin = 20, -- Standard top margin for UI elements
}

-- Currency chip configuration
Theme.currencyChip = {
	width = 100,
	height = 36,
	iconSize = 28,
	iconPadding = 6,
	valuePadding = 38, -- Space between left edge and value text
	gap = 8, -- Space between chips
}

-- Home button configuration
Theme.homeButton = {
	width = 100, -- Match chip width exactly
	height = 36, -- Match chip height exactly
	iconSize = 28, -- Match chip icon size
	textWidth = 40,
	spacing = 4, -- Gap between icon and text
	fontSize = { Min = 16, Max = 24 }, -- Match Medium text size
}

-- Icon configuration
Theme.icons = {
	currency = {
		coins = "💰", -- Money bag (more reliable)
		gems = "💎",
	},
	home = "🌀", -- Spiral icon for teleport
	settings = "⚙", -- Gear icon for settings
}

-- Boost/status icons registry (now handled by BoostDefs.lua for single source of truth)
-- Theme.icons.boost can be set to override BoostDefs defaults if needed
Theme.icons.boost = Theme.icons.boost or {}

-- Settings button configuration (matching chip sizes)
Theme.settingsButton = {
	width = 36,
	height = 36, -- Same height as currency chips
	iconSize = { Min = 24, Max = 32 },
}

-- Base panel configuration
Theme.basePanel = {
	defaultSize = UDim2.new(0.8, 0, 0.9, 0),
	headerHeight = 60,
	contentPadding = 20,
	dividerThickness = 2,
}

-- Card/Surface styling (used by DebugTab sections, dropdown menus, etc.)
-- These are smaller UI elements, not the main panels
Theme.card = {
	backgroundTransparency = 0.2, -- 80% visible - fairly solid for readability
	backgroundTransparencyDim = 0.4, -- 60% visible - for disabled/inactive cards
}

-- Button styling (transparency values: 0 = solid, 1 = invisible)
Theme.button = {
	-- Primary buttons (main actions, colored backgrounds)
	primaryTransparency = 0.8, -- Default state: 20% visible
	primaryHoverTransparency = 0.6, -- Hover state: 40% visible (doubles visibility)

	-- Surface buttons (secondary actions, blend with background)
	surfaceTransparency = 0.85, -- Default state: 15% visible (very subtle)
	surfaceHoverTransparency = 0.5, -- Hover state: 50% visible (3x more visible - much more noticeable!)
}

-- Dropdown option styling (mobile app style)
Theme.dropdown = {
	-- Individual option transparencies
	optionTransparency = 0.92, -- Default: 8% visible (very subtle)
	optionHoverTransparency = 0.82, -- Hover: 18% visible (more than 2x visibility)
	selectedTransparency = 0.7, -- Selected: 30% visible (clearly highlighted)

	-- Layout and sizing
	optionHeight = 44, -- Touch-friendly height (iOS standard)
	listMaxHeight = 250, -- Max dropdown height (~5-6 options visible)
	listPadding = 6, -- Internal padding of dropdown list
	optionGap = 0, -- Gap between options (0 = continuous list)
	listOffset = 8, -- Gap between trigger button and dropdown
	listWidthRatio = 1.0, -- Width relative to button (1.0 = same width)

	-- Container styling
	listBackgroundTransparency = 0.1, -- List background: 90% visible (nearly solid)
	shadowTransparency = 0.4, -- Drop shadow: 60% visible
}

-- UI element styling
Theme.ui = {
	dividerTransparency = 0.8, -- Divider lines: 20% visible (subtle separators)
}

-- Text sizes
Theme.buttonSize = 18 -- Default button text size

-- Initialize optional tables for ThemeManager (avoid pre-setting glassEdge to keep strict typing)
Theme.effects = Theme.effects or {}
Theme.tabs = Theme.tabs or {}
Theme.postProcessing = Theme.postProcessing or {}

-- Panel responsive sizing
Theme.panels = {
	margins = {
		phone = 0.12, -- 12% margin top/bottom on phones
		tablet = 0.10, -- 10% margin on tablets
		desktop = 0.10, -- 10% margin on desktop
	},
	widths = {
		phone = 0.90, -- 90% width on phones
		tablet = 0.85, -- 85% width on tablets
		desktop = 0.75, -- 75% width on desktop
	},
}

-- Close button configuration
Theme.closeButton = {
	size = {
		phone = 56,
		tablet = 56,
		desktop = 56,
	},
	iconSize = { Min = 20, Max = 36 },
	icon = "✖", -- Clean X emoji
}

-- Font configuration
Theme.fonts = {
	Primary = Enum.Font.SourceSansBold,
	Secondary = Enum.Font.SourceSans,
	Display = Enum.Font.SourceSansSemibold,
	Monospace = Enum.Font.RobotoMono,
}

-- Text size constraints for mobile readability
Theme.textSizes = {
	Small = { Min = 14, Max = 18 }, -- Increased from 12-16
	Medium = { Min = 18, Max = 26 }, -- Increased from 16-24
	Large = { Min = 20, Max = 30 }, -- Increased from 18-28
	Display = { Min = 22, Max = 34 }, -- Increased from 20-32
}

-- Billboard UI sizing (centralized, tweak here)
Theme.billboard = Theme.billboard
	or {
		-- Title text sizing
		title = { Min = 26, Max = 40 },
		-- Row text sizing (name/value)
		row = { Min = 26, Max = 42 },
		-- Index column sizing
		index = { Min = 22, Max = 34 },
		-- Value column sizing
		value = { Min = 24, Max = 38 },
		-- Row height in pixels (allow text to scale larger)
		rowHeight = 52,
		-- Column widths (in px)
		idxWidth = 28,
		valueWidth = 112,
	}

-- Animation presets
Theme.animations = {
	Quick = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Standard = TweenInfo.new(0.15, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
	Smooth = TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.InOut),
	Bounce = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
}

-- Responsive breakpoints
Theme.breakpoints = {
	small = 520,
	medium = 640,
	large = 768,
}

-- Z-index tiers for proper layering
Theme.z = {
	Base = 1,
	HUD = 10,
	Overlay = 20,
	Notification = 30,
	Modal = 40,
}

-- Modal configuration for scrims and overlays
Theme.modal = {
	scrimT = 0.25,
}

-- Glass edge style (for all UI borders)
Theme.glassEdge = {
	thickness = 2,
	color = Color3.new(1, 1, 1), -- White edge for glass effect
	transparency = 0.7, -- Semi-transparent but more visible than background
	lineJoinMode = Enum.LineJoinMode.Round,
	applyStrokeMode = Enum.ApplyStrokeMode.Border,
}

-- Frosted glass effect presets (used by BasePanel and other glass UI)
-- IMPORTANT: These transparencies STACK/MULTIPLY together!
-- Final visibility = base transparency + gradient overlay
Theme.effects = Theme.effects or {}
Theme.effects.frosted = {
	-- BASE LAYER: Main panel background transparency
	-- 0 = completely solid/opaque, 1 = completely invisible
	-- This is the starting transparency before gradients are applied
	backgroundTransparency = 0.15, -- 85% visible base (before gradient)

	-- GRADIENT OVERLAY: Additional transparency that varies from top to bottom
	-- These values ADD more transparency on top of the base
	-- 0 = no additional transparency, 1 = fully transparent
	gradientTopT = 0.25, -- Top of panel: adds 25% transparency (final ~60% visible)
	gradientBottomT = 0.35, -- Bottom of panel: adds 35% transparency (final ~50% visible)

	-- TEXTURE LAYER: Noise pattern for frosted glass texture effect
	noiseTransparency = 0.94, -- Nearly invisible texture (6% visible) - just adds subtle pattern
	noiseColorKey = "Background", -- Which theme color to tint the noise texture
	noiseLighten = 0.10, -- How much to lighten the tint toward white (0-1)
}

-- Toast presets (standardized, frosted, subtle)
Theme.toast = {
	anchor = "topRight", -- "topRight" | "topCenter"
	maxWidth = 220, -- narrower to reduce horizontal footprint
	gap = 6, -- tighter vertical spacing
	duration = 0.6, -- base duration in seconds (faster)
	minDuration = 0.4, -- minimum duration for short messages
	maxDuration = 1.2, -- maximum duration for long messages
	perChar = 0.006, -- additional seconds per character
	maxVisible = 3, -- maximum toasts visible at once
	padding = 6, -- smaller internal padding
	icon = {
		info = "🔔",
		success = "✅",
		error = "❌",
		warning = "⚠️",
	},
	tint = {
		info = Theme.colors.Primary,
		success = Theme.colors.Success,
		error = Theme.colors.Error,
		warning = Theme.colors.Accent, -- Golden Yellow for warnings
	},
}

-- Tabs configuration (bar + buttons)
Theme.tabs = {
	height = 50,
	spacing = 10,
	button = {
		inactiveTransparency = 0.5,
		hoverTransparency = 0.35,
		activeTransparency = 0.2,
		disabledTransparency = 0.7,
		disabledTextTransparency = 0.5,
	},
}

-- Helper function to determine scale based on screen size
function Theme.scaleForMinDim(minDim: number): number
	if minDim < Theme.breakpoints.small then
		return 0.75
	end
	if minDim < Theme.breakpoints.medium then
		return 0.82
	end
	if minDim < Theme.breakpoints.large then
		return 0.9
	end
	return 1
end

-- Post-processing overrides (populated by theme packs)
Theme.postProcessing = {}

return Theme
