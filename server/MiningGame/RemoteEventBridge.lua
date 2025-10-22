--!strict
--[[
    RemoteEventBridge.lua
    Bridges EventBus events to RemoteEvents for network communication.
    
    Features:
    - Whitelisted event routing
    - Fast-path for high-frequency events
    - Type-safe target dispatching
    - Client event validation
    - Proper DI lifecycle (Init/Start/Stop)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Time = require(Shared:WaitForChild("Time"))
local Logger = require(Shared:WaitForChild("Logger"))
local log = Logger.new("RemoteEventBridge")

local EventBus = require(Shared.EventBus)
local EventNames = require(Shared.EventNames)
local RequestNames = require(Shared.RequestNames)

local RemoteEventBridge = {}
RemoteEventBridge.__index = RemoteEventBridge

-- Module state
local _initialized = false
local _started = false
local _connections = {}
local _subscriptions = {}
local Bus: any -- EventBus instance
local RE: RemoteEvent?

-- Mark high-frequency events as fast-path (skip middleware)
local FAST_PATH_EVENTS = {
    [EventNames.DIG_FEEDBACK] = true,
    [EventNames.TERRAIN_POKE] = true,
    [EventNames.RUNTIME_EFFECTS_CHANGED] = true,
    [EventNames.SOUND_PLAY] = true,
    [EventNames.INVENTORY_DELTA] = true,
}

-- Whitelist of server -> client events
local TO_CLIENT = {
    [EventNames.LOOT_DROPPED] = true,
    [EventNames.CURRENCY_CHANGED] = true,
    [EventNames.CUBE_ORIGIN_CHANGED] = true,
    [EventNames.DIG_FEEDBACK] = true,
    [EventNames.TERRAIN_POKE] = true,
    [EventNames.RUNTIME_EFFECTS_CHANGED] = true,
    [EventNames.INVENTORY_CHANGED] = true,
    [EventNames.INVENTORY_DELTA] = true,
    [EventNames.ACHIEVEMENT_UNLOCKED] = true,
    [EventNames.ANNOUNCEMENT_BROADCAST] = true,
    [EventNames.SOUND_PLAY] = true,
    [EventNames.NOTIFICATION_PUSH] = true,
    [EventNames.EQUIPMENT_CHANGED] = true,
    [EventNames.BOOSTS_CHANGED] = true,
    [EventNames.ITEM_COLLECTED] = true,
    [EventNames.PICKUP_PROMPT] = true,
    [EventNames.REWARD_GRANTED] = true,
    [EventNames.DEBUG_RESET] = true,
    [EventNames.PROFILE_UPDATED] = true,
    [EventNames.UPGRADES_CHANGED] = true,
    [EventNames.METRICS_UPDATED] = true,
    [EventNames.SERVER_METRICS_UPDATED] = true,
    -- [EventNames.CLOTH_UPDATE] = true, -- removed: cloth now client-driven
    -- Neighborhood events
    [EventNames.NEIGHBOR_JOINED] = true,
    [EventNames.NEIGHBOR_LEFT] = true,
    [EventNames.CUBE_UPDATE] = true,
    [EventNames.BANNER_READY] = true,
    -- Pedestal lifecycle
    [EventNames.PEDESTAL_READY] = true,
    [EventNames.PEDESTAL_REMOVED] = true,
}

-- Whitelist of client -> server events
local FROM_CLIENT = {
    [RequestNames.INVENTORY_REQUEST_SELL] = true,
    [RequestNames.INVENTORY_REQUEST_EQUIP] = true,
    [RequestNames.DIG_REQUEST] = true,
    [RequestNames.UPGRADE_REQUEST_PURCHASE] = true,
    [RequestNames.COSMETIC_REQUEST_EQUIP] = true,
    [RequestNames.SETTINGS_UPDATE] = true,
    [RequestNames.METRICS_REQUEST] = true,
    [RequestNames.SERVER_METRICS_REQUEST] = true,
    [RequestNames.TELEPORT_RANDOM_SKY] = true,
}

-- Rate limiting for client events (per player per event)
local rateLimits: {[Player]: {[string]: number}} = {}
local RATE_LIMIT_WINDOW = 1.0 -- seconds
local RATE_LIMIT_MAX = {
    [RequestNames.DIG_REQUEST] = 10, -- max 10 dig requests per second
    [RequestNames.INVENTORY_REQUEST_SELL] = 5,
    [RequestNames.INVENTORY_REQUEST_EQUIP] = 5,
    default = 3 -- default max 3 per second for other events
}

local function checkRateLimit(player: Player, eventName: string): boolean
    local now = Time.mono()
    local playerLimits = rateLimits[player]
    
    if not playerLimits then
        playerLimits = {}
        rateLimits[player] = playerLimits
    end
    
    local lastTime = playerLimits[eventName] or 0
    if now - lastTime < RATE_LIMIT_WINDOW / (RATE_LIMIT_MAX[eventName] or RATE_LIMIT_MAX.default) then
        return false -- Rate limited
    end
    
    playerLimits[eventName] = now
    return true
end

-- Helper to dispatch events based on strict target type
local function dispatch(remoteEvent: RemoteEvent, name: string, target: any, payload: any)
    if type(target) ~= "table" or target.kind == nil then
        error(("[RemoteEventBridge] Invalid target for '%s' (expected EventTarget)"):format(name))
    end
    if target.kind == "all" then
        remoteEvent:FireAllClients(name, payload)
    elseif target.kind == "player" then
        remoteEvent:FireClient(target.player, name, payload)
    else -- "players"
        for _, p in ipairs(target.players) do
            remoteEvent:FireClient(p, name, payload)
        end
    end
end

-- Initialize the service
function RemoteEventBridge:Init(container)
    if _initialized then
        log:warn("Already initialized")
        return
    end
    
    -- Ensure Remotes folder exists
    local Remotes = Shared:FindFirstChild("Remotes")
    if not Remotes then
        Remotes = Instance.new("Folder")
        Remotes.Name = "Remotes"
        Remotes.Parent = Shared
    end
    
    -- Create or get the EventBus RemoteEvent
    RE = Remotes:FindFirstChild("EventBus") :: RemoteEvent?
    if not RE then
        RE = Instance.new("RemoteEvent")
        RE.Name = "EventBus"
        RE.Parent = Remotes
    end
    
    -- Get global bus
    Bus = EventBus.global()
    
    -- Mark fast-path events
    for eventName in pairs(FAST_PATH_EVENTS) do
        Bus:markFastPath(eventName)
    end
    table.freeze(FAST_PATH_EVENTS)
    
    -- Validate whitelists
    for name in pairs(TO_CLIENT) do
        assert(EventNames.isValid(name), "TO_CLIENT whitelist contains unknown event: "..tostring(name))
    end
    table.freeze(TO_CLIENT)
    
    for name in pairs(FROM_CLIENT) do
        assert(RequestNames.isValid(name), "FROM_CLIENT whitelist contains unknown request: "..tostring(name))
    end
    table.freeze(FROM_CLIENT)
    
    _initialized = true
    log:info("Initialized")
end

-- Start the service
function RemoteEventBridge:Start()
    if not _initialized then
        error("RemoteEventBridge:Start() called before Init()")
    end
    if _started then
        log:warn("Already started")
        return
    end
    
    assert(RE, "RemoteEvent not initialized")
    
    -- Subscribe to all whitelisted server -> client events
    for eventName in pairs(TO_CLIENT) do
        local unsub = Bus:on(eventName, function(msg)
            if not msg.to then
                warn(("[RemoteEventBridge] Event '%s' missing 'to' field"):format(eventName))
                return
            end
            dispatch(RE, eventName, msg.to, msg.payload)
        end, 5) -- High priority so bridge runs early
        table.insert(_subscriptions, unsub)
    end
    
    -- Handle client -> server events
    local clientConnection = RE.OnServerEvent:Connect(function(player: Player, eventName: string, payload: any)
        -- Validate event is whitelisted
        if not FROM_CLIENT[eventName] then
            warn(("[RemoteEventBridge] Blocked unauthorized client event '%s' from %s"):format(
                tostring(eventName), 
                player.Name
            ))
            return
        end
        
        -- Check rate limit
        if not checkRateLimit(player, eventName) then
            warn(("[RemoteEventBridge] Rate limited event '%s' from %s"):format(
                eventName,
                player.Name
            ))
            return
        end
        
        -- Emit on bus with player as 'from' field (never trust client-provided 'from')
        Bus:emitDeferred(eventName, {
            from = player,
            payload = payload
        })
    end)
    table.insert(_connections, clientConnection)
    
    -- Clean up rate limits when player leaves
    local playerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
        rateLimits[player] = nil
    end)
    table.insert(_connections, playerRemovingConnection)
    
    -- Note: Middleware for logging/metrics removed since EventBus doesn't support
    -- individual middleware removal and the bus is global. If needed, add a dedicated
    -- performance monitoring service that adds middleware once at startup.
    
    _started = true
    log:info("Started")
end

-- Stop the service
function RemoteEventBridge:Stop()
    if not _started then
        return
    end
    
    -- Disconnect all connections
    for _, conn in ipairs(_connections) do
        if conn and conn.Disconnect then
            pcall(function() conn:Disconnect() end)
        end
    end
    table.clear(_connections)
    
    -- Unsubscribe from all events
    for _, unsub in ipairs(_subscriptions) do
        if type(unsub) == "function" then
            pcall(unsub)
        end
    end
    table.clear(_subscriptions)
    
    -- Clear rate limits
    table.clear(rateLimits)
    
    _started = false
    log:info("Stopped")
end

return RemoteEventBridge
