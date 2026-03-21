--!strict
-- MetricsTab.lua - Shows real-time user metrics for monitoring and debugging
-- Migrated to use BaseTabComponent for consistent UI patterns

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Types = require(MiningGame:WaitForChild("Types"))
local UIFolder = MiningGame:WaitForChild("UI")
local Logger = require(MiningGame:WaitForChild("Logger"))
local UIConstants = require(UIFolder:WaitForChild("UIConstants"))
local ClientError = require(MiningGame:WaitForChild("ClientError"))
local EventBus = require(MiningGame:WaitForChild("EventBus"))
local EventNames = require(MiningGame:WaitForChild("EventNames"))
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

export type MetricsTabT = BaseTabComponent.BaseTab & {
	_refreshing: boolean,
	_autoRefresh: boolean,
	_serverFieldsContainer: Frame?,
	_serverPlaceholder: TextLabel?,
	_errorBanner: { card: Frame, label: TextLabel, show: (message: string, isError: boolean?) -> () }?,
	_errorTimeout: thread?,
	_refreshButton: TextButton?,
	_unsubs: { () -> () },
	-- local methods on this tab
	_createRefreshButton: (self: MetricsTabT) -> (),
	_createMetricsSection: (self: MetricsTabT, title: string, fields: { string }, icon: string?) -> (),
	_createServerSection: (self: MetricsTabT) -> (),
	refresh: (self: MetricsTabT) -> (),
	new: (props: Props) -> MetricsTabT,
	-- Base helper method signatures (declared for analyzer visibility)
	createStatusBanner: (
		self: MetricsTabT,
		parent: Instance?
	) -> { card: Frame, label: TextLabel, show: (message: string, isError: boolean?) -> () },
	createButton: (
		self: MetricsTabT,
		parent: Frame,
		text: string,
		onClick: () -> (),
		options: {
			isDanger: boolean?,
			primary: boolean?,
			variant: BaseTabComponent.ButtonVariant?,
			position: UDim2?,
			size: UDim2?,
			width: number?,
			layoutOrder: number?,
		}?
	) -> TextButton,
	createSectionCard: (
		self: MetricsTabT,
		parent: Instance,
		options: { name: string?, size: UDim2?, autoSize: boolean?, layoutOrder: number? }?
	) -> Frame,
	createSectionTitle: (
		self: MetricsTabT,
		parent: Frame,
		text: string,
		icon: string?,
		sizeOverride: number?
	) -> TextLabel,
	createLabel: (
		self: MetricsTabT,
		parent: Frame,
		text: string,
		options: {
			isDim: boolean?,
			size: UDim2?,
			position: UDim2?,
			textSize: number?,
			align: Enum.TextXAlignment?,
			alignment: Enum.TextXAlignment?,
			wrap: boolean?,
			layoutOrder: number?,
		}?
	) -> TextLabel,
	createFieldRow: (
		self: MetricsTabT,
		parent: Instance,
		fieldName: string,
		displayName: string
	) -> (Frame, TextLabel, TextLabel),
	startPeriodicUpdate: (self: MetricsTabT, interval: number, updateFunc: () -> ()) -> (),
	stopPeriodicUpdate: (self: MetricsTabT) -> (),
	addConnection: (self: MetricsTabT, connection: RBXScriptConnection) -> (),
	-- private helpers used by this tab
	_updateValue: (self: MetricsTabT, key: string, value: string) -> (),
	_formatFieldName: (self: MetricsTabT, fieldName: string) -> string,
	_formatMetricValue: (self: MetricsTabT, key: string, value: number | string | boolean) -> string,
	_formatDuration: (self: MetricsTabT, seconds: number) -> string,
}

-- Strong client-side shape for user metrics payloads
type UserMetricsShape = {
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
	session: {
		sessionStartTime: number,
		sessionDurationSec: number,
		totalPlaytimeSec: number,
		totalSessions: number,
		avgSessionLengthSec: number,
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
	progression: {
		speedLevel: number,
		sizeLevel: number,
		petsOwned: number,
		activePets: number,
		materialTier: string,
	},
	monetization: {
		robuxSpentLifetime: number,
		robuxSpentThisSession: number,
		purchasesCount: number,
		devProducts: number,
		gamePasses: number,
		isPayingUser: boolean,
		daysSinceLastPurchase: number?,
	}?,
}

local function asNumber(v: Types.JsonValue, default: number): number
	if type(v) == "number" then
		return v
	end
	return default
end

local function asBoolean(v: Types.JsonValue, default: boolean): boolean
	if type(v) == "boolean" then
		return v
	end
	return default
end

local function asString(v: Types.JsonValue, default: string): string
	if type(v) == "string" then
		return v
	end
	return default
end

local function asOptNumber(v: Types.JsonValue): number?
	if type(v) == "number" then
		return v
	end
	return nil
end

local function getTable(v: Types.JsonValue): { [string]: Types.JsonValue }
	if type(v) == "table" then
		return (v :: any) :: { [string]: Types.JsonValue }
	end
	return {}
end

local function narrowUserMetrics(raw: { [string]: Types.JsonValue }): UserMetricsShape
	local gameplay = getTable(raw.gameplay)
	local economy = getTable(raw.economy)
	local session = getTable(raw.session)
	local lifecycle = getTable(raw.lifecycle)
	local progression = getTable(raw.progression)
	local monetization = if raw.monetization ~= nil then getTable(raw.monetization) else nil

	local m: UserMetricsShape = {
		gameplay = {
			totalBlocksDug = asNumber(gameplay.totalBlocksDug, 0),
			dugThisSession = asNumber(gameplay.dugThisSession, 0),
			blocksPerMinute = asNumber(gameplay.blocksPerMinute, 0),
		},
		economy = {
			coins = asNumber(economy.coins, 0),
			gems = asNumber(economy.gems, 0),
			totalCoinsEarned = asNumber(economy.totalCoinsEarned, 0),
			totalCoinsSpent = asNumber(economy.totalCoinsSpent, 0),
			totalGemsEarned = asNumber(economy.totalGemsEarned, 0),
			totalGemsSpent = asNumber(economy.totalGemsSpent, 0),
			netWorth = asNumber(economy.netWorth, 0),
		},
		session = {
			sessionStartTime = asNumber(session.sessionStartTime, 0),
			sessionDurationSec = asNumber(session.sessionDurationSec, 0),
			totalPlaytimeSec = asNumber(session.totalPlaytimeSec, 0),
			totalSessions = asNumber(session.totalSessions, 0),
			avgSessionLengthSec = asNumber(session.avgSessionLengthSec, 0),
		},
		lifecycle = {
			isNewPlayer = asBoolean(lifecycle.isNewPlayer, false),
			isReturningPlayer = asBoolean(lifecycle.isReturningPlayer, false),
			isFirstDigEver = asBoolean(lifecycle.isFirstDigEver, false),
			hasDugEver = asBoolean(lifecycle.hasDugEver, false),
			hasDugThisSession = asBoolean(lifecycle.hasDugThisSession, false),
			firstPlayTime = asOptNumber(lifecycle.firstPlayTime),
			firstDigTime = asOptNumber(lifecycle.firstDigTime),
		},
		progression = {
			speedLevel = asNumber(progression.speedLevel, 0),
			sizeLevel = asNumber(progression.sizeLevel, 0),
			petsOwned = asNumber(progression.petsOwned, 0),
			activePets = asNumber(progression.activePets, 0),
			materialTier = asString(progression.materialTier, "tier1"),
		},
		monetization = if monetization
			then {
				robuxSpentLifetime = asNumber(monetization.robuxSpentLifetime, 0),
				robuxSpentThisSession = asNumber(monetization.robuxSpentThisSession, 0),
				purchasesCount = asNumber(monetization.purchasesCount, 0),
				devProducts = asNumber(monetization.devProducts, 0),
				gamePasses = asNumber(monetization.gamePasses, 0),
				isPayingUser = asBoolean(monetization.isPayingUser, false),
				daysSinceLastPurchase = asOptNumber(monetization.daysSinceLastPurchase),
			}
			else nil,
	}

	return m
end

function MetricsTab.new(props: Props): MetricsTabT
	-- Construct a BaseTabComponent instance and subclass it for strong instance typing
	local baseAny: any = BaseTabComponent.new({
		parent = props.parent,
		position = props.position,
		size = props.size,
		stacked = true,
		name = "MetricsTab",
	})
	local self: MetricsTabT = setmetatable(baseAny, MetricsTab)

	-- Tab-specific state
	self._refreshing = false
	self._autoRefresh = true
	self._unsubs = {}
	self._serverFieldsContainer = nil
	self._serverPlaceholder = nil
	self._errorBanner = nil
	self._errorTimeout = nil
	self._refreshButton = nil

	-- Using EventBus push for metrics; no RF needed here
	-- Build UI
	self._errorBanner = self:createStatusBanner(nil)
	self:_createRefreshButton()
	self:_createMetricsSection("Gameplay", {
		"totalBlocksDug",
		"dugThisSession",
		"blocksPerMinute",
	}, "⛏️")
	self:_createMetricsSection("Economy", {
		"coins",
		"gems",
		"totalCoinsEarned",
		"totalCoinsSpent",
		"totalGemsEarned",
		"totalGemsSpent",
		"netWorth",
	}, "💰")
	self:_createMetricsSection("Session", {
		"sessionStartTime",
		"sessionDurationSec",
		"totalPlaytimeSec",
		"totalSessions",
		"avgSessionLengthSec",
	}, "⏱️")
	self:_createMetricsSection("Lifecycle", {
		"isNewPlayer",
		"isReturningPlayer",
		"isFirstDigEver",
		"hasDugEver",
		"hasDugThisSession",
		"firstPlayTime",
		"firstDigTime",
	}, "🔄")
	self:_createMetricsSection("Progression", {
		"speedLevel",
		"sizeLevel",
		"petsOwned",
		"activePets",
		"materialTier",
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
	if self.container then
		self:addConnection(self.container:GetPropertyChangedSignal("Visible"):Connect(function()
			if self.container and self.container.Visible then
				-- Resume periodic updates and refresh immediately when shown
				self:startPeriodicUpdate(2, function()
					self:refresh()
				end)
				self:refresh()
			else
				-- Stop while hidden to prevent creating rows during reveal baseline capture
				self:stopPeriodicUpdate()
			end
		end))
	end

	log:info("MetricsTab created successfully")

	-- Subscribe to metrics pushes (EventBus path)
	local unsubs = self._unsubs
	table.insert(
		unsubs,
		Bus:on(EventNames.METRICS_UPDATED, function(metrics)
			if type(metrics) == "table" then
				ClientError.try("MetricsTab.ApplyUserMetrics", function()
					MetricsTab._applyUserMetrics(self :: any, metrics)
				end)
			end
		end)
	)

	-- Persistently listen for server metrics pushes as well (store latest, update UI)
	local unsubs2 = self._unsubs
	table.insert(
		unsubs2,
		Bus:on(EventNames.SERVER_METRICS_UPDATED, function(serverMetrics)
			if type(serverMetrics) == "table" then
				-- Avoid mutating UI while hidden (reveal baseline stays valid)
				if self.container and self.container.Visible then
					ClientError.try("MetricsTab.ApplyServerMetrics", function()
						MetricsTab._applyServerMetrics(self :: any, serverMetrics)
					end)
				end
			end
		end)
	)
	return self
end

function MetricsTab:_createRefreshButton()
	self._refreshButton = self:createButton(self.container, "🔄 Refresh Metrics", function()
		self:refresh()
	end, { primary = true })
end

function MetricsTab:_createMetricsSection(title: string, fields: { string }, icon: string?)
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
		local _row, _, valueLabel = self:createFieldRow(fieldsContainer, field, displayName)
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
		alignment = Enum.TextXAlignment.Left,
	})
	placeholder.Name = "Placeholder"

	self._serverFieldsContainer = fieldsContainer
	self._serverPlaceholder = placeholder
end

function MetricsTab:refresh()
	if self._refreshing then
		return
	end
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
			if off then
				ClientError.try("MetricsTab.unsubscribe", off)
			end
			doneOne()
		end)
		RemoteEventBridge.requestMetrics()
		task.delay(1.5, function()
			if not received then
				if off then
					ClientError.try("MetricsTab.unsubscribe", off)
				end
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
			if off then
				ClientError.try("MetricsTab.unsubscribe", off)
			end
			ClientError.try("MetricsTab.ApplyServerMetrics", function()
				MetricsTab._applyServerMetrics(self, serverMetrics)
			end)
			doneOne()
		end)
		RemoteEventBridge.requestServerMetrics()
		task.delay(1.5, function()
			if not received then
				if off then
					ClientError.try("MetricsTab.unsubscribe", off)
				end
				if self._serverPlaceholder and self._serverPlaceholder.Parent then
					self._serverPlaceholder.Text = "Failed to load server metrics"
				end
				doneOne()
			end
		end)
	end)
end

-- Apply server metrics payload to UI (handles placeholder, rows, and pruning)
function MetricsTab:_applyServerMetrics(serverMetrics: { [string]: Types.JsonValue })
	if not (self._serverFieldsContainer and type(serverMetrics) == "table") then
		return
	end
	-- If server metrics are intentionally unavailable (non-Studio), show message and skip pruning
	if serverMetrics.visible == false then
		if self._serverPlaceholder then
			self._serverPlaceholder.Text = "Server metrics unavailable"
		else
			local msg = self:createLabel(self._serverFieldsContainer, "Server metrics unavailable", {
				position = UDim2.new(0, UIx.Spacing.INPUT_MARGIN, 0, 0),
				size = UDim2.new(1, -(UIx.Spacing.INPUT_MARGIN * 2), 0, UIx.Size.ROW_LABEL),
				alignment = Enum.TextXAlignment.Left,
			})
			msg.Name = "NoData"
		end
		return
	end

	-- Clear placeholder on first successful load (keep reference, but ensure it's not used later)
	if self._serverPlaceholder then
		self._serverPlaceholder:Destroy()
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
			if valueLabel and valueLabel.Parent then
				valueLabel.Parent:Destroy()
			end
			self._labels[labelKey] = nil
		end
	end

	-- If nothing visible, show "No data"
	local hasMetrics = false
	for k, _ in pairs(serverMetrics) do
		if k ~= "ok" and k ~= "success" and k ~= "err" and k ~= "visible" then
			hasMetrics = true
			break
		end
	end
	if not hasMetrics then
		local noData = self:createLabel(self._serverFieldsContainer, "No server metrics available", {
			position = UDim2.new(0, UIx.Spacing.INPUT_MARGIN, 0, 0),
			size = UDim2.new(1, -(UIx.Spacing.INPUT_MARGIN * 2), 0, UIx.Size.ROW_LABEL),
			alignment = Enum.TextXAlignment.Left,
		})
		noData.Name = "NoData"
	end
end

-- Upsert a server metric row (create or update)
function MetricsTab:_upsertServerRow(key: string, value: Types.JsonValue)
	local labelKey = "server_" .. key
	local valueLabel = self._labels[labelKey]

	if not valueLabel then
		-- Create new row using base component
		local displayName = self:_formatFieldName(key)
		local _row, leftLabel, newValueLabel = self:createFieldRow(self._serverFieldsContainer, key, displayName)
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
				if c:IsA("TextLabel") then
					c.TextTransparency = 0
					c.TextStrokeTransparency = 1
					break
				end
			end
		end
	end

	-- Update the value (narrow unknowns to supported types)
	if valueLabel then
		local t = type(value)
		if t == "number" or t == "boolean" or t == "string" then
			valueLabel.Text = self:_formatMetricValue(key, value :: any)
		else
			valueLabel.Text = tostring(value)
		end
	end
end

-- Format field names consistently
function MetricsTab:_formatFieldName(fieldName: string): string
	return fieldName
		:gsub("(%l)(%u)", "%1 %2") -- Add space before capitals
		:gsub("^%l", string.upper) -- Capitalize first letter
		:gsub("_", " ") -- Replace underscores with spaces
		:gsub("Per", " Per")
		:gsub("Sec", " (sec)")
		:gsub("Earned", " Earned")
		:gsub("Spent", " Spent")
end

-- Format metric values based on type and context
function MetricsTab:_formatMetricValue(key: string, value: number | string | boolean): string
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

function MetricsTab:_updateValue(key: string, value: string)
	local label = self._labels[key]
	if label then
		label.Text = value
	end
end

-- Override destroy to handle tab-specific cleanup
function MetricsTab:destroy()
	-- Clean up tab-specific state
	self._serverFieldsContainer = nil
	-- cleared placeholder
	self._refreshButton = nil
	-- no RF fallbacks
	if self._unsubs then
		for _, u in ipairs(self._unsubs) do
			ClientError.try("MetricsTab.unsubscribe", u)
		end
		self._unsubs = {}
	end

	-- Call base destroy (handles periodic updates, connections, container)
	BaseTabComponent.destroy(self)
end

-- Apply user metrics payload to UI (shared by EventBus push and any fallback calls)
function MetricsTab:_applyUserMetrics(metrics: { [string]: Types.JsonValue })
	if not metrics or type(metrics) ~= "table" then
		return
	end

	local m = narrowUserMetrics(metrics)
	-- Gameplay
	self:_updateValue("gameplay_totalBlocksDug", self:_formatMetricValue("totalBlocksDug", m.gameplay.totalBlocksDug))
	self:_updateValue("gameplay_dugThisSession", self:_formatMetricValue("dugThisSession", m.gameplay.dugThisSession))
	self:_updateValue(
		"gameplay_blocksPerMinute",
		self:_formatMetricValue("blocksPerMinute", m.gameplay.blocksPerMinute)
	)
	-- Economy
	self:_updateValue("economy_coins", self:_formatMetricValue("coins", m.economy.coins))
	self:_updateValue("economy_gems", self:_formatMetricValue("gems", m.economy.gems))
	self:_updateValue(
		"economy_totalCoinsEarned",
		self:_formatMetricValue("totalCoinsEarned", m.economy.totalCoinsEarned)
	)
	self:_updateValue("economy_totalCoinsSpent", self:_formatMetricValue("totalCoinsSpent", m.economy.totalCoinsSpent))
	self:_updateValue("economy_totalGemsEarned", self:_formatMetricValue("totalGemsEarned", m.economy.totalGemsEarned))
	self:_updateValue("economy_totalGemsSpent", self:_formatMetricValue("totalGemsSpent", m.economy.totalGemsSpent))
	self:_updateValue("economy_netWorth", self:_formatMetricValue("netWorth", m.economy.netWorth))
	-- Session
	self:_updateValue(
		"session_sessionStartTime",
		self:_formatMetricValue("sessionStartTime", m.session.sessionStartTime)
	)
	self:_updateValue(
		"session_sessionDurationSec",
		self:_formatMetricValue("sessionDurationSec", m.session.sessionDurationSec)
	)
	self:_updateValue(
		"session_totalPlaytimeSec",
		self:_formatMetricValue("totalPlaytimeSec", m.session.totalPlaytimeSec)
	)
	self:_updateValue("session_totalSessions", self:_formatMetricValue("totalSessions", m.session.totalSessions))
	self:_updateValue(
		"session_avgSessionLengthSec",
		self:_formatMetricValue("avgSessionLengthSec", m.session.avgSessionLengthSec)
	)
	-- Lifecycle
	self:_updateValue("lifecycle_isNewPlayer", (m.lifecycle.isNewPlayer and "Yes" or "No"))
	self:_updateValue("lifecycle_isReturningPlayer", (m.lifecycle.isReturningPlayer and "Yes" or "No"))
	self:_updateValue("lifecycle_isFirstDigEver", (m.lifecycle.isFirstDigEver and "Yes" or "No"))
	self:_updateValue("lifecycle_hasDugEver", (m.lifecycle.hasDugEver and "Yes" or "No"))
	self:_updateValue("lifecycle_hasDugThisSession", (m.lifecycle.hasDugThisSession and "Yes" or "No"))
	self:_updateValue(
		"lifecycle_firstPlayTime",
		m.lifecycle.firstPlayTime and self:_formatMetricValue("firstPlayTime", m.lifecycle.firstPlayTime) or "N/A"
	)
	self:_updateValue(
		"lifecycle_firstDigTime",
		m.lifecycle.firstDigTime and self:_formatMetricValue("firstDigTime", m.lifecycle.firstDigTime) or "Never"
	)
	-- Progression
	self:_updateValue("progression_speedLevel", self:_formatMetricValue("speedLevel", m.progression.speedLevel))
	self:_updateValue("progression_sizeLevel", self:_formatMetricValue("sizeLevel", m.progression.sizeLevel))
	self:_updateValue("progression_petsOwned", self:_formatMetricValue("petsOwned", m.progression.petsOwned))
	self:_updateValue("progression_activePets", self:_formatMetricValue("activePets", m.progression.activePets))
	self:_updateValue("progression_materialTier", tostring(m.progression.materialTier))
	-- Monetization
	if m.monetization then
		self:_updateValue(
			"monetization_robuxSpentLifetime",
			self:_formatMetricValue("robuxSpentLifetime", m.monetization.robuxSpentLifetime)
		)
		self:_updateValue(
			"monetization_robuxSpentThisSession",
			self:_formatMetricValue("robuxSpentThisSession", m.monetization.robuxSpentThisSession)
		)
		self:_updateValue(
			"monetization_purchasesCount",
			self:_formatMetricValue("purchasesCount", m.monetization.purchasesCount)
		)
		self:_updateValue(
			"monetization_devProducts",
			self:_formatMetricValue("devProducts", m.monetization.devProducts)
		)
		self:_updateValue("monetization_gamePasses", self:_formatMetricValue("gamePasses", m.monetization.gamePasses))
		self:_updateValue("monetization_isPayingUser", (m.monetization.isPayingUser and "Yes" or "No"))
		self:_updateValue(
			"monetization_daysSinceLastPurchase",
			m.monetization.daysSinceLastPurchase
					and self:_formatMetricValue("daysSinceLastPurchase", m.monetization.daysSinceLastPurchase)
				or "N/A"
		)
	end
end

return MetricsTab
