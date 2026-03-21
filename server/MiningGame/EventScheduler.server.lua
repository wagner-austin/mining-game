--[[
	Event Scheduler Example
	Shows how to use TimeService to schedule events at specific times
]]

local TimeService = require(script.Parent.TimeService)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(MiningGame:WaitForChild("Logger"))
local GameConfig = require(MiningGame:WaitForChild("GameConfig"))
local log = Logger.new("EventScheduler")

-- Create TimeService instance
local timeService = TimeService.new()
timeService:Initialize()

-- Track event IDs for potential cleanup
local eventIds = {}

-- Example scheduled events
local function setupScheduledEvents()
	log:info("Setting up scheduled events...")

	-- Morning announcement (6 AM) - Recurring daily
	local morningId = timeService:ScheduleEvent(GameConfig.Scheduler.MORNING_HOUR, function()
		log:info("[Event] ☀️ Good morning! The sun is rising.")
		log:info("  -> Current game time: %.2f", timeService:GetCurrentTime())
		-- You could send notifications to players here
		-- Example: Show UI notification, give morning bonus, etc.
	end, true)
	table.insert(eventIds, morningId)

	-- Noon event (12 PM) - Recurring daily
	local noonId = timeService:ScheduleEvent(12, function()
		log:info("[Event] ☀️ It's noon! Peak daylight hours.")
		log:info("  -> Current game time: %.2f", timeService:GetCurrentTime())
		-- Example: Double XP hour, special merchant appears, etc.
	end, true)
	table.insert(eventIds, noonId)

	-- Evening event (18:00 / 6 PM) - Recurring daily
	local eveningId = timeService:ScheduleEvent(GameConfig.Scheduler.EVENING_HOUR, function()
		log:info("[Event] 🌅 Evening has arrived. The sun is setting.")
		log:info("  -> Current game time: %.2f", timeService:GetCurrentTime())
		-- Example: Spawn night creatures, change shop prices, etc.
	end, true)
	table.insert(eventIds, eveningId)

	-- Midnight event (0:00) - Recurring daily
	local midnightId = timeService:ScheduleEvent(0, function()
		log:info("[Event] 🌙 Midnight! Special event time.")
		log:info("  -> Current game time: %.2f", timeService:GetCurrentTime())
		-- Example: Rare item spawns, bonus rewards, etc.
	end, true)
	table.insert(eventIds, midnightId)

	log:info("Scheduled %d recurring events", #eventIds)
end

-- Example: Give players time-based bonuses
local function handlePlayerJoin(player: Player)
	local period = timeService:GetTimePeriod()
	local currentTime = timeService:GetCurrentTime()
	local dayNight = timeService:IsDay() and "Day" or "Night"

	log:info("%s joined during %s (%.2f:00 - %s)", player.Name, period, currentTime, dayNight)

	-- Example: Different spawn bonuses based on time
	if timeService:IsNight() then
		-- Give night vision item or torch
		log:info("  -> Giving %s night equipment (torch, night vision, etc.)", player.Name)
	else
		-- Give sun hat or daylight bonus
		log:info("  -> Giving %s daylight bonus (sun protection, visibility boost, etc.)", player.Name)
	end
end

-- Connect player events
Players.PlayerAdded:Connect(handlePlayerJoin)

-- Setup all scheduled events
setupScheduledEvents()

-- Example: Check time periodically for special conditions
local lastPeriodLogged = ""
task.spawn(function()
	while true do
		task.wait(GameConfig.Scheduler.CHECK_INTERVAL)

		local time = timeService:GetCurrentTime()
		local period = timeService:GetTimePeriod()

		-- Log period transitions
		if period ~= lastPeriodLogged then
			lastPeriodLogged = period
			log:info("Period changed to: %s (%.2f:00)", period, time)
		end

		-- Special dawn/dusk effects (currently none)
	end
end)

log:info("Initialized with scheduled events")
log:info("  - Current time: %.2f:00", timeService:GetCurrentTime())
log:info("  - Period: %s", timeService:GetTimePeriod())
log:info("  - Day/Night: %s", timeService:IsDay() and "Day" or "Night")
