--!strict
-- ClientError.lua
-- Shared, analyzer-friendly client error helper with ring buffer

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Time = require(MiningGame:WaitForChild("Time"))
local GameConfig = require(MiningGame:WaitForChild("GameConfig"))

type RingEntry = { tag: string, err: string, t: number }
local RING_MAX = (GameConfig.Client and GameConfig.Client.CLIENT_ERROR_RING_SIZE) or 20
local ring: { RingEntry } = {}

local function push(tag: string, err: string)
	if #ring >= RING_MAX then
		table.remove(ring, 1)
	end
	table.insert(ring, { tag = tag, err = err, t = Time.mono() })
end

local ClientError = {}

function ClientError.try(tag: string, fn: () -> ...any): (boolean, ...any)
	local ok, res = xpcall(fn, debug.traceback)
	if not ok then
		local msg = tostring(res)
		push(tag, msg)
		if RunService:IsStudio() then
			warn(("[Client][%s] %s"):format(tag, msg))
		end
	end
	return ok, res
end

function ClientError.recent(): { RingEntry }
	return table.clone(ring)
end

return ClientError
