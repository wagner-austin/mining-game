--!strict
-- UIConstants.lua
-- Centralized UI constants using number tokens for flexibility
-- Use these tokens to build UDim/UDim2 at call sites for DPI/theme flexibility

local UIConstants = {}

-- ============================================
-- SIZE TOKENS (in pixels)
-- ============================================
UIConstants.Size = {
	-- Component sizes
	AVATAR_PX = 80,
	AVATAR_SMALL_PX = 48,
	ICON_PX = 24,
	ICON_SMALL_PX = 20,
	ICON_LARGE_PX = 32,
	ICON_MEDIUM_PX = 28,

	-- Button sizes
	BUTTON_HEIGHT = 44,
	BUTTON_SMALL_HEIGHT = 32,
	BUTTON_MEDIUM_HEIGHT = 36,
	BUTTON_LARGE_HEIGHT = 50,
	BUTTON_WIDTH = 120, -- Common fixed-width button
	ARROW_PX = 30, -- Dropdown arrow width

	-- Row/Label heights
	ROW_TINY = 16,
	ROW_SMALL = 20,
	ROW_LABEL = 22,
	ROW_STANDARD = 24,
	ROW_MEDIUM = 28,
	ROW_HEADER = 30,
	ROW_LARGE = 40,
	ROW_SECTION = 50,

	-- Input/Interactive elements
	INPUT_HEIGHT = 36,
	PROGRESS_HEIGHT = 6,
	SLIDER_HANDLE = 20,
	SLIDER_TRACK_HEIGHT = 4,

	-- Panel dimensions
	PANEL_MIN_WIDTH = 300,
	PANEL_MAX_WIDTH = 600,
	SETTINGS_WIDTH = 400,
	SETTINGS_HEIGHT = 500,

	-- Grid/Cell dimensions
	GRID_CELL_PX = 100,
	INVENTORY_CELL_WIDTH = 90,
	INVENTORY_CELL_HEIGHT = 110,
	INVENTORY_MIN_HEIGHT = 200,

	-- Section heights
	ACCOUNT_SECTION_HEIGHT = 100,
	UPGRADE_SECTION_HEIGHT = 144,
	UPGRADE_COINS_HEIGHT = 80,

	-- Badge/Count display
	BADGE_WIDTH = 30,
	BADGE_HEIGHT = 20,
}

-- ============================================
-- SPACING TOKENS (in pixels)
-- ============================================
UIConstants.Spacing = {
	NONE = 0,
	TINY = 4,
	XS = 5,
	CHIP_INNER = 6, -- Chip padding
	SM = 8,
	SECTION = 10,
	MD = 12,
	LG = 16,
	INPUT_MARGIN = 20,
	XL = 24,
	DROPDOWN_ARROW = 35, -- Space for dropdown arrow

	-- Specific spacing
	CARD_PADDING = 16,
	GRID_GAP = 8,
}

-- Derived sizes (keep near Spacing so dependencies are available)
UIConstants.Size.LIST_ROW_HEIGHT = UIConstants.Size.ROW_SECTION + UIConstants.Spacing.MD

-- ============================================
-- VISUAL TOKENS
-- ============================================
UIConstants.Visual = {
	CORNER_RADIUS = 8,
	CORNER_RADIUS_SMALL = 3,
	CORNER_RADIUS_TINY = 1,
	BORDER_WIDTH = 2,
	TILE_SIZE = 64, -- Noise tile size

	-- Text sizes
	TEXT_TITLE = 24,
	TEXT_HEADER = 20,
	TEXT_LARGE = 18,
	TEXT_MEDIUM = 16, -- Added for UI components
	TEXT_STANDARD = 16, -- Added for UI components (same as BODY/MEDIUM)
	TEXT_BODY = 16,
	TEXT_SMALL = 14,
	TEXT_TINY = 12,
	TEXT_MINIMUM = 8,
}

-- ============================================
-- ANIMATION TOKENS (in seconds)
-- ============================================
UIConstants.Anim = {
	INSTANT = 0,
	FAST = 0.1, -- Quick hover effects (2 uses)
	QUICK = 0.15, -- Most common (8 uses) - kept for back-compat
	MEDIUM = 0.2, -- InteractionChip (2 uses)
	SMOOTH = 0.3, -- Progress bars (1 use)
	SLOW = 0.5, -- Common affordance
	VERY_SLOW = 1.0, -- Item animations (4 uses)
	EXTRA_SLOW = 1.5, -- Slow item animations (4 uses)
	-- Wait delays
	MICRO = 0.03, -- Tiny sequencing delay (1 use)
	TINY = 0.05, -- Small delay (2 uses)
}

-- ============================================
-- Z-INDEX LAYERING
-- ============================================
UIConstants.ZIndex = {
	BACKGROUND = 1,
	CONTENT = 10,
	OVERLAY = 100,
	MODAL = 1000,
	TOOLTIP = 10000,
}

-- ============================================
-- COMMON PATTERNS
-- ============================================
UIConstants.Common = {
	ORIGIN = UDim2.new(0, 0, 0, 0), -- Zero position/size
	FULL = UDim2.new(1, 0, 1, 0), -- Full scale
}

-- ============================================
-- SHORTCUTS (commonly used values)
-- ============================================
UIConstants.CORNER_SMALL = 8 -- Common small corner radius
UIConstants.ACCENT_WIDTH = 4 -- Accent strip width

-- ============================================
-- MICRO HELPERS (for common patterns)
-- ============================================

-- Build UDim2 from pixel sizes
function UIConstants.px(width: number?, height: number?): UDim2
	return UDim2.new(0, width or 0, 0, height or 0)
end

-- Build square from single pixel size
function UIConstants.square(px: number): UDim2
	return UDim2.new(0, px, 0, px)
end

-- Build UDim2 with scale (0-1)
function UIConstants.scale(widthScale: number, heightScale: number): UDim2
	return UDim2.new(widthScale, 0, heightScale, 0)
end

-- Build padding UDim
function UIConstants.pad(pixels: number): UDim
	return UDim.new(0, pixels)
end

-- Build corner radius UDim
function UIConstants.corner(): UDim
	return UDim.new(0, UIConstants.Visual.CORNER_RADIUS)
end

-- Common size presets (built from tokens)
function UIConstants.avatar(): UDim2
	return UIConstants.square(UIConstants.Size.AVATAR_PX)
end

function UIConstants.button(): UDim2
	return UDim2.new(1, 0, 0, UIConstants.Size.BUTTON_HEIGHT)
end

return table.freeze(UIConstants)
