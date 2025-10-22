--!strict
-- EventContracts.lua - runtime shape checks for frequent EventBus payloads

local function assertType(cond: boolean, msg: string)
    if not cond then error(msg, 3) end
end

local Contracts = {}

function Contracts.CURRENCY_CHANGED(payload: {currency: string, balance: number, delta: number})
    assertType(type(payload.currency) == "string", "currency required")
    assertType(type(payload.balance) == "number", "balance required")
    assertType(type(payload.delta) == "number", "delta required")
    return payload
end

function Contracts.INVENTORY_CHANGED(payload: {[string]: number})
    assertType(type(payload) == "table", "inventory map required")
    return payload
end

-- Delta-based inventory update: only changed item counts
-- Example: { iron = 2, coal = 1, head_hat_cowboy = 1 }
function Contracts.INVENTORY_DELTA(payload: {[string]: number})
    assertType(type(payload) == "table", "delta map required")
    return payload
end

function Contracts.EQUIPMENT_CHANGED(payload: {playerUserId: number, slot: string, itemId: string?})
    assertType(type(payload.playerUserId) == "number", "playerUserId required")
    assertType(type(payload.slot) == "string", "slot required")
    return payload
end

function Contracts.NOTIFICATION_PUSH(payload: {type: string, message: string, color: Color3?})
    assertType(type(payload.type) == "string", "type required")
    assertType(type(payload.message) == "string", "message required")
    return payload
end

function Contracts.BOOSTS_CHANGED(payload: {speed: number?, size: number?, luck: number?})
    assertType(type(payload) == "table", "payload required")
    -- All boost fields are optional (nil means not active)
    if payload.speed then assertType(type(payload.speed) == "number", "speed must be number") end
    if payload.size then assertType(type(payload.size) == "number", "size must be number") end
    if payload.luck then assertType(type(payload.luck) == "number", "luck must be number") end
    return payload
end

-- Reward grant payload (optional fields)
function Contracts.REWARD_GRANTED(payload: {coins: number?, gems: number?, meta: {[string]: any}?})
    assertType(type(payload) == "table", "payload required")
    if payload.coins ~= nil then assertType(type(payload.coins) == "number", "coins must be number") end
    if payload.gems ~= nil then assertType(type(payload.gems) == "number", "gems must be number") end
    -- meta is free-form; presence is enough
    return payload
end

-- Mega dig request (from MonetizationService to DigService)
function Contracts.MEGA_DIG_REQUEST(payload: {player: Player, position: Vector3, sizeBoost: number})
    assertType(typeof(payload.player) == "Instance", "player required")
    assertType(typeof(payload.position) == "Vector3", "position required")
    assertType(type(payload.sizeBoost) == "number", "sizeBoost required")
    return payload
end

-- Auto dig start request (from MonetizationService to DigService)
function Contracts.AUTO_DIG_START(payload: {player: Player})
    assertType(typeof(payload.player) == "Instance", "player required")
    return payload
end

-- Composition apply request (from CubeMaterialService to CompositionService)
function Contracts.COMPOSITION_APPLY_REQUEST(payload: {
    userId: number,
    variationMode: string?,   -- e.g. "PER_REGEN" | "DAILY" | "FIXED"
    preserveAir: boolean?,    -- default true
})
    assertType(type(payload) == "table", "payload required")
    assertType(type(payload.userId) == "number", "userId required")
    if payload.variationMode ~= nil then assertType(type(payload.variationMode) == "string", "variationMode must be string") end
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
    treeScale: number?
})
    assertType(typeof(payload.position) == "Vector3", "position Vector3 required")
    -- All other fields are optional
    return payload
end

-- Island remove request
function Contracts.ISLAND_REMOVE_REQUEST(payload: {
    position: Vector3?,
    all: boolean?
})
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
    bounds: {minX: number, maxX: number, minZ: number, maxZ: number}?,
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
    allowedPhases: {string}?
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
            assertType(typeof(payload.center) == "Vector3", "center Vector3 required when no bounds/position")
            assertType(type(payload.sizeX) == "number" and type(payload.sizeZ) == "number", "sizeX/sizeZ required")
        end
    end
    return payload
end

-- Tree clear request (supports clearing all or by bounds in future)
function Contracts.TREE_CLEAR_REQUEST(payload: {
    all: boolean?,
    bounds: {minX: number, maxX: number, minZ: number, maxZ: number}?
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
    bounds: {minX: number, maxX: number, minZ: number, maxZ: number}?,
    center: Vector3?, sizeX: number?, sizeZ: number?,
    densityPer100x100: number?, minCount: number?, maxCount: number?, count: number?,
    allowWater: boolean?, seed: number?, minSpacing: number?, playerKeepoutRadius: number?,
    parentFolder: Instance?, phase: string?, allowedPhases: {string}?,
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
    bounds: {minX: number, maxX: number, minZ: number, maxZ: number}?
})
    assertType(type(payload) == "table" or payload == nil, "payload must be table or nil")
    return payload or { all = true }
end

-- Firefly spawn/clear requests
function Contracts.FIREFLY_SPAWN_REQUEST(payload: {
    bounds: {minX: number, maxX: number, minZ: number, maxZ: number}?,
    center: Vector3?, sizeX: number?, sizeZ: number?,
    densityPer100x100: number?, minCount: number?, maxCount: number?, count: number?,
    allowWater: boolean?, seed: number?, minSpacing: number?, playerKeepoutRadius: number?,
    parentFolder: Instance?, phase: string?, allowedPhases: {string}?,
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
    bounds: {minX: number, maxX: number, minZ: number, maxZ: number}?
})
    assertType(type(payload) == "table" or payload == nil, "payload must be table or nil")
    return payload or { all = true }
end

-- NOTE: return moved to end to include cube contracts below

-- Cube spawn/despawn requests
function Contracts.CUBE_SPAWN_REQUEST(payload: { player: Player?, userId: number?, all: boolean? })
    assertType(type(payload) == "table" or payload == nil, "payload table or nil required")
    payload = payload or { all = true }
    if payload.player ~= nil then assertType(typeof(payload.player) == "Instance", "player must be Instance") end
    if payload.userId ~= nil then assertType(type(payload.userId) == "number", "userId must be number") end
    return payload
end

function Contracts.CUBE_DESPAWN_REQUEST(payload: { player: Player?, userId: number?, all: boolean? })
    assertType(type(payload) == "table" or payload == nil, "payload table or nil required")
    payload = payload or { all = true }
    if payload.player ~= nil then assertType(typeof(payload.player) == "Instance", "player must be Instance") end
    if payload.userId ~= nil then assertType(type(payload.userId) == "number", "userId must be number") end
    return payload
end

return Contracts
