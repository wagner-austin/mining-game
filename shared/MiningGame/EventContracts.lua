--!strict
-- EventContracts.lua - runtime shape checks for frequent EventBus payloads

-- Explicit payload type exports for strict typing (no 'any' types)
export type CompositionApplyRequestPayload = {
	userId: number,
	variationMode: string?,
	preserveAir: boolean?,
	themeId: string?,
}

local function assertType(cond: boolean, msg: string)
	if not cond then
		error(msg, 3)
	end
end

local Contracts = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local EventNames = require(MiningGame:WaitForChild("EventNames"))

function Contracts.CURRENCY_CHANGED(payload: { currency: string, balance: number, delta: number })
	assertType(type(payload.currency) == "string", "currency required")
	assertType(type(payload.balance) == "number", "balance required")
	assertType(type(payload.delta) == "number", "delta required")
	return payload
end

function Contracts.INVENTORY_CHANGED(payload: { [string]: number })
	assertType(type(payload) == "table", "inventory map required")
	return payload
end

-- Delta-based inventory update: only changed item counts
-- Example: { iron = 2, coal = 1, head_hat_cowboy = 1 }
function Contracts.INVENTORY_DELTA(payload: { [string]: number })
	assertType(type(payload) == "table", "delta map required")
	return payload
end

function Contracts.EQUIPMENT_CHANGED(payload: { playerUserId: number, slot: string, itemId: string? })
	assertType(type(payload.playerUserId) == "number", "playerUserId required")
	assertType(type(payload.slot) == "string", "slot required")
	return payload
end

function Contracts.NOTIFICATION_PUSH(payload: { type: string, message: string, color: Color3? })
	assertType(type(payload.type) == "string", "type required")
	assertType(type(payload.message) == "string", "message required")
	return payload
end

function Contracts.BOOSTS_CHANGED(payload: { speed: number?, size: number?, luck: number? })
	assertType(type(payload) == "table", "payload required")
	-- All boost fields are optional (nil means not active)
	if payload.speed then
		assertType(type(payload.speed) == "number", "speed must be number")
	end
	if payload.size then
		assertType(type(payload.size) == "number", "size must be number")
	end
	if payload.luck then
		assertType(type(payload.luck) == "number", "luck must be number")
	end
	return payload
end

-- Reward grant payload (optional fields)
function Contracts.REWARD_GRANTED(payload: { coins: number?, gems: number?, meta: { [string]: any }? })
	assertType(type(payload) == "table", "payload required")
	if payload.coins ~= nil then
		assertType(type(payload.coins) == "number", "coins must be number")
	end
	if payload.gems ~= nil then
		assertType(type(payload.gems) == "number", "gems must be number")
	end
	-- meta is free-form; presence is enough
	return payload
end

-- Mega dig request (from MonetizationService to DigService)
function Contracts.MEGA_DIG_REQUEST(
	payload: { player: Player, position: Vector3, sizeBoost: number }
): { player: Player, position: Vector3, sizeBoost: number }
	assertType(typeof(payload.player) == "Instance", "player required")
	assertType(typeof(payload.position) == "Vector3", "position required")
	assertType(type(payload.sizeBoost) == "number", "sizeBoost required")
	return payload
end

-- Auto dig start request (from MonetizationService to DigService)
function Contracts.AUTO_DIG_START(payload: { player: Player }): { player: Player }
	assertType(typeof(payload.player) == "Instance", "player required")
	return payload
end

-- Composition apply request (from CubeMaterialService to CompositionService)
function Contracts.COMPOSITION_APPLY_REQUEST(payload: CompositionApplyRequestPayload): CompositionApplyRequestPayload
	assertType(type(payload) == "table", "payload required")
	assertType(type(payload.userId) == "number", "userId required")
	if payload.variationMode ~= nil then
		assertType(type(payload.variationMode) == "string", "variationMode must be string")
	end
	-- preserveAir optional
	return payload
end

-- Island spawn request (for breaking WorldGen ↔ FloatingIsland cycle)
function Contracts.ISLAND_SPAWN_REQUEST(payload: {
	position: Vector3,
	preset: string?,
	theme: string?,
	customSize: Vector3?,
	elevation: number?,
	treeCount: number?,
	treeScale: number?,
}): {
	position: Vector3,
	preset: string?,
	theme: string?,
	customSize: Vector3?,
	elevation: number?,
	treeCount: number?,
	treeScale: number?,
}
	assertType(typeof(payload.position) == "Vector3", "position Vector3 required")
	-- All other fields are optional
	return payload
end

-- Island remove request
function Contracts.ISLAND_REMOVE_REQUEST(payload: {
	position: Vector3?,
	all: boolean?,
}): {
	position: Vector3?,
	all: boolean?,
}
	assertType(type(payload) == "table", "payload required")
	-- Either position or all=true
	if not payload.all then
		assertType(typeof(payload.position) == "Vector3", "position Vector3 required when not removing all")
	end
	return payload
end

-- Tree spawn request
function Contracts.TREE_SPAWN_REQUEST(payload: {
	position: Vector3?,
	bounds: { minX: number, maxX: number, minZ: number, maxZ: number }?,
	center: Vector3?,
	sizeX: number?,
	sizeZ: number?,
	densityPer100x100: number?,
	minCount: number?,
	maxCount: number?,
	allowWater: boolean?,
	seed: number?,
	minSpacing: number?,
	playerKeepoutRadius: number?,
	style: string?,
	phase: string?,
	allowedPhases: { string }?,
}): {
	position: Vector3?,
	bounds: { minX: number, maxX: number, minZ: number, maxZ: number }?,
	center: Vector3?,
	sizeX: number?,
	sizeZ: number?,
	densityPer100x100: number?,
	minCount: number?,
	maxCount: number?,
	allowWater: boolean?,
	seed: number?,
	minSpacing: number?,
	playerKeepoutRadius: number?,
	style: string?,
	phase: string?,
	allowedPhases: { string }?,
}
	assertType(type(payload) == "table", "payload required")
	if payload.position ~= nil then
		assertType(typeof(payload.position) == "Vector3", "position must be Vector3")
	else
		if payload.bounds ~= nil then
			assertType(type(payload.bounds.minX) == "number", "bounds.minX required")
			assertType(type(payload.bounds.maxX) == "number", "bounds.maxX required")
			assertType(type(payload.bounds.minZ) == "number", "bounds.minZ required")
			assertType(type(payload.bounds.maxZ) == "number", "bounds.maxZ required")
		else
			assertType(typeof(payload.center) == "Vector3", "center Vector3 required when no bounds/position")
			assertType(type(payload.sizeX) == "number" and type(payload.sizeZ) == "number", "sizeX/sizeZ required")
		end
	end
	return payload
end

-- Tree clear request (supports clearing all or by bounds in future)
function Contracts.TREE_CLEAR_REQUEST(payload: {
	all: boolean?,
	bounds: { minX: number, maxX: number, minZ: number, maxZ: number }?,
})
	assertType(type(payload) == "table" or payload == nil, "payload must be table or nil")
	payload = payload or { all = true }
	if payload.bounds ~= nil then
		assertType(type(payload.bounds.minX) == "number", "bounds.minX required")
		assertType(type(payload.bounds.maxX) == "number", "bounds.maxX required")
		assertType(type(payload.bounds.minZ) == "number", "bounds.minZ required")
		assertType(type(payload.bounds.maxZ) == "number", "bounds.maxZ required")
	end
	return payload
end

-- Rock spawn/clear requests
function Contracts.ROCK_SPAWN_REQUEST(payload: {
	position: Vector3?,
	bounds: { minX: number, maxX: number, minZ: number, maxZ: number }?,
	center: Vector3?,
	sizeX: number?,
	sizeZ: number?,
	densityPer100x100: number?,
	minCount: number?,
	maxCount: number?,
	count: number?,
	allowWater: boolean?,
	seed: number?,
	minSpacing: number?,
	playerKeepoutRadius: number?,
	parentFolder: Instance?,
	phase: string?,
	allowedPhases: { string }?,
})
	assertType(type(payload) == "table", "payload required")
	if payload.position ~= nil then
		assertType(typeof(payload.position) == "Vector3", "position must be Vector3")
	else
		if payload.bounds ~= nil then
			assertType(type(payload.bounds.minX) == "number", "bounds.minX required")
			assertType(type(payload.bounds.maxX) == "number", "bounds.maxX required")
			assertType(type(payload.bounds.minZ) == "number", "bounds.minZ required")
			assertType(type(payload.bounds.maxZ) == "number", "bounds.maxZ required")
		else
			assertType(typeof(payload.center) == "Vector3", "center required when no bounds/position")
			assertType(type(payload.sizeX) == "number" and type(payload.sizeZ) == "number", "sizeX/sizeZ required")
		end
	end
	return payload
end

function Contracts.ROCK_CLEAR_REQUEST(payload: {
	all: boolean?,
	bounds: { minX: number, maxX: number, minZ: number, maxZ: number }?,
})
	assertType(type(payload) == "table" or payload == nil, "payload must be table or nil")
	return payload or { all = true }
end

-- Firefly spawn/clear requests
function Contracts.FIREFLY_SPAWN_REQUEST(payload: {
	bounds: { minX: number, maxX: number, minZ: number, maxZ: number }?,
	center: Vector3?,
	sizeX: number?,
	sizeZ: number?,
	densityPer100x100: number?,
	minCount: number?,
	maxCount: number?,
	count: number?,
	allowWater: boolean?,
	seed: number?,
	minSpacing: number?,
	playerKeepoutRadius: number?,
	parentFolder: Instance?,
	phase: string?,
	allowedPhases: { string }?,
})
	assertType(type(payload) == "table", "payload required")
	if payload.bounds ~= nil then
		assertType(type(payload.bounds.minX) == "number", "bounds.minX required")
		assertType(type(payload.bounds.maxX) == "number", "bounds.maxX required")
		assertType(type(payload.bounds.minZ) == "number", "bounds.minZ required")
		assertType(type(payload.bounds.maxZ) == "number", "bounds.maxZ required")
	else
		assertType(typeof(payload.center) == "Vector3", "center required when no bounds")
		assertType(type(payload.sizeX) == "number" and type(payload.sizeZ) == "number", "sizeX/sizeZ required")
	end
	return payload
end

function Contracts.FIREFLY_CLEAR_REQUEST(payload: {
	all: boolean?,
	bounds: { minX: number, maxX: number, minZ: number, maxZ: number }?,
})
	assertType(type(payload) == "table" or payload == nil, "payload must be table or nil")
	return payload or { all = true }
end

-- NOTE: return moved to end to include cube contracts below

-- Cube spawn/despawn requests
function Contracts.CUBE_SPAWN_REQUEST(payload: { player: Player?, userId: number?, all: boolean? })
	assertType(type(payload) == "table" or payload == nil, "payload table or nil required")
	payload = payload or { all = true }
	if payload.player ~= nil then
		assertType(typeof(payload.player) == "Instance", "player must be Instance")
	end
	if payload.userId ~= nil then
		assertType(type(payload.userId) == "number", "userId must be number")
	end
	return payload
end

function Contracts.CUBE_DESPAWN_REQUEST(payload: { player: Player?, userId: number?, all: boolean? })
	assertType(type(payload) == "table" or payload == nil, "payload table or nil required")
	payload = payload or { all = true }
	if payload.player ~= nil then
		assertType(typeof(payload.player) == "Instance", "player must be Instance")
	end
	if payload.userId ~= nil then
		assertType(type(payload.userId) == "number", "userId must be number")
	end
	return payload
end

-- Runtime effects changed (server -> client)
function Contracts.RUNTIME_EFFECTS_CHANGED(payload: { [string]: number })
	assertType(type(payload) == "table", "effects map required")
	for k, v in pairs(payload) do
		assertType(type(k) == "string", "effect id must be string")
		assertType(type(v) == "number", "expiry must be number")
	end
	return payload
end

-- Profile updated (server -> client)
function Contracts.PROFILE_UPDATED(payload: { [string]: any })
	assertType(type(payload) == "table", "profile table required")
	-- Required core fields
	assertType(type(payload.coins) == "number", "profile.coins must be number")
	assertType(type(payload.materialId) == "string", "profile.materialId must be string")
	assertType(type(payload.cubeSeed) == "number", "profile.cubeSeed must be number")
	-- Upgrades must be map of string -> number
	assertType(type(payload.upgrades) == "table", "profile.upgrades must be table")
	for k, v in pairs(payload.upgrades) do
		assertType(type(k) == "string", "upgrades key must be string")
		assertType(type(v) == "number", "upgrades value must be number")
	end
	-- Inventory: map of itemId(string) -> count(number)
	if payload.inventory ~= nil then
		assertType(type(payload.inventory) == "table", "profile.inventory must be table")
		for k, v in pairs(payload.inventory) do
			assertType(type(k) == "string", "inventory key must be string")
			assertType(type(v) == "number", "inventory value must be number")
		end
	end
	-- Boosts: map of id(string) -> expiry(number)
	if payload.boosts ~= nil then
		assertType(type(payload.boosts) == "table", "profile.boosts must be table")
		for k, v in pairs(payload.boosts) do
			assertType(type(k) == "string", "boost id must be string")
			assertType(type(v) == "number", "boost expiry must be number")
		end
	end
	-- Equipped: map of slot(string) -> itemId(string?)
	if payload.equipped ~= nil then
		assertType(type(payload.equipped) == "table", "profile.equipped must be table")
		for k, v in pairs(payload.equipped) do
			assertType(type(k) == "string", "equipped slot must be string")
			if v ~= nil then
				assertType(type(v) == "string", "equipped itemId must be string or nil")
			end
		end
	end
	return payload
end

-- Client-local snapshot updates (client -> client modules); minimal guard
function Contracts.ACCOUNT_SNAPSHOT_UPDATED(payload: { [string]: any })
	assertType(type(payload) == "table", "snapshot table required")
	assertType(type(payload.lastUpdated) == "number", "snapshot.lastUpdated must be number")
	assertType(type(payload.sessionStartTime) == "number", "snapshot.sessionStartTime must be number")
	assertType(type(payload.isLoading) == "boolean", "snapshot.isLoading must be boolean")
	assertType(type(payload.profile) == "table", "snapshot.profile must be table")
	return payload
end

-- Sound play payload (server -> client)
-- Accepts multiple sub-shapes used by SoundBroadcast/SoundManager
function Contracts.SOUND_PLAY(payload: { [string]: any })
	assertType(type(payload) == "table", "sound payload required")
	if payload.category ~= nil then
		assertType(type(payload.category) == "string", "category must be string")
	end
	if payload.soundId ~= nil then
		assertType(type(payload.soundId) == "string", "soundId must be string")
	end
	if payload.materialKey ~= nil then
		assertType(type(payload.materialKey) == "string", "materialKey must be string")
	end
	if payload.subtype ~= nil then
		assertType(type(payload.subtype) == "string", "subtype must be string")
	end
	if payload.position ~= nil then
		assertType(typeof(payload.position) == "Vector3", "position must be Vector3")
	end
	if payload.volume ~= nil then
		assertType(type(payload.volume) == "number", "volume must be number")
	end
	if payload.pitch ~= nil then
		assertType(type(payload.pitch) == "number", "pitch must be number")
	end
	if payload.originUserId ~= nil then
		assertType(type(payload.originUserId) == "number", "originUserId must be number")
	end
	if payload.rarity ~= nil then
		assertType(type(payload.rarity) == "string", "rarity must be string")
	end
	return payload
end

Contracts.ValidatorsByName = {
	[EventNames.CURRENCY_CHANGED] = Contracts.CURRENCY_CHANGED,
	[EventNames.INVENTORY_CHANGED] = Contracts.INVENTORY_CHANGED,
	[EventNames.INVENTORY_DELTA] = Contracts.INVENTORY_DELTA,
	[EventNames.EQUIPMENT_CHANGED] = Contracts.EQUIPMENT_CHANGED,
	[EventNames.NOTIFICATION_PUSH] = Contracts.NOTIFICATION_PUSH,
	[EventNames.SOUND_PLAY] = Contracts.SOUND_PLAY,
	[EventNames.BOOSTS_CHANGED] = Contracts.BOOSTS_CHANGED,
	[EventNames.REWARD_GRANTED] = Contracts.REWARD_GRANTED,
	[EventNames.RUNTIME_EFFECTS_CHANGED] = Contracts.RUNTIME_EFFECTS_CHANGED,
	[EventNames.PROFILE_UPDATED] = Contracts.PROFILE_UPDATED,
	[EventNames.ACCOUNT_SNAPSHOT_UPDATED] = Contracts.ACCOUNT_SNAPSHOT_UPDATED,

	-- Worldgen/composition
	[EventNames.COMPOSITION_APPLY_REQUEST] = Contracts.COMPOSITION_APPLY_REQUEST,
	[EventNames.ISLAND_SPAWN_REQUEST] = Contracts.ISLAND_SPAWN_REQUEST,
	[EventNames.ISLAND_REMOVE_REQUEST] = Contracts.ISLAND_REMOVE_REQUEST,
	[EventNames.TREE_SPAWN_REQUEST] = Contracts.TREE_SPAWN_REQUEST,
	[EventNames.TREE_CLEAR_REQUEST] = Contracts.TREE_CLEAR_REQUEST,
	[EventNames.ROCK_SPAWN_REQUEST] = Contracts.ROCK_SPAWN_REQUEST,
	[EventNames.ROCK_CLEAR_REQUEST] = Contracts.ROCK_CLEAR_REQUEST,
	[EventNames.FIREFLY_SPAWN_REQUEST] = Contracts.FIREFLY_SPAWN_REQUEST,
	[EventNames.FIREFLY_CLEAR_REQUEST] = Contracts.FIREFLY_CLEAR_REQUEST,

	-- Digging monetization
	[EventNames.MEGA_DIG_REQUEST] = Contracts.MEGA_DIG_REQUEST,
	[EventNames.AUTO_DIG_START] = Contracts.AUTO_DIG_START,
} :: { [string]: (any) -> any }
-- Note: ValidatorsByName is a runtime dispatch table used by EventBus.
-- Each validator function above has its own explicit type signature for direct calls.
-- The (any) -> any type is appropriate here: this is runtime validation of dynamic event data.
-- For compile-time type safety, call validators directly: Contracts.COMPOSITION_APPLY_REQUEST(payload)

return Contracts
