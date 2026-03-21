--!strict
-- BannerConfig.lua
-- Central config for base banner placement/orientation/colors with simple setters

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(MiningGame:WaitForChild("Logger"))
local log = Logger.new("BannerConfig")

local Config = {}

Config.TUNE = {
	-- DO NOT TOUCH in normal use: PITCH_X_DEG tilts the banner. +90 hangs upright; 0 makes it flat.
	PITCH_X_DEG = 90, -- X axis (pitch)
	-- DO NOT TOUCH in normal use: YAW_Y_DEG "spins the sign" like a sign spinner (rotates around vertical).
	YAW_Y_DEG = 90, -- Y axis (yaw)
	-- Preferred control for facing: ROLL_Z_DEG "rotates the face" (0/90/180/270) without affecting hang/spin.
	ROLL_Z_DEG = 90, -- Z axis (roll)
	LIFT_Y = 28,
	INWARD_X_T = 0.05, -- 0..1 left->right
	INSIDE_Z = -4.0, -- additive after along-edge
	ALONG_Z_T = 0.625, -- 0..1 front->back
	COLOR = Color3.fromRGB(10, 30, 170),
	MATCH_GLOW_TO_BANNER = true,
	-- Billboard wiring defaults (overridable per-slot):
	FEATURE = "", -- default: no billboard feature; set per-slot
	CATEGORY = "blocks", -- default category
	FACE = "Front", -- Surface face for panel/billboard
	-- Optional multi‑spawn slots (normalized positions). If nil, spawns one banner using ALONG_Z_T/INWARD_X_T.
	-- Each slot: { alongZT = 0..1, inwardXT = 0..1 }
	-- Spawn three banners: first at current T, next two slightly higher along the Z edge.
	SLOTS = {
		-- 1) Blocks Dug (with billboard)
		{
			alongZT = 0.625,
			inwardXT = 0.05,
			color = Color3.fromRGB(10, 30, 170),
			feature = "HighScore",
			category = "blocks",
			face = "Front",
		},
		-- 2) Robux Donated (with billboard)
		{
			alongZT = 0.685,
			inwardXT = 0.05,
			color = Color3.fromRGB(170, 120, 0),
			feature = "HighScore",
			category = "donator",
			face = "Front",
		},
		-- 3) Coins Earned (with billboard)
		{
			alongZT = 0.745,
			inwardXT = 0.05,
			color = Color3.fromRGB(0, 120, 40),
			feature = "HighScore",
			category = "coins",
			face = "Front",
		},
		-- 4) Action banner: Teleport (client shows ActionChip via ProximityAction)
		{
			alongZT = 0.805,
			inwardXT = 0.05,
			color = Color3.fromRGB(100, 0, 160),
			feature = "Teleport",
			category = "teleport",
			face = "Front",
		},
	},

	-- Pedestal placement (strict; no fallbacks)
	-- Normalized coordinates along the same base edge as banners.
	-- Tweak these to position the Respawn pedestal.
	PEDESTAL = {
		alongZT = 0.765, -- near banner row but between slots to avoid overlap
		inwardXT = 0.120, -- inwards from the banner edge so it sits beside banners
		insideZ = -3.0, -- slight inset from edge
		colorSlotIndex = 4, -- scenic slot color by default
		-- Offsets applied in base-local axes:
		--  X = left->right across base (positive moves inward toward center/right)
		--  Z = front->back along base (positive moves toward back/top; negative toward bottom/front)
		offsetX = 103, -- studs inward from banner edge (toward base center)
		offsetZ = -50, -- studs toward bottom/front of the base
	},
}

-- Convenience: resolve an accent Color3 from slots or fallback COLOR
function Config.getAccentColor(slotIndex: number?): Color3
	local t = Config.TUNE
	if type(slotIndex) == "number" and t.SLOTS then
		local s = t.SLOTS[slotIndex]
		if s and typeof(s.color) == "Color3" then
			return s.color :: Color3
		end
	end
	return t.COLOR
end

function Config.update(partial: { [string]: any })
	for k, v in pairs(partial) do
		if Config.TUNE[k] ~= nil then
			Config.TUNE[k] = v
		else
			log:warn("Ignoring unknown banner config key: %s", tostring(k))
		end
	end
	return Config.TUNE
end

function Config.get()
	return Config.TUNE
end

return Config
