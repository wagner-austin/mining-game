--!strict
-- Timer.lua
-- Small helper to manage cancellable task.delay timers per owner

export type Timer = {
	set: (self: Timer, delay: number, fn: () -> ()) -> thread,
	clear: (self: Timer, h: thread?) -> (),
	clearAll: (self: Timer) -> (),
	_timers: { thread },
}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local ClientError = require(MiningGame:WaitForChild("ClientError"))

local M = {}

function M.new(): Timer
	local function set(self: Timer, delay: number, fn: () -> ()): thread
		local th: thread
		th = task.delay(delay, function()
			ClientError.try("Timer:set", fn)
			for i, h in ipairs(self._timers) do
				if h == th then
					table.remove(self._timers, i)
					break
				end
			end
		end)
		table.insert(self._timers, th)
		return th
	end

	local function clear(self: Timer, h: thread?)
		if not h then
			return
		end
		ClientError.try("Timer:clear", function()
			task.cancel(h)
			return nil
		end)
		for i, hh in ipairs(self._timers) do
			if hh == h then
				table.remove(self._timers, i)
				break
			end
		end
	end

	local function clearAll(self: Timer)
		for _, th in ipairs(self._timers) do
			ClientError.try("Timer:clearAll", function()
				task.cancel(th)
				return nil
			end)
		end
		table.clear(self._timers)
	end

	local impl: Timer = { _timers = {}, set = set, clear = clear, clearAll = clearAll }
	return impl
end

return M
