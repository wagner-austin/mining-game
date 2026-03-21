--!strict
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Time = {}

-- For testing: allow overriding time providers
local unixProvider: (() -> number)? = nil
local monoProvider: (() -> number)? = nil

local function getServerTime(): number
	if RunService:IsClient() and Workspace.GetServerTimeNow then
		-- On client, use server-authoritative time (fractional seconds)
		return Workspace:GetServerTimeNow()
	end
	-- On server, use os.time() (integer seconds)
	return os.time()
end

-- Get Unix timestamp in seconds
-- NOTE: Returns fractional seconds on client, integer seconds on server
-- For persistence, use math.floor(Time.unix()) or Time.unixMs()
function Time.unix(): number
	if unixProvider then
		return unixProvider()
	end
	return getServerTime()
end

-- Get Unix timestamp in milliseconds (rounded, consistent across client/server)
function Time.unixMs(): number
	return math.floor(Time.unix() * 1000 + 0.5)
end

-- Get monotonic high-resolution time for performance/animations/cooldowns
function Time.mono(): number
	if monoProvider then
		return monoProvider()
	end
	return os.clock()
end

-- Get monotonic time in milliseconds (useful for UI ordering, perf logs)
function Time.monoMs(): number
	return math.floor(Time.mono() * 1000 + 0.5)
end

-- Frame delta time
do
	local lastDt = 1 / 60
	RunService.Heartbeat:Connect(function(dt: number)
		lastDt = dt
	end)
	function Time.dt(): number
		return lastDt
	end
end

-- Convenience helpers
function Time.since(t: number): number
	return Time.unix() - t
end

function Time.hasPassed(t: number): boolean
	return Time.unix() >= t
end

-- Testing hooks (always defined but should only be called in tests)
function Time._setUnixProvider(fn: (() -> number)?)
	unixProvider = fn
end

function Time._setMonoProvider(fn: (() -> number)?)
	monoProvider = fn
end

function Time._clearProviders()
	unixProvider = nil
	monoProvider = nil
end

return Time
