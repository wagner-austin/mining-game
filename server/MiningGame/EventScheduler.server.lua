--[[
	Event Scheduler Example
	Shows how to use TimeService to schedule events at specific times
]]

local TimeService = require(script.Parent.TimeService)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Create TimeService instance
local timeService = TimeService.new()
timeService:Initialize()

-- Track event IDs for potential cleanup
local eventIds = {}

-- Example scheduled events
local function setupScheduledEvents()
	print("[EventScheduler] Setting up scheduled events...")
	
	-- Morning announcement (6 AM) - Recurring daily
	local morningId = timeService:ScheduleEvent(6, function()
		print("[Event] ☀️ Good morning! The sun is rising.")
		print("  -> Current game time:", string.format("%.2f", timeService:GetCurrentTime()))
		-- You could send notifications to players here
		-- Example: Show UI notification, give morning bonus, etc.
	end, true)
	table.insert(eventIds, morningId)
	
	-- Noon event (12 PM) - Recurring daily
	local noonId = timeService:ScheduleEvent(12, function()
		print("[Event] ☀️ It's noon! Peak daylight hours.")
		print("  -> Current game time:", string.format("%.2f", timeService:GetCurrentTime()))
		-- Example: Double XP hour, special merchant appears, etc.
	end, true)
	table.insert(eventIds, noonId)
	
	-- Evening event (18:00 / 6 PM) - Recurring daily
	local eveningId = timeService:ScheduleEvent(18, function()
		print("[Event] 🌅 Evening has arrived. The sun is setting.")
		print("  -> Current game time:", string.format("%.2f", timeService:GetCurrentTime()))
		-- Example: Spawn night creatures, change shop prices, etc.
	end, true)
	table.insert(eventIds, eveningId)
	
	-- Midnight event (0:00) - Recurring daily
	local midnightId = timeService:ScheduleEvent(0, function()
		print("[Event] 🌙 Midnight! Special event time.")
		print("  -> Current game time:", string.format("%.2f", timeService:GetCurrentTime()))
		-- Example: Rare item spawns, bonus rewards, etc.
	end, true)
	table.insert(eventIds, midnightId)
	
	print(string.format("[EventScheduler] Scheduled %d recurring events", #eventIds))
end

-- Example: Give players time-based bonuses
local function handlePlayerJoin(player: Player)
	local period = timeService:GetTimePeriod()
	local currentTime = timeService:GetCurrentTime()
	local dayNight = timeService:IsDay() and "Day" or "Night"
	
	print(string.format("[EventScheduler] %s joined during %s (%.2f:00 - %s)", 
		player.Name, period, currentTime, dayNight))
	
	-- Example: Different spawn bonuses based on time
	if timeService:IsNight() then
		-- Give night vision item or torch
		print(string.format("  -> Giving %s night equipment (torch, night vision, etc.)", player.Name))
	else
		-- Give sun hat or daylight bonus
		print(string.format("  -> Giving %s daylight bonus (sun protection, visibility boost, etc.)", player.Name))
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
		task.wait(30) -- Check every 30 seconds
		
		local time = timeService:GetCurrentTime()
		local period = timeService:GetTimePeriod()
		
		-- Log period transitions
		if period ~= lastPeriodLogged then
			lastPeriodLogged = period
			print(string.format("[EventScheduler] Period changed to: %s (%.2f:00)", period, time))
		end
		
		-- Special dawn/dusk effects
		if period == "Dawn" or period == "Dusk" then
			-- Could trigger special lighting effects, sounds, etc.
		end
	end
end)

print("[EventScheduler] Initialized with scheduled events")
print("  - Current time:", string.format("%.2f:00", timeService:GetCurrentTime()))
print("  - Period:", timeService:GetTimePeriod())
print("  - Day/Night:", timeService:IsDay() and "Day" or "Night")