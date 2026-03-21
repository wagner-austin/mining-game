--!strict
-- Dig/Telemetry.lua
-- Centralized dig telemetry for QA/debug RFs.

local Telemetry = {}

type TelemetryState = {
	picks: { cube: number, island: number, fallback: number },
	rejects: {
		out_of_range: number,
		outside_cube: number,
		outside_volume: number,
		invalid_terrain: number,
		not_owner: number,
		locked: number,
	},
	successes: number,
	last: { pick: string?, volId: string?, kind: string?, reason: string? },
}

local state: TelemetryState = {
	picks = { cube = 0, island = 0, fallback = 0 },
	rejects = {
		out_of_range = 0,
		outside_cube = 0,
		outside_volume = 0,
		invalid_terrain = 0,
		not_owner = 0,
		locked = 0,
	},
	successes = 0,
	last = { pick = nil, volId = nil, kind = nil, reason = nil },
}

function Telemetry.get()
	return {
		picks = table.clone(state.picks),
		rejects = table.clone(state.rejects),
		successes = state.successes,
		last = table.clone(state.last),
	}
end

function Telemetry.reset()
	state.picks.cube = 0
	state.picks.island = 0
	state.picks.fallback = 0
	state.rejects.out_of_range = 0
	state.rejects.outside_cube = 0
	state.rejects.outside_volume = 0
	state.rejects.invalid_terrain = 0
	state.rejects.not_owner = 0
	state.rejects.locked = 0
	state.successes = 0
	state.last = { pick = nil, volId = nil, kind = nil, reason = nil }
end

-- Extra helpers for in-process updates
function Telemetry.pickCube(volId: string?)
	state.picks.cube += 1
	state.last.pick = "cube"
	state.last.volId = volId
	state.last.kind = "cube"
end

function Telemetry.pickIsland(volId: string?)
	state.picks.island += 1
	state.last.pick = "island"
	state.last.volId = volId
	state.last.kind = "island"
end

function Telemetry.pickFallback(volId: string?)
	state.picks.fallback += 1
	state.last.pick = "fallback"
	state.last.volId = volId
	state.last.kind = "cube"
end

function Telemetry.reject(tag: string, reason: string)
	if state.rejects[tag] ~= nil then
		state.rejects[tag] += 1
	end
	state.last.reason = reason
end

function Telemetry.success()
	state.successes += 1
	state.last.reason = nil
end

return Telemetry
