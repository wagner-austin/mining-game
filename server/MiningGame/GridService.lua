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

-- Apply a dig operation to terrain
function GridService:ApplyDig(
    player: Player,
    cubeOrigin: CFrame,
    state: Types.CubeState,
    cellX: number,
    cellY: number,
    cellZ: number,
    radius: number,
    depth: number
): {{x: number, y: number, z: number}}
    
    -- Check throttling
    if shouldThrottle(player) then
        return {} -- Rate limited
    end
    
    local dugCells = {}
    local cellsToWrite = {}
    
    -- Collect all cells to dig (cube shape)
    for x, y, z in GridMath.cellCube(cellX, cellY, cellZ, radius) do
        -- Apply depth (dig downward)
        for d = 0, depth - 1 do
            local digX, digY, digZ = x, y - d, z
            
            -- Check bounds
            if GridMath.isInBounds(digX, digY, digZ, GameConfig.Grid.CUBE_SIZE_STUDS) then
                -- Mark cell as dug
                if markCellDug(state, digX, digY, digZ) then
                    table.insert(dugCells, {x = digX, y = digY, z = digZ})
                    table.insert(cellsToWrite, {x = digX, y = digY, z = digZ})
                end
            end
        end
    end
    
    -- Write to terrain in batches
    if #cellsToWrite > 0 then
        self:WriteCellsToTerrain(cubeOrigin, cellsToWrite, state.materialId)
    end
    
    return dugCells
end

-- Write cells to terrain using WriteVoxels
function GridService:WriteCellsToTerrain(cubeOrigin: CFrame, cells: {{x: number, y: number, z: number}}, materialId: string)
    -- Group cells by region for efficient WriteVoxels calls
    local regions = {}
    
    for _, cell in ipairs(cells) do
        -- Convert to world space and snap to voxel grid
        local region = GridMath.snapCellToVoxel(cell.x, cell.y, cell.z, CELL_SIZE, cubeOrigin)
        table.insert(regions, region)
    end
    
    -- Process regions in batches
    for _, region in ipairs(regions) do
        local success, err = pcall(function()
            -- Convert Region3 to Region3int16 for WriteVoxels
            local minPoint = region.CFrame.Position - region.Size/2
            local maxPoint = region.CFrame.Position + region.Size/2
            
            local region3int16 = Region3int16.new(
                Vector3int16.new(minPoint.X/4, minPoint.Y/4, minPoint.Z/4),
                Vector3int16.new(maxPoint.X/4, maxPoint.Y/4, maxPoint.Z/4)
            )
            
            -- Read current voxels
            local materials, occupancy = Terrain:ReadVoxels(region, 4)
            
            -- Set to air (carve out)
            local size = materials.Size
            for x = 1, size.X do
                for y = 1, size.Y do
                    for z = 1, size.Z do
                        occupancy[x][y][z] = 0 -- Air
                        materials[x][y][z] = Enum.Material.Air
                    end
                end
            end
            
            -- Write back
            Terrain:WriteVoxels(region, 4, materials, occupancy)
        end)
        
        if not success then
            warn("[GridService] Failed to write terrain:", err)
        end
    end
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
    bounds.Anchored = true
    bounds.Parent = model
    
    -- Add selection box for visual reference
    local selectionBox = Instance.new("SelectionBox")
    selectionBox.Adornee = bounds
    selectionBox.LineThickness = 0.1
    selectionBox.Transparency = 0.8
    selectionBox.Color3 = Color3.new(1, 1, 1)
    selectionBox.Parent = bounds
    
    return model
end

-- Restore cube from saved state
function GridService:RestoreCube(cubeOrigin: CFrame, state: Types.CubeState): Model
    -- Get material
    local materialData = GameConfig.CubeMaterialsById[state.materialId]
    if not materialData then
        warn("[GridService] Unknown material:", state.materialId)
        return Instance.new("Model")
    end
    
    -- Create the base cube
    local model = self:CreateTerrainCube(
        cubeOrigin,
        GameConfig.Grid.CUBE_SIZE_STUDS,
        materialData.material
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

-- Get cells in a radius (for preview)
function GridService:GetCellsInRadius(cellX: number, cellY: number, cellZ: number, radius: number, shape: string): {{x: number, y: number, z: number}}
    local cells = {}
    
    if shape == "CUBE" then
        for x, y, z in GridMath.cellCube(cellX, cellY, cellZ, radius) do
            table.insert(cells, {x = x, y = y, z = z})
        end
    elseif shape == "SPHERE" then
        for x, y, z in GridMath.cellSphere(cellX, cellY, cellZ, radius) do
            table.insert(cells, {x = x, y = y, z = z})
        end
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

return GridService