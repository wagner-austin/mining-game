--!strict
-- UpgradeService.server.lua
-- Handles player progression and upgrade calculations

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Time = require(Shared:WaitForChild("Time"))
local Logger = require(Shared:WaitForChild("Logger"))
local log = Logger.new("UpgradeService")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Types = require(Shared:WaitForChild("Types"))
local ServiceValidator = require(Shared:WaitForChild("ServiceValidator"))
-- ErrorService not needed in this module

-- Services (injected via Init)
local CurrencyService
local DataService

local UpgradeService = {}
UpgradeService.__index = UpgradeService

-- Initialize with DI container
function UpgradeService:Init(container)
	DataService = ServiceValidator.get(container, "DataService", { "GetPlayerData", "QueueSave" })
	CurrencyService = ServiceValidator.get(container, "CurrencyService", { "canAfford", "add" })
	log:info("Initialized with dependencies")
end

-- Cache upgrade definitions
-- Provide precise types for upgrade level arrays to avoid casts
type SpeedLevel = { level: number, cost: number, multiplier: number }
type SizeLevel = { level: number, cost: number, size: number }
local SPEED_LEVELS: { SpeedLevel } = GameConfig.Upgrades.SPEED_LEVELS
local SIZE_LEVELS: { SizeLevel } = GameConfig.Upgrades.SIZE_LEVELS

-- Get upgrade definition by level
type AnyUpgrade = { level: number, cost: number, multiplier: number?, size: number? }
local function getSpeedUpgradeLevel(level: number): SpeedLevel?
	for _, def in ipairs(SPEED_LEVELS) do
		if def.level == level then
			return def
		end
	end
	return nil
end

local function getSizeUpgradeLevel(level: number): SizeLevel?
	for _, def in ipairs(SIZE_LEVELS) do
		if def.level == level then
			return def
		end
	end
	return nil
end

-- Calculate effective stats including all bonuses
function UpgradeService:ComputeEffectiveStats(
	profile: Types.PlayerStats,
	gamepasses: { [string]: boolean },
	activePets: { Types.PetData }?
): Types.EffectiveStats
	-- Base values
	local baseDelay = GameConfig.Digging.BASE_DIG_DELAY
	local baseSize = GameConfig.Digging.BASE_DIG_SIZE_CELLS or 0
	local baseLuck = 1.0

	-- Get upgrade levels
	local speedLevel = profile.upgrades.speed or 0
	local sizeLevel = profile.upgrades.size or 0

	-- Apply upgrade multipliers
	local speedUpgrade = getSpeedUpgradeLevel(speedLevel)
	local sizeUpgrade = getSizeUpgradeLevel(sizeLevel)

	local delay = baseDelay * (speedUpgrade and speedUpgrade.multiplier or 1.0)
	local size = (sizeUpgrade and sizeUpgrade.size) or baseSize
	local luck = baseLuck

	-- Debug: Log the size calculation
	log:debug(
		"Size calc: sizeLevel=%d, sizeUpgrade.size=%s, baseSize=%d, final size=%d",
		sizeLevel,
		tostring(sizeUpgrade and sizeUpgrade.size or "nil"),
		baseSize,
		size
	)

	-- Apply boosts (time-limited)
	local now = Time.unix()
	for boostType, expiry in pairs(profile.boosts) do
		if expiry > now then
			if boostType == "speed" then
				delay = delay * 0.5 -- 50% faster
			elseif boostType == "luck" then
				luck = luck * 2.0 -- 2x luck
			elseif boostType == "size" then
				size = size + 2 -- +2 size
			end
		end
	end

	-- Apply gamepass bonuses (read from GameConfig when available)
	if gamepasses["VIP"] then
		local vipMult = 2.0
		local passes = (GameConfig.Monetization and GameConfig.Monetization.GAMEPASSES) or {}
		for _, p in ipairs(passes) do
			if p.id == "VIP" and p.effects and type(p.effects.loot_multiplier) == "number" then
				vipMult = p.effects.loot_multiplier
				break
			end
		end
		luck = luck * vipMult
	end
	if gamepasses["BIGGER_DIG"] then
		local sizeBonus = 3
		local passes = (GameConfig.Monetization and GameConfig.Monetization.GAMEPASSES) or {}
		for _, p in ipairs(passes) do
			if p.id == "BIGGER_DIG" and p.effects and type(p.effects.size_bonus) == "number" then
				sizeBonus = p.effects.size_bonus
				break
			end
		end
		size = size + sizeBonus
	end

	-- Cosmetic perks are mapped to runtime effects in PerkService and applied by StatsResolver.

	-- Apply pet bonuses
	if activePets then
		for _, petData in ipairs(activePets) do
			if petData.equipped then
				local petDef = nil
				for _, pet in ipairs(GameConfig.Pets.PETS) do
					if pet.id == petData.id then
						petDef = pet
						break
					end
				end

				if petDef and petDef.buffs then
					-- Apply star multiplier
					local starMult = GameConfig.Pets.STAR_MULTIPLIERS[petData.stars] or 1.0

					if petDef.buffs.speed then
						delay = delay * (1 - petDef.buffs.speed * starMult)
					end
					if petDef.buffs.size then
						local sizeBuff = petDef.buffs.size or 0
						size = size + math.floor(size * sizeBuff * starMult)
					end
					if petDef.buffs.luck then
						luck = luck * (1 + petDef.buffs.luck * starMult)
					end
				end
			end
		end
	end

	-- Get material hardness
	local materialData = GameConfig.CubeMaterialsById[profile.materialId]
	local hardness = materialData and materialData.hardness or 1.0

	-- Apply hardness to delay
	delay = delay * hardness

	-- Clamp values to reasonable ranges
	delay = math.max(0.1, delay) -- Minimum 0.1 second delay
	size = math.min(20, size) -- Maximum 20 size
	luck = math.min(10, luck) -- Maximum 10x luck

	return {
		delay = delay,
		size = size,
		luck = luck,
		hardness = hardness,
	}
end

-- Purchase an upgrade
function UpgradeService:PurchaseUpgrade(
	player: Player,
	profile: Types.PlayerStats,
	upgradeType: string
): { success: boolean, newLevel: number?, costNext: number?, reason: string? }
	-- Get current level
	local currentLevel = profile.upgrades[upgradeType] or 0

	-- Get upgrade definitions
	-- Find next level (specialized per-upgrade to keep types precise)
	local nextLevel: { level: number, cost: number }? = nil
	if upgradeType == "speed" then
		for _, level in ipairs(SPEED_LEVELS) do
			if level.level == currentLevel + 1 then
				nextLevel = { level = level.level, cost = level.cost }
				break
			end
		end
	elseif upgradeType == "size" then
		for _, level in ipairs(SIZE_LEVELS) do
			if level.level == currentLevel + 1 then
				nextLevel = { level = level.level, cost = level.cost }
				break
			end
		end
	else
		return { success = false, reason = "Invalid upgrade type" }
	end

	if not nextLevel then
		return { success = false, reason = "Max level reached" }
	end

	-- Check if player can afford
	if profile.coins < nextLevel.cost then
		return { success = false, reason = "Insufficient coins" }
	end

	-- Deduct cost and apply upgrade
	CurrencyService.add(player, "coins", -nextLevel.cost)
	profile.upgrades[upgradeType] = nextLevel.level

	-- Emit profile update after upgrade is applied
	local EventBus = require(Shared:WaitForChild("EventBus"))
	local EventNames = require(Shared:WaitForChild("EventNames"))
	local Bus = EventBus.global()
	local Contracts = require(Shared:WaitForChild("EventContracts"))
	Bus:emit(EventNames.PROFILE_UPDATED, {
		to = { kind = "player", player = player },
		payload = Contracts.PROFILE_UPDATED(profile),
	})

	-- Find cost of next level after this one
	local nextNextLevelCost: number? = nil
	if upgradeType == "speed" then
		for _, level in ipairs(SPEED_LEVELS) do
			if level.level == nextLevel.level + 1 then
				nextNextLevelCost = level.cost
				break
			end
		end
	elseif upgradeType == "size" then
		for _, level in ipairs(SIZE_LEVELS) do
			if level.level == nextLevel.level + 1 then
				nextNextLevelCost = level.cost
				break
			end
		end
	end

	return {
		success = true,
		newLevel = nextLevel.level,
		costNext = nextNextLevelCost,
	}
end

-- Apply a temporary boost
function UpgradeService:ApplyBoost(profile: Types.PlayerStats, boostType: string, duration: number)
	local expiry = Time.unix() + duration
	profile.boosts[boostType] = expiry
end

-- Check gamepass ownership using profile's tracked ownership (source of truth)
-- Note: MonetizationService backfills this on join by checking Roblox API
function UpgradeService:GetPlayerGamepasses(player: Player): { [string]: boolean }
	local gamepasses = {}

	local profile = DataService:GetPlayerData(player)
	if not profile then
		return gamepasses
	end

	local ownedGamePasses = profile.ownedGamePasses or {}

	for _, gamepass in ipairs(GameConfig.Monetization.GAMEPASSES) do
		if gamepass.gamepassId > 0 then
			gamepasses[gamepass.id] = ownedGamePasses[gamepass.gamepassId] == true
		end
	end

	return gamepasses
end

-- Get active pets for a player
function UpgradeService:GetActivePets(profile: Types.PlayerStats): { Types.PetData }
	local activePets = {}
	local equippedCount = 0
	local maxEquipped = GameConfig.Pets.MAX_EQUIPPED

	for _, petData in pairs(profile.pets) do
		if petData.equipped and equippedCount < maxEquipped then
			table.insert(activePets, petData)
			equippedCount = equippedCount + 1
		end
	end

	return activePets
end

-- Calculate total cells that will be dug
function UpgradeService:CalculateDigVolume(size: number): number
	-- Simple cube volume calculation
	local diameter = size * 2 + 1
	return diameter * diameter * diameter
end

-- Get upgrade progress
function UpgradeService:GetUpgradeProgress(
	profile: Types.PlayerStats
): { [string]: { current: number, max: number, percent: number } }
	local progress = {}

	-- Speed
	local speedCurrent = profile.upgrades.speed or 0
	local speedMax = #SPEED_LEVELS - 1
	progress.speed = {
		current = speedCurrent,
		max = speedMax,
		percent = speedMax > 0 and (speedCurrent / speedMax) or 0,
	}

	-- Size
	local sizeCurrent = profile.upgrades.size or 0
	local sizeMax = #SIZE_LEVELS - 1
	progress.size = {
		current = sizeCurrent,
		max = sizeMax,
		percent = sizeMax > 0 and (sizeCurrent / sizeMax) or 0,
	}

	return progress
end

log:info("Initialized")

return UpgradeService
