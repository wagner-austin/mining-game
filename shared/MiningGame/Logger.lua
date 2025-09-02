--[[
	Logger - Centralized logging system with category-based filtering
	
	Usage:
		local Logger = require(path.to.Logger)
		local log = Logger.new("MyCategory")
		
		log:info("Something happened")
		log:debug("Debug info: %s", someValue)
		log:warn("Warning!")
		log:error("Error occurred")
		
	Toggle categories:
		Logger.enable("Sound")
		Logger.disable("Metrics")
		Logger.solo("UI")  -- Only show UI logs
		Logger.showAll()    -- Show all categories
		Logger.hideAll()    -- Hide all categories
]]

local RunService = game:GetService("RunService")

local Logger = {}
Logger.__index = Logger

-- Node label for output
local nodeLabel = RunService:IsServer() and "Server" or "Client"

-- Category constants to avoid typos
Logger.CAT = {
	Bootstrap = "Bootstrap",
	Sound = "SoundManager",
	Ambient = "AmbientLogging",
	UI = "UIManager",
	Panel = "BasePanel",
	Settings = "SettingsPanel",
	Metrics = "MetricsTab",
	MetricsSrv = "Metrics",
	Terrain = "GridService",
	Dig = "DigService",
	Time = "DayNightCycle",
	Events = "EventScheduler",
	TimeService = "TimeService",
	Data = "DataService",
	Theme = "ThemeManager",
	ThemeTab = "ThemeTab",
	Session = "SessionService",
	Upgrade = "UpgradeService",
	Remote = "Remotes",
	Click = "Click",
}

-- Active categories (true = shown, false/nil = hidden)
local activeCategories = {}
local soloMode = false
local soloCategory = nil

-- Default all categories to visible
local defaultVisible = true

-- Log levels
local LogLevel = {
	DEBUG = 1,
	INFO = 2,
	WARN = 3,
	ERROR = 4
}

-- Current minimum log level
local minLevel = LogLevel.INFO

-- Per-category log levels
local categoryLevels = {}

-- Category statistics
local categoryStats = {}

-- Rate limiting
local rateWindow = 1.5 -- seconds; set to 0 to disable
local categoryRateWindows = {} -- per-category overrides
local lastByKey = {}
local lastCleanup = time()

-- Helper to normalize messages for rate limiting (collapse numbers)
local function normalize(s)
	return (s:gsub("%d+%.?%d*", "{num}"))
end

-- Clean up old rate limit entries
local function cleanupRateTable()
	local now = time()
	if now - lastCleanup < 10 then -- cleanup every 10 seconds
		return
	end
	lastCleanup = now
	
	for k, t in pairs(lastByKey) do
		local cat = k:match("^([^|]+)")
		local window = categoryRateWindows[cat] or rateWindow
		if now - t > math.max(5, window * 4) then
			lastByKey[k] = nil
		end
	end
end

-- Check rate limiting
local function passRateLimit(category, message)
	cleanupRateTable()
	
	local window = categoryRateWindows[category] or rateWindow
	if window <= 0 then
		return true
	end
	
	local key = category .. "|" .. normalize(message)
	local now = time()
	local last = lastByKey[key]
	
	if last and (now - last) < window then
		return false
	end
	
	lastByKey[key] = now
	return true
end

-- Create a new logger instance for a category
function Logger.new(category)
	local self = setmetatable({}, Logger)
	self.category = category
	
	-- Initialize category if not exists
	if activeCategories[category] == nil then
		activeCategories[category] = defaultVisible
	end
	
	-- Initialize stats
	if not categoryStats[category] then
		categoryStats[category] = {
			messages = 0,
			lastMessage = nil,
			throttled = 0
		}
	end
	
	return self
end

-- Check if a category should log
local function shouldLog(category, level)
	-- Check category-specific level first, then global
	local floor = categoryLevels[category] or minLevel
	if level < floor then
		return false
	end
	
	-- Check solo mode
	if soloMode then
		return category == soloCategory
	end
	
	-- Check category setting
	local active = activeCategories[category]
	if active == nil then
		return defaultVisible
	else
		return active
	end
end

-- Format the log message
local function formatMessage(category, level, message)
	local timestamp = os.date("%H:%M:%S")
	local levelStr = ""
	
	if level == LogLevel.DEBUG then
		levelStr = "[DEBUG]"
	elseif level == LogLevel.INFO then
		levelStr = "[INFO] "
	elseif level == LogLevel.WARN then
		levelStr = "[WARN] "
	elseif level == LogLevel.ERROR then
		levelStr = "[ERROR]"
	end
	
	return string.format("%s %s [%s] - %s | %s", timestamp, levelStr, nodeLabel, category, message)
end

-- Log a message
function Logger:log(level, message, ...)
	if not shouldLog(self.category, level) then
		return
	end
	
	-- Format message with arguments
	if select("#", ...) > 0 then
		local success, formatted = pcall(string.format, message, ...)
		if success then
			message = formatted
		end
	end
	
	-- Check rate limiting
	if not passRateLimit(self.category, message) then
		local stats = categoryStats[self.category]
		stats.throttled = stats.throttled + 1
		return
	end
	
	-- Update stats
	local stats = categoryStats[self.category]
	stats.messages = stats.messages + 1
	stats.lastMessage = time()
	
	-- Format and output
	local output = formatMessage(self.category, level, message)
	
	if level == LogLevel.ERROR then
		warn(output)  -- Use warn for errors to make them stand out
	else
		print(output)
	end
end

-- Convenience methods
function Logger:debug(message, ...)
	self:log(LogLevel.DEBUG, message, ...)
end

function Logger:info(message, ...)
	self:log(LogLevel.INFO, message, ...)
end

function Logger:warn(message, ...)
	self:log(LogLevel.WARN, message, ...)
end

function Logger:error(message, ...)
	self:log(LogLevel.ERROR, message, ...)
end

-- Static methods for controlling categories

-- Enable a specific category
function Logger.enable(category)
	activeCategories[category] = true
	soloMode = false
	print(string.format("[Logger] Enabled category: %s", category))
end

-- Disable a specific category
function Logger.disable(category)
	activeCategories[category] = false
	print(string.format("[Logger] Disabled category: %s", category))
end

-- Toggle a category on/off
function Logger.toggle(category)
	local current = activeCategories[category]
	if current == nil then
		current = defaultVisible
	end
	activeCategories[category] = not current
	print(string.format("[Logger] Toggled category %s: %s", category, tostring(not current)))
end

-- Solo mode - only show one category
function Logger.solo(category)
	soloMode = true
	soloCategory = category
	print(string.format("[Logger] Solo mode - Only showing: %s", category))
end

-- Show all categories
function Logger.showAll()
	soloMode = false
	defaultVisible = true
	for cat, _ in pairs(activeCategories) do
		activeCategories[cat] = true
	end
	print("[Logger] Showing all categories")
end

-- Hide all categories
function Logger.hideAll()
	soloMode = false
	defaultVisible = false
	for cat, _ in pairs(activeCategories) do
		activeCategories[cat] = false
	end
	print("[Logger] Hiding all categories")
end

-- Show only specific categories
function Logger.only(...)
	Logger.hideAll()
	for i = 1, select("#", ...) do
		local category = select(i, ...)
		activeCategories[category] = true
	end
	print(string.format("[Logger] Showing only: %s", table.concat({...}, ", ")))
end

-- Set minimum log level
function Logger.setLevel(level)
	if type(level) == "string" then
		level = LogLevel[level:upper()]
	end
	minLevel = level or LogLevel.INFO
	print(string.format("[Logger] Minimum level set to: %d", minLevel))
end

-- Set category-specific log level
function Logger.setCategoryLevel(category, level)
	if type(level) == "string" then
		level = LogLevel[level:upper()]
	end
	local configLog = Logger.new("Logger")
	if level == nil then
		categoryLevels[category] = nil -- clear override
		configLog:debug("Category %s level cleared (using global: %d)", category, minLevel)
	else
		categoryLevels[category] = level
		configLog:debug("Category %s level set to: %d", category, level)
	end
end

-- Set rate window (global)
function Logger.setRateWindow(seconds)
	rateWindow = seconds or rateWindow
	print(string.format("[Logger] Rate window set to: %.1f seconds", rateWindow))
end

-- Set rate window for specific category
function Logger.setRateWindowFor(category, seconds)
	categoryRateWindows[category] = seconds
	-- Use a config logger for all configuration messages
	local configLog = Logger.new("Logger")
	configLog:debug("Category %s rate window set to: %.1f seconds", category, seconds)
end

-- Set node label (Client/Server)
function Logger.setNodeLabel(label)
	nodeLabel = label
	print(string.format("[Logger] Node label set to: %s", label))
end

-- Enable all categories matching a pattern
function Logger.enableMatch(pattern)
	local count = 0
	for cat, _ in pairs(activeCategories) do
		if string.match(cat, pattern) then
			activeCategories[cat] = true
			count = count + 1
		end
	end
	print(string.format("[Logger] Enabled %d categories matching '%s'", count, pattern))
end

-- Show only categories matching a pattern
function Logger.onlyMatch(pattern)
	Logger.hideAll()
	local count = 0
	for cat, _ in pairs(activeCategories) do
		if string.match(cat, pattern) then
			activeCategories[cat] = true
			count = count + 1
		end
	end
	print(string.format("[Logger] Showing only %d categories matching '%s'", count, pattern))
end

-- Get current status
function Logger.status()
	print("\n=== Logger Status ===")
	print(string.format("Solo Mode: %s", tostring(soloMode)))
	if soloMode then
		print(string.format("Solo Category: %s", soloCategory))
	end
	print(string.format("Default Visible: %s", tostring(defaultVisible)))
	print(string.format("Min Level: %d", minLevel))
	
	print("\nCategories:")
	for category, active in pairs(activeCategories) do
		local stats = categoryStats[category]
		local msgCount = stats and stats.messages or 0
		local throttled = stats and stats.throttled or 0
		print(string.format("  %s: %s (messages: %d, throttled: %d)", category, tostring(active), msgCount, throttled))
	end
	print("==================\n")
end

-- List all registered categories
function Logger.list()
	local categories = {}
	for cat, _ in pairs(activeCategories) do
		table.insert(categories, cat)
	end
	table.sort(categories)
	
	print("\n=== Registered Categories ===")
	for _, cat in ipairs(categories) do
		local active = activeCategories[cat]
		local stats = categoryStats[cat]
		local msgCount = stats and stats.messages or 0
		local throttled = stats and stats.throttled or 0
		local status = active and "✓" or "✗"
		local throttleStr = throttled > 0 and string.format(", %d throttled", throttled) or ""
		print(string.format("%s %s (%d messages%s)", status, cat, msgCount, throttleStr))
	end
	print("============================\n")
end

-- Quick presets for common testing scenarios
function Logger.preset(name)
	if name == "quiet" then
		-- Errors only
		Logger.showAll()
		Logger.setLevel("ERROR")
		print("[Logger] Preset: Quiet (errors only)")
	elseif name == "normal" then
		-- Show important stuff only
		Logger.showAll()
		for _, cat in ipairs(quietByDefault) do
			Logger.setCategoryLevel(cat, "WARN")
		end
		Logger.setCategoryLevel("Bootstrap", "INFO")
		Logger.setCategoryLevel("DigService", "INFO")
		Logger.setCategoryLevel("SessionService", "INFO")
		print("[Logger] Preset: Normal (important events only)")
	elseif name == "verbose" then
		-- Show everything
		Logger.showAll()
		Logger.setLevel(LogLevel.DEBUG)
		print("[Logger] Preset: Verbose (all messages)")
	else
		print("[Logger] Unknown preset. Use: quiet, normal, or verbose")
	end
end

-- Apply default noise reduction settings - QUIET MODE BY DEFAULT
-- Use Logger.preset("normal") or Logger.preset("verbose") to see more
Logger.setRateWindowFor("MetricsTab", 3.0)
Logger.setRateWindowFor("AmbientLogging", 5.0)

-- Set most modules to WARN by default (only warnings/errors show)
local quietByDefault = {
	"Logger", "MetricsTab", "AmbientLogging", "TestClient", "CubeVisuals",
	"DataService", "GridService", "MaterialsTab", "ThemeTab",
	"CubeMaterialService", "SoundPreloader", "MaterialManager",
	"SettingsPanel", "TimeService", "EventScheduler", "SpawnService",
	"InventoryService", "LootService", "MonetizationService",
	"CubePositionService", "ThemeSettingsService", "ThemeBootstrap",
	"ThemeManager", "SoundThemeManager", "ClientUI", "UIManager",
	"AmbientBoot", "CellGizmo", "SoundReplication", "DayNightCycle"
}

for _, category in ipairs(quietByDefault) do
	Logger.setCategoryLevel(category, "WARN")
end

-- Keep these at INFO level for important events
Logger.setCategoryLevel("Bootstrap", "INFO")
Logger.setCategoryLevel("DigService", "INFO")
Logger.setCategoryLevel("SessionService", "INFO")
Logger.setCategoryLevel("Remotes", "INFO")
Logger.setCategoryLevel("UIManager", "DEBUG")  -- Show watchdog messages

return Logger