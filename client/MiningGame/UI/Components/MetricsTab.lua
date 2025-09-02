--!strict
-- MetricsTab.lua - Shows real-time user metrics for monitoring and debugging

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UIFolder = MiningGame:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))
local Logger = require(MiningGame:WaitForChild("Logger"))

-- UIUtils is optional; guard in case the module doesn't exist
local uiUtilsModule = UIFolder:FindFirstChild("UIUtils")
local UIUtils = uiUtilsModule and require(uiUtilsModule) or nil

local log = Logger.new("MetricsTab")

local MetricsTab = {}
MetricsTab.__index = MetricsTab

type Props = {
    parent: GuiObject,
    position: UDim2?,
    size: UDim2?,
}

function MetricsTab.new(props: Props)
    local self = setmetatable({}, MetricsTab)
    
    local colors = Theme.colors
    self._connections = {}
    self._labels = {}
    self._refreshing = false
    self._autoRefresh = true
    
    -- Get remotes
    local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
    local miningGameFolder = remotesFolder:WaitForChild("MiningGame")
    self._getMetrics = miningGameFolder:WaitForChild("GetMetrics")
    self._getServerMetrics = miningGameFolder:WaitForChild("GetServerMetrics")
    
    -- Main container (using Frame with AutomaticSize like AccountTab)
    local container = Instance.new("Frame")
    container.Name = "MetricsTab"
    container.Size = props.size or UDim2.new(1, 0, 0, 0)
    container.Position = props.position or UDim2.new(0, 0, 0, 0)
    container.AutomaticSize = Enum.AutomaticSize.Y
    container.BackgroundTransparency = 1
    container.Parent = props.parent
    self.container = container
    
    -- Stack sections vertically
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.Padding = UDim.new(0, 16)
    layout.Parent = container
    
    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 12)
    padding.PaddingBottom = UDim.new(0, 12)
    padding.PaddingLeft = UDim.new(0, 16)
    padding.PaddingRight = UDim.new(0, 16)
    padding.Parent = container
    
    -- Create sections
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
    
    -- Auto-refresh every 2 seconds
    task.spawn(function()
        while self.container and self.container.Parent do
            task.wait(2)
            self:refresh()
        end
    end)
    
    log:info("MetricsTab created successfully")
    return self
end

function MetricsTab:_createRefreshButton()
    local colors = Theme.colors
    
    local button = Instance.new("TextButton")
    button.Name = "RefreshButton"
    button.Size = UDim2.new(1, 0, 0, 40)
    button.BackgroundColor3 = colors.Primary
    button.BackgroundTransparency = Theme.button.primaryTransparency
    button.Text = "🔄 Refresh Metrics"
    button.TextColor3 = colors.Text
    button.Font = Theme.fonts.Primary
    button.TextSize = 16
    button.Parent = self.container
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, Theme.sizes.CornerRadius)
    corner.Parent = button
    
    button.Activated:Connect(function()
        self:refresh()
    end)
    
    self._refreshButton = button
end

function MetricsTab:_createMetricsSection(title: string, fields: {string}, icon: string?)
    local colors = Theme.colors
    
    -- Section card
    local card = Instance.new("Frame")
    card.Name = title .. "Section"
    card.Size = UDim2.new(1, 0, 0, 0)
    card.AutomaticSize = Enum.AutomaticSize.Y
    card.BackgroundColor3 = colors.Surface
    card.BackgroundTransparency = Theme.card.backgroundTransparency
    card.Parent = self.container
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, Theme.sizes.CornerRadius)
    corner.Parent = card
    
    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 12)
    padding.PaddingBottom = UDim.new(0, 12)
    padding.PaddingLeft = UDim.new(0, 16)
    padding.PaddingRight = UDim.new(0, 16)
    padding.Parent = card
    
    -- Title with icon
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(1, 0, 0, 24)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = (icon and (icon .. " ") or "") .. title .. " Statistics"
    titleLabel.TextColor3 = colors.Text  -- Use primary text for better visibility
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Font = Theme.fonts.Primary
    titleLabel.TextSize = 18  -- Slightly bigger
    titleLabel.Parent = card
    
    -- Fields container
    local fieldsContainer = Instance.new("Frame")
    fieldsContainer.Name = "Fields"
    fieldsContainer.Size = UDim2.new(1, 0, 0, 0)
    fieldsContainer.Position = UDim2.new(0, 0, 0, 30)
    fieldsContainer.BackgroundTransparency = 1
    fieldsContainer.AutomaticSize = Enum.AutomaticSize.Y
    fieldsContainer.Parent = card
    
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.Padding = UDim.new(0, 4)
    layout.Parent = fieldsContainer
    
    -- Create field labels using helper method (DRY)
    for _, field in ipairs(fields) do
        local displayName = self:_formatFieldName(field)
        local valueLabel = self:_createFieldRow(fieldsContainer, field, displayName)
        self._labels[title:lower() .. "_" .. field] = valueLabel
    end
end

function MetricsTab:_createServerSection()
    local colors = Theme.colors
    
    -- Section card
    local card = Instance.new("Frame")
    card.Name = "ServerSection"
    card.Size = UDim2.new(1, 0, 0, 0)
    card.AutomaticSize = Enum.AutomaticSize.Y
    card.BackgroundColor3 = colors.Surface
    card.BackgroundTransparency = Theme.card.backgroundTransparency
    card.Parent = self.container
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, Theme.sizes.CornerRadius)
    corner.Parent = card
    
    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 12)
    padding.PaddingBottom = UDim.new(0, 12)
    padding.PaddingLeft = UDim.new(0, 16)
    padding.PaddingRight = UDim.new(0, 16)
    padding.Parent = card
    
    -- Title with icon
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(1, 0, 0, 24)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "🌐 Server Metrics"
    titleLabel.TextColor3 = colors.Text
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Font = Theme.fonts.Primary
    titleLabel.TextSize = 18
    titleLabel.Parent = card
    
    -- Fields container (like other sections)
    local fieldsContainer = Instance.new("Frame")
    fieldsContainer.Name = "Fields"
    fieldsContainer.Size = UDim2.new(1, 0, 0, 0)
    fieldsContainer.Position = UDim2.new(0, 0, 0, 30)
    fieldsContainer.BackgroundTransparency = 1
    fieldsContainer.AutomaticSize = Enum.AutomaticSize.Y
    fieldsContainer.Parent = card
    
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.Padding = UDim.new(0, 4)
    layout.Parent = fieldsContainer
    
    -- Placeholder text while loading
    local placeholder = Instance.new("TextLabel")
    placeholder.Name = "Placeholder"
    placeholder.Size = UDim2.new(1, -40, 0, 22)
    placeholder.Position = UDim2.new(0, 20, 0, 0)
    placeholder.BackgroundTransparency = 1
    placeholder.Text = "Loading server metrics..."
    placeholder.TextColor3 = colors.Text
    placeholder.TextXAlignment = Enum.TextXAlignment.Left
    placeholder.Font = Theme.fonts.Primary
    placeholder.TextSize = 16
    placeholder.Parent = fieldsContainer
    
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
    
    -- Fetch user metrics
    task.spawn(function()
        log:debug("Invoking GetMetrics...")
        local success, metrics = pcall(function()
            return self._getMetrics:InvokeServer()
        end)
        
        log:debug("GetMetrics result - Success: %s, Has metrics: %s", tostring(success), tostring(metrics ~= nil))
        
        if success and metrics then
            log:debug("Updating UI with metrics")
            -- Update gameplay
            self:_updateValue("gameplay_totalBlocksDug", self:_formatMetricValue("totalBlocksDug", metrics.gameplay.totalBlocksDug))
            self:_updateValue("gameplay_dugThisSession", self:_formatMetricValue("dugThisSession", metrics.gameplay.dugThisSession))
            self:_updateValue("gameplay_blocksPerMinute", self:_formatMetricValue("blocksPerMinute", metrics.gameplay.blocksPerMinute))
            
            -- Update economy - use consistent formatting
            self:_updateValue("economy_coins", self:_formatMetricValue("coins", metrics.economy.coins))
            self:_updateValue("economy_gems", self:_formatMetricValue("gems", metrics.economy.gems))
            self:_updateValue("economy_totalCoinsEarned", self:_formatMetricValue("totalCoinsEarned", metrics.economy.totalCoinsEarned))
            self:_updateValue("economy_totalCoinsSpent", self:_formatMetricValue("totalCoinsSpent", metrics.economy.totalCoinsSpent))
            self:_updateValue("economy_totalGemsEarned", self:_formatMetricValue("totalGemsEarned", metrics.economy.totalGemsEarned))
            self:_updateValue("economy_totalGemsSpent", self:_formatMetricValue("totalGemsSpent", metrics.economy.totalGemsSpent))
            self:_updateValue("economy_netWorth", self:_formatMetricValue("netWorth", metrics.economy.netWorth))
            
            -- Update session - use consistent time formatting
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
            
            -- Update progression - use consistent formatting
            self:_updateValue("progression_speedLevel", self:_formatMetricValue("speedLevel", metrics.progression.speedLevel))
            self:_updateValue("progression_sizeLevel", self:_formatMetricValue("sizeLevel", metrics.progression.sizeLevel))
            self:_updateValue("progression_petsOwned", self:_formatMetricValue("petsOwned", metrics.progression.petsOwned))
            self:_updateValue("progression_activePets", self:_formatMetricValue("activePets", metrics.progression.activePets))
            self:_updateValue("progression_materialTier", self:_formatMetricValue("materialTier", metrics.progression.materialTier))
            
            -- Update monetization (if present) - use consistent formatting
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
            log:warn("Failed to get metrics: %s", tostring(metrics))
        end
    end)
    
    -- Fetch server metrics
    task.spawn(function()
        local success, serverMetrics = pcall(function()
            return self._getServerMetrics:InvokeServer()
        end)
        
        if success and serverMetrics and self._serverFieldsContainer then
            -- Clear placeholder on first successful load
            if self._serverPlaceholder then
                self._serverPlaceholder:Destroy()
                self._serverPlaceholder = nil
            end
            
            -- Track which keys we've seen this refresh
            local seen = {}
            
            -- Upsert each metric
            for key, value in pairs(serverMetrics) do
                self:_upsertServerRow(key, value)
                seen[key] = true
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
                local noData = Instance.new("TextLabel")
                noData.Name = "NoData"
                noData.Size = UDim2.new(1, -40, 0, 22)
                noData.Position = UDim2.new(0, 20, 0, 0)
                noData.BackgroundTransparency = 1
                noData.Text = "No server metrics available"
                noData.TextColor3 = Theme.colors.Text
                noData.TextXAlignment = Enum.TextXAlignment.Left
                noData.Font = Theme.fonts.Primary
                noData.TextSize = 16
                noData.Parent = self._serverFieldsContainer
            end
        elseif self._serverPlaceholder then
            self._serverPlaceholder.Text = "Failed to load server metrics"
        end
    end)
    
    task.wait(0.5)
    if self._refreshButton then
        self._refreshButton.Text = "🔄 Refresh Metrics"
    end
    self._refreshing = false
end

-- Helper to create a formatted field row (DRY)
function MetricsTab:_createFieldRow(parent: Instance, fieldName: string, displayName: string): TextLabel
    local colors = Theme.colors
    
    local row = Instance.new("Frame")
    row.Name = fieldName
    row.Size = UDim2.new(1, 0, 0, 22)
    row.BackgroundTransparency = 1
    row.Parent = parent
    
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.5, -10, 1, 0)
    label.Position = UDim2.new(0, 20, 0, 0)  -- Indented
    label.BackgroundTransparency = 1
    label.Text = displayName .. ":"
    label.TextColor3 = colors.Text
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Font = Theme.fonts.Primary
    label.TextSize = 16
    label.Parent = row
    
    local value = Instance.new("TextLabel")
    value.Size = UDim2.new(0.5, -20, 1, 0)
    value.Position = UDim2.new(0.5, 10, 0, 0)
    value.BackgroundTransparency = 1
    value.Text = "—"
    value.TextColor3 = colors.Text
    value.TextXAlignment = Enum.TextXAlignment.Right
    value.Font = Theme.fonts.Primary
    value.TextSize = 16
    value.Parent = row
    
    return value
end

-- Upsert a server metric row (create or update)
function MetricsTab:_upsertServerRow(key: string, value: any)
    local labelKey = "server_" .. key
    local valueLabel = self._labels[labelKey]
    
    if not valueLabel then
        -- Create new row
        local displayName = self:_formatFieldName(key)
        valueLabel = self:_createFieldRow(self._serverFieldsContainer, key, displayName)
        self._labels[labelKey] = valueLabel
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

function MetricsTab:destroy()
    for _, conn in ipairs(self._connections) do
        if conn then conn:Disconnect() end
    end
    self._connections = {}
    
    if self.container then
        self.container:Destroy()
        self.container = nil
    end
end

return MetricsTab