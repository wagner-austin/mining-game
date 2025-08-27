--!strict
-- DigPerformance.lua
-- Simple performance timing wrapper for dig operations

local DigPerformance = {}

local timings = {}
local enabled = true

function DigPerformance.measureSection(name: string, func: () -> ...any): ...any
    if not enabled then
        return func()
    end
    
    local start = os.clock()
    local results = {func()}
    local elapsed = os.clock() - start
    
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