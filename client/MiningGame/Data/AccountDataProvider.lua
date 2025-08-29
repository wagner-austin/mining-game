--!strict
-- AccountDataProvider.lua
-- Centralized client-side data management for account/profile information

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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
        sessionStartTime = self._sessionStartTime or os.time(), -- Safe fallback
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
    for _, conn in ipairs(self._connections) do
        if conn then conn:Disconnect() end
    end
    self._connections = {}
    
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
        joinTime = os.time(),
        playTime = 0,
        username = "Loading...",
        displayName = "Loading...",
        userId = 0,
    }
end

function AccountDataProvider:_fetchInitialData()
    if self._isLoading then return end
    
    self._isLoading = true
    self:_notifyChange()
    
    task.spawn(function()
        local profileData = nil
        
        -- Use UIUtils if available, otherwise direct remote call
        if self._uiUtils and self._uiUtils.getProfileWithRetry then
            profileData = self._uiUtils.getProfileWithRetry(self._remotes, 3, 1)
        else
            local success, result = pcall(function()
                return self._remotes.RF.GetProfile:InvokeServer()
            end)
            if success then
                profileData = result
            end
        end
        
        self._isLoading = false
        
        if profileData then
            if profileData.profile then
                self:_updateProfile(profileData.profile)
                -- Prefer server-authored session start time
                self._sessionStartTime = profileData.profile.sessionStartTime 
                    or profileData.profile.joinTime 
                    or self._sessionStartTime 
                    or os.time()
            end
            if profileData.cubeStats then
                self._cubeStats = profileData.cubeStats
            end
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
    
    self._lastUpdated = os.time()
    self:_notifyChange()
end

function AccountDataProvider:_updateField(key: string, value: any)
    if not self._profile then
        self._profile = self:_getDefaultProfile()
    end
    
    (self._profile :: any)[key] = value
    self._lastUpdated = os.time()
    self:_notifyChange(key, value)
end

function AccountDataProvider:_notifyChange(key: string?, value: any?)
    self._changed:Fire(key, value, self:getSnapshot())
end

function AccountDataProvider:_setupEventListeners()
    local RE = self._remotes and self._remotes.RE
    if not RE then return end
    
    -- Currency changes
    if RE.OnCurrencyChanged then
        local conn = RE.OnCurrencyChanged.OnClientEvent:Connect(function(currencyType: string, newValue: number)
            if currencyType == "coins" then
                self:_updateField("coins", newValue)
            elseif currencyType == "gems" then
                self:_updateField("gems", newValue)
            end
        end)
        table.insert(self._connections, conn)
    end
    
    -- Profile updates
    if RE.OnProfileUpdate then
        local conn = RE.OnProfileUpdate.OnClientEvent:Connect(function(profileData: {[string]: any})
            self:_updateProfile(profileData)
        end)
        table.insert(self._connections, conn)
    end
end

return AccountDataProvider