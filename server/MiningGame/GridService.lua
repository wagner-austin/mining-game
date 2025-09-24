--!strict
--[[
    GridService.server.lua
    Core terrain management service handling voxel operations and chunk state.
    
    Features:
    - Efficient terrain writing using WriteVoxels API
    - Chunk-based state management with bit compression
    - Throttling to prevent performance issues
    - Support for multi-cell dig patterns
    - Visual indicators for cube boundaries
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Terrain = Workspace.Terrain
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(Shared:WaitForChild("Logger"))
local log = Logger.new("GridService")
local MathUtils = require(Shared:WaitForChild("MathUtils"))

local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Types = require(Shared:WaitForChild("Types"))
local Time = require(Shared:WaitForChild("Time"))
local TerrainSurfaceDetector = require(Shared:WaitForChild("TerrainSurfaceDetector"))
local GridMath = require(Shared:WaitForChild("Utils"):WaitForChild("GridMath"))
local ChunkCodec = require(Shared:WaitForChild("Utils"):WaitForChild("ChunkCodec"))
local MaterialKeys = require(Shared:WaitForChild("MaterialKeys"))
local MaterialDefinitions = require(Shared:WaitForChild("MaterialDefinitions"))

-- Performance tracking (optional)
local DigPerformance = require(script.Parent:WaitForChild("DigPerformance"))

-- Visual indicators module
local CubeVisuals = require(script.Parent:WaitForChild("CubeVisuals"))

-- Additional modules
local CubeThemes = require(ReplicatedStorage.MiningGame:WaitForChild("CubeThemes"))
local ServiceValidator = require(Shared:WaitForChild("ServiceValidator"))

-- Services (injected via Init)
local DataService
local MixedMaterialService  -- optional
local ErrorService  -- For safe error handling

local GridService = {}

type Cell = { x: number, y: number, z: number }
type SoundHint = { materialKey: string?, worldPos: Vector3? }

-- Player tracking (moved before Start method to avoid forward reference)
local lastWriteTime: {[Player]: number} = {}

-- Connection tracking for cleanup
local _conns = {}

-- Initialize with DI container
function GridService:Init(container)
    DataService = ServiceValidator.get(container, "DataService", {"GetPlayerData", "GetMaterialPrefs", "QueueSave"})
    -- MixedMaterialService is now required (boot order fixed in ServiceManager)
    MixedMaterialService = ServiceValidator.get(container, "MixedMaterialService", {"ApplyMixedMaterials"})
    -- Get ErrorService for safe error handling
    ErrorService = ServiceValidator.get(container, "ErrorService", {"safecall"})
    log:info("Initialized with dependencies")
end

-- Start lifecycle - setup connections
function GridService:Start()
    -- Setup player cleanup connection
    table.insert(_conns, Players.PlayerRemoving:Connect(function(player)
        -- Cleanup per-player caches
        lastWriteTime[player] = nil
        -- Any other player-specific cleanup
    end))
    log:info("Started with event connections")
end

-- Stop lifecycle - cleanup connections
function GridService:Stop()
    for _, c in ipairs(_conns) do 
        if c and c.Disconnect then 
            pcall(function() c:Disconnect() end) 
        end 
    end
    table.clear(_conns)
    log:info("Stopped and cleaned up connections")
end

-- Constants
local CELL_SIZE = GameConfig.Grid.CELL_SIZE_STUDS
local VOX = GameConfig.Terrain.VOXEL_RESOLUTION
local CHUNK_SIZE = GameConfig.Grid.CHUNK_CELLS
local CELLS_PER_CHUNK = CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE
local FACE_PROBE_EPSILON = math.min(0.01, CELL_SIZE * 0.01)  -- Small offset for face probing

-- Throttling for terrain writes (lastWriteTime already declared at top)
local WRITE_THROTTLE = GameConfig.Performance.GRID_WRITE_THROTTLE

--[[
    Create a new cube state for a player.
    Initializes an empty cube with no dug cells.
    
    @param ownerId: number - The player's UserId
    @param materialId: string - The material identifier for the cube
    @return Types.CubeState - The initialized cube state
]]
function GridService:CreateCubeState(ownerId: number, materialId: string): Types.CubeState
    return {
        ownerId = ownerId,
        materialId = materialId,
        cellSize = CELL_SIZE,
        chunkSize = CHUNK_SIZE,
        chunks = {},
        totalDug = 0,
        createdAt = Time.unix(),
    }
end

-- Get or create a chunk
local function getOrCreateChunk(state: Types.CubeState, chunkX: number, chunkY: number, chunkZ: number): Types.Chunk
    local key = GridMath.chunkKey(chunkX, chunkY, chunkZ)
    local chunk = state.chunks[key]
    
    if not chunk then
        -- Create new chunk (all undug)
        chunk = {
            size = CHUNK_SIZE,
            dugBits = ChunkCodec.empty(CELLS_PER_CHUNK),
            dirty = false,
            lastModified = Time.unix(),
        }
        state.chunks[key] = chunk
    end
    
    return chunk
end

-- Mark a cell as dug in the state
local function markCellDug(state: Types.CubeState, cellX: number, cellY: number, cellZ: number): boolean
    -- Get chunk coordinates
    local chunkX, chunkY, chunkZ = GridMath.cellToChunk(cellX, cellY, cellZ, CHUNK_SIZE)
    local chunk = getOrCreateChunk(state, chunkX, chunkY, chunkZ)
    
    -- Get local cell position within chunk
    local localX, localY, localZ = GridMath.cellToChunkLocal(cellX, cellY, cellZ, CHUNK_SIZE)
    local index = GridMath.chunkLocalToIndex(localX, localY, localZ, CHUNK_SIZE)
    
    -- Check if already dug
    if ChunkCodec.getBit(chunk.dugBits, index, CELLS_PER_CHUNK) then
        return false -- Already dug
    end
    
    -- Mark as dug
    chunk.dugBits = ChunkCodec.setBit(chunk.dugBits, index, true, CELLS_PER_CHUNK)
    chunk.dirty = true
    chunk.lastModified = Time.unix()
    state.totalDug = state.totalDug + 1
    
    return true
end

-- Check if we should throttle terrain writes
local function shouldThrottle(player: Player): boolean
    local now = Time.mono()
    local lastWrite = lastWriteTime[player] or -math.huge
    
    if now - lastWrite < WRITE_THROTTLE then
        return true
    end
    
    lastWriteTime[player] = now
    return false
end

-- Check if a cell position has solid terrain
local function hasSolidTerrain(worldPos: Vector3): boolean
    local region = Region3.new(
        worldPos - Vector3.new(0.1, 0.1, 0.1),
        worldPos + Vector3.new(0.1, 0.1, 0.1)
    ):ExpandToGrid(4)
    
    local materials, occupancies = Terrain:ReadVoxels(region, 4)
    local mat = materials[1][1][1]
    local occ = occupancies[1][1][1]
    
    return mat ~= Enum.Material.Air and occ > 0.5
end

--[[
    Apply a dig operation to terrain, removing voxels in a cube pattern.
    Handles state updates, terrain modification, and performance tracking.
    
    @param cubeOrigin: CFrame - The cube's origin position
    @param state: Types.CubeState - The cube's current state
    @param cellX: number - X coordinate of the center cell
    @param cellY: number - Y coordinate of the center cell
    @param cellZ: number - Z coordinate of the center cell
    @param player: Player - The player performing the dig
    @param size: number - Radius of cells to dig (1 = single cell)
    @return {Cell}, SoundHint? - Dug cell list and optional sound hint
]]
function GridService:ApplyDig(
    player: Player,
    cubeOrigin: CFrame,
    state: Types.CubeState,
    cellX: number,
    cellY: number,
    cellZ: number,
    size: number,
    options: {mode: string?, normal: Vector3?}?
): ({Cell}, SoundHint?)
    local DigEngine = require(script.Parent.Grid:WaitForChild("DigEngine"))
    return DigEngine.ApplyDig(player, cubeOrigin, state, cellX, cellY, cellZ, size, options)
end

--[[
    Write multiple cells to terrain in a single efficient operation.
    Uses ReadVoxels/WriteVoxels for optimal performance.
    
    @param cubeOrigin: CFrame - The cube's origin position
    @param cells: {{x: number, y: number, z: number}} - Array of cell coordinates to write
    @param materialId: string - The material to write ("air" for deletion)
]]
function GridService:WriteCellsToTerrain(
    cubeOrigin: CFrame,
    cells: {Cell},
    materialId: string
): SoundHint
    local DigEngine = require(script.Parent.Grid:WaitForChild("DigEngine"))
    return DigEngine.WriteCellsToTerrain(cubeOrigin, cells, materialId)
end

--[[
    Create the initial terrain cube with optional floor material.
    Generates a solid cube of terrain and adds visual boundary indicators.
    
    @param cubeOrigin: CFrame - The cube's center position
    @param size: number - The cube size in studs
    @param material: Enum.Material - The primary material for the cube
    @param initialFloor: Enum.Material? - Optional different material for the bottom layer
    @return Model - The cube model containing terrain and visual indicators
]]
function GridService:CreateTerrainCube(cubeOrigin: CFrame, size: number, material: Enum.Material, initialFloor: Enum.Material?): Model
    -- Create a model to hold the cube
    local model = Instance.new("Model")
    model.Name = "MiningCube"
    
    -- Use FillBlock for initial cube creation
    local region = Region3.new(
        cubeOrigin.Position - Vector3.new(size/2, size/2, size/2),
        cubeOrigin.Position + Vector3.new(size/2, size/2, size/2)
    )
    region = region:ExpandToGrid(VOX)
    
    ErrorService.safecall("Terrain:FillBlock", function()
        Terrain:FillBlock(cubeOrigin, Vector3.new(size, size, size), material)
    end, { origin = tostring(cubeOrigin.Position), size = size, material = tostring(material) })
    -- Clear surface detection cache after terrain creation
    ErrorService.safecall("TerrainSurfaceDetector.ClearCache", function()
        TerrainSurfaceDetector.ClearCache()
    end)
    
    -- Add bounds indicator
    local bounds = Instance.new("Part")
    bounds.Name = "Bounds"
    bounds.Size = Vector3.new(size, size, size)
    bounds.CFrame = cubeOrigin
    bounds.Transparency = 1
    bounds.CanCollide = false
    bounds.CanTouch = false
    bounds.CanQuery = false  -- IMPORTANT: Prevent raycast hits
    bounds.Anchored = true
    bounds.Parent = model
    
    -- Visual indicators (use initialFloor if provided, otherwise use config default)
    local floorMaterial = initialFloor or (GameConfig.Visuals and GameConfig.Visuals.FLOOR_GLOW_REPLACEMENT_MATERIAL) or Enum.Material.Concrete
    CubeVisuals.CreateFloorGlow(model, cubeOrigin, size, floorMaterial)
    CubeVisuals.AddCubeLight(bounds, size)
    CubeVisuals.CreateStudioSelectionBox(bounds) -- Studio-only debug
    
    -- Optional whole cube glow (for monetization/upgrades)
    -- This can be made player-specific later by checking player data
    local cubeGlowEnabled = GameConfig.Visuals.CUBE_GLOW_ENABLED
    CubeVisuals.CreateCubeGlow(model, cubeOrigin, size, cubeGlowEnabled)
    
    return model
end

--[[
    Restore a cube from saved state, recreating previously dug patterns.
    Efficiently rebuilds terrain by only writing undug cells.
    
    @param cubeOrigin: CFrame - The cube's center position
    @param state: Types.CubeState - The saved cube state with chunk data
    @param initialFloor: Enum.Material? - Optional floor material override
    @return Model - The restored cube model
]]
function GridService:RestoreCube(cubeOrigin: CFrame, state: Types.CubeState, initialFloor: Enum.Material?): Model
    -- Get material (handle both old and new material IDs)
    local materialId = state.materialId or "tier1"
    local materialData = GameConfig.CubeMaterialsById[materialId]
    
    if not materialData then
        log:warn("Unknown material ID: %s - using tier1", tostring(materialId))
        materialData = GameConfig.CubeMaterialsById["tier1"]
    end
    
    -- Get the terrain material enum from the terrainKey via the canonical map
    local terrainMaterial: Enum.Material = Enum.Material.Rock
    if materialData and materialData.terrainKey then
        terrainMaterial = MaterialKeys.EnumFromKey[materialData.terrainKey] or Enum.Material.Rock
        log:debug("Material resolved: %s -> %s -> %s",
            materialId, tostring(materialData.terrainKey), tostring(terrainMaterial))
    else
        log:warn("No terrainKey for material: %s - defaulting to Rock", tostring(materialId))
    end
    
    -- Create the base cube (now guaranteed to have a valid material)
    local model = self:CreateTerrainCube(
        cubeOrigin,
        GameConfig.Grid.CUBE_SIZE_STUDS,
        terrainMaterial,
        initialFloor
    )
    
    -- If player is in composition mode, overwrite terrain with mixed materials first
    local ownerPlayer = Players:GetPlayerByUserId(state.ownerId)
    if ownerPlayer then
        local prefs = DataService:GetMaterialPrefs(ownerPlayer) or {}
        if prefs.mode == "composition" then
            -- Theme-only composition: get components from active theme
            local themeId = prefs.activeThemeId or "underwater_cave"
            local comps = CubeThemes.GetThemeComponents(themeId) or {}
            local swathes = {}
            for _, c in ipairs(comps) do
                local matEnum = MaterialDefinitions.GetEnum(c.materialKey)
                if matEnum then 
                    table.insert(swathes, { 
                        material = matEnum, 
                        weight = c.weight, 
                        scale = c.scale 
                    }) 
                end
            end
            if #swathes > 0 then
                if MixedMaterialService then
                    MixedMaterialService:ApplyMixedMaterials(
                        cubeOrigin,
                        GameConfig.Grid.CUBE_SIZE_STUDS,
                        { 
                            seed = prefs.compositionSeed or 1, 
                            blendMode = "hard", 
                            swathes = swathes 
                        },
                        false -- Don't preserve air on initial restore
                    )
                else
                    log:warn("MixedMaterialService not available - skipping mixed materials for UID %s", tostring(state.ownerId))
                end
                log:debug("Restored theme '%s' (%d materials) for UID %d", themeId, #swathes, state.ownerId)
            end
        end
    end
    
    -- Apply dug cells from state
    local cellsToCarve = {}
    
    for chunkKey, chunk in pairs(state.chunks) do
        if chunk.dugBits and chunk.dugBits ~= "" then
            local chunkX, chunkY, chunkZ = GridMath.parseChunkKey(chunkKey)
            local bits = ChunkCodec.unpack(chunk.dugBits, CELLS_PER_CHUNK)
            
            for i = 1, CELLS_PER_CHUNK do
                if bits[i] then
                    local localX, localY, localZ = GridMath.indexToChunkLocal(i, CHUNK_SIZE)
                    local cellX = chunkX * CHUNK_SIZE + localX
                    local cellY = chunkY * CHUNK_SIZE + localY
                    local cellZ = chunkZ * CHUNK_SIZE + localZ
                    
                    table.insert(cellsToCarve, {x = cellX, y = cellY, z = cellZ})
                end
            end
        end
    end
    
    -- Carve out dug cells
    if #cellsToCarve > 0 then
        local DigEngine = require(script.Parent.Grid:WaitForChild("DigEngine"))
        DigEngine.WriteCellsToTerrain(cubeOrigin, cellsToCarve, state.materialId)
    end
    
    model.Name = "MiningCube_" .. tostring(state.ownerId)
    return model
end

-- Get cells in a cube (for preview)
function GridService:GetCellsInCube(cellX: number, cellY: number, cellZ: number, size: number): {{x: number, y: number, z: number}}
    local cells = {}
    
    for x, y, z in GridMath.cellCube(cellX, cellY, cellZ, size) do
        table.insert(cells, {x = x, y = y, z = z})
    end
    
    return cells
end

-- Check if a cell is dug
function GridService:IsCellDug(state: Types.CubeState, cellX: number, cellY: number, cellZ: number): boolean
    local chunkX, chunkY, chunkZ = GridMath.cellToChunk(cellX, cellY, cellZ, CHUNK_SIZE)
    local key = GridMath.chunkKey(chunkX, chunkY, chunkZ)
    local chunk = state.chunks[key]
    
    if not chunk then
        return false
    end
    
    local localX, localY, localZ = GridMath.cellToChunkLocal(cellX, cellY, cellZ, CHUNK_SIZE)
    local index = GridMath.chunkLocalToIndex(localX, localY, localZ, CHUNK_SIZE)
    
    return ChunkCodec.getBit(chunk.dugBits, index, CELLS_PER_CHUNK)
end

-- Get chunk statistics
function GridService:GetChunkStats(state: Types.CubeState): {totalChunks: number, dugCells: number, compressedSize: number}
    local totalChunks = 0
    local dugCells = 0
    local compressedSize = 0
    
    for _, chunk in pairs(state.chunks) do
        totalChunks = totalChunks + 1
        dugCells = dugCells + ChunkCodec.countDug(chunk.dugBits, CELLS_PER_CHUNK)
        compressedSize = compressedSize + ChunkCodec.getByteSize(chunk.dugBits)
    end
    
    return {
        totalChunks = totalChunks,
        dugCells = dugCells,
        compressedSize = compressedSize,
    }
end

-- Cleanup is now handled in GridService:Start() lifecycle method

log:info("Module loaded")

-- Debug command to print performance report
local lastPerfLog = 0
RunService.Heartbeat:Connect(function()
    local perfReport = DigPerformance.getReport()
    if perfReport and #perfReport > 50 then  -- Only print if there's data
        -- Print at most once every 30s if there's new data
        local now = Time.mono()
        if now - lastPerfLog >= 30 then
            lastPerfLog = now
            log:debug(perfReport)
        end
    end
end)

return GridService
