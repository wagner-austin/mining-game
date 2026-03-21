--!strict
-- testez-lite.luau
-- Minimal TestEZ-compatible test framework for Lune
-- Supports: describe, it, expect (with .to.equal, .to.be.ok, .to.throw, .never)

type ExpectChain = {
	to: ExpectTo,
	never: { to: ExpectTo },
}

type ExpectTo = {
	equal: (other: any) -> (),
	be: {
		ok: () -> (),
		near: (other: number, epsilon: number?) -> (),
		a: (typeName: string) -> (),
	},
	throw: () -> (),
}

local TestRunner = {}

local passed = 0
local failed = 0
local errors: { string } = {}
local contextStack: { string } = {}

local function fullName(name: string): string
	local parts = table.clone(contextStack)
	table.insert(parts, name)
	return table.concat(parts, " > ")
end

local function makeExpect(value: any): ExpectChain
	local function makeEqualFn(negated: boolean)
		return function(other: any)
			local pass = value == other
			if negated then
				pass = not pass
			end
			if not pass then
				local msg = if negated
					then string.format("Expected %s to NOT equal %s", tostring(value), tostring(other))
					else string.format("Expected %s, got %s", tostring(other), tostring(value))
				error(msg, 2)
			end
		end
	end

	local function makeOkFn(negated: boolean)
		return function()
			local pass = value ~= nil and value ~= false
			if negated then
				pass = not pass
			end
			if not pass then
				local msg = if negated
					then string.format("Expected %s to NOT be ok", tostring(value))
					else string.format("Expected value to be ok, got %s", tostring(value))
				error(msg, 2)
			end
		end
	end

	local function makeNearFn(negated: boolean)
		return function(other: number, epsilon: number?)
			local eps = epsilon or 1e-7
			local pass = math.abs((value :: number) - other) <= eps
			if negated then
				pass = not pass
			end
			if not pass then
				local msg = if negated
					then string.format("Expected %s to NOT be near %s", tostring(value), tostring(other))
					else string.format(
						"Expected %s to be near %s (epsilon=%s)",
						tostring(value),
						tostring(other),
						tostring(eps)
					)
				error(msg, 2)
			end
		end
	end

	local function makeAFn(negated: boolean)
		return function(typeName: string)
			local pass = type(value) == typeName
			if negated then
				pass = not pass
			end
			if not pass then
				local msg = if negated
					then string.format("Expected type to NOT be '%s'", typeName)
					else string.format("Expected type '%s', got '%s'", typeName, type(value))
				error(msg, 2)
			end
		end
	end

	local function makeThrowFn(negated: boolean)
		return function()
			local ok, _ = pcall(value :: any)
			local pass = not ok
			if negated then
				pass = not pass
			end
			if not pass then
				local msg = if negated
					then "Expected function to NOT throw"
					else "Expected function to throw, but it did not"
				error(msg, 2)
			end
		end
	end

	local function makeTo(negated: boolean): ExpectTo
		return {
			equal = makeEqualFn(negated),
			be = {
				ok = makeOkFn(negated),
				near = makeNearFn(negated),
				a = makeAFn(negated),
			},
			throw = makeThrowFn(negated),
		}
	end

	return {
		to = makeTo(false),
		never = { to = makeTo(true) },
	}
end

function TestRunner.run(specFiles: { { name: string, fn: () -> () } }): (number, number)
	passed = 0
	failed = 0
	errors = {}
	contextStack = {}

	-- Set globals for spec files
	local _G = (getfenv :: any)() or {}
	_G.describe = function(name: string, fn: () -> ())
		table.insert(contextStack, name)
		fn()
		table.remove(contextStack)
	end

	_G.it = function(name: string, fn: () -> ())
		local full = fullName(name)
		local ok, err = pcall(fn)
		if ok then
			passed += 1
			print("  PASS  " .. full)
		else
			failed += 1
			print("  FAIL  " .. full)
			print("        " .. tostring(err))
			table.insert(errors, full .. ": " .. tostring(err))
		end
	end

	_G.expect = makeExpect

	for _, spec in specFiles do
		print("\n" .. spec.name)
		print(string.rep("-", #spec.name))
		spec.fn()
	end

	print("\n" .. string.rep("=", 40))
	print(string.format("Results: %d passed, %d failed", passed, failed))
	print(string.rep("=", 40))

	if #errors > 0 then
		print("\nFailures:")
		for i, e in errors do
			print(string.format("  %d) %s", i, e))
		end
	end

	return passed, failed
end

return TestRunner
