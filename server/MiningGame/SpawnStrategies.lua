--!strict
-- SpawnStrategies.lua
-- Pluggable spawn strategies for cube positioning

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(Shared:WaitForChild("Logger"))
local log = Logger.new("SpawnStrategies")
local MathUtils = require(Shared:WaitForChild("MathUtils"))

local Strategies = {}

-- Deterministic seed (uses PCGConfig if present)
local BASE_SPAWN_SEED do
    local ok, PCGConfig = pcall(function() return require(Shared:WaitForChild("PCGConfig")) end)
    BASE_SPAWN_SEED = (ok and PCGConfig and PCGConfig.Seeds and PCGConfig.Seeds.CUBE_SPAWN) or 1337
end

-- Simple, stable integer hash → [0, 1)
local function rand01(seed, salt)
    local n = (seed + salt * 1013904223) % 0x100000000
    n = bit32.bxor(n, bit32.rshift(n, 16))
    n = (n * 0x45d9f3b) % 0x100000000
    n = bit32.bxor(n, bit32.rshift(n, 16))
    n = (n * 0x45d9f3b) % 0x100000000
    n = bit32.band(n, 0x7fffffff)
    return n / 0x7fffffff
end

-- Cache results so we can enforce spacing against ALL previous positions
local memo_random_dispersed: {[number]: CFrame} = {}

-- Helpers
local function halfCube(gc) 
    return gc.Grid.CUBE_SIZE_STUDS * 0.5 
end

-- Pure spiral position calculation (no PCG module dependencies)
local function spiral_position(ord: number, GameConfig): (Vector3, number)
    local CUBE_SIZE = (GameConfig.Grid and GameConfig.Grid.CUBE_SIZE_STUDS) or 128
    local minGap   = (GameConfig.Multiplayer and GameConfig.Multiplayer.MIN_GAP_STUDS) or 64
    local spacing  = math.max(
        (GameConfig.Multiplayer and GameConfig.Multiplayer.CUBE_SPACING) or (CUBE_SIZE + minGap),
        CUBE_SIZE + minGap
    )
    local k = MathUtils.nonNegative(ord - 1)
    local phi = math.pi * (3 - math.sqrt(5))
    local r = spacing * math.sqrt(k)
    local theta = k * phi
    local x = math.cos(theta) * r
    local z = math.sin(theta) * r
    local y = 0  -- just a placeholder; we set Y from ground later
    -- NO ROTATION - cubes don't need to face any direction
    return Vector3.new(x, y, z), 0
end

-- Get spawn bounds from world or config
local function getSpawnBounds(gc)
    -- Strict: require explicit bounds part or explicit Baseplate
    -- 1) Named part
    local partName = (gc.Multiplayer and gc.Multiplayer.SPAWN_BOUNDS_PART) or "SpawnBounds"
    local p = Workspace:FindFirstChild(partName)
    if p and p:IsA("BasePart") then
        log:debug("Found spawn bounds part '%s': center=%s, size=(%s, %s)", 
            partName, tostring(p.Position), tostring(p.Size.X), tostring(p.Size.Z))
        return p.Position, p.Size.X, p.Size.Z
    end
    -- 2) Legacy explicit Baseplate part
    local base = Workspace:FindFirstChild("Baseplate")
    if base and base:IsA("BasePart") then
        log:debug("Using Baseplate for bounds: center=%s, size=(%s, %s)",
            tostring(base.Position), tostring(base.Size.X), tostring(base.Size.Z))
        return base.Position, base.Size.X, base.Size.Z
    end
    error(("Spawn bounds not found. Add a BasePart named '%s' to Workspace or set GameConfig.Multiplayer.SPAWN_BOUNDS_PART to your bounds part name."):format(partName))
end

local function snapToTerrainY(x: number, z: number, yFallback: number, excludes: {Instance}?): number
    -- Filter out nil entries to avoid raycast errors
    local filtered = {}
    if excludes then
        for _, inst in ipairs(excludes) do
            if inst then table.insert(filtered, inst) end
        end
    end
    
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = filtered
    params.IgnoreWater = true
    local castY = 2048
    local hit = Workspace:Raycast(Vector3.new(x, castY, z), Vector3.new(0, -castY*2, 0), params)
    return hit and hit.Position.Y or yFallback
end

-- DEFAULT: grid in XZ, fixed Y (today's behavior)
function Strategies.grid(ord: number, GameConfig)
    local spacing = (GameConfig.Multiplayer and GameConfig.Multiplayer.CUBE_SPACING) or 96
    local cols = (GameConfig.Multiplayer and GameConfig.Multiplayer.GRID_COLS) or 3
    local gx = (ord-1) % cols
    local gz = math.floor((ord-1)/cols)
    local y = halfCube(GameConfig) -- sits on base level
    local cf = CFrame.new(gx*spacing, y, gz*spacing)
    log:debug("Grid strategy: ord=%d -> grid(%d,%d) -> pos=%s", ord, gx, gz, tostring(cf.Position))
    return cf
end

-- GRID + altitude noise (quick vertical variety; deterministic per ord)
function Strategies.grid_altitude_noise(ord: number, GameConfig)
    local cf = Strategies.grid(ord, GameConfig)
    -- Just use grid's Y position for consistency
    return cf
end

-- GRID + terrain snap (raycast to ground, then center = ground + halfCube)
function Strategies.grid_terrain_snap(ord: number, GameConfig)
    local cf = Strategies.grid(ord, GameConfig)
    -- Just use grid's Y position for consistency
    return cf
end

-- spiral: golden-angle spiral distribution for even spacing
function Strategies.spiral(ord: number, GameConfig)
    log:info("Spiral strategy for ordinal %d", ord)

    -- 1) compute spiral locally
    local pos, yaw = spiral_position(ord, GameConfig)

    -- 2) clamp to spawn bounds (still supports optional SpawnBounds part)
    local center, sx, sz = getSpawnBounds(GameConfig)
    local margin = (GameConfig.Multiplayer and GameConfig.Multiplayer.EDGE_MARGIN) or 200
    local minX, maxX = center.X - sx*0.5 + margin, center.X + sx*0.5 - margin
    local minZ, maxZ = center.Z - sz*0.5 + margin, center.Z + sz*0.5 - margin
    local clampedX, clampedZ = math.clamp(pos.X, minX, maxX), math.clamp(pos.Z, minZ, maxZ)

    -- 3) Use same Y as grid strategy - simple and consistent
    local y = halfCube(GameConfig)  -- Just like grid does it
    
    -- 4) Quantize X and Z to voxel grid (NOT Y)
    local cellSize = (GameConfig.Grid and GameConfig.Grid.CELL_SIZE_STUDS) or 4
    local function q(n) return math.floor(n/cellSize + 0.5)*cellSize end
    
    -- NO ROTATION - just position the cube without any rotation
    local cf = CFrame.new(q(clampedX), y, q(clampedZ))
    log:info("Spiral final position for ord %d: %s", ord, tostring(cf.Position))
    return cf
end

-- random_dispersed: Poisson-like best-candidate with hard min spacing
function Strategies.random_dispersed(ord: number, GameConfig)
    if memo_random_dispersed[ord] then
        return memo_random_dispersed[ord]
    end

    log:info("Random dispersed strategy for ordinal %d", ord)

    -- Config & bounds
    local CUBE_SIZE = (GameConfig.Grid and GameConfig.Grid.CUBE_SIZE_STUDS) or 128
    local minGap    = (GameConfig.Multiplayer and GameConfig.Multiplayer.MIN_GAP_STUDS) or 64
    local minDist   = CUBE_SIZE + minGap

    local center, sx, sz = getSpawnBounds(GameConfig)
    local margin = (GameConfig.Multiplayer and GameConfig.Multiplayer.EDGE_MARGIN) or 200
    local minX, maxX = center.X - sx*0.5 + margin, center.X + sx*0.5 - margin
    local minZ, maxZ = center.Z - sz*0.5 + margin, center.Z + sz*0.5 - margin

    local cellSize = (GameConfig.Grid and GameConfig.Grid.CELL_SIZE_STUDS) or 4
    local function q(n) return math.floor(n / cellSize + 0.5) * cellSize end

    -- Ensure all previous ordinals are in the cache (deterministic)
    for j = 1, ord - 1 do
        if not memo_random_dispersed[j] then
            memo_random_dispersed[j] = Strategies.random_dispersed(j, GameConfig)
        end
    end

    -- Try multiple candidates and keep the one with the largest min distance
    local baseSeed = BASE_SPAWN_SEED + ord * 374761393
    local maxAttempts = 48
    local bestCF: CFrame? = nil
    local bestMin = -math.huge

    for attempt = 1, maxAttempts do
        local ux = rand01(baseSeed, attempt * 2)
        local uz = rand01(baseSeed, attempt * 2 + 1)
        local x = q(minX + (maxX - minX) * ux)
        local z = q(minZ + (maxZ - minZ) * uz)

        -- Compute min distance to all prior placements (use quantized coords)
        local md = math.huge
        for j = 1, ord - 1 do
            local pc = memo_random_dispersed[j]
            local px, pz = pc.X, pc.Z
            local dx, dz = x - px, z - pz
            local d = (dx*dx + dz*dz) ^ 0.5
            if d < md then md = d end
            if md < bestMin and bestMin >= minDist then
                -- Early exit: this candidate cannot beat a valid best
                break
            end
        end

        if md >= minDist then
            -- Perfect: meets spacing; take it and stop
            bestCF = CFrame.new(x, halfCube(GameConfig), z)
            bestMin = md
            break
        elseif md > bestMin then
            bestCF = CFrame.new(x, halfCube(GameConfig), z)
            bestMin = md
        end
    end

    if not bestCF then
        log:warn("random_dispersed: could not meet minDist=%.1f for ord=%d (best=%.1f). Using best candidate.",
            minDist, ord, bestMin)
    end

    local cf = bestCF or CFrame.new(q(center.X), halfCube(GameConfig), q(center.Z))
    memo_random_dispersed[ord] = cf
    log:info("Random dispersed final position for ord %d: %s", ord, tostring(cf.Position))
    return cf
end

-- Runtime strategy management
local currentStrategy = nil -- Will use GameConfig default if not set

-- Get current strategy name
function Strategies.GetCurrentStrategyName()
    if currentStrategy then
        return currentStrategy
    end
    -- Fall back to GameConfig
    local GameConfig = require(Shared:WaitForChild("GameConfig"))
    return (GameConfig.Multiplayer and GameConfig.Multiplayer.SPAWN_STRATEGY) or "grid"
end

-- List all available strategies
function Strategies.ListStrategies()
    local list = {}
    for name, value in pairs(Strategies) do
        if type(value) == "function" and name ~= "GetCurrentStrategyName" 
            and name ~= "ListStrategies" and name ~= "SetStrategy" 
            and name ~= "GetStrategy" then
            table.insert(list, name)
        end
    end
    table.sort(list)
    return list
end

-- Set the active strategy (runtime override)
function Strategies.SetStrategy(name: string): boolean
    -- Validate the strategy exists
    if not Strategies[name] or type(Strategies[name]) ~= "function" then
        log:warn("SetStrategy: Unknown strategy '%s'", name)
        return false
    end
    
    currentStrategy = name
    log:info("SetStrategy: Changed active strategy to '%s'", name)
    
    -- Clear memoization caches when strategy changes
    memo_random_dispersed = {}
    
    return true
end

-- Get the active strategy function
function Strategies.GetStrategy()
    local name = Strategies.GetCurrentStrategyName()
    return Strategies[name] or Strategies.grid
end

return Strategies
