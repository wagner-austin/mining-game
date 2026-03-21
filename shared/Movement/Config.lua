--[[
    Movement Configuration Module for Mining Game
    ==============================================
    Central configuration for all player movement parameters.
    This module is used by all movement scripts to ensure consistency.
    
    Simplified version without sprint functionality
    Tunable movement speed, jump height, gravity, and double jump
    
    Location: ReplicatedStorage/Movement/Config.lua (via Rojo: shared/Movement/Config.lua)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local MaterialDefinitions = require(MiningGame:WaitForChild("MaterialDefinitions"))

local Config = {}

-- Base Movement Parameters
-- These values define the default movement characteristics for all players
Config.BASE_SPEED = 24 -- Base walking speed in studs/second (50% faster than default 16)
Config.BASE_JUMP_HEIGHT = 10 -- Base jump height in studs (higher than default 7.2 for mining gameplay)

-- Movement Limits
-- Prevents extreme values that could break gameplay
Config.LIMITS = {
	speedMin = 8, -- Minimum walk speed (prevents getting stuck)
	speedMax = 100, -- Maximum walk speed (prevents breaking physics)
	jumpMin = 5, -- Minimum jump height
	jumpMax = 50, -- Maximum jump height (capped for balance)
}

-- Gravity Multiplier (applied server-wide)
-- 1.0 = normal Roblox gravity (196.2)
-- Lower values = floatier jumps, higher values = heavier feel
Config.GRAVITY_MULT = 0.45 -- Moderately reduced gravity for enhanced vertical mobility

-- Double Jump Configuration
Config.DOUBLE_JUMP = {
	enabled = true, -- Enable/disable double jump feature
	maxJumps = 2, -- Total jumps (1 ground + 1 air)
	scale = 0.95, -- Second jump height multiplier (0.95 = 95% of base jump)
	impulseScale = 0.3, -- Scales the additive impulse (0.3 = 30% strength for balanced feel)
	coyoteTime = 0.15, -- Grace period after leaving ground (seconds)
	jumpCooldown = 0.10, -- Cooldown between jump inputs (prevents spam)
}

-- Terrain voxel speeds from MaterialDefinitions
Config.TERRAIN_MULT = {}
for _, def in pairs(MaterialDefinitions.Materials) do
	Config.TERRAIN_MULT[def.enum] = def.properties.speedMultiplier
end

-- Non-terrain BasePart surface multipliers (preserves previous behavior)
-- These apply to part materials that aren't terrain voxels
Config.PART_SURFACE_MULT = {
	[Enum.Material.Metal] = 1.15, -- Metal platforms/rails give speed boost
	[Enum.Material.Granite] = 0.90, -- Harder rock, more difficult
}

-- Helper function to get speed multiplier from Enum.Material
function Config.GetSpeedFromEnum(mat: Enum.Material): number
	return Config.TERRAIN_MULT[mat] or Config.PART_SURFACE_MULT[mat] or 1.0
end

-- Helper function to get speed multiplier from material key (for convenience)
function Config.GetSpeedFromKey(materialKey: string): number
	if type(materialKey) == "string" then
		local key = string.lower(materialKey)
		local enum = MaterialDefinitions.GetEnum(key)
		if enum then
			return Config.GetSpeedFromEnum(enum)
		end
	end
	return 1.0
end

-- Item/Upgrade Modifiers
-- These can be applied when players get upgrades or equipment
Config.UPGRADE_MODS = {
	-- Speed upgrades
	speedBoots1 = { speedMult = 1.15 }, -- 15% speed increase
	speedBoots2 = { speedMult = 1.30 }, -- 30% speed increase
	speedBoots3 = { speedMult = 1.50 }, -- 50% speed increase

	-- Jump upgrades
	jumpBoots1 = { jumpMult = 1.20 }, -- 20% jump increase
	jumpBoots2 = { jumpMult = 1.40 }, -- 40% jump increase
	jumpBoots3 = { jumpMult = 1.60 }, -- 60% jump increase

	-- Combined upgrades
	minerGear1 = { speedMult = 1.10, jumpMult = 1.10 }, -- 10% both
	minerGear2 = { speedMult = 1.20, jumpMult = 1.20 }, -- 20% both
	minerGear3 = { speedMult = 1.35, jumpMult = 1.35 }, -- 35% both
}

return Config
