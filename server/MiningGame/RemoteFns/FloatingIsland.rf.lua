--!strict
-- FloatingIsland.rf.lua
-- Debug-only RemoteFunction specs for floating island spawning
-- Contract: top-level { ok, success, ... }. Exceptions: GetServerUnix (scalar), Equipped maps (raw).

local RunService = game:GetService("RunService")

-- Return a factory function that accepts the DI container
return function(container)
    -- Resolve services from the container
    local FloatingIslandService = container:Get("FloatingIslandService")

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
        name = "Debug_SpawnIsland",
        handler = function(ctx, request: any)
            if not isDev(ctx.player) then
                return {
                    ok = false,
                    success = false,
                    err = "FORBIDDEN",
                    reason = "Not authorized"
                }
            end
            
            -- Helper to normalize strings (lowercase + trim)
            local function norm(s)
                return type(s) == "string" and (s:lower():gsub("^%s*(.-)%s*$", "%1")) or nil
            end
            
            -- Extract parameters from request with defaults
            local position = request.position or Vector3.new(0, 50, 0)
            local preset = norm(request.preset)
            local theme = norm(request.theme)
            local customSize = request.customSize
            local elevation = request.elevation
            
            -- Optional: Clamp elevation to reasonable bounds
            if elevation then
                elevation = math.clamp(elevation, -100, 500)
            end
            
            -- Call the service method (colon call since it's a method)
            local ok = FloatingIslandService:GenerateIsland(position, preset, theme, customSize, elevation)
            if ok then
                return {
                    ok = true,
                    success = true
                }
            end
            return {
                ok = false,
                success = false,
                err = "SPAWN_FAILED",
                reason = "Failed to generate island"
            }
        end,
        validate = function(request)
            -- Validate request is a table
            if type(request) ~= "table" then return false end
            -- Validate optional fields have correct types
            if request.position ~= nil and typeof(request.position) ~= "Vector3" then return false end
            if request.customSize ~= nil and typeof(request.customSize) ~= "Vector3" then return false end
            if request.elevation ~= nil and type(request.elevation) ~= "number" then return false end
            if request.preset ~= nil and type(request.preset) ~= "string" then return false end
            if request.theme ~= nil and type(request.theme) ~= "string" then return false end
            return true
        end,
        opts = { requireProfile = false, rateLimitSec = 1.0, debugOnly = true },
    },
}

    return specs
end -- End of factory function