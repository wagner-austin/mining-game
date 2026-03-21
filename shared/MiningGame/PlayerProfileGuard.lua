--!strict
-- PlayerProfileGuard.lua
-- Centralized utility for safe player profile access
-- Reduces 18+ direct DataService/GetProfile calls to single gateway

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MG = ReplicatedStorage:WaitForChild("MiningGame")
local Time = require(MG:WaitForChild("Time"))
local GameConfig = require(MG:WaitForChild("GameConfig"))
local ClientError = require(MG:WaitForChild("ClientError"))
local MathUtils = require(MG:WaitForChild("MathUtils"))

-- Lazy-load ClientRF only on client
local ClientRF = nil
if RunService:IsClient() then
	local ok, cf = ClientError.try("PlayerProfileGuard.requireClientRF", function()
		return require(MG:WaitForChild("ClientRF"))
	end)
	if ok then
		ClientRF = cf
	end
end

-- Lazy-load EventNames
local EventNames = nil
do
	local okEN, EN = ClientError.try("PlayerProfileGuard.requireEventNames", function()
		return require(MG:WaitForChild("EventNames"))
	end)
	if okEN then
		EventNames = EN
	end
end

-- Types
export type PlayerProfile = {
	coins: number?,
	blocksDug: number?,
	upgrades: { [string]: number }?,
	inventory: { [string]: number }?,
	equipped: { [string]: string }?,
	achievements: { [string]: any }?,
	preferences: { [string]: any }?,
	stats: { [string]: any }?,
	-- Add other profile fields as needed
}

local PlayerProfileGuard = {}

-- Client-side profile fetching with caching
local profileCache: PlayerProfile? = nil
local cacheTime: number = 0 -- Using Time.mono() for monotonic timing
local CACHE_DURATION = GameConfig and GameConfig.Cache and GameConfig.Cache.TTL_SHORT or 5

-- Get player profile (client-side)
function PlayerProfileGuard.get(): (PlayerProfile?, string?)
	if RunService:IsServer() then
		return nil, "PlayerProfileGuard.get() is client-only. Use DataService on server."
	end

	-- Return cached profile if fresh (use monotonic clock for duration checks)
	local now = Time.mono()
	if profileCache and (now - cacheTime) < CACHE_DURATION then
		return profileCache, nil
	end

	-- Fetch fresh profile with retry for boot timing
	if ClientRF and type(ClientRF.call) == "function" then
		-- Try with retry if available, fallback to single call
		local data, err
		if type(ClientRF.callWithRetry) == "function" then
			data, err = ClientRF.callWithRetry("GetProfile", 2)
		else
			data, err = ClientRF.call("GetProfile")
		end
		if err then
			return nil, tostring(err)
		end

		-- Extract profile from response (handle different response formats)
		local profile = nil
		if type(data) == "table" then
			profile = data.profile or data
		end

		if profile then
			profileCache = profile
			cacheTime = Time.mono() -- Monotonic time for cache expiry
			return profile, nil
		else
			return nil, "Invalid profile response format"
		end
	end

	-- Fallback for studio/testing
	return nil, "ClientRF unavailable"
end

-- Get specific field from profile
function PlayerProfileGuard.getField(fieldName: string): (any?, string?)
	local profile, err = PlayerProfileGuard.get()
	if not profile then
		return nil, err
	end

	return profile[fieldName], nil
end

-- Get coins specifically (common use case)
function PlayerProfileGuard.getCoins(): (number, string?)
	local coins, err = PlayerProfileGuard.getField("coins")
	if err then
		return 0, err
	end
	return tonumber(coins) or 0, nil
end

-- Get upgrades (common use case)
function PlayerProfileGuard.getUpgrades(): ({ [string]: number }, string?)
	local upgrades, err = PlayerProfileGuard.getField("upgrades")
	if err then
		return {}, err
	end
	return upgrades or {}, nil
end

-- Clear cache (useful after purchases/upgrades)
function PlayerProfileGuard.clearCache()
	profileCache = nil
	cacheTime = 0
end

-- Optional: Configure cache duration
function PlayerProfileGuard.setCacheDuration(seconds: number)
	CACHE_DURATION = MathUtils.nonNegative(seconds)
end

-- Subscribe to profile changes (if EventBus is available)
local EventBus = nil
do
	local okEB, eb = ClientError.try("PlayerProfileGuard.requireEventBus", function()
		return require(MG:WaitForChild("EventBus"))
	end)
	if okEB then
		EventBus = eb
	end
end

if EventBus and RunService:IsClient() and EventNames then
	local Bus = EventBus.global()

	local function bust()
		PlayerProfileGuard.clearCache()
	end

	-- Clear cache on any profile-affecting events
	Bus:on(EventNames.PROFILE_UPDATED, bust)
	Bus:on(EventNames.CURRENCY_CHANGED, bust)
	Bus:on(EventNames.UPGRADES_CHANGED, bust)
	Bus:on(EventNames.INVENTORY_CHANGED, bust)
	Bus:on(EventNames.ACHIEVEMENT_UNLOCKED, bust)
	Bus:on(EventNames.EQUIPMENT_CHANGED, bust) -- Correct event name
end

return table.freeze(PlayerProfileGuard)
