--!strict
-- Magnet.lua
-- Helper functions for auto-collect and owner magnet logic

local Magnet = {}

type ConstantsT = {
	ITEM_PICKUP_RANGE: number,
	LOOT_MAGNET_ENABLED: boolean,
	MAGNET_START_DELAY: number,
	MAGNET_START_RANGE: number,
	MAGNET_MAX_RANGE: number,
	MAGNET_GROWTH_SECONDS: number,
}

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
	effectivePickupRange: (
		self: MagnetT,
		dropData: any,
		player: Player,
		age: number,
		hasAuto: boolean,
		magnetRange: number?
	) -> number,
}

function Magnet.new(ctx): MagnetT
	local c: ConstantsT = ctx.constants
	local self: MagnetT = {
		_GameConfig = ctx.GameConfig,
		_UpgradeService = ctx.UpgradeService,
		_ITEM_MAGNET_RANGE = ctx.defaults.ITEM_MAGNET_RANGE,
		_ITEM_PICKUP_RANGE = c.ITEM_PICKUP_RANGE,
		_LOOT_MAGNET_ENABLED = c.LOOT_MAGNET_ENABLED,
		_MAGNET_START_DELAY = c.MAGNET_START_DELAY,
		_MAGNET_START_RANGE = c.MAGNET_START_RANGE,
		_MAGNET_MAX_RANGE = c.MAGNET_MAX_RANGE,
		_MAGNET_GROWTH_SECONDS = c.MAGNET_GROWTH_SECONDS,
		getAutoCollectRangeFromConfig = function(this: MagnetT): number
			return this._ITEM_MAGNET_RANGE
		end,
		hasAutoCollect = function(this: MagnetT, player: Player): (boolean, number?)
			local UpgradeService = this._UpgradeService
			local ITEM_MAGNET_RANGE = this._ITEM_MAGNET_RANGE
			if not UpgradeService or not UpgradeService.GetPlayerGamepasses then
				return false, nil
			end
			local gamepasses = UpgradeService:GetPlayerGamepasses(player)
			if gamepasses["VIP"] then
				return true, ITEM_MAGNET_RANGE
			end
			return false, nil
		end,
		effectivePickupRange = function(
			this: MagnetT,
			dropData: any,
			player: Player,
			age: number,
			hasAuto: boolean,
			magnetRange: number?
		): number
			local baseRange = this._ITEM_PICKUP_RANGE
			if not dropData then
				return baseRange
			end
			if dropData.owner == player then
				local ownerMagnet: number = 0
				if this._LOOT_MAGNET_ENABLED and age >= this._MAGNET_START_DELAY then
					local startDelay: number = this._MAGNET_START_DELAY
					local growthSec: number = this._MAGNET_GROWTH_SECONDS
					local startRange: number = this._MAGNET_START_RANGE
					local maxRange: number = this._MAGNET_MAX_RANGE
					local t = math.min(1, (age - startDelay) / math.max(growthSec, 0.001))
					ownerMagnet = startRange + t * (maxRange - startRange)
				end
				local autoRange = hasAuto and (magnetRange or this._ITEM_MAGNET_RANGE) or 0
				return math.max(baseRange, ownerMagnet, autoRange)
			else
				return hasAuto and (magnetRange or this._ITEM_MAGNET_RANGE) or baseRange
			end
		end,
	}

	return self
end

return Magnet
