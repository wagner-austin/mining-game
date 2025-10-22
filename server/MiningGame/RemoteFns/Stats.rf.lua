--!strict
-- Stats.rf.lua
-- RemoteFunction: expose effective dig stats (size, luck, delay, hardness) for the local player

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(Shared:WaitForChild("Logger"))

local log = Logger.new("StatsRF")

return function(container)
    local DataService = container:Get("DataService")
    local UpgradeService = container:Get("UpgradeService")

    type RFSpec = {
        name: string,
        handler: (ctx: any, ...any) -> any,
        validate: ((...any) -> boolean)?,
        opts: {requireProfile: boolean?, rateLimitSec: number?}?,
    }

    local specs: {RFSpec} = {
        {
            name = "GetEffectiveStats",
            validate = function()
                return true
            end,
            handler = function(ctx)
                local player = ctx.player
                local profile = DataService:GetPlayerData(player)
                if not profile then
                    return { ok = false, success = false, err = "NO_PROFILE" }
                end

                -- Some stat providers used by UpgradeService depend on player & profile
                local gamepasses = UpgradeService.GetPlayerGamepasses and UpgradeService:GetPlayerGamepasses(player) or nil
                local activePets = UpgradeService.GetActivePets and UpgradeService:GetActivePets(profile) or nil
                local eff = UpgradeService:ComputeEffectiveStats(profile, gamepasses, activePets)
                if not eff then
                    return { ok = false, success = false, err = "NO_STATS" }
                end

                return {
                    ok = true,
                    success = true,
                    effectiveStats = {
                        delay = eff.delay,
                        size = eff.size,
                        luck = eff.luck,
                        hardness = eff.hardness,
                    },
                    materialId = profile.materialId,
                }
            end,
            opts = { requireProfile = true, rateLimitSec = 0.2 },
        },
    }

    return specs
end

