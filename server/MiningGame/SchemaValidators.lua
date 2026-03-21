--!strict
-- SchemaValidators.lua
-- Common schema validators for remote input validation

export type Validator = (any) -> (boolean, string?)
export type MultiValidator = (...any) -> (boolean, string?)

local SchemaValidators = {}

-- Validate Vector3 input
function SchemaValidators.Vector3(input: any): (boolean, string?)
	if typeof(input) ~= "Vector3" then
		return false, "Expected Vector3"
	end
	return true, nil
end

-- Validate string input
function SchemaValidators.String(input: any): (boolean, string?)
	if typeof(input) ~= "string" or input == "" then
		return false, "Expected non-empty string"
	end
	return true, nil
end

-- Validate positive number
function SchemaValidators.PositiveNumber(input: any): (boolean, string?)
	if typeof(input) ~= "number" or input <= 0 then
		return false, "Expected positive number"
	end
	return true, nil
end

-- Validate positive integer
function SchemaValidators.PositiveInteger(input: any): (boolean, string?)
	if typeof(input) ~= "number" or input <= 0 or input % 1 ~= 0 then
		return false, "Expected positive integer"
	end
	return true, nil
end

-- Validate currency type
function SchemaValidators.CurrencyType(input: any): (boolean, string?)
	if input ~= "coins" and input ~= "gems" then
		return false, "Expected 'coins' or 'gems'"
	end
	return true, nil
end

-- Validate item counts table
function SchemaValidators.ItemCounts(input: any): (boolean, string?)
	if typeof(input) ~= "table" then
		return false, "Expected table of itemId -> count"
	end

	for itemId, count in pairs(input) do
		if typeof(itemId) ~= "string" or itemId == "" then
			return false, "Invalid item ID"
		end
		if typeof(count) ~= "number" or count <= 0 or count % 1 ~= 0 then
			return false, "Invalid item count"
		end
	end

	return true, nil
end

-- Validate enum value with safe string conversion
function SchemaValidators.Enum<T>(validValues: { T }): Validator
	local valueSet = {}
	for _, v in ipairs(validValues) do
		valueSet[v] = true
	end

	-- Pre-compute error message with safe string conversion
	local labels = {}
	for i, v in ipairs(validValues) do
		labels[i] = tostring(v)
	end
	local errorMsg = ("Expected one of: %s"):format(table.concat(labels, ", "))

	return function(input: any): (boolean, string?)
		if not valueSet[input] then
			return false, errorMsg
		end
		return true, nil
	end
end

-- Validate equipment slot names
function SchemaValidators.EquipmentSlot(input: any): (boolean, string?)
	local validSlots = {
		head = true,
		back = true,
		aura = true,
		trail = true,
		hand = true, -- right-hand cosmetic items (sword/pickaxe/warhammer)
		-- modelSwap removed
		terrainTheme = true,
	}

	if typeof(input) ~= "string" or not validSlots[input] then
		return false, "Invalid equipment slot"
	end

	return true, nil
end

-- Validate weights table (string keys -> non-negative numbers)
function SchemaValidators.WeightsTable(input: any): (boolean, string?)
	if typeof(input) ~= "table" then
		return false, "Expected table"
	end

	for k, v in pairs(input) do
		if typeof(k) ~= "string" then
			return false, "Keys must be strings"
		end
		if typeof(v) ~= "number" or v < 0 then
			return false, ("Invalid weight for %s"):format(tostring(k))
		end
	end

	return true, nil
end

-- Validate Instance is a specific class
function SchemaValidators.InstanceIsA(className: string): (any) -> (boolean, string?)
	return function(x: any): (boolean, string?)
		if typeof(x) ~= "Instance" or not x:IsA(className) then
			return false, ("Expected Instance:%s"):format(className)
		end
		return true, nil
	end
end

-- Combine multiple validators
function SchemaValidators.Multiple(...: (any) -> (boolean, string?)): (any) -> (boolean, string?)
	local validators = { ... }

	return function(...: any): (boolean, string?)
		local args = { ... }
		if #args ~= #validators then
			return false, ("Expected %d arguments, got %d"):format(#validators, #args)
		end

		for i, validator in ipairs(validators) do
			local valid, err = validator(args[i])
			if not valid then
				return false, ("Argument %d: %s"):format(i, err or "Invalid")
			end
		end

		return true, nil
	end
end

-- Validate any input (always passes)
function SchemaValidators.Any(...: any): (boolean, string?)
	local _ = select("#", ...)
	return true, nil
end

return table.freeze(SchemaValidators)
