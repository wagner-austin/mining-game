--!strict
-- Types.lua
-- Types for Character State (no runtime logic)

export type EffectId = "speed" | "luck" | "size" | "wet"

export type EffectSnapshot = { [EffectId]: number } -- effect id -> expiry (unix timestamp)

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
    ApplyTimedEffect: (self: ManagerApi, player: Player, effectId: EffectId, durationSec: number?) -> boolean,
    RemoveEffect: (self: ManagerApi, player: Player, effectId: EffectId) -> (),
}

return {}