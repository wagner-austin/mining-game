--!strict
-- TreeGenerationService.lua
-- Dedicated service for spawning ground trees with configurable knobs

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(Shared:WaitForChild("Logger"))
local Time = require(Shared:WaitForChild("Time"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local ServiceValidator = require(Shared:WaitForChild("ServiceValidator"))
local PCGConfig = require(Shared:WaitForChild("PCGConfig"))
local EventBus = require(Shared:WaitForChild("EventBus"))
local EventNames = require(Shared:WaitForChild("EventNames"))
local EventContracts = require(Shared:WaitForChild("EventContracts"))
local WorldGenUtils = require(Shared:WaitForChild("WorldGenUtils"))
local TreeFactory = require(Shared:WaitForChild("TreeFactory"))

local log = Logger.new("TreeGenerationService")
local Bus = EventBus.global()

-- Optional dependency
local CubePositionService: any = nil

-- State
local _lastStats = {
    count = 0,
    seed = 0,
    bounds = nil :: any,
}

-- Utils
-- Use shared WorldGenUtils for yield and ground queries

-- Blocky tree generation moved to TreeFactory.SpawnBlocky

-- Public API
local TreeGenerationService = {}
local _eventsRegistered = false

function TreeGenerationService:Init(container)
    CubePositionService = ServiceValidator.tryGet(container, "CubePositionService")
    if CubePositionService then
        log:info("Initialized (CubePositionService wired)")
    else
        log:warn("Initialized (CubePositionService missing) - using default keepout only")
    end

    if not _eventsRegistered then
        -- TREE_SPAWN_REQUEST: spawn single or generate area based on payload
        Bus:on(EventNames.TREE_SPAWN_REQUEST, function(msg)
            local ok, payload = pcall(EventContracts.TREE_SPAWN_REQUEST, msg.payload)
            if not ok then
                log:warn("Invalid TREE_SPAWN_REQUEST payload")
                return
            end
            if payload.position then
                local model = self:SpawnAt(payload.position, payload)
                if model then
                    log:info("Spawned tree at %s via event", tostring(payload.position))
                end
            else
                local positions = self:GenerateInArea({
                    bounds = payload.bounds,
                    center = payload.center,
                    sizeX = payload.sizeX,
                    sizeZ = payload.sizeZ,
                    densityPer100x100 = payload.densityPer100x100,
                    minCount = payload.minCount,
                    maxCount = payload.maxCount,
                    allowWater = payload.allowWater,
                    seed = payload.seed,
                    minSpacing = payload.minSpacing,
                    playerKeepoutRadius = payload.playerKeepoutRadius,
                })
                log:info("Generated %d trees via event", positions and #positions or 0)
            end
        end)

        -- TREE_CLEAR_REQUEST: clear all trees (bounds optional - not yet implemented)
        Bus:on(EventNames.TREE_CLEAR_REQUEST, function(msg)
            local ok = pcall(EventContracts.TREE_CLEAR_REQUEST, msg.payload)
            if not ok then
                log:warn("Invalid TREE_CLEAR_REQUEST payload")
                return
            end
            self:ClearAll()
        end)

        _eventsRegistered = true
        log:info("Event listeners registered")
    end
end

function TreeGenerationService:Start()
    -- No auto-spawn here; WorldGenerationService orchestrates.
end

export type GenerateOpts = {
    bounds: {minX: number, maxX: number, minZ: number, maxZ: number}?,
    center: Vector3?,
    sizeX: number?,
    sizeZ: number?,
    densityPer100x100: number?,
    minCount: number?,
    maxCount: number?,
    count: number?,
    allowWater: boolean?,
    seed: number?,
    minSpacing: number?,
    playerKeepoutRadius: number?,
    style: string?, -- "blocky" | "assetPack" (blocky default)
    scaleRange: {min: number, max: number}?,
    parentFolder: Instance?,
    phase: string?,
    allowedPhases: {string}?,
}

function TreeGenerationService:GenerateInArea(opts: GenerateOpts): {Vector3}
    opts = opts or {}

    -- Optional time-of-day filter (future-ready)
    if (opts :: any).phase or (opts :: any).allowedPhases then
        local phase = WorldGenUtils.getDayNightPhase()
        local allowed = false
        if (opts :: any).allowedPhases and type((opts :: any).allowedPhases) == "table" then
            for _, p in ipairs((opts :: any).allowedPhases) do
                if p == phase then allowed = true break end
            end
        elseif (opts :: any).phase and type((opts :: any).phase) == "string" then
            allowed = ((opts :: any).phase == "any") or ((opts :: any).phase == phase)
        else
            allowed = true
        end
        if not allowed then
            log:info("Phase mismatch (%s) -> skipping tree generation for this request", phase)
            return {}
        end
    end

    local minX, maxX, minZ, maxZ
    if opts.bounds then
        minX, maxX, minZ, maxZ = opts.bounds.minX, opts.bounds.maxX, opts.bounds.minZ, opts.bounds.maxZ
    elseif opts.center and opts.sizeX and opts.sizeZ then
        minX = opts.center.X - opts.sizeX * 0.5
        maxX = opts.center.X + opts.sizeX * 0.5
        minZ = opts.center.Z - opts.sizeZ * 0.5
        maxZ = opts.center.Z + opts.sizeZ * 0.5
    else
        error("GenerateInArea requires bounds or center+sizeX+sizeZ")
    end

    local density = opts.densityPer100x100
    if density == nil then density = (GameConfig.Decorations and GameConfig.Decorations.TREES_PER_100x100) or 1.2 end
    local minCount = opts.minCount or (GameConfig.Decorations and GameConfig.Decorations.MIN_TREES) or 20
    local maxCount = opts.maxCount or (GameConfig.Decorations and GameConfig.Decorations.MAX_TREES) or 300
    local allowWater = opts.allowWater
    if allowWater == nil then allowWater = (GameConfig.Decorations and GameConfig.Decorations.ALLOW_WATER_TREES) or false end
    local minSpacing = opts.minSpacing or 12
    local keepout = opts.playerKeepoutRadius or WorldGenUtils.getDefaultKeepoutRadius()
    local parentFolder = (opts.parentFolder and opts.parentFolder:IsA("Instance")) and opts.parentFolder or WorldGenUtils.getDecorationFolder()

    local area = (maxX - minX) * (maxZ - minZ)
    local tiles = area / 10000
    local targetCount = opts.count or math.floor(tiles * density)
    targetCount = math.clamp(targetCount, minCount, maxCount)

    local seed = opts.seed
    if seed == nil then seed = (PCGConfig.Seeds and PCGConfig.Seeds.DECORATION_SPAWN) or 67890 end
    local rng = Random.new(seed + 101)

    local cubes = WorldGenUtils.getPlayerCubePositions(CubePositionService)
    local positions: {Vector3} = {}
    local spawned = 0

    log:info("Tree spawn target=%d (tiles=%.1f, density=%.2f)", targetCount, tiles, density or 0)

    local attempts, maxAttempts, lastTick = 0, targetCount * 20, Time.mono()
    while spawned < targetCount and attempts < maxAttempts do
        attempts += 1
        lastTick = WorldGenUtils.budgetYield(lastTick)
        local x = rng:NextNumber(minX, maxX)
        local z = rng:NextNumber(minZ, maxZ)

        if not WorldGenUtils.isTooCloseToPlayerCube(x, z, cubes, keepout) and not WorldGenUtils.isTooClose(x, z, positions, minSpacing) then
            local ground = WorldGenUtils.findGroundPosition(x, z, { allowWater = allowWater })
            if ground then
                -- Spawn procedural blocky tree via shared factory (atomic parent assign after)
                local model = TreeFactory.SpawnBlocky(ground, rng)
                model.Parent = parentFolder
                spawned += 1
                table.insert(positions, ground)
                if spawned <= 3 then
                    log:info("Tree #%d at (%.1f, %.1f, %.1f)", spawned, ground.X, ground.Y, ground.Z)
                end
            end
        end
    end

    _lastStats = { count = spawned, seed = seed, bounds = {minX=minX,maxX=maxX,minZ=minZ,maxZ=maxZ} }
    log:info("Tree generation complete: %d spawned (attempts=%d)", spawned, attempts)
    return positions
end

function TreeGenerationService:SpawnAt(position: Vector3, opts: {style: string?}?)
    local rng = Random.new()
    local model = TreeFactory.SpawnBlocky(position, rng)
    model.Parent = WorldGenUtils.getDecorationFolder()
    return model
end

function TreeGenerationService:ClearAll()
    local folder = WorldGenUtils.getDecorationFolder()
    for _, inst in ipairs(folder:GetChildren()) do
        if inst:IsA("Model") then
            if CollectionService:HasTag(inst, "BlockTree") or inst.Name:find("Tree") then
                inst:Destroy()
                RunService.Heartbeat:Wait()
            end
        end
    end
    log:info("Cleared all trees in BlockDecorations")
end

function TreeGenerationService:GetStats()
    return _lastStats
end

function TreeGenerationService:GetDefaults()
    local deco = GameConfig.Decorations or {}
    return {
        densityPer100x100 = deco.TREES_PER_100x100 or 1.2,
        minCount = deco.MIN_TREES or 20,
        maxCount = deco.MAX_TREES or 300,
        allowWater = deco.ALLOW_WATER_TREES or false,
        minSpacing = 12,
        keepoutRadius = WorldGenUtils.getDefaultKeepoutRadius(),
        phase = deco.TREES_PHASE or deco.TREES_phase,
        allowedPhases = deco.TREES_ALLOWED_PHASES,
    }
end

return TreeGenerationService
