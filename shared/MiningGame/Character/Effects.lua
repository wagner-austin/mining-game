--!strict
-- Effects.lua
-- Canonical effect definitions. Keys match DataService.profile.boosts (no aliases).

export type EffectId =
    "luck" | "size" | "wet" |
    "cosmetic_extra_jumps_1" | "cosmetic_extra_jumps_2" | "cosmetic_extra_jumps_3" | "cosmetic_extra_jumps_4" |
    "potion_speed_tier_1" | "potion_speed_tier_2" | "potion_speed_tier_3" | "potion_speed_tier_4"

export type EffectDefinition = {
    kind: "buff" | "debuff" | "neutral",
    displayName: string?,
    description: string?,
    movement: { speedMult: number?, speedAdd: number?, jumpMult: number?, jumpAdd: number? }?,
    tags: { [string]: boolean }?,
    duration: number?,
}

local DEFS: { [EffectId]: EffectDefinition } = {
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



    -- Extra jump tiers (beyond base double jump). Use highest present tier.
    cosmetic_extra_jumps_1 = {
        kind = "buff",
        displayName = "+1 Extra Jump",
        description = "Allows one additional air jump",
    },
    cosmetic_extra_jumps_2 = {
        kind = "buff",
        displayName = "+2 Extra Jumps",
        description = "Allows two additional air jumps",
    },
    cosmetic_extra_jumps_3 = {
        kind = "buff",
        displayName = "+3 Extra Jumps",
        description = "Allows three additional air jumps",
    },
    cosmetic_extra_jumps_4 = {
        kind = "buff",
        displayName = "+4 Extra Jumps",
        description = "Allows four additional air jumps",
    },

    -- Movement-only speed potions (stacking, capped by GameConfig.MovementBoosts)
    potion_speed_tier_1 = {
        kind = "buff",
        displayName = "Speed Potion",
        movement = { speedMult = 1.10 },
    },
    potion_speed_tier_2 = {
        kind = "buff",
        displayName = "Speed Potion",
        movement = { speedMult = 1.20 },
    },
    potion_speed_tier_3 = {
        kind = "buff",
        displayName = "Speed Potion",
        movement = { speedMult = 1.30 },
    },
    potion_speed_tier_4 = {
        kind = "buff",
        displayName = "Speed Potion",
        movement = { speedMult = 1.40 },
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

-- return moved to end of module (after dynamic helpers)

-- Normalize IDs that include parameters and stack suffixes
-- Examples:
--   cosmetic_speed@1.08#2  -> base = "cosmetic_speed", mult = 1.08, stack = 2
--   cosmetic_luck@1.12     -> base = "cosmetic_luck", mult = 1.12
--   cosmetic_speed_110#1   -> base = "cosmetic_speed_110"
function Effects._parse(id: any): (string, number?, number?)
    local s = tostring(id)
    local stackN: number? = nil
    local mult: number? = nil
    -- Extract stack suffix
    do
        local n = string.match(s, "#(%d+)$")
        if n then stackN = tonumber(n) end
        s = string.gsub(s, "#%d+$", "")
    end
    -- Extract @mult
    do
        local m = string.match(s, "@([0-9%.]+)")
        if m then mult = tonumber(m) end
        s = string.gsub(s, "@([0-9%.]+)", "")
    end
    return s, mult, stackN
end

-- Dynamic effect bases that we synthesize at runtime
local DYNAMIC_BASES: {[string]: boolean} = {
    cosmetic_speed = true,
    potion_speed = true,
    cosmetic_luck = true,
    dig_speed = true,
}

do
    local _orig_get = Effects.get
    function Effects.get(id: EffectId): EffectDefinition?
        local base, mult = Effects._parse(id)
        local def = _orig_get((base :: any))
        if def then return def end
        if DYNAMIC_BASES[base] then
            -- Synthesize minimal defs; movement is only for speed (client movement)
            if base == "cosmetic_speed" or base == "potion_speed" then
                local mm = (type(mult) == "number" and mult or 1.0)
                return { kind = "buff", movement = { speedMult = mm } }
            end
            -- For luck/dig_speed we don't need movement component here
            return { kind = "buff" }
        end
        return nil
    end

    local _orig_exists = Effects.exists
    function Effects.exists(id: EffectId): boolean
        local base = select(1, Effects._parse(id))
        if _orig_exists((base :: any)) then return true end
        return DYNAMIC_BASES[base] == true
    end
end

return Effects
