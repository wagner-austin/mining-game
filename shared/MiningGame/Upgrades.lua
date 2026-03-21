--!strict
-- Upgrades.lua
-- Typed helpers for upgrade level definitions

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local GameConfig = require(MiningGame:WaitForChild("GameConfig"))

export type SpeedLevelDef = { level: number, cost: number, multiplier: number }
export type SizeLevelDef = { level: number, cost: number, size: number }
export type LevelDef = SpeedLevelDef | SizeLevelDef
export type UpgradeType = "speed" | "size"

local Upgrades = {}

function Upgrades.getLevelDef(upgradeType: UpgradeType, level: number): LevelDef?
	local levels = if upgradeType == "speed" then GameConfig.Upgrades.SPEED_LEVELS else GameConfig.Upgrades.SIZE_LEVELS
	for _, def in ipairs(levels) do
		if def.level == level then
			return def
		end
	end
	return nil
end

function Upgrades.getMaxLevel(upgradeType: UpgradeType): number
	local levels = if upgradeType == "speed" then GameConfig.Upgrades.SPEED_LEVELS else GameConfig.Upgrades.SIZE_LEVELS
	return #levels - 1
end

return Upgrades
