--!strict
-- ClientRF.lua
-- Client-side helper for cleaner RemoteFunction calls with Result unwrapping
-- 
-- Usage:
--   local RF = require(ReplicatedStorage.MiningGame.ClientRF)
--   local data, err = RF.call("GetProfile")
--   if not data then 
--       warn("Failed:", err)
--       return
--   end
--   -- Use data...

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Ready = require(MiningGame:WaitForChild("Ready"))
local Remotes = require(MiningGame:WaitForChild("Remotes"))
local Timeout = require(MiningGame:WaitForChild("Timeout"))
local LoadCfg = require(MiningGame:WaitForChild("LoadingConstants"))

local ClientRF = {}

-- Type definition for cleaner syntax
type TypedCaller<T> = (...any) -> (T?, string?)

-- Single preflight check on first RF call
local _didReadyCheck = false

-- Track which RFs we've already warned about (to avoid spam)
local warnedAboutNested = {}

-- Allowlist for intentional non-standard RFs:
-- GetServerUnix returns scalar via Result.ok (for DayNightCycle compatibility)
-- GetEquippedItems/GetAllEquipped return raw maps (wrapped by RemoteManager)
local nestedOk = { GetEquippedItems = true, GetAllEquipped = true, GetServerUnix = true }

-- Call a RemoteFunction and unwrap the Result
function ClientRF.call(name: string, ...: any): (any?, string?)
    local args = table.pack(...)
    local rf = Remotes.RF[name]
    if not rf then
        return nil, ("Missing RemoteFunction '%s'"):format(name)
    end
    
    -- Enforce a client-side ceiling on request time
    local ok, valueOrErr = Timeout.run(function()
        return rf:InvokeServer(table.unpack(args, 1, args.n))
    end, LoadCfg.TIMEOUTS.RemoteCall, LoadCfg.POLL_INTERVALS.Fine)
    
    if not ok then
        -- If Timeout.run timed out it returns (false, "TIMEOUT"); otherwise it's the pcall error
        if valueOrErr == "TIMEOUT" then
            return nil, "TIMEOUT"
        else
            return nil, ("RF call failed: %s"):format(tostring(valueOrErr))
        end
    end
    
    local result = valueOrErr
    
    if not result then
        -- No response
        return nil, "No response from server"
    end
    
    -- Check for Result format
    if type(result) == "table" then
        if result.ok == true then
            -- Studio warning for nested data (convention violation) - warn once per RF
            if RunService:IsStudio() and result.data ~= nil and not warnedAboutNested[name] and not nestedOk[name] then
                warnedAboutNested[name] = true
                warn(("[ClientRF] %s returned nested data; convention is top-level { ok, success, ... }"):format(name))
            end
            -- Success - return data (or the whole result if no data field)
            return result.data or result, nil
        elseif result.ok == false then
            -- Check for retry flag (services initializing)
            if result.retry == true then
                task.wait(0.2)
                -- Retry once
                local retryResult = rf:InvokeServer(table.unpack(args, 1, args.n))
                if type(retryResult) == "table" and retryResult.ok == true then
                    return retryResult.data or retryResult, nil
                elseif type(retryResult) == "table" and retryResult.ok == false then
                    local code = retryResult.err or retryResult.error or "Request failed"
                    local why = retryResult.reason and (": " .. tostring(retryResult.reason)) or ""
                    return nil, code .. why
                else
                    return retryResult, nil
                end
            end
            -- Explicit failure - include reason if present for better debugging
            local code = result.err or result.error or "Request failed"
            local why = result.reason and (": " .. tostring(result.reason)) or ""
            return nil, code .. why
        end
    end
    
    -- Non-Result format (legacy or raw value) - return as-is
    return result, nil
end

-- Call with automatic retry on network failure
function ClientRF.callWithRetry(name: string, maxRetries: number?, ...: any): (any?, string?)
    maxRetries = maxRetries or 3
    local args = {...}
    
    for attempt = 1, maxRetries do
        local data, err = ClientRF.call(name, table.unpack(args))
        
        if data ~= nil then
            return data, nil
        end
        
        -- Don't retry on explicit server errors (only network failures and timeouts)
        if err and (err ~= "TIMEOUT") and not err:match("^RF call failed:") then
            return nil, err
        end
        
        if attempt < maxRetries then
            task.wait(0.1 * attempt) -- Exponential backoff
        end
    end
    
    return nil, ("Failed after %d retries"):format(maxRetries)
end

-- Type-safe wrapper for specific RFs (optional pattern)
function ClientRF.typed<T>(name: string): TypedCaller<T>
    return function(...: any): (T?, string?)
        local args = table.pack(...)
        local res, err = ClientRF.call(name, table.unpack(args, 1, args.n))
        return res :: T?, err
    end
end

return ClientRF