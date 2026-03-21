--!strict
-- ResultClient.lua
-- Client-side helper for Result handling with RemoteFunctions

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Result = require(script.Parent.Result)

type TypedCaller<T> = (...any) -> (T?, string?)

-- Try to get ClientRF if available
local ClientRFModule = MiningGame:FindFirstChild("ClientRF")
local ClientError = require(MiningGame:WaitForChild("ClientError"))
local ClientRF: any = nil
if ClientRFModule and ClientRFModule:IsA("ModuleScript") then
	local okRF, rf = ClientError.try("ResultClient.LoadClientRF", function()
		return require(ClientRFModule)
	end)
	if okRF then
		ClientRF = rf
	end
end

local ResultClient = {}

-- Invoke a RemoteFunction and unwrap the Result
function ResultClient.invoke<T>(remoteFunction: RemoteFunction, ...: any): (boolean, T | string)
	-- Prefer ClientRF if available (by name)
	if ClientRF and type(ClientRF.call) == "function" and remoteFunction and remoteFunction.Name then
		local data, err = ClientRF.call(remoteFunction.Name, ...)
		if err then
			return false, tostring(err)
		end
		-- If server uses Result, unwrap; otherwise return data as-is
		if type(data) == "table" and Result.isResult(data) then
			return Result.unwrap(data)
		end
		return true, data
	end

	-- Fallback: direct InvokeServer with legacy/Result handling
	local args = table.pack(...)
	local okInvoke, response = ClientError.try("ResultClient.InvokeServer", function()
		return remoteFunction:InvokeServer(table.unpack(args, 1, args.n))
	end)

	if not okInvoke then
		return false, tostring(response)
	end

	if Result.isResult(response) then
		return Result.unwrap(response)
	end

	-- Legacy format or unexpected response
	if type(response) == "table" then
		-- Handle legacy {success: boolean, reason?: string} format
		if response.success ~= nil then
			if response.success then
				return true, response.data or response
			else
				return false, response.reason or "Request failed"
			end
		end
	end

	-- Unknown format, assume success
	return true, response
end

-- Invoke and only return data on success, nil on failure
function ResultClient.tryInvoke<T>(remoteFunction: RemoteFunction, ...: any): T?
	local success, data = ResultClient.invoke(remoteFunction, ...)
	if success then
		return data :: T
	end
	return nil
end

-- Invoke with error logging
function ResultClient.invokeWithLog<T>(remoteFunction: RemoteFunction, ...: any): (boolean, T | string)
	local success, dataOrError = ResultClient.invoke(remoteFunction, ...)

	if not success then
		warn(("[%s] Failed: %s"):format(remoteFunction.Name, tostring(dataOrError)))
	end

	return success, dataOrError
end

return table.freeze(ResultClient)
