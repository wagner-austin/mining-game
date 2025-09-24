--!strict
-- MetricsTab.lua - Shows real-time user metrics for monitoring and debugging
-- Migrated to use BaseTabComponent for consistent UI patterns

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UIFolder = MiningGame:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))
local Logger = require(MiningGame:WaitForChild("Logger"))
local UIConstants = require(UIFolder:WaitForChild("UIConstants"))
local EventBus = require(MiningGame:WaitForChild("EventBus"))
local EventNames = require(MiningGame:WaitForChild("EventNames"))
local RequestNames = require(MiningGame:WaitForChild("RequestNames"))
local Bus = EventBus.global()
-- Client-local bridge for EventBus requests
local RemoteEventBridge = require(script.Parent.Parent.Parent:WaitForChild("RemoteEventBridge"))

-- Shorthand
local UIx = UIConstants

-- UIUtils is optional; guard in case the module doesn't exist
local uiUtilsModule = UIFolder:FindFirstChild("UIUtils")
local UIUtils = uiUtilsModule and require(uiUtilsModule) or nil

local BaseTabComponent = require(script.Parent:WaitForChild("BaseTabComponent"))

local log = Logger.new("MetricsTab")

local MetricsTab = {}
MetricsTab.__index = MetricsTab
setmetatable(MetricsTab, { __index = BaseTabComponent })

type Props = {
    parent: GuiObject,
    position: UDim2?,
    size: UDim2?,
}

type MetricsTabT = typeof(setmetatable({} :: any, MetricsTab)) & {
    _refreshing: boolean,
    _autoRefresh: boolean,
    _serverFieldsContainer: Frame?,
    _serverPlaceholder: TextLabel?,
    _errorBanner: Frame?,
    _errorTimeout: thread?,
    _refreshButton: TextButton?,
    new: (props: Props) -> MetricsTabT,
}

function MetricsTab.new(props: Props): MetricsTabT
    -- Initialize base component with stacked=true (MetricsTab already uses stacked layout)
    local self = setmetatable(BaseTabComponent.new({
        parent = props.parent,
        position = props.position,
        size = props.size,
        stacked = true,  -- MetricsTab already uses UIListLayout
        name = "MetricsTab",
    }), MetricsTab)
    
    -- Tab-specific state
    self._refreshing = false
    self._autoRefresh = true
    self._serverFieldsContainer = nil
    self._serverPlaceholder = nil
    self._errorBanner = nil
    self._errorTimeout = nil
    
    -- Using EventBus push for metrics; no RF needed here
    
    -- Build UI
    self._errorBanner = self:createStatusBanner()
    self:_createRefreshButton()
    self:_createMetricsSection("Gameplay", {
        "totalBlocksDug",
        "dugThisSession", 
        "blocksPerMinute"
    }, "⛏️")
    self:_createMetricsSection("Economy", {
        "coins",
        "gems",
        "totalCoinsEarned",
        "totalCoinsSpent",
        "totalGemsEarned",
        "totalGemsSpent",
        "netWorth"
    }, "💰")
    self:_createMetricsSection("Session", {
        "sessionStartTime",
        "sessionDurationSec",
        "totalPlaytimeSec",
        "totalSessions",
        "avgSessionLengthSec"
    }, "⏱️")
    self:_createMetricsSection("Lifecycle", {
        "isNewPlayer",
        "isReturningPlayer",
        "isFirstDigEver",
        "hasDugEver",
        "hasDugThisSession",
        "firstPlayTime",
        "firstDigTime"
    }, "🔄")
    self:_createMetricsSection("Progression", {
        "speedLevel",
        "sizeLevel",
        "petsOwned",
        "activePets",
        "materialTier"
    }, "📈")
    self:_createMetricsSection("Monetization", {
        "robuxSpentLifetime",
        "robuxSpentThisSession",
        "purchasesCount",
        "devProducts",
        "gamePasses",
        "isPayingUser",
        "daysSinceLastPurchase",
    }, "🛒")
    self:_createServerSection()
    
    -- Initial fetch
    log:info("Starting initial refresh")
    self:refresh()
    
    -- Use base component's periodic update for auto-refresh (paused when hidden)
    self:startPeriodicUpdate(2, function()
        self:refresh()
    end)
    
    -- Pause auto refresh when tab not visible to avoid mutating UI while hidden
    self:addConnection(self.container:GetPropertyChangedSignal("Visible"):Connect(function()
        if self.container.Visible then
            -- Resume periodic updates and refresh immediately when shown
            self:startPeriodicUpdate(2, function() self:refresh() end)
            self:refresh()
        else
            -- Stop while hidden to prevent creating rows during reveal baseline capture
            self:stopPeriodicUpdate()
        end
    end))
    
    log:info("MetricsTab created successfully")
    
    -- Subscribe to metrics pushes (EventBus path)
    self._unsubs = {}
    table.insert(self._unsubs, Bus:on(EventNames.METRICS_UPDATED, function(metrics)
        if type(metrics) == "table" then
            pcall(function() self:_applyUserMetrics(metrics) end)
        end
    end))
    
    -- Persistently listen for server metrics pushes as well (store latest, update UI)
    table.insert(self._unsubs, Bus:on(EventNames.SERVER_METRICS_UPDATED, function(serverMetrics)
        if type(serverMetrics) == "table" then
            -- Avoid mutating UI while hidden (reveal baseline stays valid)
            if self.container and self.container.Visible then
                pcall(function() self:_applyServerMetrics(serverMetrics) end)
            end
        end
    end))
    return self :: any
end

function MetricsTab:_createRefreshButton()
    self._refreshButton = self:createButton(
        self.container, 
        "🔄 Refresh Metrics",
        function() self:refresh() end,
        { primary = true }
    )
end

function MetricsTab:_createMetricsSection(title: string, fields: {string}, icon: string?)
    -- Create section card using base component
    local card = self:createSectionCard(self.container, {})
    
    -- Title with icon
    local titleText = (icon and (icon .. " ") or "") .. title .. " Statistics"
    self:createSectionTitle(card, titleText)
    
    -- Fields container for better layout control
    local fieldsContainer = Instance.new("Frame")
    fieldsContainer.Name = "Fields"
    fieldsContainer.Size = UDim2.new(1, 0, 0, 0)
    fieldsContainer.BackgroundTransparency = 1
    fieldsContainer.AutomaticSize = Enum.AutomaticSize.Y
    fieldsContainer.Parent = card
    
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.Padding = UDim.new(0, UIx.Spacing.TINY)
    layout.Parent = fieldsContainer
    
    -- Create field rows using base component's method
    for _, field in ipairs(fields) do
        local displayName = self:_formatFieldName(field)
        local labelKey = title:lower() .. "_" .. field
        local row, _, valueLabel = self:createFieldRow(fieldsContainer, field, displayName)
        self._labels[labelKey] = valueLabel
    end
end

function MetricsTab:_createServerSection()
    -- Create section card using base component
    local card = self:createSectionCard(self.container, {})
    
    -- Title
    self:createSectionTitle(card, "🌐 Server Metrics")
    
    -- Fields container for server metrics
    local fieldsContainer = Instance.new("Frame")
    fieldsContainer.Name = "Fields"
    fieldsContainer.Size = UDim2.new(1, 0, 0, 0)
    fieldsContainer.BackgroundTransparency = 1
    fieldsContainer.AutomaticSize = Enum.AutomaticSize.Y
    fieldsContainer.Parent = card
    
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.Padding = UDim.new(0, UIx.Spacing.TINY)
    layout.Parent = fieldsContainer
    
    -- Placeholder text while loading
    local placeholder = self:createLabel(fieldsContainer, "Loading server metrics...", {
        position = UDim2.new(0, UIx.Spacing.INPUT_MARGIN, 0, 0),
        size = UDim2.new(1, -(UIx.Spacing.INPUT_MARGIN * 2), 0, UIx.Size.ROW_LABEL),
        alignment = Enum.TextXAlignment.Left
    })
    placeholder.Name = "Placeholder"
    
    self._serverFieldsContainer = fieldsContainer
    self._serverPlaceholder = placeholder
end

function MetricsTab:refresh()
    if self._refreshing then return end
    self._refreshing = true
    
    log:debug("Refreshing metrics...")
    
    if self._refreshButton then
        self._refreshButton.Text = "⏳ Refreshing..."
    end
    
    -- Track pending async calls
    local pending = 2
    local function doneOne()
        pending -= 1
        if pending == 0 then
            self._refreshing = false
            if self._refreshButton then
                self._refreshButton.Text = "🔄 Refresh Metrics"
            end
        end
    end
    
    -- Fetch user metrics via EventBus: request + wait for push (fallback timeout)
    task.spawn(function()
        local received = false
        -- One-shot waiter to count completion; UI updates handled by persistent subscriber
        local off
        off = Bus:on(EventNames.METRICS_UPDATED, function(_)
            received = true
            if off then pcall(off) end
            doneOne()
        end)
        RemoteEventBridge.requestMetrics()
        task.delay(1.5, function()
            if not received then
                if off then pcall(off) end
                if self._errorBanner and self._errorBanner.show then
                    self._errorBanner.show("Metrics request timed out", true)
                end
                doneOne()
            end
        end)
    end)
    
    -- Fetch server metrics via EventBus: request + wait for push (fallback timeout)
    task.spawn(function()
        local received = false
        local off
        off = Bus:on(EventNames.SERVER_METRICS_UPDATED, function(serverMetrics)
            received = true
            if off then pcall(off) end
            self:_applyServerMetrics(serverMetrics)
            doneOne()
        end)
        RemoteEventBridge.requestServerMetrics()
        task.delay(1.5, function()
            if not received then
                if off then pcall(off) end
                if self._serverPlaceholder then
                    self._serverPlaceholder.Text = "Failed to load server metrics"
                end
                doneOne()
            end
    end)
    end)
end

-- Apply server metrics payload to UI (handles placeholder, rows, and pruning)
function MetricsTab:_applyServerMetrics(serverMetrics: any)
    if not (self._serverFieldsContainer and type(serverMetrics) == "table") then return end
    -- If server metrics are intentionally unavailable (non-Studio), show message and skip pruning
    if serverMetrics.visible == false then
        if self._serverPlaceholder then
            self._serverPlaceholder.Text = "Server metrics unavailable"
        else
            local msg = self:createLabel(self._serverFieldsContainer, "Server metrics unavailable", {
                position = UDim2.new(0, UIx.Spacing.INPUT_MARGIN, 0, 0),
                size = UDim2.new(1, -(UIx.Spacing.INPUT_MARGIN * 2), 0, UIx.Size.ROW_LABEL),
                alignment = Enum.TextXAlignment.Left
            })
            msg.Name = "NoData"
        end
        return
    end
    
    -- Clear placeholder on first successful load
    if self._serverPlaceholder then
        self._serverPlaceholder:Destroy()
        self._serverPlaceholder = nil
    end
    
    -- Track which keys we've seen this refresh
    local seen = {}
    for key, value in pairs(serverMetrics) do
        if key ~= "ok" and key ~= "success" and key ~= "err" and key ~= "visible" then
            self:_upsertServerRow(key, value)
            seen[key] = true
        end
    end
    
    -- Prune stale rows that weren't present in this payload
    for labelKey, valueLabel in pairs(self._labels) do
        local serverKey = labelKey:match("^server_(.+)$")
        if serverKey and not seen[serverKey] then
            if valueLabel and valueLabel.Parent then valueLabel.Parent:Destroy() end
            self._labels[labelKey] = nil
        end
    end
    
    -- If nothing visible, show "No data"
    local hasMetrics = false
    for k, _ in pairs(serverMetrics) do
        if k ~= "ok" and k ~= "success" and k ~= "err" and k ~= "visible" then hasMetrics = true; break end
    end
    if not hasMetrics then
        local noData = self:createLabel(self._serverFieldsContainer, "No server metrics available", {
            position = UDim2.new(0, UIx.Spacing.INPUT_MARGIN, 0, 0),
            size = UDim2.new(1, -(UIx.Spacing.INPUT_MARGIN * 2), 0, UIx.Size.ROW_LABEL),
            alignment = Enum.TextXAlignment.Left
        })
        noData.Name = "NoData"
    end
end

-- Upsert a server metric row (create or update)
function MetricsTab:_upsertServerRow(key: string, value: any)
    local labelKey = "server_" .. key
    local valueLabel = self._labels[labelKey]
    
    if not valueLabel then
        -- Create new row using base component
        local displayName = self:_formatFieldName(key)
        local row, leftLabel, newValueLabel = self:createFieldRow(self._serverFieldsContainer, key, displayName)
        -- Ensure both labels are visible (avoid lingering hidden state from panel hide)
        if leftLabel then
            leftLabel.TextTransparency = 0
            leftLabel.TextStrokeTransparency = 1
        end
        newValueLabel.TextTransparency = 0
        newValueLabel.TextStrokeTransparency = 1
        self._labels[labelKey] = newValueLabel
        valueLabel = newValueLabel
    else
        -- Also ensure left label is visible for existing rows
        local row = valueLabel.Parent
        if row and row:IsA("Frame") then
            for _, c in ipairs(row:GetChildren()) do
                if c:IsA("TextLabel") and c ~= valueLabel then
                    c.TextTransparency = 0
                    c.TextStrokeTransparency = 1
                    break
                end
            end
        end
    end
    
    -- Update the value
    valueLabel.Text = self:_formatMetricValue(key, value)
end

-- Format field names consistently
function MetricsTab:_formatFieldName(fieldName: string): string
    return fieldName
        :gsub("(%l)(%u)", "%1 %2")  -- Add space before capitals
        :gsub("^%l", string.upper)  -- Capitalize first letter
        :gsub("_", " ")  -- Replace underscores with spaces
        :gsub("Per", " Per")
        :gsub("Sec", " (sec)")
        :gsub("Earned", " Earned")
        :gsub("Spent", " Spent")
end

-- Format metric values based on type and context
function MetricsTab:_formatMetricValue(key: string, value: any): string
    if type(value) == "number" then
        local keyLower = key:lower()
        
        -- Rates per minute/second
        if keyLower:find("perminute") or keyLower:find("per_minute") or keyLower:find("blocksperminute") then
            return string.format("%.1f", value)
        elseif keyLower:find("persecond") or keyLower:find("per_second") then
            return string.format("%.2f", value)
        
        -- Percentages
        elseif keyLower:find("rate") or keyLower:find("percent") then
            return string.format("%.1f%%", value * 100)
        
        -- Time durations and timestamps
        elseif keyLower:find("time") and not keyLower:find("lifetime") then
            if keyLower:find("start") or keyLower:find("first") or keyLower:find("last") then
                return os.date("%X", value)
            elseif keyLower:find("hours") then
                -- Convert hours to hours+minutes format
                local totalMinutes = math.floor(value * 60)
                local hours = math.floor(totalMinutes / 60)
                local minutes = totalMinutes % 60
                if hours > 0 then
                    return string.format("%dh %dm", hours, minutes)
                else
                    return string.format("%dm", minutes)
                end
            else
                return self:_formatDuration(value)
            end
        elseif keyLower:find("sec") or keyLower:find("seconds") then
            return self:_formatDuration(value)
        elseif keyLower:find("dayssince") then
            -- Days since values should show as plain numbers with "days" suffix
            return string.format("%d days", math.floor(value))
        
        -- Currency and counts - use UIUtils for consistent formatting
        elseif UIUtils and UIUtils.formatNumber then
            return UIUtils.formatNumber(value)
        
        -- Fallback formatting
        else
            return tostring(math.floor(value + 0.5))
        end
    elseif type(value) == "boolean" then
        return value and "✅" or "❌"
    else
        return tostring(value)
    end
end

-- Format duration in seconds to human-readable format
function MetricsTab:_formatDuration(seconds: number): string
    if seconds < 60 then
        return string.format("%ds", math.floor(seconds))
    elseif seconds < 3600 then
        local minutes = math.floor(seconds / 60)
        local secs = math.floor(seconds % 60)
        return string.format("%dm %ds", minutes, secs)
    else
        local hours = math.floor(seconds / 3600)
        local minutes = math.floor((seconds % 3600) / 60)
        return string.format("%dh %dm", hours, minutes)
    end
end

function MetricsTab:_updateValue(key: string, value: any)
    local label = self._labels[key]
    if label then
        label.Text = tostring(value)
    end
end

-- Override destroy to handle tab-specific cleanup
function MetricsTab:destroy()
    -- Clean up tab-specific state
    self._serverFieldsContainer = nil
    self._serverPlaceholder = nil
    self._refreshButton = nil
    -- no RF fallbacks
    if self._unsubs then
        for _, u in ipairs(self._unsubs) do pcall(u) end
        self._unsubs = nil
    end
    
    -- Call base destroy (handles periodic updates, connections, container)
    BaseTabComponent.destroy(self)
end

-- Apply user metrics payload to UI (shared by EventBus push and any fallback calls)
function MetricsTab:_applyUserMetrics(metrics: any)
    if not metrics or type(metrics) ~= "table" then return end
    -- Gameplay
    if metrics.gameplay then
        self:_updateValue("gameplay_totalBlocksDug", self:_formatMetricValue("totalBlocksDug", metrics.gameplay.totalBlocksDug))
        self:_updateValue("gameplay_dugThisSession", self:_formatMetricValue("dugThisSession", metrics.gameplay.dugThisSession))
        self:_updateValue("gameplay_blocksPerMinute", self:_formatMetricValue("blocksPerMinute", metrics.gameplay.blocksPerMinute))
    end
    -- Economy
    if metrics.economy then
        self:_updateValue("economy_coins", self:_formatMetricValue("coins", metrics.economy.coins))
        self:_updateValue("economy_gems", self:_formatMetricValue("gems", metrics.economy.gems))
        self:_updateValue("economy_totalCoinsEarned", self:_formatMetricValue("totalCoinsEarned", metrics.economy.totalCoinsEarned))
        self:_updateValue("economy_totalCoinsSpent", self:_formatMetricValue("totalCoinsSpent", metrics.economy.totalCoinsSpent))
        self:_updateValue("economy_totalGemsEarned", self:_formatMetricValue("totalGemsEarned", metrics.economy.totalGemsEarned))
        self:_updateValue("economy_totalGemsSpent", self:_formatMetricValue("totalGemsSpent", metrics.economy.totalGemsSpent))
        self:_updateValue("economy_netWorth", self:_formatMetricValue("netWorth", metrics.economy.netWorth))
    end
    -- Session
    if metrics.session then
        self:_updateValue("session_sessionStartTime", self:_formatMetricValue("sessionStartTime", metrics.session.sessionStartTime))
        self:_updateValue("session_sessionDurationSec", self:_formatMetricValue("sessionDurationSec", metrics.session.sessionDurationSec))
        self:_updateValue("session_totalPlaytimeSec", self:_formatMetricValue("totalPlaytimeSec", metrics.session.totalPlaytimeSec))
        self:_updateValue("session_totalSessions", self:_formatMetricValue("totalSessions", metrics.session.totalSessions))
        self:_updateValue("session_avgSessionLengthSec", self:_formatMetricValue("avgSessionLengthSec", metrics.session.avgSessionLengthSec))
    end
    -- Lifecycle
    if metrics.lifecycle then
        self:_updateValue("lifecycle_isNewPlayer", self:_formatMetricValue("isNewPlayer", metrics.lifecycle.isNewPlayer))
        self:_updateValue("lifecycle_isReturningPlayer", self:_formatMetricValue("isReturningPlayer", metrics.lifecycle.isReturningPlayer))
        self:_updateValue("lifecycle_isFirstDigEver", self:_formatMetricValue("isFirstDigEver", metrics.lifecycle.isFirstDigEver))
        self:_updateValue("lifecycle_hasDugEver", self:_formatMetricValue("hasDugEver", metrics.lifecycle.hasDugEver))
        self:_updateValue("lifecycle_hasDugThisSession", self:_formatMetricValue("hasDugThisSession", metrics.lifecycle.hasDugThisSession))
        self:_updateValue("lifecycle_firstPlayTime", metrics.lifecycle.firstPlayTime and self:_formatMetricValue("firstPlayTime", metrics.lifecycle.firstPlayTime) or "N/A")
        self:_updateValue("lifecycle_firstDigTime", metrics.lifecycle.firstDigTime and self:_formatMetricValue("firstDigTime", metrics.lifecycle.firstDigTime) or "Never")
    end
    -- Progression
    if metrics.progression then
        self:_updateValue("progression_speedLevel", self:_formatMetricValue("speedLevel", metrics.progression.speedLevel))
        self:_updateValue("progression_sizeLevel", self:_formatMetricValue("sizeLevel", metrics.progression.sizeLevel))
        self:_updateValue("progression_petsOwned", self:_formatMetricValue("petsOwned", metrics.progression.petsOwned))
        self:_updateValue("progression_activePets", self:_formatMetricValue("activePets", metrics.progression.activePets))
        self:_updateValue("progression_materialTier", self:_formatMetricValue("materialTier", metrics.progression.materialTier))
    end
    -- Monetization
    if metrics.monetization then
        self:_updateValue("monetization_robuxSpentLifetime", self:_formatMetricValue("robuxSpentLifetime", metrics.monetization.robuxSpentLifetime or 0))
        self:_updateValue("monetization_robuxSpentThisSession", self:_formatMetricValue("robuxSpentThisSession", metrics.monetization.robuxSpentThisSession or 0))
        self:_updateValue("monetization_purchasesCount", self:_formatMetricValue("purchasesCount", metrics.monetization.purchasesCount or 0))
        self:_updateValue("monetization_devProducts", self:_formatMetricValue("devProducts", metrics.monetization.devProducts or 0))
        self:_updateValue("monetization_gamePasses", self:_formatMetricValue("gamePasses", metrics.monetization.gamePasses or 0))
        self:_updateValue("monetization_isPayingUser", self:_formatMetricValue("isPayingUser", metrics.monetization.isPayingUser or false))
        self:_updateValue("monetization_daysSinceLastPurchase", metrics.monetization.daysSinceLastPurchase and self:_formatMetricValue("daysSinceLastPurchase", metrics.monetization.daysSinceLastPurchase) or "N/A")
    end
end

return MetricsTab

