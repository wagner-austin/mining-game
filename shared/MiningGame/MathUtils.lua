--!strict
-- MathUtils.lua
-- Minimal math utility functions to eliminate repetition (37+ occurrences of math.max(0, x))

local MathUtils = {}

-- Ensure value is non-negative (most common pattern in codebase)
-- Replaces: math.max(0, value)
function MathUtils.nonNegative(value: number): number
	assert(type(value) == "number", "MathUtils.nonNegative expects a number")
	if value ~= value then
		return 0
	end -- Handle NaN
	return math.max(0, value)
end

-- Saturating subtraction - always returns non-negative result
-- Replaces: math.max(0, a - b)
function MathUtils.saturatingSub(minuend: number, subtrahend: number): number
	assert(type(minuend) == "number", "MathUtils.saturatingSub expects numbers")
	assert(type(subtrahend) == "number", "MathUtils.saturatingSub expects numbers")
	if minuend ~= minuend or subtrahend ~= subtrahend then
		return 0
	end -- Handle NaN
	return math.max(0, minuend - subtrahend)
end

-- Clamp value to range [min, max]
function MathUtils.clampRange(value: number, min: number, max: number): number
	assert(type(value) == "number", "MathUtils.clampRange expects numbers")
	assert(type(min) == "number", "MathUtils.clampRange expects numbers")
	assert(type(max) == "number", "MathUtils.clampRange expects numbers")
	assert(min <= max, "MathUtils.clampRange: min must be <= max")
	if value ~= value then
		return min
	end -- Handle NaN
	return math.clamp(value, min, max)
end

-- Saturating addition - result clamped to non-negative
-- Useful for currency/health additions
function MathUtils.saturatingAdd(a: number, b: number): number
	assert(type(a) == "number", "MathUtils.saturatingAdd expects numbers")
	assert(type(b) == "number", "MathUtils.saturatingAdd expects numbers")
	if a ~= a or b ~= b then
		return 0
	end -- Handle NaN
	return math.max(0, a + b)
end

-- Clamp to [0, 1] range (common for alpha/percentages)
function MathUtils.clamp01(value: number): number
	assert(type(value) == "number", "MathUtils.clamp01 expects a number")
	if value ~= value then
		return 0
	end -- Handle NaN
	return math.clamp(value, 0, 1)
end

return table.freeze(MathUtils)
