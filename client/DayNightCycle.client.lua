--!strict
--[[
	Day/Night Cycle Client
	Smooth, world-clock synchronized lighting updates
	Uses calibrated Unix time for perfect sync across all servers
]]

local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Time = require(MiningGame:WaitForChild("Time"))
local WorldTime = require(MiningGame:WaitForChild("WorldTime"))
local Logger = require(MiningGame:WaitForChild("Logger"))
local _ = require(MiningGame:WaitForChild("ClientRF"))

local log = Logger.new("DayNightCycle")

-- No calibration needed - Time module handles server sync internally

-- Track last ClockTime for micro-optimization
local lastClockTime = 0
local updateCount = 0
local lastLogTime = 0

-- Smooth lighting updates using RenderStepped for visual quality
RunService.RenderStepped:Connect(function()
	-- Get server-authoritative time from Time module
	local unixNow = Time.unix()

	-- Apply world time formula
	local newClockTime = WorldTime.clockTimeFromUnix(unixNow)

	-- Only update if change is significant (reduces work on low-end devices)
	if math.abs(newClockTime - lastClockTime) > 1 / 240 then -- ~0.004 hours ≈ 0.24 minutes
		Lighting.ClockTime = newClockTime
		lastClockTime = newClockTime
		updateCount = updateCount + 1

		-- Log periodic status (every game hour = ~25 real seconds at 10 min/day)
		if math.floor(newClockTime) ~= lastLogTime then
			lastLogTime = math.floor(newClockTime)
			local period = WorldTime.getTimePeriod(newClockTime)
			local isDay = WorldTime.isDay(newClockTime)
			log:debug(
				"Time: %.2f:00 (%s - %s) | Updates: %d",
				newClockTime,
				period,
				isDay and "Day" or "Night",
				updateCount
			)
		end
	end
end)

log:info("Initialized")
log:info("  - Day length: %d minutes", WorldTime.MINUTES_PER_DAY)
log:info("  - Initial time: %.2f:00", WorldTime.clockTimeFromUnix(Time.unix()))
