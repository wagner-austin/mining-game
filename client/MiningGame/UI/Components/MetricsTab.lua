--!strict
-- MetricsTab.lua - Shows real-time user metrics for monitoring and debugging
-- Migrated to use BaseTabComponent for consistent UI patterns

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UIFolder = MiningGame:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))
local Logger = require(MiningGame:WaitForChild("Logger"))
local ClientRF = require(MiningGame:WaitForChild("ClientRF"))
local UIConstants = require(UIFolder:WaitForChild("UIConstants"))

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
    
    -- No need to get remotes directly anymore - ClientRF handles it
    
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
    
    -- Use base component's periodic update for auto-refresh
    self:startPeriodicUpdate(2, function()
        self:refresh()
    end)
    
    log:info("MetricsTab created successfully")
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
    
    -- Fetch user metrics
    task.spawn(function()
        log:debug("Invoking GetMetrics...")
        local metrics, err = ClientRF.call("GetMetrics")
        
        log:debug("GetMetrics result - Error: %s, Has metrics: %s", tostring(err), tostring(metrics ~= nil))
        
        if not err and metrics then
            log:debug("Updating UI with metrics")
            -- Update gameplay
            self:_updateValue("gameplay_totalBlocksDug", self:_formatMetricValue("totalBlocksDug", metrics.gameplay.totalBlocksDug))
            self:_updateValue("gameplay_dugThisSession", self:_formatMetricValue("dugThisSession", metrics.gameplay.dugThisSession))
            self:_updateValue("gameplay_blocksPerMinute", self:_formatMetricValue("blocksPerMinute", metrics.gameplay.blocksPerMinute))
            
            -- Update economy
            self:_updateValue("economy_coins", self:_formatMetricValue("coins", metrics.economy.coins))
            self:_updateValue("economy_gems", self:_formatMetricValue("gems", metrics.economy.gems))
            self:_updateValue("economy_totalCoinsEarned", self:_formatMetricValue("totalCoinsEarned", metrics.economy.totalCoinsEarned))
            self:_updateValue("economy_totalCoinsSpent", self:_formatMetricValue("totalCoinsSpent", metrics.economy.totalCoinsSpent))
            self:_updateValue("economy_totalGemsEarned", self:_formatMetricValue("totalGemsEarned", metrics.economy.totalGemsEarned))
            self:_updateValue("economy_totalGemsSpent", self:_formatMetricValue("totalGemsSpent", metrics.economy.totalGemsSpent))
            self:_updateValue("economy_netWorth", self:_formatMetricValue("netWorth", metrics.economy.netWorth))
            
            -- Update session
            self:_updateValue("session_sessionStartTime", self:_formatMetricValue("sessionStartTime", metrics.session.sessionStartTime))
            self:_updateValue("session_sessionDurationSec", self:_formatMetricValue("sessionDurationSec", metrics.session.sessionDurationSec))
            self:_updateValue("session_totalPlaytimeSec", self:_formatMetricValue("totalPlaytimeSec", metrics.session.totalPlaytimeSec))
            self:_updateValue("session_totalSessions", self:_formatMetricValue("totalSessions", metrics.session.totalSessions))
            self:_updateValue("session_avgSessionLengthSec", self:_formatMetricValue("avgSessionLengthSec", metrics.session.avgSessionLengthSec))
            
            -- Update lifecycle (if present)
            if metrics.lifecycle then
                self:_updateValue("lifecycle_isNewPlayer", self:_formatMetricValue("isNewPlayer", metrics.lifecycle.isNewPlayer))
                self:_updateValue("lifecycle_isReturningPlayer", self:_formatMetricValue("isReturningPlayer", metrics.lifecycle.isReturningPlayer))
                self:_updateValue("lifecycle_isFirstDigEver", self:_formatMetricValue("isFirstDigEver", metrics.lifecycle.isFirstDigEver))
                self:_updateValue("lifecycle_hasDugEver", self:_formatMetricValue("hasDugEver", metrics.lifecycle.hasDugEver))
                self:_updateValue("lifecycle_hasDugThisSession", self:_formatMetricValue("hasDugThisSession", metrics.lifecycle.hasDugThisSession))
                self:_updateValue("lifecycle_firstPlayTime", metrics.lifecycle.firstPlayTime and self:_formatMetricValue("firstPlayTime", metrics.lifecycle.firstPlayTime) or "N/A")
                self:_updateValue("lifecycle_firstDigTime", metrics.lifecycle.firstDigTime and self:_formatMetricValue("firstDigTime", metrics.lifecycle.firstDigTime) or "Never")
            end
            
            -- Update progression
            self:_updateValue("progression_speedLevel", self:_formatMetricValue("speedLevel", metrics.progression.speedLevel))
            self:_updateValue("progression_sizeLevel", self:_formatMetricValue("sizeLevel", metrics.progression.sizeLevel))
            self:_updateValue("progression_petsOwned", self:_formatMetricValue("petsOwned", metrics.progression.petsOwned))
            self:_updateValue("progression_activePets", self:_formatMetricValue("activePets", metrics.progression.activePets))
            self:_updateValue("progression_materialTier", self:_formatMetricValue("materialTier", metrics.progression.materialTier))
            
            -- Update monetization (if present)
            if metrics.monetization then
                self:_updateValue("monetization_robuxSpentLifetime", self:_formatMetricValue("robuxSpentLifetime", metrics.monetization.robuxSpentLifetime or 0))
                self:_updateValue("monetization_robuxSpentThisSession", self:_formatMetricValue("robuxSpentThisSession", metrics.monetization.robuxSpentThisSession or 0))
                self:_updateValue("monetization_purchasesCount", self:_formatMetricValue("purchasesCount", metrics.monetization.purchasesCount or 0))
                self:_updateValue("monetization_devProducts", self:_formatMetricValue("devProducts", metrics.monetization.devProducts or 0))
                self:_updateValue("monetization_gamePasses", self:_formatMetricValue("gamePasses", metrics.monetization.gamePasses or 0))
                self:_updateValue("monetization_isPayingUser", self:_formatMetricValue("isPayingUser", metrics.monetization.isPayingUser or false))
                self:_updateValue("monetization_daysSinceLastPurchase", 
                    metrics.monetization.daysSinceLastPurchase and self:_formatMetricValue("daysSinceLastPurchase", metrics.monetization.daysSinceLastPurchase) or "N/A")
            end
        else
            log:warn("Failed to get metrics: %s", tostring(err or "Unknown error"))
            if self._errorBanner and self._errorBanner.show then
                self._errorBanner.show("Failed to load metrics: " .. tostring(err or "Unknown error"), true)
            end
        end
        doneOne()
    end)
    
    -- Fetch server metrics
    task.spawn(function()
        local serverMetrics, err = ClientRF.call("GetServerMetrics")
        
        if not err and serverMetrics and self._serverFieldsContainer then
            -- Clear placeholder on first successful load
            if self._serverPlaceholder then
                self._serverPlaceholder:Destroy()
                self._serverPlaceholder = nil
            end
            
            -- Track which keys we've seen this refresh
            local seen = {}
            
            -- Upsert each metric (skip metadata fields)
            for key, value in pairs(serverMetrics) do
                -- Skip metadata fields that aren't actual metrics
                if key ~= "ok" and key ~= "success" and key ~= "err" and key ~= "visible" then
                    self:_upsertServerRow(key, value)
                    seen[key] = true
                end
            end
            
            -- Prune stale server metrics
            for labelKey, valueLabel in pairs(self._labels) do
                local serverKey = labelKey:match("^server_(.+)$")
                if serverKey and not seen[serverKey] then
                    -- Remove the entire row
                    if valueLabel and valueLabel.Parent then
                        valueLabel.Parent:Destroy()
                    end
                    self._labels[labelKey] = nil
                end
            end
            
            -- If no metrics, show a message
            local hasMetrics = false
            for _ in pairs(serverMetrics) do
                hasMetrics = true
                break
            end
            
            if not hasMetrics then
                local noData = self:createLabel(self._serverFieldsContainer, "No server metrics available", {
                    position = UDim2.new(0, UIx.Spacing.INPUT_MARGIN, 0, 0),
                    size = UDim2.new(1, -(UIx.Spacing.INPUT_MARGIN * 2), 0, UIx.Size.ROW_LABEL),
                    alignment = Enum.TextXAlignment.Left
                })
                noData.Name = "NoData"
            end
        elseif self._serverPlaceholder then
            self._serverPlaceholder.Text = "Failed to load server metrics"
        end
        doneOne()
    end)
end

-- Upsert a server metric row (create or update)
function MetricsTab:_upsertServerRow(key: string, value: any)
    local labelKey = "server_" .. key
    local valueLabel = self._labels[labelKey]
    
    if not valueLabel then
        -- Create new row using base component
        local displayName = self:_formatFieldName(key)
        local row, _, newValueLabel = self:createFieldRow(self._serverFieldsContainer, key, displayName)
        self._labels[labelKey] = newValueLabel
        valueLabel = newValueLabel
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
    self._getMetrics = nil
    self._getServerMetrics = nil
    
    -- Call base destroy (handles periodic updates, connections, container)
    BaseTabComponent.destroy(self)
end

return MetricsTab
