--!strict
-- Result.lua
-- Universal result type for all remote communications with full type safety

export type Ok<T> = { ok: true, data: T?, __kind: "Result" }
export type Err = { ok: false, code: string, reason: string?, __kind: "Result" }
export type Result<T> = Ok<T> | Err

local Result = {}

function Result.ok<T>(data: T?): Result<T>
	return { ok = true, data = data, __kind = "Result" }
end

function Result.err<T>(code: string, reason: string?): Result<T>
	return { ok = false, code = code, reason = reason, __kind = "Result" }
end

-- Type guard to check if a result is ok
function Result.isOk<T>(result: Result<T>): boolean
	return result.__kind == "Result" and result.ok == true
end

-- Type guard to check if a result is an error
function Result.isErr<T>(result: Result<T>): boolean
	return result.__kind == "Result" and result.ok == false
end

-- Check if something is a Result type
function Result.isResult(value: any): boolean
	return type(value) == "table" and value.__kind == "Result"
end

-- Unwrap a result, returning success status and data/error
function Result.unwrap<T>(result: Result<T>): (boolean, T | string)
	if result.ok then
		return true, result.data :: T
	else
		return false, result.reason or result.code
	end
end

return table.freeze(Result)
