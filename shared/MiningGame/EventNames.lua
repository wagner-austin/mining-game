--!strict
local E = {
    -- Core events
    CURRENCY_CHANGED = "currency.changed",
    COMPOSITION_APPLY_REQUEST = "composition.apply.request",
    ERROR_REPORTED = "error.reported",
    PROFILE_UPDATED = "profile.updated",
    INVENTORY_CHANGED = "inventory.changed",
    INVENTORY_DELTA = "inventory.delta",
    DIG_FEEDBACK = "dig.feedback",
    CUBE_ORIGIN_CHANGED = "cube.origin.changed",
    LOOT_DROPPED = "loot.dropped",
    RUNTIME_EFFECTS_CHANGED = "runtime.effects.changed",
    ACHIEVEMENT_UNLOCKED = "achievement.unlocked",
    ANNOUNCEMENT_BROADCAST = "announcement.broadcast",
    
    -- Additional events
    EQUIPMENT_CHANGED = "equipment.changed",
    BOOSTS_CHANGED = "boosts.changed",
    DEBUG_RESET = "debug.reset",
    UPGRADES_CHANGED = "upgrades.changed",
    ITEM_COLLECTED = "item.collected",
    PICKUP_PROMPT = "pickup.prompt",
    REWARD_GRANTED = "reward.granted",
    NOTIFICATION_PUSH = "notification.push",
    SOUND_PLAY = "sound.play",
    TERRAIN_POKE = "terrain.poke",
    CLOTH_UPDATE = "cloth.update",
    
    -- Dig service events
    MEGA_DIG_REQUEST = "dig.mega_request",
    AUTO_DIG_START = "dig.auto_start",
    
    -- Neighborhood events
    NEIGHBOR_JOINED = "neighbor.joined",
    NEIGHBOR_LEFT = "neighbor.left",
    CUBE_UPDATE = "cube.update",
    
    -- Island events (for breaking WorldGen ↔ FloatingIsland cycle)
    ISLAND_SPAWN_REQUEST = "island.spawn.request",
    ISLAND_REMOVE_REQUEST = "island.remove.request",
    -- Tree generation events (procedural decorations)
    TREE_SPAWN_REQUEST = "tree.spawn.request",
    TREE_CLEAR_REQUEST = "tree.clear.request",

    -- Rock generation events
    ROCK_SPAWN_REQUEST = "rock.spawn.request",
    ROCK_CLEAR_REQUEST = "rock.clear.request",

    -- Firefly generation events
    FIREFLY_SPAWN_REQUEST = "firefly.spawn.request",
    FIREFLY_CLEAR_REQUEST = "firefly.clear.request",
}

-- Build validation table for whitelists/tests
local VALID: {[string]: true} = {}
for _, v in pairs(E) do
    if type(v) == "string" then 
        VALID[v] = true 
    end
end

-- Helper function to validate event names
function E.isValid(name: string): boolean
    return VALID[name] == true
end

table.freeze(E)

export type EventName =
    "currency.changed" | "profile.updated" | "inventory.changed" | "inventory.delta" | "dig.feedback" |
    "cube.origin.changed" | "loot.dropped" | "runtime.effects.changed" |
    "achievement.unlocked" | "announcement.broadcast" |
    "equipment.changed" | "boosts.changed" | "debug.reset" | "upgrades.changed" |
    "item.collected" | "pickup.prompt" | "reward.granted" | "notification.push" |
    "sound.play" | "terrain.poke" | "cloth.update" |
    "neighbor.joined" | "neighbor.left" | "cube.update" | "error.reported" |
    "dig.mega_request" | "dig.auto_start" | "composition.apply.request" |
    "island.spawn.request" | "island.remove.request" |
    "tree.spawn.request" | "tree.clear.request" |
    "rock.spawn.request" | "rock.clear.request" |
    "firefly.spawn.request" | "firefly.clear.request"

return E
