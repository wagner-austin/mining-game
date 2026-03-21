--!strict
-- FallbackRegistry.lua
-- Centralized, explicit stubs for non-critical services to allow graceful degradation

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(Shared:WaitForChild("Logger"))
local log = Logger.new(Logger.CAT.ServiceContainer or "FallbackRegistry")

local FallbackRegistry = {}

local function noop() end

local function AchievementsStub()
	return {
		Init = noop,
		Start = noop,
		Stop = noop,
		SetRewardItemCallback = noop,
		RecordFirstDig = noop,
		RecordFirstCosmeticEquip = noop,
		RecordRarityFind = noop,
		RecordCoinsEarned = noop,
		RecordBlocksDug = noop,
		GetPlayerAchievements = function()
			return {}
		end,
		GetAchievementDefinition = function()
			return nil
		end,
		GetAllAchievements = function()
			return {}
		end,
	}
end

local function AnnouncementStub()
	return {
		Init = noop,
		Start = noop,
		Stop = noop,
		ServerBanner = noop,
		GlobalBanner = noop,
		AnnounceRareDrop = noop,
		AnnounceRareFind = noop,
	}
end

local function UserMetricsStub()
	return {
		Init = noop,
		Start = noop,
		Stop = noop,
		GetMetrics = function()
			return nil
		end,
		GetServerMetrics = function()
			return { visible = false }
		end,
	}
end

local STUBS = {
	AchievementService = AchievementsStub,
	AnnouncementService = AnnouncementStub,
	UserMetricsService = UserMetricsStub,
}

function FallbackRegistry.has(name: string): boolean
	return STUBS[name] ~= nil
end

function FallbackRegistry.get(name: string)
	local f = STUBS[name]
	if not f then
		return nil
	end
	log:warn("Using fallback stub for %s", name)
	return f()
end

return FallbackRegistry
