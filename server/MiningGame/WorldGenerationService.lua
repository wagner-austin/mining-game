--!strict
-- WorldGenerationService.lua
-- Beautiful procedural tree and rock generation

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(Shared:WaitForChild("Logger"))
local log = Logger.new("WorldGenerationService")
local EventBus = require(Shared:WaitForChild("EventBus"))
local EventNames = require(Shared:WaitForChild("EventNames"))
local Bus = EventBus.global()
local Time = require(Shared:WaitForChild("Time"))
local WorldTime = require(Shared:WaitForChild("WorldTime"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local ServiceValidator = require(Shared:WaitForChild("ServiceValidator"))
local CubeThemes = require(Shared:WaitForChild("CubeThemes"))

local WorldGenerationService = {}
local DigPerformance = require(script.Parent.DigPerformance)

-- Dependencies
local GridService
local CubePositionService
local ErrorService
local WorldGenUtils = require(Shared:WaitForChild("WorldGenUtils"))
local TreeGenerationService
local RockGenerationService
local FireflyGenerationService
local TreeGenerationService

-- Configuration for blocky tree generation
local BLOCK_SIZE = 8
local TRUNK_COLOR = Color3.fromRGB(101, 67, 33)
local LEAVES_COLOR = Color3.fromRGB(106, 157, 77)
local LEAVES_ACCENT_COLOR = Color3.fromRGB(141, 190, 97)
local ROCK_COLOR = Color3.fromRGB(150, 150, 150)
local ROCK_ACCENT_COLOR = Color3.fromRGB(180, 180, 190)

-- Tree parameters
local MIN_TRUNK_HEIGHT = 5
local MAX_TRUNK_HEIGHT = 12
local BRANCH_CHANCE = 0.4
local MIN_BRANCH_LENGTH = 2
local MAX_BRANCH_LENGTH = 4
local LEAVES_RADIUS_HORIZONTAL = 3
local LEAVES_RADIUS_VERTICAL = 2
local TRUNK_THICKNESS = 1.2
local TRUNK_VARIATION = 0.15
local BRANCH_START_HEIGHT = 0.5

-- Rock parameters
local MIN_ROCK_SIZE = 1
local MAX_ROCK_SIZE = 3

-- Light budget
local decorLightCount = 0
local DECOR_LIGHT_BUDGET = 30

-- Utils
local function budgetYield(lastTick: number, slice: number?): number
    return WorldGenUtils.budgetYield(lastTick, slice)
end

local function getDecorationFolder(): Folder
    return WorldGenUtils.getDecorationFolder()
end

local function getSpawnBounds(): (Vector3, number, number)
    return WorldGenUtils.getSpawnBounds()
end

local function getPlayerCubePositions(): {Vector3}
    local list = {}
    if not CubePositionService then return list end
    local players = Players:GetPlayers()
    if #players > 0 then
        for _, plr in ipairs(players) do
            local ok, cf = pcall(function() return CubePositionService:GetOrigin(plr) end)
            if ok and cf then table.insert(list, cf.Position) end
        end
    else
        local cf = CubePositionService:ComputeDefaultOriginForOrdinal(1)
        if cf then table.insert(list, cf.Position) end
    end
    return list
end

local function isTooCloseToPlayerCube(x: number, z: number, cubes: {Vector3}): boolean
    local keepout = math.max(200, (GameConfig.Grid.CUBE_SIZE_STUDS or 128) * 1.2)
    local k2 = keepout * keepout
    for _, pos in ipairs(cubes) do
        local dx, dz = x - pos.X, z - pos.Z
        if (dx*dx + dz*dz) < k2 then return true end
    end
    return false
end

-- Debug counter for raycast logging
local DEBUG_RAY_LOG_LIMIT = 20  -- Increased for debugging

local function findGroundPosition(x: number, z: number, opts: {allowWater: boolean?}?): Vector3?
    return WorldGenUtils.findGroundPosition(x, z, { allowWater = opts and opts.allowWater })
end

-- spawnFireflies removed; delegated to FireflyGenerationService

-- Generate terrain baseplate if it doesn't exist
local function ensureTerrainBaseplate()
    log:info("Checking for terrain baseplate...")
    local terrain = Workspace.Terrain
    
    -- Check if there's already terrain at ground level (check at Y=10 where we expect terrain)
    local testRegion = Region3.new(Vector3.new(-10, -5, -10), Vector3.new(10, 20, 10))
    testRegion = testRegion:ExpandToGrid(4)
    
    local hasGround = false
    local ok, err = pcall(function()
        local materials, size = terrain:ReadVoxels(testRegion, 4)
        if materials and size and size.X then
            -- Size is a Vector3, extract components safely
            local sizeX = math.floor(size.X or 0)
            local sizeY = math.floor(size.Y or 0)
            local sizeZ = math.floor(size.Z or 0)
            log:debug("ReadVoxels returned size: %dx%dx%d", sizeX, sizeY, sizeZ)
            
            for x = 1, sizeX do
                for y = 1, sizeY do
                    for z = 1, sizeZ do
                        if materials[x][y][z] ~= Enum.Material.Air then
                            hasGround = true
                            log:debug("Found terrain material %s at voxel (%d,%d,%d)", 
                                tostring(materials[x][y][z]), x, y, z)
                            return
                        end
                    end
                end
            end
        end
    end)
    
    if not ok then
        log:warn("Failed to read terrain voxels: %s", tostring(err))
        hasGround = false
    end
    
    if not hasGround then
        log:info("No terrain baseplate detected, generating one...")
        
        -- Generate a large grass terrain baseplate
        local baseplateSize = 2048  -- Large enough for decorations
        local baseplateThickness = 40
        local baseplateY = 10  -- Raise ground level slightly above 0
        
        -- Use FillBlock to create terrain
        local success, fillErr = pcall(function()
            terrain:FillBlock(
                CFrame.new(0, baseplateY - baseplateThickness/2, 0),
                Vector3.new(baseplateSize, baseplateThickness, baseplateSize),
                Enum.Material.Grass
            )
        end)
        
        if success then
            log:info("Generated %dx%d terrain baseplate at Y=%d (from Y=%d to Y=%d)", 
                baseplateSize, baseplateSize, baseplateY, 
                baseplateY - baseplateThickness/2, baseplateY + baseplateThickness/2)
            
            -- Verify terrain was actually created
            wait(0.1) -- Give terrain a moment to update
            local verifyOk, verifyErr = pcall(function()
                local verifyRegion = Region3.new(Vector3.new(-10, -5, -10), Vector3.new(10, 20, 10))
                verifyRegion = verifyRegion:ExpandToGrid(4)
                local materials, size = terrain:ReadVoxels(verifyRegion, 4)
                if materials and size and size.X then
                    -- Size is a Vector3, extract components safely
                    local sizeX = math.floor(size.X or 0)
                    local sizeY = math.floor(size.Y or 0)
                    local sizeZ = math.floor(size.Z or 0)
                    
                    local foundTerrain = false
                    for x = 1, sizeX do
                        for y = 1, sizeY do
                            for z = 1, sizeZ do
                                if materials[x][y][z] ~= Enum.Material.Air then
                                    foundTerrain = true
                                    break
                                end
                            end
                            if foundTerrain then break end
                        end
                        if foundTerrain then break end
                    end
                    log:info("Terrain verification: %s", foundTerrain and "SUCCESS" or "FAILED")
                end
            end)
            if not verifyOk then
                log:warn("Failed to verify terrain: %s", tostring(verifyErr))
            end
        else
            log:error("Failed to generate terrain baseplate: %s", tostring(fillErr))
        end
    else
        log:info("Terrain baseplate already exists")
    end

    -- Apply global terrain grass settings (best-effort; guarded by pcall for API diffs)
    pcall(function()
        terrain.Decoration = true -- ensure foliage is enabled
    end)
    -- Reduce grass length from default (~0.7) to a shorter look
    pcall(function()
        terrain.GrassLength = 0.4
    end)
end

-- Ensure a SpawnBounds part exists to define spawn area explicitly
local function ensureSpawnBoundsPart()
    local partName = (GameConfig.Multiplayer and GameConfig.Multiplayer.SPAWN_BOUNDS_PART) or "SpawnBounds"
    local existing = Workspace:FindFirstChild(partName)
    if existing and existing:IsA("BasePart") then
        return existing
    end
    -- Create an invisible, non-collidable bounds part matching our default baseplate size
    local p = Instance.new("Part")
    p.Name = partName
    p.Anchored = true
    p.CanCollide = false
    p.CanTouch = false
    p.CanQuery = false
    p.CastShadow = false
    p.Transparency = 1
    -- Match the worldgen baseplate (2048x2048) and center
    p.Size = Vector3.new(2048, 1, 2048)
    p.CFrame = CFrame.new(0, 10, 0)
    p.Parent = Workspace
    log:info("SpawnBounds created (auto) at %s size=(%d, %d)", tostring(p.Position), p.Size.X, p.Size.Z)
    return p
end

-- Core spawn
function WorldGenerationService.SpawnDecorations()
    local worldGen = GameConfig.WorldGen
    if not worldGen then
        log:warn("No WorldGen config found in GameConfig")
        return
    end
    
    log:info("SpawnDecorations called - ENABLED=%s, STUDIO_ONLY=%s, IsStudio=%s", 
        tostring(worldGen.ENABLED), 
        tostring(worldGen.STUDIO_ONLY), 
        tostring(RunService:IsStudio()))
    
    if not worldGen.ENABLED then 
        log:warn("WorldGen.ENABLED is false, skipping decorations")
        return 
    end
    if worldGen.STUDIO_ONLY and not RunService:IsStudio() then 
        log:warn("WorldGen.STUDIO_ONLY is true but not in Studio, skipping")
        return 
    end
    
    -- Ensure we have ground for decorations to spawn on and explicit spawn bounds
    DigPerformance.measureSection("PCG_EnsureBaseplate", function()
        ensureTerrainBaseplate()
    end)
    ensureSpawnBoundsPart()
    
    local deco = GameConfig.Decorations or {}
    local treesActive = deco.TREES_ENABLED ~= false
    local rocksActive = deco.ROCKS_ENABLED ~= false
    local fliesActive = deco.FIREFLIES_ENABLED ~= false
    local shouldSpawnAny = treesActive or rocksActive or fliesActive
    
    log:info("Decoration settings: Trees=%s, Rocks=%s, Fireflies=%s",
        tostring(treesActive), tostring(rocksActive), tostring(fliesActive))
    
    local folder = getDecorationFolder()
    if shouldSpawnAny then folder:ClearAllChildren() end
    
    -- Reset light budget
    decorLightCount = 0
    
    local center, sx, sz = getSpawnBounds()
    local rawMargin = worldGen.SPAWN_MARGIN or 200
    local minX, maxX = center.X - sx*0.5 + rawMargin, center.X + sx*0.5 - rawMargin
    local minZ, maxZ = center.Z - sz*0.5 + rawMargin, center.Z + sz*0.5 - rawMargin
    local area = (maxX - minX) * (maxZ - minZ)
    local tiles = area / 10000
    
    local TREE_COUNT = math.clamp(math.floor(tiles * (deco.TREES_PER_100x100 or 1.2)), deco.MIN_TREES or 20, deco.MAX_TREES or 300)
    local ROCK_COUNT = math.clamp(math.floor(tiles * (deco.ROCKS_PER_100x100 or 0.9)), deco.MIN_ROCKS or 15, deco.MAX_ROCKS or 200)
    local FLY_COUNT  = math.clamp(math.floor(tiles * (deco.FIREFLIES_PER_100x100 or 0.6)), deco.MIN_FIREFLIES or 10, deco.MAX_FIREFLIES or 120)
    
    log:info("Target counts: Trees=%d, Rocks=%d, Fireflies=%d (area=%.0f, tiles=%.1f)",
        TREE_COUNT, ROCK_COUNT, FLY_COUNT, area, tiles)
    log:info("Spawn bounds: X=[%.1f, %.1f], Z=[%.1f, %.1f]", minX, maxX, minZ, maxZ)
    
    local rngTrees = Random.new(67890 + 101)
    local rngRocks = Random.new(67890 + 202)
    local rngFlies = Random.new(67890 + 303)
    
    local cubes = getPlayerCubePositions()
    
    local treesSpawned, rocksSpawned, fliesSpawned = 0, 0, 0
    
    if treesActive then
        log:info("Delegating tree spawning to TreeGenerationService (target=%d)...", TREE_COUNT)
        if TreeGenerationService and TreeGenerationService.GenerateInArea then
            -- Optional phase gating from config
            local phase = (GameConfig.WorldGen and GameConfig.WorldGen.PHASE) or nil
            local treesPhase = (deco and (deco.TREES_PHASE or deco.TREES_phase)) or nil
            local treesAllowed = (deco and deco.TREES_ALLOWED_PHASES) or nil
            local positions
            DigPerformance.measureSection("PCG_Trees_Call", function()
                positions = TreeGenerationService:GenerateInArea({
                bounds = {minX=minX, maxX=maxX, minZ=minZ, maxZ=maxZ},
                densityPer100x100 = deco.TREES_PER_100x100,
                minCount = deco.MIN_TREES,
                maxCount = deco.MAX_TREES,
                allowWater = deco.ALLOW_WATER_TREES,
                parentFolder = folder,
                phase = treesPhase or phase,
                allowedPhases = treesAllowed,
                -- Slightly closer to player cubes than default
                playerKeepoutRadius = WorldGenUtils.getDefaultKeepoutRadius() * 0.85,
                -- keep service defaults for spacing/keepout unless configured
                })
            end)
            treesSpawned = positions and #positions or 0
        else
            log:warn("TreeGenerationService missing; skipping tree spawn block")
        end
    end
    
    -- Optional phase gating for rocks
    local rocksPhase = (deco and (deco.ROCKS_PHASE or deco.ROCKS_phase)) or nil
    local rocksAllowed = (deco and deco.ROCKS_ALLOWED_PHASES) or nil
    local currentPhase = WorldGenUtils.getDayNightPhase()
    local rocksPhaseOk = true
    if typeof(rocksAllowed) == "table" then
        rocksPhaseOk = false
        for _, p in ipairs(rocksAllowed) do if p == currentPhase then rocksPhaseOk = true break end end
    elseif type(rocksPhase) == "string" and rocksPhase ~= "any" then
        rocksPhaseOk = (rocksPhase == currentPhase)
    end

    if rocksActive and rocksPhaseOk then
        if RockGenerationService and RockGenerationService.GenerateInArea then
            local positions = RockGenerationService:GenerateInArea({
                bounds = {minX=minX, maxX=maxX, minZ=minZ, maxZ=maxZ},
                densityPer100x100 = deco.ROCKS_PER_100x100,
                minCount = deco.MIN_ROCKS,
                maxCount = deco.MAX_ROCKS,
                allowWater = deco.ALLOW_WATER_ROCKS,
                parentFolder = folder,
                phase = rocksPhase,
                allowedPhases = rocksAllowed,
                playerKeepoutRadius = WorldGenUtils.getDefaultKeepoutRadius(),
            })
            rocksSpawned = positions and #positions or 0
        else
            log:warn("RockGenerationService missing; skipping rock spawn block")
        end
    end
    
    -- Optional phase gating for fireflies
    local fliesPhase = (deco and (deco.FIREFLIES_PHASE or deco.FIREFLIES_phase)) or nil
    local fliesAllowed = (deco and deco.FIREFLIES_ALLOWED_PHASES) or nil
    local fliesPhaseOk = true
    if typeof(fliesAllowed) == "table" then
        fliesPhaseOk = false
        for _, p in ipairs(fliesAllowed) do if p == currentPhase then fliesPhaseOk = true break end end
    elseif type(fliesPhase) == "string" and fliesPhase ~= "any" then
        fliesPhaseOk = (fliesPhase == currentPhase)
    end

    if fliesActive and fliesPhaseOk then
        if FireflyGenerationService and FireflyGenerationService.GenerateInArea then
            local positions
            DigPerformance.measureSection("PCG_Flies_Call", function()
                positions = FireflyGenerationService:GenerateInArea({
                bounds = {minX=minX, maxX=maxX, minZ=minZ, maxZ=maxZ},
                densityPer100x100 = deco.FIREFLIES_PER_100x100,
                minCount = deco.MIN_FIREFLIES,
                maxCount = deco.MAX_FIREFLIES,
                allowWater = deco.ALLOW_WATER_FIREFLIES,
                parentFolder = folder,
                phase = fliesPhase,
                allowedPhases = fliesAllowed,
                playerKeepoutRadius = WorldGenUtils.getDefaultKeepoutRadius(),
                })
            end)
            fliesSpawned = positions and #positions or 0
        else
            log:warn("FireflyGenerationService missing; skipping firefly spawn block")
        end
    end
    
    local mode = (GameConfig.WorldGen and GameConfig.WorldGen.CONSISTENT_MODE) or "independent"
    if mode == "all_or_none" then
        local anyEnabled = treesActive or rocksActive or fliesActive
        if anyEnabled and ((treesActive and treesSpawned==0) or (rocksActive and rocksSpawned==0) or (fliesActive and fliesSpawned==0)) then
            getDecorationFolder():ClearAllChildren()
            treesSpawned, rocksSpawned, fliesSpawned = 0,0,0
            log:warn("CONSISTENT_MODE=all_or_none -> cleared BlockDecorations due to empty category")
        end
    elseif mode == "guarantee_min" then
        local center = Vector3.new((minX+maxX)/2, 0, (minZ+maxZ)/2)
        if treesActive and treesSpawned==0 then 
            local g=findGroundPosition(center.X, center.Z, { allowWater = deco.ALLOW_WATER_TREES }) 
            if g then 
                if TreeGenerationService and TreeGenerationService.SpawnAt then
                    TreeGenerationService:SpawnAt(g)
                else
                    log:warn("TreeGenerationService unavailable for guarantee_min tree")
                end
            end 
        end
        if rocksActive and rocksSpawned==0 then 
            local g=findGroundPosition(center.X+10, center.Z+10, { allowWater = deco.ALLOW_WATER_ROCKS }) 
            if g then 
                if RockGenerationService and RockGenerationService.SpawnAt then
                    RockGenerationService:SpawnAt(g)
                else
                    log:warn("RockGenerationService unavailable for guarantee_min rock")
                end
            end 
        end
        if fliesActive and fliesSpawned==0 then 
            local g=findGroundPosition(center.X-10, center.Z-10, { allowWater = deco.ALLOW_WATER_FIREFLIES }) 
            if g then 
                if FireflyGenerationService and FireflyGenerationService.SpawnAt then
                    FireflyGenerationService:SpawnAt(g)
                else
                    log:warn("FireflyGenerationService unavailable for guarantee_min fireflies")
                end
            end 
        end
    end
    
    log:info("World Generation Complete: %d trees, %d rocks, %d firefly groups", treesSpawned, rocksSpawned, fliesSpawned)
    -- Notify systems that worldgen is finished so dependent visuals can run safely after
    -- Server-local signal; no network target
    Bus:emit(EventNames.WORLDGEN_DONE, {})
end

local spawning = false
local function safeSpawn()
    if spawning then return end
    spawning = true
    
    -- Only spawn ground decorations here
    -- FloatingIslandService will handle its own spawning in its Start method
    local ok, err = pcall(WorldGenerationService.SpawnDecorations)
    if not ok then log:warn("SpawnDecorations error: %s", tostring(err)) end
    
    spawning = false
end

function WorldGenerationService:Init(container)
    GridService = ServiceValidator.tryGet(container, "GridService")
    CubePositionService = ServiceValidator.tryGet(container, "CubePositionService")
    ErrorService = ServiceValidator.tryGet(container, "ErrorService")
    TreeGenerationService = ServiceValidator.tryGet(container, "TreeGenerationService")
    RockGenerationService = ServiceValidator.tryGet(container, "RockGenerationService")
    FireflyGenerationService = ServiceValidator.tryGet(container, "FireflyGenerationService")
    log:info("Initialized")
end

function WorldGenerationService:Start(container)
    -- Reacquire optional services now that container has built instances
    TreeGenerationService = ServiceValidator.tryGet(container, "TreeGenerationService")
    RockGenerationService = ServiceValidator.tryGet(container, "RockGenerationService")
    FireflyGenerationService = ServiceValidator.tryGet(container, "FireflyGenerationService")
    -- Enforce grass settings on start to ensure Studio reflects values
    local terrain = Workspace.Terrain
    pcall(function() terrain.Decoration = true end)
    pcall(function() terrain.GrassLength = 0.4 end)
    safeSpawn()
end

return WorldGenerationService
