--!strict
-- RateLimitService.lua - token-bucket limiter for RF/RE and server-side actions

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Time = require(MiningGame:WaitForChild("Time"))

local buckets: { [number]: { [string]: { tokens: number, last: number, rate: number, burst: number } } } = {}

local RateLimitService = {}

-- Initialize with DI container (no dependencies)
function RateLimitService:Init(_container)
	-- No dependencies needed
end

-- rate: tokens/second; burst: max capacity
function RateLimitService.allow(userId: number, key: string, rate: number, burst: number): boolean
	local user = buckets[userId]
	if not user then
		user = {}
		buckets[userId] = user
	end

	local b = user[key]
	if not b then
		b = { tokens = burst, last = Time.mono(), rate = rate, burst = burst }
		user[key] = b
	end

	local now = Time.mono()
	local dt = now - b.last
	b.last = now
	b.tokens = math.min(b.burst, b.tokens + dt * b.rate)

	if b.tokens >= 1 then
		b.tokens -= 1
		return true
	end
	return false
end

function RateLimitService.reset(userId: number)
	buckets[userId] = nil
end

return RateLimitService
