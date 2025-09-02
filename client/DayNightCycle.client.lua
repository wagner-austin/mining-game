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
local WorldTime = require(MiningGame:WaitForChild("WorldTime"))
local Logger = require(MiningGame:WaitForChild("Logger"))

local log = Logger.new("DayNightCycle")

-- Wait for server Unix time remote
local GetServerUnix = ReplicatedStorage:WaitForChild("GetServerUnix", 10) :: RemoteFunction?

-- Calibration: map GetServerTimeNow() -> Unix time
local serverUnixOffset: number
local calibrationMethod: string

if GetServerUnix then
	-- Get precise Unix time from server
	local serverUnix = GetServerUnix:InvokeServer()
	local localServerTime = workspace:GetServerTimeNow()
	serverUnixOffset = serverUnix - localServerTime
	calibrationMethod = "Server remote"
	
	log:info("Calibrated with server")
	log:info("  - Server Unix: %d", serverUnix)
	log:info("  - Local server time: %.2f", localServerTime)
	log:info("  - Offset: %.2f", serverUnixOffset)
else
	-- Fallback: assume server and client have similar system time
	warn("[DayNightCycle] GetServerUnix remote not found, using local time estimation")
	serverUnixOffset = os.time() - workspace:GetServerTimeNow()
	calibrationMethod = "Local estimation"
end

-- Track last ClockTime for micro-optimization
local lastClockTime = 0
local updateCount = 0
local lastLogTime = 0

-- Smooth lighting updates using RenderStepped for visual quality
RunService.RenderStepped:Connect(function()
	-- Convert server time to Unix (no network calls in loop)
	local unixNow = workspace:GetServerTimeNow() + serverUnixOffset
	
	-- Apply world time formula
	local newClockTime = WorldTime.clockTimeFromUnix(unixNow)
	
	-- Only update if change is significant (reduces work on low-end devices)
	if math.abs(newClockTime - lastClockTime) > 1/240 then -- ~0.004 hours ≈ 0.24 minutes
		Lighting.ClockTime = newClockTime
		lastClockTime = newClockTime
		updateCount = updateCount + 1
		
		-- Log periodic status (every game hour = ~25 real seconds at 10 min/day)
		if math.floor(newClockTime) ~= lastLogTime then
			lastLogTime = math.floor(newClockTime)
			local period = WorldTime.getTimePeriod(newClockTime)
			local isDay = WorldTime.isDay(newClockTime)
			log:debug("Time: %.2f:00 (%s - %s) | Updates: %d", 
				newClockTime, period, isDay and "Day" or "Night", updateCount)
		end
	end
end)

log:info("Initialized")
log:info("  - Day length: %d minutes", WorldTime.MINUTES_PER_DAY)
log:info("  - Calibration: %s", calibrationMethod)
log:info("  - Initial time: %.2f:00", WorldTime.clockTimeFromUnix(os.time()))