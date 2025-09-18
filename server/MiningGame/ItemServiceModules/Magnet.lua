--!strict
-- Magnet.lua
-- Helper functions for auto-collect and owner magnet logic

local Magnet = {}

export type MagnetT = {
    _GameConfig: any,
    _UpgradeService: any,
    _ITEM_MAGNET_RANGE: number,
    _ITEM_PICKUP_RANGE: number,
    _LOOT_MAGNET_ENABLED: boolean,
    _MAGNET_START_DELAY: number,
    _MAGNET_START_RANGE: number,
    _MAGNET_MAX_RANGE: number,
    _MAGNET_GROWTH_SECONDS: number,
    getAutoCollectRangeFromConfig: (self: MagnetT) -> number,
    hasAutoCollect: (self: MagnetT, player: Player) -> (boolean, number?),
    effectivePickupRange: (self: MagnetT, dropData: any, player: Player, age: number, hasAuto: boolean, magnetRange: number?) -> number,
}

function Magnet.new(ctx): MagnetT
    local c = ctx.constants or {}
    local obj = {
        _GameConfig = ctx.GameConfig,
        _UpgradeService = ctx.UpgradeService,
        _ITEM_MAGNET_RANGE = ctx.defaults.ITEM_MAGNET_RANGE,
        _ITEM_PICKUP_RANGE = c.ITEM_PICKUP_RANGE or 10,
        _LOOT_MAGNET_ENABLED = c.LOOT_MAGNET_ENABLED ~= false,
        _MAGNET_START_DELAY = c.MAGNET_START_DELAY or 0.8,
        _MAGNET_START_RANGE = c.MAGNET_START_RANGE or 12,
        _MAGNET_MAX_RANGE = c.MAGNET_MAX_RANGE or 35,
        _MAGNET_GROWTH_SECONDS = c.MAGNET_GROWTH_SECONDS or 3,
    }

    function obj:getAutoCollectRangeFromConfig(): number
        local GameConfig = self._GameConfig
        local ITEM_MAGNET_RANGE = self._ITEM_MAGNET_RANGE
        if GameConfig and GameConfig.Monetization and GameConfig.Monetization.GAMEPASSES then
            for _, pass in ipairs(GameConfig.Monetization.GAMEPASSES) do
                if pass.id == "AUTO_COLLECT" then
                    return (pass.effects and pass.effects.auto_collect_range) or ITEM_MAGNET_RANGE
                end
            end
        end
        return ITEM_MAGNET_RANGE
    end

    function obj:hasAutoCollect(player: Player): (boolean, number?)
        local UpgradeService = self._UpgradeService
        local ITEM_MAGNET_RANGE = self._ITEM_MAGNET_RANGE
        if not UpgradeService or not UpgradeService.GetPlayerGamepasses then
            return false, nil
        end
        local gamepasses = UpgradeService:GetPlayerGamepasses(player)
        if gamepasses["AUTO_COLLECT"] then
            return true, self:getAutoCollectRangeFromConfig()
        end
        if gamepasses["VIP"] then
            return true, ITEM_MAGNET_RANGE
        end
        return false, nil
    end

    function obj:effectivePickupRange(dropData: any, player: Player, age: number, hasAuto: boolean, magnetRange: number?): number
        local baseRange = self._ITEM_PICKUP_RANGE
        if not dropData then return baseRange end
        if dropData.owner == player then
            local ownerMagnet = 0
            if self._LOOT_MAGNET_ENABLED and age >= self._MAGNET_START_DELAY then
                local t = math.min(1, (age - self._MAGNET_START_DELAY) / math.max(self._MAGNET_GROWTH_SECONDS, 0.001))
                ownerMagnet = self._MAGNET_START_RANGE + t * (self._MAGNET_MAX_RANGE - self._MAGNET_START_RANGE)
            end
            local autoRange = hasAuto and (magnetRange or self._ITEM_MAGNET_RANGE) or 0
            return math.max(baseRange, ownerMagnet, autoRange)
        else
            return hasAuto and (magnetRange or self._ITEM_MAGNET_RANGE) or baseRange
        end
    end

    return obj
end

return Magnet
