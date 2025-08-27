--!strict
-- GridService.server.lua
-- Manages terrain voxels and chunk state using WriteVoxels for performance

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Terrain = Workspace.Terrain
local Shared = ReplicatedStorage:WaitForChild("MiningGame")

local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Types = require(Shared:WaitForChild("Types"))
local GridMath = require(Shared:WaitForChild("Utils"):WaitForChild("GridMath"))
local ChunkCodec = require(Shared:WaitForChild("Utils"):WaitForChild("ChunkCodec"))

-- Performance tracking (optional)
local DigPerformance = require(script.Parent:WaitForChild("DigPerformance"))

-- Visual indicators module
local CubeVisuals = require(script.Parent:WaitForChild("CubeVisuals"))

local GridService = {}

-- Constants
local CELL_SIZE = GameConfig.Grid.CELL_SIZE_STUDS
local CHUNK_SIZE = GameConfig.Grid.CHUNK_CELLS
local CELLS_PER_CHUNK = CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE

-- Throttling for terrain writes
local lastWriteTime: {[Player]: number} = {}
local WRITE_THROTTLE = GameConfig.Performance.GRID_WRITE_THROTTLE

-- Create a new cube state
function GridService:CreateCubeState(ownerId: number, materialId: string): Types.CubeState
    return {
        ownerId = ownerId,
        materialId = materialId,
        cellSize = CELL_SIZE,
        chunkSize = CHUNK_SIZE,
        chunks = {},
        totalDug = 0,
        createdAt = os.time(),
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
            lastModified = os.time(),
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
    chunk.lastModified = os.time()
    state.totalDug = state.totalDug + 1
    
    return true
end

-- Check if we should throttle terrain writes
local function shouldThrottle(player: Player): boolean
    local now = tick()
    local lastWrite = lastWriteTime[player] or 0
    
    if now - lastWrite < WRITE_THROTTLE then
        return true
    end
    
    lastWriteTime[player] = now
    return false
end

-- Apply a dig operation to terrain (optimized cube shape)
function GridService:ApplyDig(
    player: Player,
    cubeOrigin: CFrame,
    state: Types.CubeState,
    cellX: number,
    cellY: number,
    cellZ: number,
    size: number
): {{x: number, y: number, z: number}}
    
    -- Throttle per-player writes
    if shouldThrottle(player) then
        return {}
    end
    
    -- Guard input to prevent negative size
    size = math.max(0, size)
    
    local halfCells = (GameConfig.Grid.CUBE_SIZE_STUDS / CELL_SIZE) / 2
    local minBound, maxBound = -halfCells, halfCells - 1
    
    -- Create a cube centered on the target cell
    local xMin = math.max(cellX - size, minBound)
    local xMax = math.min(cellX + size, maxBound)
    local yMin = math.max(cellY - size, minBound)
    local yMax = math.min(cellY + size, maxBound)
    local zMin = math.max(cellZ - size, minBound)
    local zMax = math.min(cellZ + size, maxBound)
    
    -- Early exit if bounds are invalid
    if xMin > xMax or yMin > yMax or zMin > zMax then
        return {}
    end
    
    -- Preallocate based on actual volume
    local width = xMax - xMin + 1
    local height = yMax - yMin + 1
    local length = zMax - zMin + 1
    local expected = width * height * length
    
    local prealloc = math.min(expected, 10000)
    local dugCells = table.create(prealloc)
    local cellsToWrite = table.create(prealloc)
    local dugCount, writeCount = 0, 0
    
    -- Iterate once over unique cells (no duplicates)
    DigPerformance.measureSection("CellIteration", function()
        for y = yMax, yMin, -1 do
            for x = xMin, xMax do
                for z = zMin, zMax do
                    if markCellDug(state, x, y, z) then
                        dugCount = dugCount + 1
                        writeCount = writeCount + 1
                        local cell = {x = x, y = y, z = z}
                        dugCells[dugCount] = cell
                        cellsToWrite[writeCount] = cell
                    end
                end
            end
        end
    end)
    
    -- Early exit if nothing was dug
    if writeCount == 0 then
        return {}
    end
    
    -- Trim arrays to actual size (important for #cells to work correctly)
    for i = dugCount + 1, #dugCells do
        dugCells[i] = nil
    end
    for i = writeCount + 1, #cellsToWrite do
        cellsToWrite[i] = nil
    end
    
    -- Single pass terrain write
    DigPerformance.measureSection("TerrainWrite", function()
        self:WriteCellsToTerrain(cubeOrigin, cellsToWrite, state.materialId)
    end)
    
    return dugCells
end

-- Write cells to terrain using a single Read/Write pass
function GridService:WriteCellsToTerrain(cubeOrigin: CFrame, cells: {{x: number, y: number, z: number}}, materialId: string)
    if #cells == 0 then return end
    
    -- 1) Compute cell-space AABB of the dig set
    local minX, minY, minZ = math.huge, math.huge, math.huge
    local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
    for _, c in ipairs(cells) do
        if c.x < minX then minX = c.x end
        if c.y < minY then minY = c.y end
        if c.z < minZ then minZ = c.z end
        if c.x > maxX then maxX = c.x end
        if c.y > maxY then maxY = c.y end
        if c.z > maxZ then maxZ = c.z end
    end
    
    -- 2) Convert the cell AABB to world-space voxel-aligned Region3
    local function cellToWorldCorner(cx, cy, cz)
        -- cell center:
        local center = GridMath.cellToWorld(cx, cy, cz, cubeOrigin, CELL_SIZE)
        -- convert to min world corner of that cell
        return center - Vector3.new(CELL_SIZE/2, CELL_SIZE/2, CELL_SIZE/2)
    end
    local cellMinWorld = cellToWorldCorner(minX, minY, minZ)
    local cellMaxWorld = cellToWorldCorner(maxX, maxY, maxZ) + Vector3.new(CELL_SIZE, CELL_SIZE, CELL_SIZE)
    
    -- align to 4-stud voxel grid
    local function snapDown4(v)
        return Vector3.new(
            math.floor(v.X/4)*4, 
            math.floor(v.Y/4)*4, 
            math.floor(v.Z/4)*4
        )
    end
    local function snapUp4(v)
        return Vector3.new(
            math.ceil(v.X/4)*4,
            math.ceil(v.Y/4)*4,
            math.ceil(v.Z/4)*4
        )
    end
    
    local rmin = snapDown4(cellMinWorld)
    local rmax = snapUp4(cellMaxWorld)
    local region = Region3.new(rmin, rmax):ExpandToGrid(4)
    
    -- 3) Read once
    local materials, occupancy = DigPerformance.measureSection("ReadVoxels", function()
        return Terrain:ReadVoxels(region, 4)
    end)
    local size = materials.Size  -- Vector3int16 of voxel counts
    
    -- 4) Mark only targeted voxels (optimized with inline calculations)
    local regionMin = region.CFrame.Position - region.Size/2
    local maxVX, maxVY, maxVZ = size.X, size.Y, size.Z
    local invVoxel = 0.25  -- 1/4 for voxel size
    
    for i = 1, #cells do
        local c = cells[i]
        
        -- Inline world position calculation (saves function call overhead)
        local localPos = Vector3.new(
            (c.x + 0.5) * CELL_SIZE,
            (c.y + 0.5) * CELL_SIZE,
            (c.z + 0.5) * CELL_SIZE
        )
        local wCenter = cubeOrigin:PointToWorldSpace(localPos)
        local rel = wCenter - regionMin
        
        -- Use integer floor operator // to avoid function call
        local vx = (rel.X * invVoxel) // 1 + 1
        local vy = (rel.Y * invVoxel) // 1 + 1
        local vz = (rel.Z * invVoxel) // 1 + 1
        
        if vx >= 1 and vx <= maxVX and vy >= 1 and vy <= maxVY and vz >= 1 and vz <= maxVZ then
            occupancy[vx][vy][vz] = 0
            materials[vx][vy][vz] = Enum.Material.Air
        end
    end
    
    -- 5) Write once
    DigPerformance.measureSection("WriteVoxels", function()
        Terrain:WriteVoxels(region, 4, materials, occupancy)
    end)
end

-- Create the initial terrain cube
function GridService:CreateTerrainCube(cubeOrigin: CFrame, size: number, material: Enum.Material): Model
    -- Create a model to hold the cube
    local model = Instance.new("Model")
    model.Name = "MiningCube"
    
    -- Use FillBlock for initial cube creation
    local region = Region3.new(
        cubeOrigin.Position - Vector3.new(size/2, size/2, size/2),
        cubeOrigin.Position + Vector3.new(size/2, size/2, size/2)
    )
    region = region:ExpandToGrid(4)
    
    Terrain:FillBlock(cubeOrigin, Vector3.new(size, size, size), material)
    
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
    
    -- Visual indicators
    CubeVisuals.CreateFloorGlow(model, cubeOrigin, size)
    CubeVisuals.AddCubeLight(bounds, size)
    CubeVisuals.CreateStudioSelectionBox(bounds) -- Studio-only debug
    
    -- Optional whole cube glow (for monetization/upgrades)
    -- This can be made player-specific later by checking player data
    local cubeGlowEnabled = GameConfig.Visuals.CUBE_GLOW_ENABLED
    CubeVisuals.CreateCubeGlow(model, cubeOrigin, size, cubeGlowEnabled)
    
    return model
end

-- Restore cube from saved state
function GridService:RestoreCube(cubeOrigin: CFrame, state: Types.CubeState): Model
    -- Get material (handle both old and new material IDs)
    local materialId = state.materialId or "tier1"
    local materialData = GameConfig.CubeMaterialsById[materialId]
    
    if not materialData then
        warn("[GridService] Unknown material ID:", materialId, "- using tier1")
        materialData = GameConfig.CubeMaterialsById["tier1"]
    end
    
    -- Get the terrain material enum from the terrainKey
    local terrainMaterial: Enum.Material = Enum.Material.Rock
    if materialData and materialData.terrainKey then
        local terrainKeyMap = {
            rock = Enum.Material.Rock,
            sandstone = Enum.Material.Sandstone,
            basalt = Enum.Material.Basalt,
            slate = Enum.Material.Slate,
            limestone = Enum.Material.Limestone,
            glacier = Enum.Material.Glacier,
        }
        terrainMaterial = terrainKeyMap[materialData.terrainKey] or Enum.Material.Rock
        print("[GridService] Material resolved:", materialId, "->", materialData.terrainKey, "->", tostring(terrainMaterial))
    else
        warn("[GridService] No terrainKey for material:", materialId, "- defaulting to Rock")
    end
    
    -- Create the base cube (now guaranteed to have a valid material)
    local model = self:CreateTerrainCube(
        cubeOrigin,
        GameConfig.Grid.CUBE_SIZE_STUDS,
        terrainMaterial
    )
    
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
        self:WriteCellsToTerrain(cubeOrigin, cellsToCarve, state.materialId)
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

-- Clean up player throttle data
local function cleanupPlayer(player: Player)
    lastWriteTime[player] = nil
end

-- Connect cleanup
game.Players.PlayerRemoving:Connect(cleanupPlayer)

print("[GridService] Initialized")

-- Debug command to print performance report
game:GetService("RunService").Heartbeat:Connect(function()
    local perfReport = DigPerformance.getReport()
    if perfReport and #perfReport > 50 then  -- Only print if there's data
        -- Print every 30 seconds if there's new data
        if tick() % 30 < 0.1 then
            print(perfReport)
        end
    end
end)

return GridService