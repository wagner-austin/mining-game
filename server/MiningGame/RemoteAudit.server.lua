--!strict
-- RemoteAudit.server.lua
-- Studio-only strict audit that errors on any misconfig
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then return end

local RemoteManager = require(script.Parent.RemoteManager)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(MiningGame:WaitForChild("Logger"))
local log = Logger.new("RemoteAudit")

task.wait(1) -- Allow InitRemotes + registrations to finish

local function ensure(cond: boolean, msg: string)
    if not cond then error(msg, 2) end
end

local function check(kind: string, map: {[string]: any})
    for name, meta in pairs(map) do
        ensure(type(name) == "string" and name ~= "", ("[RF Audit] invalid %s name"):format(kind))
        ensure(type(meta) == "table", ("[RF Audit] %s meta missing for %s"):format(kind, name))
        ensure(type(meta.rateLimitSec) == "number" or meta.rateLimitSec == 0,
            ("[RF Audit] %s '%s' missing/invalid rateLimitSec"):format(kind, name))
        ensure(type(meta.schema) == "function",
            ("[RF Audit] %s '%s' missing/invalid schema"):format(kind, name))
        ensure(type(meta.requireProfile) == "boolean",
            ("[RF Audit] %s '%s' requireProfile not boolean"):format(kind, name))
    end
end

check("RF", RemoteManager.getRegisteredRF())
check("RE", RemoteManager.getRegisteredRE())
log:info("strict pass")
