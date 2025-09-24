--!strict
-- EventMetrics.lua
-- Lightweight counters for EventBus events (server-side)

local EventMetrics = {}

local counts: {[string]: number} = {}

function EventMetrics.Inc(name: string)
    if type(name) ~= "string" then return end
    counts[name] = (counts[name] or 0) + 1
end

function EventMetrics.Snapshot(): {[string]: number}
    local out = {}
    for k, v in pairs(counts) do out[k] = v end
    return out
end

function EventMetrics.Reset()
    table.clear(counts)
end

return EventMetrics

