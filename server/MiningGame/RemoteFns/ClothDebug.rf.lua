--!strict
-- ClothDebug.rf.lua
-- Debug-only RemoteFunction specs for cloth simulation testing
-- Contract: top-level { ok, success, ... }. Exceptions: GetServerUnix (scalar), Equipped maps (raw).

local RunService = game:GetService("RunService")

-- Return a factory function that accepts the DI container
return function(container)
    -- Try to get ClothService from container (optional)
    local ClothService = container:tryGet("ClothService")

type RFSpec = {
    name: string,
    handler: (ctx: any, ...any) -> any,
    validate: ((...any) -> boolean)?,
    opts: {requireProfile: boolean?, rateLimitSec: number?, debugOnly: boolean?}?
}

-- Helper
local function isDev(player: Player): boolean
    return RunService:IsStudio()
end

local specs: {RFSpec} = {
    {
        name = "ClothSpawn",
        handler = function(ctx, position: Vector3?, size: number?)
            if not isDev(ctx.player) then
                return {
                    ok = false,
                    success = false,
                    err = "FORBIDDEN",
                    reason = "Not authorized"
                }
            end
            if ClothService then
                -- Forward parameters if/when ClothService supports them
                local opts = {}
                if typeof(position) == "Vector3" then
                    opts.position = position
                end
                if type(size) == "number" then
                    opts.size = size
                end
                -- For now, ClothServiceSimple doesn't use opts, but ready for future
                local ok = ClothService:spawnFor(ctx.player, opts)
                if ok then
                    return {
                        ok = true,
                        success = true
                    }
                else
                    return {
                        ok = false,
                        success = false,
                        err = "APPLY_FAILED",
                        reason = "Failed to apply cloth operation"
                    }
                end
            else
                return {
                    ok = false,
                    success = false,
                    err = "NOT_IMPLEMENTED",
                    reason = "Cloth service not available"
                }
            end
        end,
        validate = function(position, size)
            if position ~= nil and typeof(position) ~= "Vector3" then return false end
            if size ~= nil then
                if type(size) ~= "number" or size <= 0 or size > 100 then return false end
            end
            return true
        end,
        opts = { requireProfile = false, rateLimitSec = 0.5, debugOnly = true },
    },
    
    {
        name = "ClothDestroy",
        handler = function(ctx, clothId: string?)
            if not isDev(ctx.player) then
                return {
                    ok = false,
                    success = false,
                    err = "FORBIDDEN",
                    reason = "Not authorized"
                }
            end
            if ClothService then
                ClothService:destroyFor(ctx.player)
                return {
                    ok = true,
                    success = true
                }
            else
                return {
                    ok = false,
                    success = false,
                    err = "NOT_IMPLEMENTED",
                    reason = "Cloth service not available"
                }
            end
        end,
        validate = function(clothId)
            if clothId ~= nil and type(clothId) ~= "string" then return false end
            return true
        end,
        opts = { requireProfile = false, rateLimitSec = 0.5, debugOnly = true },
    },
}

    return specs
end -- End of factory function