--!strict
-- AchievementConstants.lua
-- Centralized constants for achievement system to avoid magic strings

local AchievementConstants = {}

-- Achievement rarity levels (matches save data)
AchievementConstants.RARITY = table.freeze({
	COMMON = "COMMON",
	RARE = "RARE",
	EPIC = "EPIC",
	LEGENDARY = "LEGENDARY",
	MYTHIC = "MYTHIC",
})

-- Achievement categories
AchievementConstants.CATEGORY = table.freeze({
	DIGGING = "DIGGING",
	COLLECTING = "COLLECTING",
	CURRENCY = "CURRENCY",
	EXPLORATION = "EXPLORATION",
	SOCIAL = "SOCIAL",
	SPECIAL = "SPECIAL",
})

-- Achievement status
AchievementConstants.STATUS = table.freeze({
	LOCKED = "LOCKED",
	IN_PROGRESS = "IN_PROGRESS",
	COMPLETED = "COMPLETED",
	CLAIMED = "CLAIMED",
})

-- Point values by rarity
AchievementConstants.POINTS = table.freeze({
	[AchievementConstants.RARITY.COMMON] = 10,
	[AchievementConstants.RARITY.RARE] = 25,
	[AchievementConstants.RARITY.EPIC] = 50,
	[AchievementConstants.RARITY.LEGENDARY] = 100,
	[AchievementConstants.RARITY.MYTHIC] = 250,
})

-- Display colors by rarity (for UI)
AchievementConstants.COLORS = table.freeze({
	[AchievementConstants.RARITY.COMMON] = Color3.fromRGB(200, 200, 200),
	[AchievementConstants.RARITY.RARE] = Color3.fromRGB(85, 170, 255),
	[AchievementConstants.RARITY.EPIC] = Color3.fromRGB(163, 53, 238),
	[AchievementConstants.RARITY.LEGENDARY] = Color3.fromRGB(255, 170, 0),
	[AchievementConstants.RARITY.MYTHIC] = Color3.fromRGB(255, 85, 255),
})

-- Type guards
function AchievementConstants.isValidRarity(value: any): boolean
	if type(value) ~= "string" then
		return false
	end
	return AchievementConstants.RARITY[value] ~= nil
end

function AchievementConstants.isValidCategory(value: any): boolean
	if type(value) ~= "string" then
		return false
	end
	return AchievementConstants.CATEGORY[value] ~= nil
end

function AchievementConstants.isValidStatus(value: any): boolean
	if type(value) ~= "string" then
		return false
	end
	return AchievementConstants.STATUS[value] ~= nil
end

return table.freeze(AchievementConstants)
