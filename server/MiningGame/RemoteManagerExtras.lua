--!strict
-- RemoteManagerExtras.lua
-- Strict wrapper for RemoteManager with no defaults
local RM = require(script.Parent.RemoteManager)

type RegisterOptions = RM.RegisterOptions
type Context = RM.Context
type HandlerResult<T> = RM.HandlerResult<T>

local function ensure(name: string, opts: RegisterOptions): RegisterOptions
    assert(opts ~= nil, ("'%s' requires opts"):format(name))
    assert(type(opts.rateLimitSec) == "number" and opts.rateLimitSec >= 0,
        ("'%s' requires opts.rateLimitSec (number >= 0)"):format(name))
    assert(type(opts.schema) == "function",
        ("'%s' requires opts.schema (function)"):format(name))
    return opts
end

local function RF<T>(name: string, handler: (Context, ...any) -> HandlerResult<T>, opts: RegisterOptions)
    return RM.registerRF(name, handler, ensure(name, opts))
end

local function RE(name: string, handler: (Context, ...any) -> (), opts: RegisterOptions)
    return RM.registerRE(name, handler, ensure(name, opts))
end

return { RF = RF, RE = RE }