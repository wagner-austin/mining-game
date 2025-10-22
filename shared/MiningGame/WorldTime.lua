--!strict
--[[
	WorldTime: Single source of truth for game-time math
	Ensures client and server always agree on day/night cycle timing
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Time = require(MiningGame:WaitForChild("Time"))

local WorldTime = {}

-- CONFIG: Change these in one place for the entire game
WorldTime.MINUTES_PER_DAY = 10        -- 1 in-game day = 10 real minutes
WorldTime.EPOCH_UNIX      = 1735689600 -- 2025-01-01T00:00:00Z (fixed reference point)

function WorldTime.secondsPerGameDay(): number
	return WorldTime.MINUTES_PER_DAY * 60
end

-- Convert a Unix timestamp to Lighting.ClockTime hours [0,24)
function WorldTime.clockTimeFromUnix(unix: number): number
	local daySec = WorldTime.secondsPerGameDay()
	local phase  = (unix - WorldTime.EPOCH_UNIX) % daySec
	return (phase / daySec) * 24
end

-- Real seconds until a target in-game hour (0-24) from a given Unix time
function WorldTime.secondsUntilHour(targetHour: number, fromUnix: number?): number
	fromUnix = fromUnix or Time.unix()
	local daySec     = WorldTime.secondsPerGameDay()
	local curPhase   = (fromUnix - WorldTime.EPOCH_UNIX) % daySec
	local targetSec  = ((targetHour % 24) / 24) * daySec
	return (targetSec - curPhase) % daySec
end

-- Get time period string for current time
function WorldTime.getTimePeriod(clockTime: number): string
	if clockTime >= 5 and clockTime < 8 then
		return "Dawn"
	elseif clockTime >= 8 and clockTime < 12 then
		return "Morning"
	elseif clockTime >= 12 and clockTime < 17 then
		return "Afternoon"
	elseif clockTime >= 17 and clockTime < 20 then
		return "Dusk"
	else
		return "Night"
	end
end

-- Check if given time is during day hours (6 AM to 6 PM)
function WorldTime.isDay(clockTime: number): boolean
	return clockTime >= 6 and clockTime < 18
end

return WorldTime