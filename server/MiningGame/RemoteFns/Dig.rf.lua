--!strict
-- Dig.rf.lua
-- RemoteFunction specs for digging operations
-- Contract: top-level { ok, success, ... } for all user-facing RFs

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(MiningGame:WaitForChild("Logger"))
local log = Logger.new("RF:Dig")

-- Return a factory function that accepts the DI container
return function(container)
    -- Resolve services from the container
    local DataService = container:Get("DataService")
    local DigService = container:Get("DigService")
    local UpgradeService = container:Get("UpgradeService")
    local GridService = container:Get("GridService")
    local SessionService = container:Get("SessionService")
    local CubePositionService = container:Get("CubePositionService")

    type RFSpec = {
    name: string,
    handler: (ctx: any, ...any) -> any,
    validate: ((...any) -> boolean)?,
    opts: {requireProfile: boolean?, rateLimitSec: number?}?
}

    local specs: {RFSpec} = {
    {
        name = "GetProfile",
        handler = function(ctx)
            local player = ctx.player
            local profile = DataService:GetPlayerData(player)
            if not profile then 
                return {
                    ok = false,
                    success = false,
                    err = "NO_PROFILE",
                    reason = "No profile found"
                }
            end
            
            -- Get data in correct order for ComputeEffectiveStats
            local gamepasses = UpgradeService:GetPlayerGamepasses(player)
            local activePets = UpgradeService:GetActivePets(profile)
            local stats = UpgradeService:ComputeEffectiveStats(profile, gamepasses, activePets)
            
            -- Get cube stats from the state instead of non-existent methods
            local cubeState = DataService:GetCubeData(player)
            local cubeStats = cubeState and GridService:GetChunkStats(cubeState) or nil
            local cubeOrigin = DigService.playerCubes[player] and DigService.playerCubes[player].origin or nil
            
            -- Return at top level to match client expectations
            return {
                ok = true,
                success = true,
                profile = profile,
                effectiveStats = stats,
                cubeStats = cubeStats,
                gamepasses = gamepasses,
                cubeOrigin = cubeOrigin,
            }
        end,
        opts = { requireProfile = true, rateLimitSec = 0.25 },
    },
    
    {
        name = "RequestDig",
        handler = function(ctx, position)
            -- Visibility into incoming dig requests
            pcall(function()
                log:info("RequestDig: player=%s pos=%s", ctx.player and ctx.player.Name or "?", tostring(position))
            end)
            -- Client sends position directly, not wrapped in a request object
            -- ProcessDigRequest already returns a Result-like format with ok field
            local res = DigService:ProcessDigRequest(ctx.player, position)
            pcall(function()
                if res and res.ok then
                    log:info("RequestDig: OK cells=%s next=%.3f", tostring(res.cellsDug or 0), tonumber(res.nextAllowedAt or 0))
                else
                    log:info("RequestDig: FAIL reason=%s", (res and tostring(res.reason)) or "(nil)")
                end
            end)
            return res
        end,
        validate = function(position)
            -- Client sends Vector3 directly
            return typeof(position) == "Vector3"
        end,
        opts = { requireProfile = true, rateLimitSec = 0.05 },
    },
    
    {
        name = "StartContinuousDig",
        handler = function(ctx, position)
            -- Client likely sends position directly
            DigService:StartHoldDig(ctx.player, position)
            -- Return at top level for consistency
            return {
                ok = true,
                success = true,
                started = true
            }
        end,
        validate = function(position)
            return typeof(position) == "Vector3"
        end,
        opts = { requireProfile = true, rateLimitSec = 0.1 },
    },
    
    {
        name = "StopContinuousDig",
        handler = function(ctx)
            -- Call the actual method name in DigService
            DigService:StopHoldDig(ctx.player)
            -- Return at top level for consistency
            return {
                ok = true,
                success = true,
                stopped = true
            }
        end,
        opts = { requireProfile = true, rateLimitSec = 0.1 },
    },
    
    {
        name = "RespawnCubeModel",
        handler = function(ctx)
            local player = ctx.player
            -- Get cube state from DataService
            local cubeState = DataService:GetCubeData(player)
            -- Get cube model info from DigService
            local cubeInfo = DigService.playerCubes[player]
            
            if cubeState and cubeInfo then
                -- Destroy old model if exists
                if cubeInfo.model then
                    cubeInfo.model:Destroy()
                    cubeInfo.model = nil
                end
                
                -- Force re-initialization of the cube
                DigService:InitializePlayerCube(player)
                
                return {
                    ok = true,
                    success = true,
                    respawned = true
                }
            end
            return {
                ok = false,
                success = false,
                err = "NO_CUBE",
                reason = "No cube data found"
            }
        end,
        opts = { requireProfile = true, rateLimitSec = 2.0 },
    },
}

    return specs
end -- End of factory function
