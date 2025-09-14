--!strict
-- Dig/Telemetry.lua
-- Centralized dig telemetry for QA/debug RFs.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("MiningGame")

local Telemetry = {}

local state = {
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

local function cloneTable(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

function Telemetry.get()
    return {
        picks = cloneTable(state.picks),
        rejects = cloneTable(state.rejects),
        successes = state.successes,
        last = cloneTable(state.last),
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
    state.last.pick = "cube"; state.last.volId = volId; state.last.kind = "cube"
end

function Telemetry.pickIsland(volId: string?)
    state.picks.island += 1
    state.last.pick = "island"; state.last.volId = volId; state.last.kind = "island"
end

function Telemetry.pickFallback(volId: string?)
    state.picks.fallback += 1
    state.last.pick = "fallback"; state.last.volId = volId; state.last.kind = "cube"
end

function Telemetry.reject(tag: string, reason: string)
    if state.rejects[tag] ~= nil then state.rejects[tag] += 1 end
    state.last.reason = reason
end

function Telemetry.success()
    state.successes += 1
    state.last.reason = nil
end

return Telemetry
