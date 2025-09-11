-- Types.lua
-- Type definitions for the mining game system

export type PurchaseEntry = {
    kind: "DevProduct" | "GamePass",
    id: number,
    priceRobux: number,
    at: number,
    source: ("Prompt" | "Backfill")?,
}

-- NOTE: EffectiveStats is declared once below with full shape (delay,size,luck,hardness)

export type CellCoord = { x: number, y: number, z: number }

-- Equipment for a player is dynamically indexed by validated slot names
-- Keep this as an indexable map so code can use profile.equipped[slot]
export type EquippedItems = { [string]: string? }  -- slot -> itemId

-- NOTE: DigResult is declared once below with the full shape

export type MaterialPreferences = {
    palette: string,        -- Palette key (e.g., "default", "industrial")
    cubeMaterial: string,   -- MaterialKeys key (e.g., "rock", "basalt")
    floorMaterial: string,  -- MaterialKeys key (e.g., "concrete", "slate")
}

export type ThemeSettings = {
    uiTheme: string,        -- UI theme key (e.g., "default", "ocean", "forest")
    soundPack: string,      -- Sound pack key (e.g., "default", "retro")
}

export type PlayerStats = {
    coins: number,
    gems: number,
    materialId: string,
    cubeSeed: number,
    upgrades: { [string]: number }, -- "speed", "size"
    boosts: { [string]: number },   -- boost type -> unix timestamp expiry
    pets: { [string]: PetData },    -- pet instance id -> pet data
    inventory: { [string]: number }, -- item id -> count
    equipped: EquippedItems,
    materialPreferences: MaterialPreferences?, -- Optional for backward compatibility
    themeSettings: ThemeSettings?, -- Optional for backward compatibility
    totalBlocksDug: number,
    playtime: number,
    lastSaveTime: number,
    sessionStartTime: number?, -- Session-scoped, sent to clients in GetProfile
    totalCoinsEarned: number?,   -- running lifetime counter
    totalCoinsSpent: number?,    -- running lifetime counter
    totalGemsEarned: number?,    -- running lifetime counter
    totalGemsSpent: number?,     -- running lifetime counter
    totalSessions: number?,      -- lifetime sessions count
    lastLoginTime: number?,      -- unix
    sessionStartBlocks: number?, -- baseline for this session
    firstPlayTime: number?,      -- unix timestamp of first-ever join
    firstDigTime: number?,       -- unix timestamp of first-ever dig
    
    -- Achievement tracking
    achievements: { [string]: boolean }?,  -- unlocked achievement IDs
    statCounters: { [string]: number }?,   -- e.g., "rares_found", "epics_found", "mythics_found"
    
    -- Monetization tracking
    robuxSpentLifetime: number?,
    robuxSpentDevProducts: number?,
    robuxSpentGamePasses: number?,
    purchasesCount: number?,
    firstPurchaseTime: number?,
    lastPurchaseTime: number?,
    sessionStartRobuxSpent: number?, -- baseline for session tracking
    
    -- Server-only fields (not sent to clients)
    processedReceiptIds: { [string]: boolean }?, -- bounded map for idempotency (max 500)
    ownedGamePasses: { [number]: boolean }?, -- snapshot to diff new purchases
    purchaseLog: { PurchaseEntry }?, -- bounded log (max 20 recent purchases)
}

export type PetData = {
    id: string,
    stars: number,
    equipped: boolean,
    obtained: number, -- unix timestamp
}

-- EquippedItems was already declared as an indexable map above; the
-- record-style version caused conflicts when indexing by dynamic slot.
-- Keep only the indexable definition to support code paths like
-- profile.equipped[slot] where slot is validated at runtime.

export type AchievementDef = {
    id: string,
    name: string,
    desc: string,
    tier: "bronze" | "silver" | "gold" | "platinum" | "diamond",
    icon: string?,  -- rbxassetid if you want
    reward: {
        coins: number?,
        gems: number?,
        itemId: string?,
    }?,
    requirement: {
        type: string,       -- "blocks_dug", "item_found", "rarity_found", etc.
        value: number?,     -- threshold value
        rarity: string?,    -- for rarity-specific achievements
    },
}

export type ChunkId = string -- "x_y_z" format
export type Chunk = {
    size: number,              -- 16 (cells per axis)
    dugBits: string,           -- compact string from ChunkCodec
    dirty: boolean?,           -- needs save
    lastModified: number?,     -- unix timestamp
}

export type CubeState = {
    ownerId: number,
    materialId: string,
    cellSize: number,          -- 4 (studs)
    chunkSize: number,         -- 16 (cells)
    chunks: { [ChunkId]: Chunk },
    totalDug: number,
    createdAt: number,
}

export type DigRequest = {
    worldPos: Vector3,
    timestamp: number,
}

-- Unified effective stats used across server/client
export type EffectiveStats = {
    delay: number,  -- Seconds between digs
    size: number,   -- Dig radius half-extent in cells (1 = 3x3x3, 2 = 5x5x5, ...)
    luck: number,   -- Loot multiplier (1.0 = normal, 2.0 = double)
    hardness: number,
}

-- Unified dig result returned by DigService and related flows
export type DigResult = {
    ok: boolean,
    reason: string?,                      -- Present if ok=false
    cellsDug: number?,                    -- Count dug this action
    lootGranted: {},                      -- Legacy/placeholder (empty)
    lootCounts: { [string]: number }?,    -- Items dropped (not collected yet)
    nextAllowedAt: number?,               -- Server-side cooldown resume time (Time.mono-based)
    effectiveStats: EffectiveStats?,      -- Snapshot used for this dig
    soundMaterialKey: string?,            -- "rock", etc.
    soundWorldPos: Vector3?,              -- Position for sound effect
    centerCell: CellCoord?,               -- Clamped cell the server used
}

export type LootDrop = {
    id: string,
    name: string,
    rarity: string,
    type: string,
    value: number?,
    stats: { [string]: number }?,
    effect: string?,
    duration: number?,
    
    -- NEW: which cell produced this drop (for per-cell spawn)
    cellX: number?,  -- integer cell coords
    cellY: number?,
    cellZ: number?,
}

export type UpgradeLevel = {
    level: number,
    cost: number,
    multiplier: number?,
    size: number?,
}

export type Product = {
    id: string,
    productId: number,
    robux: number,
    effect: string?,
    multiplier: number?,
    duration: number?,
    coins: number?,
    size: number?,
}

export type GamePass = {
    id: string,
    gamepassId: number,
    robux: number,
    effects: { [string]: any },
}

export type Material = {
    id: string,
    name: string,
    material: Enum.Material,
    color: Color3,
    lootMultiplier: number,
    unlockCost: number,
    hardness: number,
}

export type Pet = {
    id: string,
    name: string,
    rarity: string,
    buffs: {
        speed: number?,
        size: number?,
        luck: number?,
    },
}

export type NeighborhoodData = {
    players: {Player},
    cubes: {CubeInstance},
    maxPlayers: number,
}

export type CubeInstance = {
    owner: Player,
    model: Model,
    origin: CFrame,
    state: CubeState,
}

export type RemotePayload = {
    type: string,
    data: any,
    timestamp: number,
}

export type SessionData = {
    playerId: number,
    startTime: number,
    lastActivity: number,
    locked: boolean,
}

return {}
