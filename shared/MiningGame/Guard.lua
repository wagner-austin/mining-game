--!strict
-- Guard.lua - declarative validators for internal (non-remote) APIs

type Validator = (any) -> (boolean, string?)
local Guard = {}

function Guard.args(validators: { Validator }, fn: (...any) -> ...any)
	return function(...: any)
		local args = { ... }
		if #args < #validators then
			error(("Expected %d args, got %d"):format(#validators, #args))
		end
		for i, v in ipairs(validators) do
			local ok, msg = v(args[i])
			if not ok then
				error(("arg %d invalid: %s"):format(i, msg or "invalid"))
			end
		end
		return fn(table.unpack(args))
	end
end

return Guard
