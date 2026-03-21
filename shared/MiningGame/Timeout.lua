--!strict
-- Timeout.lua
-- Run a blocking function on a separate thread; wait up to timeoutSec

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Time = require(Shared:WaitForChild("Time"))

export type CancelToken = { cancelled: boolean }

-- Module-scope RNG to avoid math.random
local rng = Random.new()

local Timeout = {}

function Timeout.token(): CancelToken
	return { cancelled = false }
end

-- Run fn on a spawned thread and wait up to timeoutSec.
-- Returns pcall-style: (ok: boolean, ...resultsOrError)
-- pollIntervalSec defaults to 0 (yield until next frame).
function Timeout.run(
	fn: (CancelToken?) -> ...any,
	timeoutSec: number,
	pollIntervalSec: number?,
	token: CancelToken?
): (boolean, ...any)
	local interval = (pollIntervalSec or 0)
	if timeoutSec <= 0 then
		return false, "TIMEOUT"
	end

	local done = false
	local packed --: { n: number, [number]: any }

	task.spawn(function()
		local ok, res1, res2, res3, res4, res5 = xpcall(function()
			return fn(token)
		end, debug.traceback)
		if ok then
			packed = table.pack(true, res1, res2, res3, res4, res5)
		else
			packed = table.pack(false, res1)
		end
		done = true
	end)

	local t0 = Time.mono()
	while not done do
		if Time.mono() - t0 >= timeoutSec then
			if token then
				token.cancelled = true
			end
			return false, "TIMEOUT"
		end
		task.wait(interval)
	end

	-- pcall-style return
	return table.unpack(packed, 1, packed.n)
end

-- Helper: add jitter to avoid thundering herds
local function jitter(seconds: number): number
	return seconds * (0.9 + rng:NextNumber() * 0.2) -- ±10%
end

-- Convenience: retry with backoff
function Timeout.runWithRetry(
	fn: (CancelToken?) -> ...any,
	timeoutSec: number,
	attempts: number,
	backoffSec: number
): (boolean, ...any)
	attempts = attempts or 1
	backoffSec = backoffSec or 0
	local packed

	for i = 1, attempts do
		local token = Timeout.token()
		packed = table.pack(Timeout.run(fn, timeoutSec, 0, token))
		if packed[1] == true then
			return table.unpack(packed, 1, packed.n)
		end
		if i < attempts then
			task.wait(jitter(backoffSec))
		end
	end
	return table.unpack(packed, 1, packed.n)
end

return Timeout
