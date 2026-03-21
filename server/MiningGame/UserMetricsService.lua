--!strict
-- UserMetricsService.lua
-- Composes trusted, queryable user metrics with lightweight caching.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Time = require(MiningGame:WaitForChild("Time"))
local Logger = require(MiningGame:WaitForChild("Logger"))
local log = Logger.new(Logger.CAT.UserMetrics or "UserMetricsService")
local MathUtils = require(MiningGame:WaitForChild("MathUtils"))
local ServiceValidator = require(MiningGame:WaitForChild("ServiceValidator"))
local EventBus = require(MiningGame:WaitForChild("EventBus"))
local EventNames = require(MiningGame:WaitForChild("EventNames"))
local RequestNames = require(MiningGame:WaitForChild("RequestNames"))
local Bus = EventBus.global()
local SpawnOrchestrator = require(script.Parent:WaitForChild("SpawnOrchestrator"))

-- Services (injected via Init)
local DataService
local SessionService
local UpgradeService
local GridService
local MonetizationService -- Optional

export type UserMetrics = {
	userId: number,
	username: string,
	displayName: string,
	accountAgeDays: number,

	gameplay: {
		totalBlocksDug: number,
		dugThisSession: number,
		blocksPerMinute: number,
	},

	economy: {
		coins: number,
		gems: number,
		totalCoinsEarned: number,
		totalCoinsSpent: number,
		totalGemsEarned: number,
		totalGemsSpent: number,
		netWorth: number,
	},

	progression: {
		speedLevel: number,
		sizeLevel: number,
		petsOwned: number,
		activePets: number,
		materialTier: string,
	},

	session: {
		sessionStartTime: number,
		sessionDurationSec: number,
		totalPlaytimeSec: number,
		totalSessions: number,
		avgSessionLengthSec: number,
		lastLoginTime: number,
	},

	lifecycle: {
		isNewPlayer: boolean,
		isReturningPlayer: boolean,
		isFirstDigEver: boolean,
		hasDugEver: boolean,
		hasDugThisSession: boolean,
		firstPlayTime: number?,
		firstDigTime: number?,
	},

	world: {
		cube: { totalChunks: number, dugCells: number, compressedSize: number },
		effectiveStats: { delay: number, size: number, luck: number, hardness: number },
	},

	-- Optional monetization metrics snapshot (server-only)
	monetization: any?,

	lastUpdated: number,
}

local CACHE_TTL = 5
local cache: { [Player]: { data: UserMetrics, at: number } } = {}

local UserMetricsService = {}
UserMetricsService.__index = UserMetricsService

local function safeDiv(a: number, b: number): number
	if b == 0 then
		return 0
	end
	return a / b
end

-- Initialize with DI container
function UserMetricsService:Init(container)
	DataService = ServiceValidator.get(container, "DataService", {
		"GetPlayerData",
		"GetCubeData",
		"EnsureLoaded",
		"QueueSave",
	})
	SessionService = ServiceValidator.tryGet(container, "SessionService", { "getSessionStartTime" })
	UpgradeService = ServiceValidator.get(container, "UpgradeService", {
		"GetPlayerGamepasses",
		"GetActivePets",
		"ComputeEffectiveStats",
	})
	GridService = ServiceValidator.get(container, "GridService", { "GetChunkStats" })
	MonetizationService = ServiceValidator.tryGet(container, "MonetizationService", { "GetMetrics" })

	log:info("Initialized with dependencies")
end

-- Start method to connect events after all services are initialized
function UserMetricsService:Start(_container)
	-- Set up player cleanup
	Players.PlayerRemoving:Connect(function(p)
		cache[p] = nil
	end)

	log:info("Started with player connections")

	-- Optional: handle client -> server metrics request via EventBus bridge
	Bus:on(RequestNames.METRICS_REQUEST, function(evt)
		local from = evt and evt.from
		local player = from
		if typeof(player) ~= "Instance" then
			return
		end
		local m = self:GetMetrics(player)
		if type(m) ~= "table" then
			return
		end
		Bus:emit(EventNames.METRICS_UPDATED, {
			to = { kind = "player", player = player },
			payload = m,
		})
	end)

	-- Optional: server metrics via EventBus (dev-only visibility, mirrors RF behavior)
	Bus:on(RequestNames.SERVER_METRICS_REQUEST, function(evt)
		local from = evt and evt.from
		local player = from
		if typeof(player) ~= "Instance" then
			return
		end
		if not RunService:IsStudio() then
			-- Send minimal payload to indicate lack of visibility
			Bus:emit(EventNames.SERVER_METRICS_UPDATED, {
				to = { kind = "player", player = player },
				payload = { visible = false },
			})
			return
		end
		local serverMetrics = self:GetServerMetrics()
		Bus:emit(EventNames.SERVER_METRICS_UPDATED, {
			to = { kind = "player", player = player },
			payload = serverMetrics,
		})
	end)
end

function UserMetricsService.new()
	local self = setmetatable({}, UserMetricsService)
	return self
end

function UserMetricsService:GetMetrics(player: Player): UserMetrics?
	local t0 = Time.mono()
	local uid = player.UserId

	-- Cache current time for consistency
	local now = Time.unix()

	-- Services should be loaded via Init
	if not DataService then
		log:error("Services not initialized - Init() not called?")
		return nil
	end

	local c = cache[player]
	if c and (now - c.at) < CACHE_TTL then
		log:debug("cache hit uid=%d age=%.2fs", uid, now - c.at)
		return c.data
	end
	log:debug("cache miss uid=%d", uid)

	if not DataService then
		log:error("DataService not available uid=%d", uid)
		return nil
	end

	-- Ensure profile is loaded if missing
	local profile = DataService:GetPlayerData(player)
	if not profile and typeof(DataService.EnsureLoaded) == "function" then
		local ok = DataService:EnsureLoaded(player)
		if ok then
			profile = DataService:GetPlayerData(player)
		end
	end
	if not profile then
		log:error("profile load failed uid=%d", uid)
		return nil
	end

	local cube = DataService:GetCubeData(player)

	local sessionStart = (SessionService and SessionService.getSessionStartTime(player.UserId))
		or profile.sessionStartTime
		or now
	local sessionDur = MathUtils.nonNegative(now - sessionStart)
	local sessionMin = sessionDur / 60

	-- Calculate blocks dug this session
	local currentBlocks = MathUtils.nonNegative(profile.totalBlocksDug or 0)
	local sessionStartBlocks = profile.sessionStartBlocks

	-- If sessionStartBlocks is nil, this means the session tracking hasn't been set up yet
	-- In this case, assume they haven't dug this session
	local dugThisSession = 0
	if sessionStartBlocks ~= nil then
		-- Clamp to handle resets
		sessionStartBlocks = MathUtils.nonNegative(sessionStartBlocks)
		if currentBlocks < sessionStartBlocks then
			sessionStartBlocks = currentBlocks
			profile.sessionStartBlocks = currentBlocks
		end
		dugThisSession = currentBlocks - sessionStartBlocks
	end
	local bpm = sessionMin > 0 and (dugThisSession / sessionMin) or 0

	local gamepasses = UpgradeService and UpgradeService:GetPlayerGamepasses(player) or {}
	local activePets = UpgradeService and UpgradeService:GetActivePets(profile) or {}
	local eff = UpgradeService and UpgradeService:ComputeEffectiveStats(profile, gamepasses, activePets)
		or { delay = 1, size = 1, luck = 1, hardness = 1 }

	local cubeStats = (cube and GridService and GridService:GetChunkStats(cube))
		or { totalChunks = 0, dugCells = 0, compressedSize = 0 }

	-- Net worth heuristic: coins + gems*100 (adjust later if you value inventory)
	local netWorth = (profile.coins or 0) + (profile.gems or 0) * 100

	local petsOwned, petsActive = 0, 0
	if profile.pets then
		for _, p in pairs(profile.pets) do
			petsOwned = petsOwned + 1
			if p.equipped then
				petsActive = petsActive + 1
			end
		end
	end

	local totalSessions = math.max(1, profile.totalSessions or 1)
	local m: UserMetrics = {
		userId = player.UserId,
		username = player.Name,
		displayName = player.DisplayName,
		accountAgeDays = player.AccountAge, -- already days; do not convert from seconds

		gameplay = {
			totalBlocksDug = profile.totalBlocksDug or 0,
			dugThisSession = dugThisSession,
			blocksPerMinute = bpm,
		},

		economy = {
			coins = profile.coins or 0,
			gems = profile.gems or 0,
			totalCoinsEarned = profile.totalCoinsEarned or (profile.coins or 0),
			totalCoinsSpent = profile.totalCoinsSpent or 0,
			totalGemsEarned = profile.totalGemsEarned or (profile.gems or 0),
			totalGemsSpent = profile.totalGemsSpent or 0,
			netWorth = netWorth,
		},

		progression = {
			speedLevel = (profile.upgrades and profile.upgrades.speed) or 0,
			sizeLevel = (profile.upgrades and profile.upgrades.size) or 0,
			petsOwned = petsOwned,
			activePets = petsActive,
			materialTier = profile.materialId or "tier1",
		},

		session = {
			sessionStartTime = sessionStart,
			sessionDurationSec = sessionDur,
			totalPlaytimeSec = profile.playtime or 0,
			totalSessions = totalSessions,
			avgSessionLengthSec = safeDiv(profile.playtime or 0, totalSessions),
			lastLoginTime = profile.lastLoginTime or sessionStart,
		},

		lifecycle = {
			isNewPlayer = totalSessions <= 1,
			isReturningPlayer = totalSessions > 1,
			isFirstDigEver = profile.firstDigTime == nil,
			hasDugEver = ((profile.totalBlocksDug or 0) > 0) or (profile.firstDigTime ~= nil),
			hasDugThisSession = dugThisSession > 0,
			firstPlayTime = profile.firstPlayTime or sessionStart,
			firstDigTime = profile.firstDigTime,
		},

		world = {
			cube = cubeStats,
			effectiveStats = eff,
		},

		lastUpdated = now,
	}

	-- Add monetization metrics (optional service)
	if MonetizationService then
		m.monetization = MonetizationService:GetMetrics(player)
	end

	cache[player] = { data = m, at = now }

	log:perf("UserMetricsService:GetMetrics", t0)

	-- Best-effort payload size logging
	do
		local ErrorService = require(script.Parent.ErrorService)
		local okJ, json = ErrorService.safecall("UserMetrics.JSONEncode", function()
			return HttpService:JSONEncode(m)
		end)
		if okJ and type(json) == "string" then
			log:metric("metrics_payload_bytes", #json, { uid = uid })
		end
	end

	return m
end

function UserMetricsService:GetServerMetrics()
	local t0 = Time.mono()
	local totalPlayers, totalBlocks, totalCoins, totalPlaytime = 0, 0, 0, 0
	for _, p in ipairs(Players:GetPlayers()) do
		local m = self:GetMetrics(p)
		if m then
			totalPlayers = totalPlayers + 1
			totalBlocks = totalBlocks + m.gameplay.totalBlocksDug
			totalCoins = totalCoins + m.economy.coins
			totalPlaytime = totalPlaytime + m.session.totalPlaytimeSec
		end
	end

	local serverMetrics = {
		totalPlayers = totalPlayers,
		totalBlocksDug = totalBlocks,
		totalCoins = totalCoins,
		totalPlaytimeHours = totalPlaytime / 3600,
		serverUptimeSec = workspace.DistributedGameTime,
	}
	-- Include spawn orchestration metrics snapshot
	local ErrorService = require(script.Parent.ErrorService)
	local ok, spawnMetrics = ErrorService.safecall("SpawnOrchestrator.GetMetrics", function()
		return SpawnOrchestrator.GetMetrics()
	end)
	if ok and type(spawnMetrics) == "table" then
		serverMetrics.spawn = spawnMetrics
	else
		serverMetrics.spawn = { enabled = false }
	end

	log:perf("UserMetricsService:GetServerMetrics", t0)
	log:metric("server_active_players", totalPlayers)
	-- Include EventBus event counters (best effort)
	local okEvt, evt = ErrorService.safecall("EventMetrics.Snapshot", function()
		return require(script.Parent.EventMetrics).Snapshot()
	end)
	if okEvt and type(evt) == "table" then
		serverMetrics.eventBus = evt
	end

	return serverMetrics
end

function UserMetricsService:ExportMetrics(player: Player): string?
	local m = self:GetMetrics(player)
	if not m then
		return nil
	end
	local ErrorService = require(script.Parent.ErrorService)
	local ok, json = ErrorService.safecall("UserMetrics.ExportJSON", function()
		return HttpService:JSONEncode(m)
	end)
	if ok and type(json) == "string" then
		return json
	end
	return nil
end

function UserMetricsService:Invalidate(player: Player?, reason: string?)
	if player then
		cache[player] = nil
		log:debug("invalidate uid=%d reason=%s", player.UserId, reason or "unknown")
	else
		table.clear(cache)
		log:debug("invalidate all caches")
	end
end

local instance = UserMetricsService.new()
return instance
