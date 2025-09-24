--!strict
-- DigPerformance.lua
-- Simple performance timing wrapper for dig operations

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Time = require(MiningGame:WaitForChild("Time"))

local DigPerformance = {}

local timings = {}
local enabled = true

function DigPerformance.measureSection(name: string, func: () -> ...any): ...any
    if not enabled then
        return func()
    end
    
    local start = Time.mono()
    local results = {func()}
    local elapsed = Time.mono() - start
    
    -- Track timing
    if not timings[name] then
        timings[name] = {
            total = 0,
            count = 0,
            min = math.huge,
            max = 0,
            last = 0
        }
    end
    
    local timing = timings[name]
    timing.total = timing.total + elapsed
    timing.count = timing.count + 1
    timing.min = math.min(timing.min, elapsed)
    timing.max = math.max(timing.max, elapsed)
    timing.last = elapsed
    
    return table.unpack(results)
end

-- Return a shallow snapshot of timings { [name] = { last=, avg=, min=, max=, count= } }
function DigPerformance.getSnapshot(): {[string]: {last: number, avg: number, min: number, max: number, count: number}}
    local snap = {}
    for name, t in pairs(timings) do
        local avg = (t.count > 0) and (t.total / t.count) or 0
        snap[name] = { last = t.last or 0, avg = avg, min = t.min or 0, max = t.max or 0, count = t.count or 0 }
    end
    return snap
end

function DigPerformance.getReport(): string
    local lines = {"=== Dig Performance Report ==="}
    
    for name, timing in pairs(timings) do
        local avg = timing.total / timing.count
        table.insert(lines, string.format(
            "%s: Last=%.2fms, Avg=%.2fms, Min=%.2fms, Max=%.2fms (n=%d)",
            name,
            timing.last * 1000,
            avg * 1000,
            timing.min * 1000,
            timing.max * 1000,
            timing.count
        ))
    end
    
    return table.concat(lines, "\n")
end

function DigPerformance.reset()
    timings = {}
end

function DigPerformance.setEnabled(value: boolean)
    enabled = value
end

return DigPerformance
