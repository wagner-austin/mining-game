--!strict
-- UserMetricsService.lua
-- Composes trusted, queryable user metrics with lightweight caching.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")

local DataService
local SessionService
local UpgradeService
local GridService

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

    lastUpdated: number,
}

local CACHE_TTL = 5
local cache: {[Player]: {data: UserMetrics, at: number}} = {}

local UserMetricsService = {}
UserMetricsService.__index = UserMetricsService

local function safeDiv(a: number, b: number): number
    if b == 0 then return 0 end
    return a / b
end

function UserMetricsService.new()
    local self = setmetatable({}, UserMetricsService)

    task.defer(function()
        DataService = require(script.Parent:WaitForChild("DataService"))
        SessionService = require(script.Parent:WaitForChild("SessionService"))
        UpgradeService = require(script.Parent:WaitForChild("UpgradeService"))
        GridService = require(script.Parent:WaitForChild("GridService"))
    end)

    Players.PlayerRemoving:Connect(function(p)
        cache[p] = nil
    end)

    return self
end

function UserMetricsService:GetMetrics(player: Player): UserMetrics?
    -- Cache current time for consistency
    local now = os.time()
    
    -- Ensure services are loaded
    if not DataService then
        pcall(function()
            DataService = require(script.Parent.DataService)
            SessionService = require(script.Parent.SessionService)
            UpgradeService = require(script.Parent.UpgradeService)
            GridService = require(script.Parent.GridService)
        end)
    end
    
    local c = cache[player]
    if c and (now - c.at) < CACHE_TTL then
        return c.data
    end

    if not DataService then return nil end
    
    -- Ensure profile is loaded if missing
    local profile = DataService:GetPlayerData(player)
    if not profile and typeof(DataService.EnsureLoaded) == "function" then
        local ok = DataService:EnsureLoaded(player)
        if ok then profile = DataService:GetPlayerData(player) end
    end
    if not profile then return nil end
    
    local cube = DataService:GetCubeData(player)

    local sessionStart = (SessionService and SessionService.getSessionStartTime(player.UserId)) or profile.sessionStartTime or now
    local sessionDur = math.max(0, now - sessionStart)
    local sessionMin = sessionDur / 60

    -- Calculate blocks dug this session
    local currentBlocks = math.max(0, profile.totalBlocksDug or 0)
    local sessionStartBlocks = profile.sessionStartBlocks
    
    -- If sessionStartBlocks is nil, this means the session tracking hasn't been set up yet
    -- In this case, assume they haven't dug this session
    local dugThisSession = 0
    if sessionStartBlocks ~= nil then
        -- Clamp to handle resets
        sessionStartBlocks = math.max(0, sessionStartBlocks)
        if currentBlocks < sessionStartBlocks then
            sessionStartBlocks = currentBlocks
            profile.sessionStartBlocks = currentBlocks
        end
        dugThisSession = currentBlocks - sessionStartBlocks
    end
    local bpm = sessionMin > 0 and (dugThisSession / sessionMin) or 0

    local gamepasses = UpgradeService and UpgradeService:GetPlayerGamepasses(player) or {}
    local activePets = UpgradeService and UpgradeService:GetActivePets(profile) or {}
    local eff = UpgradeService and UpgradeService:ComputeEffectiveStats(profile, gamepasses, activePets) or {delay=1,size=1,luck=1,hardness=1}

    local cubeStats = (cube and GridService and GridService:GetChunkStats(cube)) or {totalChunks=0,dugCells=0,compressedSize=0}

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
    
    -- Add monetization metrics (lazy require to avoid cycles)
    local okMon, MonetizationService = pcall(function()
        return require(script.Parent.MonetizationService)
    end)
    if okMon and MonetizationService and typeof(MonetizationService.GetMetrics) == "function" then
        m.monetization = MonetizationService:GetMetrics(player)
    end

    cache[player] = {data = m, at = now}
    return m
end

function UserMetricsService:GetServerMetrics()
    local totalPlayers, totalBlocks, totalCoins, totalPlaytime = 0,0,0,0
    for _, p in ipairs(Players:GetPlayers()) do
        local m = self:GetMetrics(p)
        if m then
            totalPlayers = totalPlayers + 1
            totalBlocks = totalBlocks + m.gameplay.totalBlocksDug
            totalCoins = totalCoins + m.economy.coins
            totalPlaytime = totalPlaytime + m.session.totalPlaytimeSec
        end
    end
    return {
        totalPlayers = totalPlayers,
        totalBlocksDug = totalBlocks,
        totalCoins = totalCoins,
        totalPlaytimeHours = totalPlaytime / 3600,
        serverUptimeSec = workspace.DistributedGameTime,
    }
end

function UserMetricsService:ExportMetrics(player: Player): string?
    local m = self:GetMetrics(player)
    if not m then return nil end
    local ok, json = pcall(HttpService.JSONEncode, HttpService, m)
    return ok and json or nil
end

function UserMetricsService:Invalidate(player: Player?)
    if player then
        cache[player] = nil
    else
        table.clear(cache)
    end
end

local instance = UserMetricsService.new()
return instance