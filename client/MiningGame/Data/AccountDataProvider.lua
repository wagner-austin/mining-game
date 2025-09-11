--!strict
-- AccountDataProvider.lua
-- Centralized client-side data management for account/profile information

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Use EventBus for events
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Ready = require(MiningGame:WaitForChild("Ready"))
local Time = require(MiningGame:WaitForChild("Time"))
local EventBus = require(MiningGame:WaitForChild("EventBus"))
local EventNames = require(MiningGame:WaitForChild("EventNames"))
local ClientRF = require(MiningGame:WaitForChild("ClientRF"))
local PlayerProfileGuard = require(MiningGame:WaitForChild("PlayerProfileGuard"))
local Bus = EventBus.global()

local AccountDataProvider = {}
AccountDataProvider.__index = AccountDataProvider

export type Profile = {
    coins: number,
    gems: number?,
    totalBlocksDug: number?,
    currentDepth: number?,
    maxDepth: number?,
    joinTime: number?,
    playTime: number?,
    username: string?,
    displayName: string?,
    userId: number?,
    -- Extended data
    inventory: {[string]: any}?,
    settings: {[string]: any}?,
    statistics: {[string]: number}?,
    upgrades: {[string]: number}?,
    equipped: {[string]: any}?,
}

export type AccountSnapshot = {
    profile: Profile,
    cubeStats: {totalChunks: number, dugCells: number, compressedSize: number}?,
    sessionStartTime: number,
    lastUpdated: number,
    isLoading: boolean,
}

function AccountDataProvider.new(remotes: any, uiUtils: any?)
    local self = setmetatable({}, AccountDataProvider)
    
    self._remotes = remotes
    self._uiUtils = uiUtils
    self._profile = nil :: Profile?
    self._cubeStats = nil :: {totalChunks: number, dugCells: number, compressedSize: number}?
    self._sessionStartTime = nil -- Will be set from server
    self._lastUpdated = 0
    self._isLoading = false
    self._connections = {} :: {RBXScriptConnection}
    self._busUnsubs = {} :: {() -> ()}
    
    -- Event for changes
    self._changed = Instance.new("BindableEvent")
    
    -- Initialize
    self:_fetchInitialData()
    self:_setupEventListeners()
    
    return self
end

-- Public API

function AccountDataProvider:getProfile(): Profile?
    return self._profile
end

function AccountDataProvider:getSnapshot(): AccountSnapshot
    return {
        profile = self._profile or self:_getDefaultProfile(),
        cubeStats = self._cubeStats,
        sessionStartTime = self._sessionStartTime or Time.unix(), -- Safe fallback
        lastUpdated = self._lastUpdated,
        isLoading = self._isLoading,
    }
end

function AccountDataProvider:onChanged(): RBXScriptSignal
    return self._changed.Event
end

function AccountDataProvider:refresh()
    self:_fetchInitialData()
end

function AccountDataProvider:destroy()
    -- Clean up EventBus subscriptions
    if self._busUnsubs then
        for _, unsub in ipairs(self._busUnsubs) do
            pcall(unsub)
        end
        self._busUnsubs = nil
    end
    
    -- Clean up RBXScriptConnections
    if self._connections then
        for _, conn in ipairs(self._connections) do
            if typeof(conn) == "RBXScriptConnection" then
                pcall(function() conn:Disconnect() end)
            end
        end
        self._connections = nil
    end
    
    if self._changed then
        self._changed:Destroy()
        self._changed = nil :: any
    end
end

-- Private Methods

function AccountDataProvider:_getDefaultProfile(): Profile
    return {
        coins = 0,
        gems = 0,
        totalBlocksDug = 0,
        currentDepth = 0,
        maxDepth = 0,
        joinTime = Time.unix(),
        playTime = 0,
        username = "Loading...",
        displayName = "Loading...",
        userId = 0,
        upgrades = { speed = 0, size = 0 },
        inventory = {},  -- add these two
        equipped = {},   -- add these two
    }
end

function AccountDataProvider:_fetchInitialData()
    if self._isLoading then return end
    
    -- Defensive check: if server isn't ready yet, defer until it is
    if not Ready.wait(0) then
        -- Server not ready, set up deferred fetch
        local conn
        conn = MiningGame:GetAttributeChangedSignal("ServerReady"):Connect(function()
            if MiningGame:GetAttribute("ServerReady") then
                conn:Disconnect()
                self:_fetchInitialData() -- Retry when ready
            end
        end)
        return
    end
    
    self._isLoading = true
    self:_notifyChange()
    
    task.spawn(function()
        -- Use PlayerProfileGuard for centralized profile access
        local profile, err = PlayerProfileGuard.get()
        
        self._isLoading = false
        
        if profile then
            self:_updateProfile(profile)
            -- Prefer server-authored session start time
            self._sessionStartTime = profile.sessionStartTime 
                or profile.joinTime 
                or self._sessionStartTime 
                or Time.unix()
            
            -- Cube stats are now included in the GetProfile response
            if profile.cubeStats then
                self._cubeStats = profile.cubeStats
            end
        elseif err then
            -- Log error but don't crash
            warn("[AccountDataProvider] Failed to fetch profile:", err)
        end
    end)
end

function AccountDataProvider:_updateProfile(newData: {[string]: any})
    if not self._profile then
        self._profile = self:_getDefaultProfile()
    end
    
    -- Update fields
    for key, value in pairs(newData) do
        (self._profile :: any)[key] = value
    end
    
    self._lastUpdated = Time.unix()
    self:_notifyChange()
end

function AccountDataProvider:_updateField(key: string, value: any)
    if not self._profile then
        self._profile = self:_getDefaultProfile()
    end
    
    (self._profile :: any)[key] = value
    self._lastUpdated = Time.unix()
    self:_notifyChange(key, value)
end

function AccountDataProvider:_notifyChange(key: string?, value: any?)
    self._changed:Fire(key, value, self:getSnapshot())
end

function AccountDataProvider:_setupEventListeners()
    -- Store unsubscribe functions for cleanup
    self._busUnsubs = {}
    
    -- Profile updates (full snapshot from server)
    table.insert(self._busUnsubs, Bus:on(EventNames.PROFILE_UPDATED, function(profile)
        self._profile = profile
        self._changed:Fire(nil, nil, self:getSnapshot())
    end))
    
    -- Currency changes
    table.insert(self._busUnsubs, Bus:on(EventNames.CURRENCY_CHANGED, function(currencyData)
        local p = self._profile or self:_getDefaultProfile()
        local c = currencyData
        if c then
            if c.currency == "coins" then 
                p.coins = c.balance 
            end
            if c.currency == "gems" then 
                p.gems = c.balance 
            end
        end
        self._profile = p
        self._changed:Fire(nil, nil, self:getSnapshot())
    end))
    
    -- Inventory changes (full snapshot)
    table.insert(self._busUnsubs, Bus:on(EventNames.INVENTORY_CHANGED, function(inventory)
        local p = self._profile or self:_getDefaultProfile()
        p.inventory = inventory
        self._profile = p
        self._changed:Fire(nil, nil, self:getSnapshot())
    end))

    -- Inventory deltas (incremental updates)
    table.insert(self._busUnsubs, Bus:on(EventNames.INVENTORY_DELTA, function(delta)
        local p = self._profile or self:_getDefaultProfile()
        p.inventory = p.inventory or {}
        for itemId, inc in pairs(delta) do
            local current = p.inventory[itemId] or 0
            p.inventory[itemId] = current + inc
        end
        self._profile = p
        self._changed:Fire("inventoryDelta", delta, self:getSnapshot())
    end))
    
    -- Debug reset via EventBus - refresh entire profile
    table.insert(self._busUnsubs, Bus:on(EventNames.DEBUG_RESET, function()
        -- Refetch entire profile from server
        self:_fetchInitialData()
    end))
    
    -- Boosts changes via EventBus (keeping for compatibility)
    table.insert(self._busUnsubs, Bus:on(EventNames.BOOSTS_CHANGED, function(boosts)
        local prof = self._profile or self:_getDefaultProfile()
        prof.boosts = boosts
        self:_notifyChange("boosts", boosts)
    end))
    
    -- Upgrades changes via EventBus
    table.insert(self._busUnsubs, Bus:on(EventNames.UPGRADES_CHANGED, function(upgrades)
        self:_updateField("upgrades", upgrades)
    end))
end

return AccountDataProvider
