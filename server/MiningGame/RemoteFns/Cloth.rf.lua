--!strict
-- Cloth.rf.lua
-- RemoteFunction specs for cloth simulation control
-- Contract: top-level { ok, success, ... } for user-facing handlers.

local RunService = game:GetService("RunService")

return function(container)
    local ClothService = container:tryGet("ClothService")

    local function serviceUnavailable()
        return {
            ok = false,
            success = false,
            err = "NOT_IMPLEMENTED",
            reason = "Cloth service not available",
        }
    end

    local function isDev(player: Player): boolean
        return RunService:IsStudio()
    end

    local specs = {
        {
            name = "ClothSpawn",
            handler = function(ctx, positionOrOpts: any, size: any)
                if not isDev(ctx.player) then
                    return {
                        ok = false,
                        success = false,
                        err = "FORBIDDEN",
                        reason = "Not authorized",
                    }
                end

                if not ClothService then
                    return serviceUnavailable()
                end

                local opts = {}
                if typeof(positionOrOpts) == "Vector3" then
                    opts.position = positionOrOpts
                elseif type(positionOrOpts) == "table" then
                    for key, value in pairs(positionOrOpts) do
                        opts[key] = value
                    end
                end

                if type(size) == "number" then
                    opts.size = size
                elseif typeof(size) == "Vector3" and opts.position == nil then
                    opts.position = size
                end

                local ok = ClothService:spawnFor(ctx.player, opts)
                if ok then
                    return { ok = true, success = true }
                else
                    return {
                        ok = false,
                        success = false,
                        err = "APPLY_FAILED",
                        reason = "Failed to apply cloth operation",
                    }
                end
            end,
            validate = function(positionOrOpts, size)
                local function validSize(n)
                    return type(n) == "number" and n > 0 and n <= 100
                end

                if positionOrOpts == nil and size == nil then return true end

                if typeof(positionOrOpts) == "Vector3" then
                    if size == nil or validSize(size) then
                        return true
                    end
                    return false
                end

                if type(positionOrOpts) == "table" then
                    if size ~= nil then return false end
                    local span = positionOrOpts.span
                    if span ~= nil and not validSize(span) then
                        return false
                    end
                    return true
                end

                if size ~= nil then
                    if typeof(size) == "Vector3" and positionOrOpts == nil then
                        return true
                    end
                    if validSize(size) and positionOrOpts == nil then
                        return true
                    end
                end

                return false
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
                        reason = "Not authorized",
                    }
                end

                if not ClothService then
                    return serviceUnavailable()
                end

                ClothService:destroyFor(ctx.player)
                return { ok = true, success = true }
            end,
            validate = function(clothId)
                if clothId ~= nil and type(clothId) ~= "string" then return false end
                return true
            end,
            opts = { requireProfile = false, rateLimitSec = 0.5, debugOnly = true },
        },
    }

    return specs
end