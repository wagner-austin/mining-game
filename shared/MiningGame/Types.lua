--!strict
-- Types.lua
-- Type definitions for the mining game system

export type MaterialPreferences = {
    palette: string,        -- Palette key (e.g., "default", "industrial")
    cubeMaterial: string,   -- MaterialKeys key (e.g., "rock", "basalt")
    floorMaterial: string,  -- MaterialKeys key (e.g., "concrete", "slate")
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
    totalBlocksDug: number,
    playtime: number,
    lastSaveTime: number,
    sessionStartTime: number?, -- Session-scoped, sent to clients in GetProfile
}

export type PetData = {
    id: string,
    stars: number,
    equipped: boolean,
    obtained: number, -- unix timestamp
}

export type EquippedItems = {
    pickaxe: string?,
    head: string?,
    back: string?,
    aura: string?,
    trail: string?,
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

export type DigResult = {
    ok: boolean,
    reason: string?,
    cellsDug: number?,
    lootGranted: {string}?,
    lootCounts: {[string]: number}?,
    nextAllowedAt: number?,
    effectiveStats: EffectiveStats?,
    soundMaterialKey: string?,   -- new: exact material used by server
    soundWorldPos: Vector3?,     -- new: exact position for sound
}

export type EffectiveStats = {
    delay: number,
    size: number,
    luck: number,
    hardness: number,
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