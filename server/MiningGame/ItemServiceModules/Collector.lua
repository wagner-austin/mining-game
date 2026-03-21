--!strict
-- Collector.lua
-- Manual and forced collection flows shared by ItemService

local Collector = {}

export type CollectorT = {
	AutoCollectDrop: (dropModel: Model, collector: Player) -> boolean,
	CollectDrop: (dropModel: Model, collector: Player) -> boolean,
	animateAndRemove: (dropModel: Model, player: Player, onRemoved: (() -> ())?) -> (),
	EmitCollected: (player: Player, itemId: string, count: number, rarity: string?) -> (),
	RareSignals: (player: Player, itemId: string, rarity: string?) -> (),
}

-- Import module types for strong typing
local _DropRegistryMod = require(script.Parent.DropRegistry)
type RegistryT = _DropRegistryMod.RegistryT

function Collector.new(ctx: {
	GameConfig: typeof(require(
		game:GetService("ReplicatedStorage"):WaitForChild("MiningGame"):WaitForChild("GameConfig")
	)),
	InventoryService: { AddItemsBulk: (any, Player, { [string]: number }) -> { [string]: number } },
	LootService: { GetItemDefinition: (any, string) -> { id: string, name: string?, rarity: string?, type: string? }? },
	AchievementService: { RecordRarityFind: (any, Player, string) -> () },
	AnnouncementService: { AnnounceRareDrop: (string, string, string) -> () },
	SoundBroadcast: typeof(require(script.Parent.Parent.SoundBroadcast)),
	ItemAnimations: {
		flyDropToPlayer: (Model, Player, (() -> ())?) -> (),
		stopAnimations: (Model, Tween?) -> (),
		pulsePartialPickup: (BasePart) -> (),
	},
	dropRegistry: RegistryT,
	constants: { ITEM_PICKUP_RANGE: number },
	scheduleFinalHardDespawn: ((Model) -> ())?,
}): CollectorT
	local GameConfig = ctx.GameConfig
	local InventoryService = ctx.InventoryService
	local LootService = ctx.LootService
	local AchievementService = ctx.AchievementService
	local AnnouncementService = ctx.AnnouncementService
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Shared = ReplicatedStorage:WaitForChild("MiningGame")
	local TextUtils = require(Shared:WaitForChild("TextUtils"))
	local EventBus = require(Shared:WaitForChild("EventBus"))
	local EventNames = require(Shared:WaitForChild("EventNames"))
	local Bus = EventBus.global()
	local Time = require(Shared:WaitForChild("Time"))
	local MathUtils = require(Shared:WaitForChild("MathUtils"))
	local Logger = require(Shared:WaitForChild("Logger"))
	local log = Logger.new("ItemService.Collector")
	local SoundBroadcast = ctx.SoundBroadcast
	local ItemAnimations = ctx.ItemAnimations
	local dropRegistry = ctx.dropRegistry
	local ErrorService = require(script.Parent.Parent.ErrorService)

	local ITEM_PICKUP_RANGE: number = ctx.constants.ITEM_PICKUP_RANGE

	local function animateAndRemove(dropModel: Model, player: Player, onRemoved: (() -> ())?)
		if dropModel.PrimaryPart then
			ItemAnimations.stopAnimations(dropModel, dropRegistry.state.hoverTweens[dropModel])
			dropRegistry.state.hoverTweens[dropModel] = nil
			ItemAnimations.flyDropToPlayer(dropModel, player, function()
				dropRegistry.removeDrop(dropModel)
				if onRemoved then
					ErrorService.safecall("Collector:onRemoved", onRemoved)
				end
			end)
		else
			dropRegistry.removeDrop(dropModel)
			if onRemoved then
				ErrorService.safecall("Collector:onRemoved", onRemoved)
			end
		end
	end

	local function emitCollected(player: Player, itemId: string, count: number, rarity: string?)
		Bus:emit(EventNames.ITEM_COLLECTED, {
			to = { kind = "player", player = player },
			payload = {
				itemId = itemId,
				count = count,
				rarity = rarity,
			},
		})
	end

	local function announceRare(player: Player, itemId: string, rarity: string?)
		if not rarity then
			return
		end
		if rarity ~= "EPIC" and rarity ~= "LEGENDARY" and rarity ~= "MYTHIC" then
			return
		end
		local itemDef = LootService:GetItemDefinition(itemId)
		local displayName = TextUtils.prettifyItemName(itemId, itemDef)
		AnnouncementService.AnnounceRareDrop(player.DisplayName, displayName, rarity)
	end

	local function rareSignals(player: Player, itemId: string, rarity: string?)
		if not rarity then
			return
		end
		if rarity == "EPIC" or rarity == "LEGENDARY" or rarity == "MYTHIC" then
			AchievementService:RecordRarityFind(player, rarity)
			announceRare(player, itemId, rarity)
		end
	end

	local function addToInventory(player: Player, itemId: string, count: number): number
		local actuallyAdded = InventoryService:AddItemsBulk(player, { [itemId] = count })
		local added = actuallyAdded[itemId] or 0
		return added
	end

	local function tryMakePublicOnStackCap(dropData)
		local def = LootService:GetItemDefinition(dropData.itemId)
		if GameConfig.Loot.ALLOW_PUBLIC_ON_STACK_CAP and def and (def.type == "pickaxe" or def.type == "cosmetic") then
			local owner: Player? = dropData.owner
			if owner then
				dropRegistry.state.playerDropCounts[owner] =
					MathUtils.saturatingSub((dropRegistry.state.playerDropCounts[owner] or 0), 1)
			end
			dropData.owner = nil
			log:debug("Stack-capped item made public: %s", dropData.itemId)
			return true
		end
		return false
	end

	local function AutoCollectDrop(dropModel: Model, collector: Player): boolean
		local dropData = dropRegistry.state.activeDrops[dropModel] :: _DropRegistryMod.DropDataT
		if not dropData or dropData.claimed then
			return false
		end

		dropData.claimed = true

		local addedCount = addToInventory(collector, dropData.itemId, dropData.count)
		if addedCount > 0 then
			emitCollected(collector, dropData.itemId, addedCount, dropData.rarity)
			if dropModel.PrimaryPart then
				SoundBroadcast.Collect(collector, dropModel.PrimaryPart.Position, dropData.rarity or "")
			end
			rareSignals(collector, dropData.itemId, dropData.rarity)

			-- Demote noisy event to DEBUG for performance
			log:debug(
				"[EVENT] item_auto_collected | uid=%s, itemId=%s, count=%d, rarity=%s",
				tostring(collector.UserId),
				tostring(dropData.itemId),
				addedCount,
				tostring(dropData.rarity)
			)

			local remaining = dropData.count - addedCount
			if remaining > 0 then
				dropData.claimed = false
				dropData.count = remaining
				dropRegistry.updateDropCountLabel(dropModel, remaining)
				return true
			else
				animateAndRemove(dropModel, collector)
				return true
			end
		else
			-- Inventory full / at stack limit case
			if tryMakePublicOnStackCap(dropData) and ctx.scheduleFinalHardDespawn then
				ctx.scheduleFinalHardDespawn(dropModel)
			end
			dropData.claimed = false
			return false
		end
	end

	local function CollectDrop(dropModel: Model, collector: Player): boolean
		local dropData = dropRegistry.state.activeDrops[dropModel] :: any
		log:debug("CollectDrop called - dropData exists:", dropData ~= nil)
		if not dropData or dropData.claimed then
			log:debug("Drop not found or already claimed")
			return false
		end

		if dropData.owner and dropData.owner ~= collector then
			log:debug("Drop owned by another player")
			return false
		end

		local character = collector.Character
		if not character or not character.PrimaryPart then
			log:debug("No character or PrimaryPart")
			return false
		end
		if not dropModel.PrimaryPart then
			log:debug("Drop has no PrimaryPart")
			return false
		end

		local distance = (character.PrimaryPart.Position - dropModel.PrimaryPart.Position).Magnitude
		log:debug("Pickup distance:", distance, "Max range:", ITEM_PICKUP_RANGE + 1)
		if distance > (ITEM_PICKUP_RANGE + 1) then
			log:debug("Player too far from drop")
			return false
		end

		local now: number = Time.mono()
		local lastPickup = dropRegistry.state.playerPickupCooldowns[collector] or 0
		if now - lastPickup < 0.1 then
			return false
		end
		dropRegistry.state.playerPickupCooldowns[collector] = now

		dropData.claimed = true

		local addedCount = addToInventory(collector, dropData.itemId, dropData.count)
		if addedCount > 0 then
			local remaining = dropData.count - addedCount

			emitCollected(collector, dropData.itemId, addedCount, dropData.rarity)
			rareSignals(collector, dropData.itemId, dropData.rarity)

			-- Demote noisy event to DEBUG for performance
			log:debug(
				"[EVENT] item_collected | uid=%s, itemId=%s, count=%d, rarity=%s",
				tostring(collector.UserId),
				tostring(dropData.itemId),
				addedCount,
				tostring(dropData.rarity)
			)

			if dropModel.PrimaryPart then
				SoundBroadcast.Collect(collector, dropModel.PrimaryPart.Position, dropData.rarity or "")
			end

			if remaining > 0 then
				dropData.count = remaining
				dropData.claimed = false
				dropRegistry.updateDropCountLabel(dropModel, remaining)
				if dropModel.PrimaryPart then
					ItemAnimations.pulsePartialPickup(dropModel.PrimaryPart)
				end
				log:debug(
					"Partial pickup %s: collected %d, remaining %d (by %s)",
					dropData.itemId,
					addedCount,
					remaining,
					collector.Name
				)
				return true
			else
				animateAndRemove(dropModel, collector)
				log:debug("Item fully collected: %s x%d by %s", dropData.itemId, addedCount, collector.Name)
				return true
			end
		else
			dropData.claimed = false
			local Contracts = require(Shared:WaitForChild("EventContracts"))
			Bus:emit(EventNames.NOTIFICATION_PUSH, {
				to = { kind = "player", player = collector },
				payload = Contracts.NOTIFICATION_PUSH({
					message = "Inventory full!",
					type = "error",
				}),
			})
			return false
		end
	end

	return {
		AutoCollectDrop = AutoCollectDrop,
		CollectDrop = CollectDrop,
		animateAndRemove = animateAndRemove,
		EmitCollected = emitCollected,
		RareSignals = rareSignals,
	}
end

return Collector
