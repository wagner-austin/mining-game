--!strict
-- Types.lua
-- Types for Character State (no runtime logic)

-- Base effect identifiers that are predefined in the game.
-- Dynamic/runtime keys (e.g., "cosmetic_speed@1.08#2") are represented by EffectKey (string).
export type EffectId = "speed" | "luck" | "size" | "wet"

-- Runtime effect key (includes dynamic, parameterized, and stacked keys)
-- Examples: "cosmetic_speed@1.08#2", "cosmetic_luck@1.12", "cosmetic_extra_jumps_1#3"
export type EffectKey = string

-- Snapshot keyed by runtime EffectKey. This allows dynamic effects without unsafe casts.
export type EffectSnapshot = { [EffectKey]: number } -- effect key -> expiry (unix timestamp)

export type State = {
	maxHealth: number,
	health: number,
	maxStamina: number,
	stamina: number,
	nextDigAllowedAt: number?,
	effects: EffectSnapshot,
}

export type ManagerApi = {
	Get: (self: ManagerApi, player: Player) -> State?,
	SetNextDigAllowedAt: (self: ManagerApi, player: Player, ts: number) -> (),
	Damage: (self: ManagerApi, player: Player, amount: number) -> (),
	Heal: (self: ManagerApi, player: Player, amount: number) -> (),
	-- Use EffectKey for runtime operations to allow dynamic keys.
	ApplyTimedEffect: (self: ManagerApi, player: Player, effectId: EffectKey, durationSec: number?) -> boolean,
	RemoveEffect: (self: ManagerApi, player: Player, effectId: EffectKey) -> (),
}

return {}
