--!strict
-- GridMath.lua
-- Grid coordinate system and spatial calculations

local GridMath = {}

-- Convert world position to cell coordinates relative to cube origin
function GridMath.worldToCell(worldPos: Vector3, cubeOrigin: CFrame, cellSize: number)
    local localPos = cubeOrigin:PointToObjectSpace(worldPos)
    return math.floor(localPos.X / cellSize),
           math.floor(localPos.Y / cellSize),
           math.floor(localPos.Z / cellSize)
end

-- Convert cell coordinates back to world position (center of cell)
function GridMath.cellToWorld(cellX: number, cellY: number, cellZ: number, cubeOrigin: CFrame, cellSize: number): Vector3
    local localPos = Vector3.new(
        (cellX + 0.5) * cellSize,
        (cellY + 0.5) * cellSize,
        (cellZ + 0.5) * cellSize
    )
    return cubeOrigin:PointToWorldSpace(localPos)
end

-- Snap cell coordinates to Terrain voxel grid (4x4x4 studs)
-- Returns a Region3 aligned to voxel boundaries
function GridMath.snapCellToVoxel(cellX: number, cellY: number, cellZ: number, cellSize: number, cubeOrigin: CFrame): Region3
    assert(cellSize == 4, "Cell size must be 4 to match Terrain voxels")
    
    -- Convert to world space
    local worldPos = GridMath.cellToWorld(cellX, cellY, cellZ, cubeOrigin, cellSize)
    
    -- Snap to voxel grid (4-stud alignment)
    local min = Vector3.new(
        math.floor(worldPos.X / 4) * 4,
        math.floor(worldPos.Y / 4) * 4,
        math.floor(worldPos.Z / 4) * 4
    )
    local max = min + Vector3.new(4, 4, 4)
    
    -- Expand to voxel grid alignment if needed
    local region = Region3.new(min, max)
    region = region:ExpandToGrid(4)
    
    return region
end

-- Iterator for all cells in a cube shape
function GridMath.cellCube(centerX: number, centerY: number, centerZ: number, radius: number)
    return coroutine.wrap(function()
        for dz = -radius, radius do
            for dy = -radius, radius do
                for dx = -radius, radius do
                    coroutine.yield(centerX + dx, centerY + dy, centerZ + dz)
                end
            end
        end
    end)
end

-- Iterator for all cells in a sphere shape (for future expansion)
function GridMath.cellSphere(centerX: number, centerY: number, centerZ: number, radius: number)
    local radiusSq = radius * radius
    return coroutine.wrap(function()
        for dz = -radius, radius do
            for dy = -radius, radius do
                for dx = -radius, radius do
                    if (dx*dx + dy*dy + dz*dz) <= radiusSq then
                        coroutine.yield(centerX + dx, centerY + dy, centerZ + dz)
                    end
                end
            end
        end
    end)
end

-- Get chunk coordinates for a cell
function GridMath.cellToChunk(cellX: number, cellY: number, cellZ: number, chunkSize: number)
    return math.floor(cellX / chunkSize),
           math.floor(cellY / chunkSize),
           math.floor(cellZ / chunkSize)
end

-- Get local cell position within a chunk (0 to chunkSize-1)
function GridMath.cellToChunkLocal(cellX: number, cellY: number, cellZ: number, chunkSize: number)
    return cellX % chunkSize,
           cellY % chunkSize,
           cellZ % chunkSize
end

-- Convert chunk coordinates to a string key
function GridMath.chunkKey(chunkX: number, chunkY: number, chunkZ: number): string
    return string.format("%d_%d_%d", chunkX, chunkY, chunkZ)
end

-- Parse chunk key back to coordinates
function GridMath.parseChunkKey(key: string): (number, number, number)
    local parts = string.split(key, "_")
    return tonumber(parts[1]) :: number,
           tonumber(parts[2]) :: number,
           tonumber(parts[3]) :: number
end

-- Get 1D index from 3D chunk-local coordinates
function GridMath.chunkLocalToIndex(localX: number, localY: number, localZ: number, chunkSize: number): number
    assert(localX >= 0 and localX < chunkSize, "localX out of bounds")
    assert(localY >= 0 and localY < chunkSize, "localY out of bounds")
    assert(localZ >= 0 and localZ < chunkSize, "localZ out of bounds")
    
    -- Z-major order for better cache locality
    return localZ * chunkSize * chunkSize + localY * chunkSize + localX + 1 -- Lua 1-indexed
end

-- Convert 1D index back to 3D chunk-local coordinates
function GridMath.indexToChunkLocal(index: number, chunkSize: number): (number, number, number)
    index = index - 1 -- Convert to 0-indexed
    local localX = index % chunkSize
    local localY = math.floor(index / chunkSize) % chunkSize
    local localZ = math.floor(index / (chunkSize * chunkSize))
    return localX, localY, localZ
end

-- Check if a cell is within cube bounds
-- The cube is centered at origin, so cells go from -halfSize to +halfSize
function GridMath.isInBounds(cellX: number, cellY: number, cellZ: number, cubeSize: number): boolean
    local halfCells = cubeSize / 4 / 2 -- 4 studs per cell, then divide by 2 for half
    return cellX >= -halfCells and cellX < halfCells and
           cellY >= -halfCells and cellY < halfCells and
           cellZ >= -halfCells and cellZ < halfCells
end

-- Get all chunks affected by a dig operation
function GridMath.getAffectedChunks(centerX: number, centerY: number, centerZ: number, radius: number, chunkSize: number)
    local chunks = {}
    local seen = {}
    
    for x, y, z in GridMath.cellCube(centerX, centerY, centerZ, radius) do
        local cx, cy, cz = GridMath.cellToChunk(x, y, z, chunkSize)
        local key = GridMath.chunkKey(cx, cy, cz)
        
        if not seen[key] then
            seen[key] = true
            table.insert(chunks, {x = cx, y = cy, z = cz, key = key})
        end
    end
    
    return chunks
end

-- Calculate distance between two cells (Manhattan distance)
function GridMath.cellDistance(x1: number, y1: number, z1: number, x2: number, y2: number, z2: number): number
    return math.abs(x2 - x1) + math.abs(y2 - y1) + math.abs(z2 - z1)
end

-- Calculate distance between two cells (Euclidean distance)
function GridMath.cellDistanceEuclidean(x1: number, y1: number, z1: number, x2: number, y2: number, z2: number): number
    local dx = x2 - x1
    local dy = y2 - y1
    local dz = z2 - z1
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

return GridMath