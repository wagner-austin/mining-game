--!strict
--[[
	TimeService
	Server-side time tracking and event scheduling system
	Uses Unix-based world clock for perfect synchronization
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local WorldTime = require(MiningGame:WaitForChild("WorldTime"))

local TimeService = {}
TimeService.__index = TimeService

type ScheduledEvent = {
	hour: number,
	recurring: boolean,
	running: boolean,
	nextUnix: number,
	callback: () -> ()
}

local scheduledEvents: {[string]: ScheduledEvent} = {}

function TimeService.new()
	return setmetatable({ running = false }, TimeService)
end

-- Get current game time (0-24 hours) using Unix time
function TimeService:GetCurrentTime(): number
	return WorldTime.clockTimeFromUnix(os.time())
end

-- Get time until a specific hour (in real seconds)
function TimeService:GetSecondsUntilTime(targetHour: number): number
	return WorldTime.secondsUntilHour(targetHour, os.time())
end

-- Internal helper to loop a daily event using absolute timestamps (drift-resistant)
local function loopDaily(eventId: string)
	while true do
		local ev = scheduledEvents[eventId]
		if not ev or not ev.running then return end
		
		local waitSec = math.max(0, ev.nextUnix - os.time())
		-- Break long waits into chunks so BindToClose can stop quickly
		while waitSec > 5 do
			task.wait(math.min(30, waitSec))
			if not scheduledEvents[eventId] or not scheduledEvents[eventId].running then return end
			waitSec = math.max(0, ev.nextUnix - os.time())
		end
		task.wait(waitSec)
		
		-- Fire safely
		ev = scheduledEvents[eventId]
		if not ev or not ev.running then return end
		
		print(string.format("[TimeService] Firing event at %d:00 (current time: %.2f)", 
			ev.hour, WorldTime.clockTimeFromUnix(os.time())))
		
		local ok, err = pcall(ev.callback)
		if not ok then
			warn("[TimeService] Event error:", err)
		end
		
		if ev.recurring then
			ev.nextUnix += WorldTime.secondsPerGameDay()
			print(string.format("[TimeService] Rescheduled recurring event at %d:00 for next cycle", ev.hour))
		else
			ev.running = false
			scheduledEvents[eventId] = nil
			print(string.format("[TimeService] Completed one-time event at %d:00", ev.hour))
			return
		end
	end
end

-- Schedule an event at a specific game hour
function TimeService:ScheduleEvent(hour: number, callback: () -> (), recurring: boolean?): string
	local id = HttpService:GenerateGUID(false)
	local secondsUntil = self:GetSecondsUntilTime(hour)
	local nextUnix = os.time() + secondsUntil
	
	scheduledEvents[id] = {
		hour = hour,
		callback = callback,
		recurring = recurring == true,
		nextUnix = nextUnix,
		running = true,
	}
	
	-- Log scheduling
	local eventType = recurring and "recurring" or "one-time"
	print(string.format("[TimeService] Scheduled %s event at %d:00 - fires in %.1f seconds (%.2f minutes)", 
		eventType, hour, secondsUntil, secondsUntil / 60))
	
	task.spawn(loopDaily, id)
	return id
end

-- Cancel a scheduled event
function TimeService:CancelEvent(eventId: string)
	local ev = scheduledEvents[eventId]
	if ev then
		ev.running = false
	end
	scheduledEvents[eventId] = nil
end

-- Check if it's currently day (6 AM to 6 PM)
function TimeService:IsDay(): boolean
	return WorldTime.isDay(self:GetCurrentTime())
end

-- Check if it's currently night (6 PM to 6 AM)
function TimeService:IsNight(): boolean
	return not self:IsDay()
end

-- Get time period string
function TimeService:GetTimePeriod(): string
	return WorldTime.getTimePeriod(self:GetCurrentTime())
end

-- Initialize the service
function TimeService:Initialize()
	if self.running then return end
	self.running = true
	
	local currentTime = self:GetCurrentTime()
	local period = self:GetTimePeriod()
	local dayNight = self:IsDay() and "Day" or "Night"
	
	print(string.format("[TimeService] Initialized"))
	print(string.format("  - Current time: %.2f:00 (%s - %s)", currentTime, period, dayNight))
	print(string.format("  - Day length: %d real minutes", WorldTime.MINUTES_PER_DAY))
	print(string.format("  - Unix epoch: %d", WorldTime.EPOCH_UNIX))
	
	-- Clean up on server shutdown
	game:BindToClose(function()
		self:Destroy()
	end)
end

-- Cleanup
function TimeService:Destroy()
	self.running = false
	
	-- Cancel all events
	for id, ev in pairs(scheduledEvents) do
		ev.running = false
		scheduledEvents[id] = nil
	end
end

return TimeService