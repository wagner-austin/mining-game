--!strict
-- WorldGenUtils.lua
-- Shared helpers for procedural generation (DRY across services)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Time = require(Shared:WaitForChild("Time"))
local Logger = require(Shared:WaitForChild("Logger"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local log = Logger.new("WorldGenUtils")

local WorldGenUtils = {}

-- Frame budget yielding to avoid spikes
function WorldGenUtils.budgetYield(lastTick: number, slice: number?): number
    if (Time.mono() - lastTick) > (slice or 0.005) then
        RunService.Heartbeat:Wait()
        return Time.mono()
    end
    return lastTick
end

-- Decoration folder (ground trees/rocks/fireflies)
function WorldGenUtils.getDecorationFolder(): Folder
    local f = Workspace:FindFirstChild("BlockDecorations")
    if not f then
        f = Instance.new("Folder")
        f.Name = "BlockDecorations"
        f.Parent = Workspace
    end
    return f
end

-- Floating islands folder
function WorldGenUtils.getIslandsFolder(): Folder
    local folder = Workspace:FindFirstChild("FloatingIslands")
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = "FloatingIslands"
        folder.Parent = Workspace
    end
    return folder
end

-- Acquire player cube positions via service (optional)
function WorldGenUtils.getPlayerCubePositions(CubePositionService: any): {Vector3}
    local list = {}
    if not CubePositionService then return list end
    local Players = game:GetService("Players")
    local players = Players:GetPlayers()
    if #players > 0 then
        for _, plr in ipairs(players) do
            local ok, cf = pcall(function() return CubePositionService:GetOrigin(plr) end)
            if ok and cf then table.insert(list, cf.Position) end
        end
    else
        local ok, cf = pcall(function() return CubePositionService:ComputeDefaultOriginForOrdinal(1) end)
        if ok and cf then table.insert(list, cf.Position) end
    end
    return list
end

-- Generic proximity checks
function WorldGenUtils.isTooClose(x: number, z: number, positions: {Vector3}, minDist: number): boolean
    local k = math.max(minDist or 0, 0)
    if k <= 0 then return false end
    local k2 = k * k
    for _, pos in ipairs(positions) do
        local dx, dz = x - pos.X, z - pos.Z
        if (dx*dx + dz*dz) < k2 then return true end
    end
    return false
end

function WorldGenUtils.isTooCloseToPlayerCube(x: number, z: number, cubes: {Vector3}, keepout: number): boolean
    local k = math.max(keepout or 0, 0)
    if k <= 0 then return false end
    local k2 = k * k
    for _, pos in ipairs(cubes) do
        local dx, dz = x - pos.X, z - pos.Z
        if (dx*dx + dz*dz) < k2 then return true end
    end
    return false
end

-- Versatile ground ray: third arg may be boolean allowWater or table { allowWater: bool, debug: bool }
local DEBUG_RAY_LOG_LIMIT = 20
function WorldGenUtils.findGroundPosition(x: number, z: number, optsOrAllow: any): Vector3?
    local allowWater = false
    local debugLog = false
    if type(optsOrAllow) == "boolean" then
        allowWater = optsOrAllow
    elseif type(optsOrAllow) == "table" then
        allowWater = optsOrAllow.allowWater == true
        debugLog = optsOrAllow.debug == true
    end

    local RAY_START_Y = 500
    local RAY_LENGTH = 1000

    local excludes: {Instance} = {}
    local deco = Workspace:FindFirstChild("BlockDecorations")
    if deco then table.insert(excludes, deco) end
    local islands = Workspace:FindFirstChild("FloatingIslands")
    if islands then table.insert(excludes, islands) end
    local cubesFolder = Workspace:FindFirstChild("Cubes")
    if cubesFolder then table.insert(excludes, cubesFolder) end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = excludes
    params.IgnoreWater = not allowWater

    if (GameConfig.WorldGen and GameConfig.WorldGen.LOG_VERBOSE) and DEBUG_RAY_LOG_LIMIT > 0 then
        DEBUG_RAY_LOG_LIMIT -= 1
        log:debug("Ray@ (%.1f, %.1f): startY=%.0f len=%.0f allowWater=%s", x, z, RAY_START_Y, RAY_LENGTH, tostring(allowWater))
    elseif debugLog then
        log:debug("Ray@ (%.1f, %.1f) [debug]", x, z)
    end

    local hit = Workspace:Raycast(Vector3.new(x, RAY_START_Y, z), Vector3.new(0, -RAY_LENGTH, 0), params)
    if not hit then return nil end
    if hit.Material == Enum.Material.Water and not allowWater then return nil end
    return hit.Position
end

-- Spawn bounds from Workspace (SpawnBounds or Baseplate)
function WorldGenUtils.getSpawnBounds(): (Vector3, number, number)
    local Workspace = game:GetService("Workspace")
    local partName = ((GameConfig.Multiplayer and GameConfig.Multiplayer.SPAWN_BOUNDS_PART) or "SpawnBounds")
    -- Strict: require explicit bounds part or explicit Baseplate
    -- 1) Explicit bounds part present
    local p = Workspace:FindFirstChild(partName)
    if p and p:IsA("BasePart") then return p.Position, p.Size.X, p.Size.Z end
    -- 2) Legacy explicit Baseplate part
    local base = Workspace:FindFirstChild("Baseplate")
    if base and base:IsA("BasePart") then return base.Position, base.Size.X, base.Size.Z end
    -- No attribute fallback: enforce explicit authoring
    error(("Spawn bounds not found. Add a BasePart named '%s' to Workspace or set GameConfig.Multiplayer.SPAWN_BOUNDS_PART."):format(partName))
end

-- Default player keepout radius around cube origins
function WorldGenUtils.getDefaultKeepoutRadius(): number
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Shared = ReplicatedStorage:WaitForChild("MiningGame")
    local ok, GC = pcall(function() return require(Shared:WaitForChild("GameConfig")) end)
    local cube = (ok and GC and GC.Grid and GC.Grid.CUBE_SIZE_STUDS) or 128
    return math.max(200, cube * 1.2)
end

-- Time helpers (scaffolding for time-sensitive spawning)
-- Returns "day" | "night" (simple two-state model for now)
function WorldGenUtils.getDayNightPhase(): string
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Shared = ReplicatedStorage:WaitForChild("MiningGame")
    local ok, WorldTime = pcall(function() return require(Shared:WaitForChild("WorldTime")) end)
    if ok and WorldTime and type(WorldTime.IsNight) == "function" then
        return WorldTime:IsNight() and "night" or "day"
    end
    -- Fallback: use Lighting clock time if available
    local Lighting = game:GetService("Lighting")
    if Lighting and typeof(Lighting.ClockTime) == "number" then
        local t = Lighting.ClockTime
        return (t >= 18 or t < 6) and "night" or "day"
    end
    return "day"
end

function WorldGenUtils.isNight(): boolean
    return WorldGenUtils.getDayNightPhase() == "night"
end


return WorldGenUtils
