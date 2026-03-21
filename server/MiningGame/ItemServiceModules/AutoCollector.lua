--!strict
-- AutoCollector.lua
-- Handles periodic auto-collection and owner magnet behavior

local AutoCollector = {}

export type AutoCollectorT = {
	handleAutoCollection: (dt: number) -> (),
}

function AutoCollector.new(ctx): AutoCollectorT
	type Ctx = {
		Players: any,
		Time: any,
		LootService: any,
		InventoryService: any,
		AchievementService: any,
		AnnouncementService: any,
		ItemAnimations: any,
		dropRegistry: any,
		Bus: any,
		EventNames: any,
		Magnet: any,
		collector: any,
		constants: {
			ITEM_PICKUP_RANGE: number,
			ITEM_MAGNET_RANGE: number,
			LOOT_MAGNET_ENABLED: boolean,
			MAGNET_MAX_RANGE: number,
			OWNER_GRACE_SECONDS: number,
			AUTO_COLLECT_INTERVAL: number,
		},
	}
	ctx = ctx :: Ctx
	local Players = ctx.Players
	local Time = ctx.Time
	local LootService = ctx.LootService
	local InventoryService = ctx.InventoryService
	local AchievementService = ctx.AchievementService
	local AnnouncementService = ctx.AnnouncementService
	local ItemAnimations = ctx.ItemAnimations
	local dropRegistry = ctx.dropRegistry
	local Bus = ctx.Bus
	local EventNames = ctx.EventNames
	local Magnet = ctx.Magnet
	local collectorHelpers = ctx.collector

	local ITEM_PICKUP_RANGE: number = ctx.constants.ITEM_PICKUP_RANGE
	local ITEM_MAGNET_RANGE: number = ctx.constants.ITEM_MAGNET_RANGE
	local LOOT_MAGNET_ENABLED: boolean = ctx.constants.LOOT_MAGNET_ENABLED
	-- Growth parameters used internally by Magnet; not needed here
	local MAGNET_MAX_RANGE: number = ctx.constants.MAGNET_MAX_RANGE

	local autoCollectAccumulator = 0

	local function handleAutoCollection(dt: number)
		autoCollectAccumulator += dt
		if autoCollectAccumulator < (ctx.constants.AUTO_COLLECT_INTERVAL or 0.2) then
			return
		end
		autoCollectAccumulator = 0

		local DigPerformance = require(script.Parent.Parent.DigPerformance)
		DigPerformance.measureSection("AC_Tick", function()
			for _, player in ipairs(Players:GetPlayers()) do
				local character = player.Character
				if not (character and character.PrimaryPart) then
					continue
				end

				local playerPos = character.PrimaryPart.Position
				local hasAuto, magnetRange = Magnet:hasAutoCollect(player)
				local baseRange = hasAuto and (magnetRange or ITEM_MAGNET_RANGE) or ITEM_PICKUP_RANGE
				local candidateRange = (
					LOOT_MAGNET_ENABLED
					and MAGNET_MAX_RANGE
					and math.max(baseRange, MAGNET_MAX_RANGE)
				) or baseRange
				local nearby = dropRegistry.getNearbyDrops(playerPos, candidateRange)

				local perItem: { [string]: { Model } } = {}
				for _, dropModel in ipairs(nearby) do
					local dropData = dropRegistry.state.activeDrops[dropModel]
					if dropData and not dropData.claimed and dropModel.PrimaryPart then
						local now: number = Time.mono()
						local age = now - dropData.spawnTime
						local canPickup = not dropData.owner
							or (dropData.owner == player)
							or (age > (ctx.constants.OWNER_GRACE_SECONDS or 5))
						if canPickup then
							local effectiveRange =
								Magnet:effectivePickupRange(dropData, player, age, hasAuto, magnetRange)
							local distance = (dropModel.PrimaryPart.Position - playerPos).Magnitude
							if distance <= effectiveRange then
								local bucket = perItem[dropData.itemId]
								if not bucket then
									bucket = {}
									perItem[dropData.itemId] = bucket
								end
								table.insert(bucket, dropModel)
							end
						end
					end
				end

				if next(perItem) ~= nil then
					local countsById: { [string]: number } = {}
					for itemId, list in pairs(perItem) do
						countsById[itemId] = #list
					end

					local actuallyAdded = InventoryService:AddItemsBulk(player, countsById)

					for itemId, added in pairs(actuallyAdded) do
						if added > 0 then
							local bucket = perItem[itemId]
							local def = LootService:GetItemDefinition(itemId)
							local rarity = def and def.rarity or nil
							if collectorHelpers and collectorHelpers.EmitCollected then
								collectorHelpers.EmitCollected(player, itemId, added, rarity)
							else
								Bus:emit(EventNames.ITEM_COLLECTED, {
									to = { kind = "player", player = player },
									payload = { itemId = itemId, count = added, rarity = rarity },
								})
							end
							if collectorHelpers and collectorHelpers.RareSignals then
								collectorHelpers.RareSignals(player, itemId, rarity)
							else
								if rarity and (rarity == "EPIC" or rarity == "LEGENDARY" or rarity == "MYTHIC") then
									AchievementService.RecordRarityFind(player, rarity)
									AnnouncementService.AnnounceRareDrop(
										player.DisplayName,
										(def and def.name) or itemId,
										rarity
									)
								end
							end

							for i = 1, math.min(added, #bucket) do
								local model = bucket[i]
								local d = dropRegistry.state.activeDrops[model]
								if d and not d.claimed then
									d.claimed = true
									if collectorHelpers and collectorHelpers.animateAndRemove then
										collectorHelpers.animateAndRemove(model, player)
									else
										if model.PrimaryPart then
											ItemAnimations.stopAnimations(model, dropRegistry.state.hoverTweens[model])
											dropRegistry.state.hoverTweens[model] = nil
											ItemAnimations.flyDropToPlayer(model, player, function()
												dropRegistry.removeDrop(model)
											end)
										else
											dropRegistry.removeDrop(model)
										end
									end
								end
							end
						end
					end
				end
			end -- for Players
		end) -- AC_Tick
	end

	return {
		handleAutoCollection = handleAutoCollection,
	}
end

return AutoCollector
