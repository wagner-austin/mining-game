--!strict
-- ErrorService.lua
-- Centralized error reporting & safe wrappers

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Time = require(Shared:WaitForChild("Time"))
local Logger = require(Shared:WaitForChild("Logger"))
local EventBus = require(Shared:WaitForChild("EventBus"))
local EventNames = require(Shared:WaitForChild("EventNames"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local log = Logger.new(Logger.CAT.ErrorService)
local Bus = EventBus.global()

export type Tags = {[string]: string | number | boolean}
export type Extra = {[string]: any}

local ErrorService = {}

-- Error deduplication tracking
local errorCache: {[string]: {count: number, lastSeen: number}} = {}
local _lastCleanup = 0
local CLEANUP_INTERVAL = 5 -- Run cleanup at most every 5 seconds

-- Configurable limits (with defaults from GameConfig if available)
local ERROR_CACHE_TTL = (GameConfig.Debug and GameConfig.Debug.ERROR_CACHE_TTL) or 60
local MAX_ERROR_CACHE_SIZE = (GameConfig.Debug and GameConfig.Debug.MAX_ERROR_CACHE_SIZE) or 100
local RATE_LIMIT_THRESHOLD = (GameConfig.Debug and GameConfig.Debug.ERROR_RATE_LIMIT) or 5

-- DI Lifecycle: Initialize error service with config
function ErrorService:Init(container: any)
    -- Apply configuration from GameConfig if available
    if GameConfig.Debug then
        ErrorService.setLogLimits({
            TTL = GameConfig.Debug.ERROR_CACHE_TTL,
            MaxCacheSize = GameConfig.Debug.MAX_ERROR_CACHE_SIZE,
            RateThreshold = GameConfig.Debug.ERROR_RATE_LIMIT
        })
    end
    
    log:info("ErrorService initialized (TTL=%ds, MaxCache=%d, RateLimit=%d)", 
        ERROR_CACHE_TTL, MAX_ERROR_CACHE_SIZE, RATE_LIMIT_THRESHOLD)
end

-- DI Lifecycle: Start (no-op for this service)
function ErrorService:Start(container: any)
    -- ErrorService doesn't need startup logic
    log:debug("ErrorService started")
end

-- DI Lifecycle: Stop (no-op for this service)
function ErrorService:Stop()
    -- ErrorService doesn't need cleanup logic yet
    log:debug("ErrorService stopped")
end

-- Helper to normalize error messages for better deduplication
local function normalizeMessage(msg: string): string
    return msg
        :gsub("0x%x+", "0x*")           -- Normalize hex addresses
        :gsub("%d%d%d%d%d%d+", "*")     -- Normalize long numbers (IDs, timestamps)
        :gsub("at %S+:%d+", "at *:*")   -- Normalize file:line references (tighter match)
        :sub(1, 200)                     -- Keep first 200 chars for good clustering
end

-- Helper to determine if an error should be logged
-- Returns: shouldLog, isHot (frequent error flag)
local function _shouldLog(where: string, msg: string): (boolean, boolean)
    local now = Time.mono()
    local normalized = normalizeMessage(msg)
    local key = where .. ":" .. normalized  -- No second truncation
    
    -- Check cache
    local cached = errorCache[key]
    if cached then
        cached.count = cached.count + 1
        cached.lastSeen = now
        
        local isHot = cached.count == RATE_LIMIT_THRESHOLD
        local shouldLog = cached.count <= 2 or cached.count % 10 == 0
        
        return shouldLog, isHot
    end
    
    -- Add to cache
    errorCache[key] = {count = 1, lastSeen = now}
    
    -- Throttled cleanup
    if now - _lastCleanup > CLEANUP_INTERVAL and next(errorCache) then
        _lastCleanup = now
        
        -- Remove expired entries
        local cacheSize = 0
        for k, v in pairs(errorCache) do
            if now - v.lastSeen > ERROR_CACHE_TTL then
                errorCache[k] = nil
            else
                cacheSize = cacheSize + 1
            end
        end
        
        -- If still too large, clear oldest half
        if cacheSize > MAX_ERROR_CACHE_SIZE then
            local entries = {}
            for k, v in pairs(errorCache) do
                table.insert(entries, {key = k, lastSeen = v.lastSeen})
            end
            table.sort(entries, function(a, b) return a.lastSeen < b.lastSeen end)
            
            -- Remove oldest 50%
            for i = 1, math.floor(#entries / 2) do
                errorCache[entries[i].key] = nil
            end
        end
    end
    
    return true, false -- Log first occurrence, not hot
end

-- Configure error logging limits at runtime
function ErrorService.setLogLimits(opts: {
    TTL: number?,
    MaxCacheSize: number?,
    RateThreshold: number?
}?)
    if typeof(opts) ~= "table" then return end
    if tonumber(opts.TTL) then ERROR_CACHE_TTL = opts.TTL end
    if tonumber(opts.MaxCacheSize) then MAX_ERROR_CACHE_SIZE = opts.MaxCacheSize end
    if tonumber(opts.RateThreshold) then RATE_LIMIT_THRESHOLD = opts.RateThreshold end
end

local function emit(where: string, err: string, tags: Tags?, extra: Extra?)
    -- Server-only event; wire to analytics or dev banners if desired
    if EventNames.ERROR_REPORTED then
        Bus:emit(EventNames.ERROR_REPORTED, {
            to = { kind = "server" },
            payload = {
                where = where,
                message = err,
                tags = tags or {},
                extra = extra or {},
                timestamp = math.floor(Time.unix()),
            }
        })
    end
end

-- xpcall wrapper that logs + emits and then rethrows (so callers may handle)
function ErrorService.wrap<T...>(where: string, fn: (...any) -> T...)
    return function(...: any): ...T
        local args = table.pack(...)
        local packed = table.pack(xpcall(function()
            return fn(table.unpack(args, 1, args.n))
        end, debug.traceback))
        
        local ok = packed[1]
        if not ok then
            local msg = tostring(packed[2])
            local shouldLog, isHot = _shouldLog(where, msg)
            if isHot then 
                log:warn("[%s] Frequent error spike (seen %d times): %s", where, RATE_LIMIT_THRESHOLD, msg:sub(1, 150))
            end
            if shouldLog then 
                log:error("[%s] %s", where, msg)
            end
            emit(where, msg, nil, { argsCount = args.n })
            error(packed[2]) -- rethrow with original traceback string
        end
        return table.unpack(packed, 2, packed.n) -- forward all return values
    end
end

-- Never throws; returns (ok, valueOrErrorString)
function ErrorService.safecall<T>(where: string, fn: () -> T, tags: Tags?, extra: Extra?): (boolean, T | string)
    local ok, res = xpcall(fn, debug.traceback)
    if not ok then
        local msg = tostring(res)
        local shouldLog, isHot = _shouldLog(where, msg)
        if isHot then 
            log:warn("[%s] Frequent error spike (seen %d times): %s", where, RATE_LIMIT_THRESHOLD, msg:sub(1, 150))
        end
        if shouldLog then 
            log:error("[%s] %s", where, msg)
        end
        emit(where, msg, tags, extra)
        return false, msg
    end
    return true, res
end

function ErrorService.report(where: string, err: string, tags: Tags?, extra: Extra?)
    local shouldLog, isHot = _shouldLog(where, err)
    if isHot then 
        log:warn("[%s] Frequent error spike (seen %d times): %s", where, RATE_LIMIT_THRESHOLD, err:sub(1, 150))
    end
    if shouldLog then 
        log:error("[%s] %s", where, err)
    end
    emit(where, err, tags, extra)
end

return ErrorService