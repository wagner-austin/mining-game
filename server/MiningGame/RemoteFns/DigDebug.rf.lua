--!strict
-- DigDebug.rf.lua
-- Studio-only RFs to inspect/reset dig telemetry during QA

return function(container)
    local DigService = container:Get("DigService")

    type RFSpec = {
        name: string,
        handler: (ctx: any, ...any) -> any,
        validate: ((...any) -> boolean)?,
        opts: { requireProfile: boolean?, rateLimitSec: number?, debugOnly: boolean? }?,
    }

    local specs: {RFSpec} = {
        {
            name = "GetDigTelemetry",
            handler = function(ctx)
                local t = DigService.GetTelemetry()
                return { ok = true, success = true, telemetry = t }
            end,
            validate = function()
                return true
            end,
            opts = { requireProfile = false, rateLimitSec = 0.25, debugOnly = true },
        },
        {
            name = "ResetDigTelemetry",
            handler = function(ctx)
                DigService.ResetTelemetry()
                return { ok = true, success = true, reset = true }
            end,
            validate = function()
                return true
            end,
            opts = { requireProfile = false, rateLimitSec = 0.25, debugOnly = true },
        },
    }

    return specs
end

