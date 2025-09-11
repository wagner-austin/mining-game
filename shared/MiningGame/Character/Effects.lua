--!strict
-- Effects.lua
-- Canonical effect definitions. Keys match DataService.profile.boosts (no aliases).

export type EffectId = "speed" | "luck" | "size" | "wet"

export type EffectDefinition = {
    kind: "buff" | "debuff" | "neutral",
    displayName: string?,
    description: string?,
    movement: { speedMult: number?, speedAdd: number?, jumpMult: number?, jumpAdd: number? }?,
    tags: { [string]: boolean }?,
    duration: number?,
}

local DEFS: { [EffectId]: EffectDefinition } = {
    -- Persisted boosts (affect digging via UpgradeService; shown in UI only here)
    speed = {
        kind = "buff",
        displayName = "Speed Boost",
        description = "Faster digging speed",
        tags = { diggingSpeed = true },
    },
    luck = {
        kind = "buff",
        displayName = "Lucky",
        description = "Increased luck while digging",
        tags = { diggingLuck = true },
    },
    size = {
        kind = "buff",
        displayName = "Size Boost",
        description = "Bigger dig size",
        tags = { diggingSize = true },
    },

    -- Runtime, server-authored movement effect
    wet = {
        kind = "debuff",
        displayName = "Wet",
        description = "Slowed by water",
        movement = { speedMult = 0.80 }, -- 20% slower movement
        duration = 5, -- used for server-timed application when no explicit expiry is given
    },
}

local Effects = {}

function Effects.get(id: EffectId): EffectDefinition?
    return DEFS[id]
end

function Effects.exists(id: EffectId): boolean
    return DEFS[id] ~= nil
end

function Effects.all(): { [EffectId]: EffectDefinition }
    return DEFS
end

return Effects