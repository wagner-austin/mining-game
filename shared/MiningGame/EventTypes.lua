--!strict
--[[
    EventTypes.lua
    Central registry of all event types and their payloads for type safety.
    
    Convention:
    - Server->Client events include a "to" field
    - Client->Server events include a "from" field
]]

local Types = require(script.Parent.Types)

-- Strict, tagged event target
export type EventTarget = { kind: "all" } | { kind: "player", player: Player } | { kind: "players", players: { Player } }

-- Currency types (strict)
export type CurrencyType = "coins" | "gems"

-- Action types (strict)
export type InventoryAction = "add" | "remove" | "equip" | "unequip" | "bulk"
export type AnnouncementType = "info" | "warning" | "success" | "error" | "banner"

-- Event name unions
export type ServerToClientEventName =
	"loot.dropped"
	| "currency.changed"
	| "cube.origin.changed"
	| "dig.feedback"
	| "terrain.poke"
	| "runtime.effects.changed"
	| "inventory.changed"
	| "achievement.unlocked"
	| "announcement.broadcast"
	| "sound.play"
	| "notification.push"
	| "equipment.changed"
	| "boosts.changed"
	| "item.collected"
	| "pickup.prompt"
	| "reward.granted"
	| "debug.reset"
	| "profile.updated"
	| "upgrades.changed"

export type ClientToServerEventName =
	"inventory.request.sell"
	| "inventory.request.equip"
	| "dig.request"
	| "upgrade.request.purchase"
	| "cosmetic.request.equip"
	| "settings.update"
	| "metrics.request"

export type InternalServerEventName =
	"player.joined"
	| "player.leaving"
	| "data.loaded"
	| "data.saving"
	| "cube.destroyed"
	| "item.created"
	| "transaction.completed"

export type EventName = ServerToClientEventName | ClientToServerEventName | InternalServerEventName

-- Server -> Client Event Payloads
export type LootDroppedEvent = {
	to: EventTarget,
	payload: {
		counts: { [string]: number },
		position: Vector3?,
		schema: number?, -- e.g. 4 for per-cell spawn
		mode: string?, -- e.g. "per_cell"
		worldPos: Vector3?, -- legacy field name support
	},
}

export type CurrencyChangedEvent = {
	to: Player,
	payload: {
		currency: CurrencyType,
		value: number,
		delta: number?,
	},
}

export type CubeOriginChangedEvent = {
	to: Player,
	payload: {
		origin: CFrame | Vector3,
	},
}

export type DigFeedbackEvent = {
	to: Player,
	payload: {
		size: number,
		cells: { { x: number, y: number, z: number } }?,
		damage: number?,
		materials: { [string]: number }?,
		centerPos: Vector3?,
		cellCount: number?,
		shake: boolean?,
		particles: boolean?,
	},
}

export type TerrainPokeEvent = {
	to: Player,
	payload: {
		pos: Vector3,
	},
}

export type FirstDigEvent = {
	to: Player,
	payload: {
		timestamp: number,
		depth: number?,
		totalBlocksDug: number?,
	},
}

export type RuntimeEffectsChangedEvent = {
	to: Player,
	payload: Types.RuntimeEffects,
}

export type InventoryChangePayload = {
	-- Action-based diff style
	action: InventoryAction?,
	itemId: string?,
	count: number?, -- amount added/removed
	total: number?, -- new total after change
	slot: string?, -- for equip/unequip operations
	previousItem: string?, -- for unequip operations
	-- NOTE: no snapshot payload in v1 (no back-compat)
}

export type InventoryChangedEvent = {
	to: Player,
	payload: InventoryChangePayload,
}

export type AchievementUnlockedEvent = {
	to: EventTarget,
	payload: {
		achievementId: string,
		playerName: string?,
		reward: Types.AchievementReward?,
	},
}

export type AnnouncementBroadcastEvent = {
	to: { kind: "all" },
	payload: {
		message: string,
		type: AnnouncementType,
		duration: number?,
	},
}

export type SoundPlayEvent = {
	to: EventTarget,
	payload: {
		soundId: string,
		position: Vector3?,
		volume: number?,
		pitch: number?,
		originUserId: number?,
	},
}

export type NotificationPushEvent = {
	to: EventTarget,
	payload: {
		message: string,
		type: AnnouncementType,
		duration: number?,
		color: Color3?,
	},
}

export type EquipmentChangedEvent = {
	to: { kind: "all" },
	payload: {
		playerUserId: number,
		slot: string,
		itemId: string?,
	},
}

export type BoostsChangedEvent = {
	to: { kind: "player", player: Player },
	payload: { [string]: number },
}

export type ItemCollectedEvent = {
	to: { kind: "player", player: Player },
	payload: {
		itemId: string,
		count: number,
		rarity: string?,
		position: Vector3?,
	},
}

export type PickupPromptEvent = {
	to: { kind: "player", player: Player },
	payload: any,
}

export type RewardGrantedEvent = {
	to: { kind: "player", player: Player },
	payload: {
		coins: number?,
		gems: number?,
		itemId: string?,
		meta: { [string]: any }?,
	},
}

export type DebugResetEvent = {
	to: { kind: "player", player: Player },
	payload: {},
}

export type ProfileUpdatedEvent = {
	to: { kind: "player", player: Player },
	payload: Types.PlayerProfile,
}

export type UpgradesChangedEvent = {
	to: { kind: "player", player: Player },
	payload: { [string]: number },
}

-- Client -> Server Event Payloads
export type InventoryRequestSellEvent = {
	from: Player,
	payload: {
		itemId: string,
		quantity: number,
	},
}

export type InventoryRequestEquipEvent = {
	from: Player,
	payload: {
		itemId: string,
		slot: string?,
	},
}

export type DigRequestEvent = {
	from: Player,
	payload: {
		position: Vector3,
		toolId: string?,
	},
}

export type UpgradeRequestPurchaseEvent = {
	from: Player,
	payload: {
		upgradeId: string,
	},
}

export type CosmeticRequestEquipEvent = {
	from: Player,
	payload: {
		cosmeticId: string,
		slot: string,
	},
}

export type SettingsUpdateEvent = {
	from: Player,
	payload: {
		key: string,
		value: any,
	},
}

export type MetricsRequestEvent = {
	from: Player,
	payload: {},
}

-- Internal Server Event Payloads
export type PlayerJoinedEvent = {
	player: Player,
}

export type PlayerLeavingEvent = {
	player: Player,
}

export type DataLoadedEvent = {
	player: Player,
	profile: Types.PlayerProfile,
}

export type DataSavingEvent = {
	player: Player,
	profile: Types.PlayerProfile,
}

export type CubeDestroyedEvent = {
	position: Vector3,
	material: string,
	destroyer: Player?,
}

export type ItemCreatedEvent = {
	itemId: string,
	owner: Player?,
	quantity: number,
}

export type TransactionCompletedEvent = {
	player: Player,
	type: string, -- "purchase" | "sale" | "reward"
	items: { [string]: number }?,
	currency: { [string]: number }?,
}

-- Cloth simulation updates (high-rate)
export type ClothUpdateEvent = {
	to: EventTarget,
	payload: {
		id: number,
		offsets: { Vector3 },
	},
}

-- Generic event message type
export type EventMessage<T> = {
	event: string,
	data: T,
}

return {}
