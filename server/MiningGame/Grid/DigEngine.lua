--!strict
-- Grid/DigEngine.lua
-- Terrain dig engine and voxel write routines extracted from GridService.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Terrain = Workspace.Terrain
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(Shared:WaitForChild("Logger"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Types = require(Shared:WaitForChild("Types"))
local Time = require(Shared:WaitForChild("Time"))
local GridMath = require(Shared:WaitForChild("Utils"):WaitForChild("GridMath"))
local ChunkCodec = require(Shared:WaitForChild("Utils"):WaitForChild("ChunkCodec"))
local MaterialKeys = require(Shared:WaitForChild("MaterialKeys"))
-- Use server ErrorService directly to avoid infinite WaitForChild on shared
local ErrorService = require(script.Parent.Parent.ErrorService)
local DigPerformance = require(script.Parent.Parent.DigPerformance)

local log = Logger.new("GridDigEngine")

type Cell = { x: number, y: number, z: number }
type SoundHint = { materialKey: string?, worldPos: Vector3? }

local CELL_SIZE = GameConfig.Grid.CELL_SIZE_STUDS
local VOX = GameConfig.Terrain.VOXEL_RESOLUTION
local CHUNK_SIZE = GameConfig.Grid.CHUNK_CELLS
local CELLS_PER_CHUNK = CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE

-- Chunk helpers (local copy; acts directly on state)
local function getOrCreateChunk(state: Types.CubeState, chunkX: number, chunkY: number, chunkZ: number)
    local key = GridMath.chunkKey(chunkX, chunkY, chunkZ)
    local chunk = state.chunks[key]
    if not chunk then
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

local function markCellDug(state: Types.CubeState, cellX: number, cellY: number, cellZ: number): boolean
    local chunkX, chunkY, chunkZ = GridMath.cellToChunk(cellX, cellY, cellZ, CHUNK_SIZE)
    local chunk = getOrCreateChunk(state, chunkX, chunkY, chunkZ)
    local localX, localY, localZ = GridMath.cellToChunkLocal(cellX, cellY, cellZ, CHUNK_SIZE)
    local index = GridMath.chunkLocalToIndex(localX, localY, localZ, CHUNK_SIZE)
    if ChunkCodec.getBit(chunk.dugBits, index, CELLS_PER_CHUNK) then
        return false
    end
    chunk.dugBits = ChunkCodec.setBit(chunk.dugBits, index, true, CELLS_PER_CHUNK)
    chunk.dirty = true
    chunk.lastModified = Time.unix()
    state.totalDug = state.totalDug + 1
    return true
end

local DigEngine = {}

function DigEngine.ApplyDig(
    player: Player,
    cubeOrigin: CFrame,
    state: Types.CubeState,
    cellX: number,
    cellY: number,
    cellZ: number,
    size: number,
    options: {mode: string?, normal: Vector3?, surfacePos: Vector3?}?
): ({Cell}, SoundHint?)
    -- Guard input
    size = math.max(0, math.floor(tonumber(size) or 0))

    local fallbackHalf = (GameConfig.Grid.CUBE_SIZE_STUDS / CELL_SIZE) / 2
    local halfX, halfY, halfZ
    if state and state.extentsCells then
        halfX = math.floor(state.extentsCells.X)
        halfY = math.floor(state.extentsCells.Y)
        halfZ = math.floor(state.extentsCells.Z)
    else
        halfX, halfY, halfZ = fallbackHalf, fallbackHalf, fallbackHalf
    end

    local minX, maxX = -halfX, halfX - 1
    local minY, maxY = -halfY, halfY - 1
    local minZ, maxZ = -halfZ, halfZ - 1

    local xMin = math.max(cellX - size, minX)
    local xMax = math.min(cellX + size, maxX)
    local yMin = math.max(cellY - size, minY)
    local yMax = math.min(cellY + size, maxY)
    local zMin = math.max(cellZ - size, minZ)
    local zMax = math.min(cellZ + size, maxZ)
    if xMin > xMax or yMin > yMax or zMin > zMax then
        return {}
    end

    local isSurface = false
    local width = xMax - xMin + 1
    local height = yMax - yMin + 1
    local length = zMax - zMin + 1
    local expected = width * height * length

    local dugCells = table.create(math.min(expected, 10000))
    local cellsToWrite = table.create(math.min(expected, 10000))
    local dugCount, writeCount = 0, 0

    -- Batch per-chunk bit updates to avoid O(cells * chunkSize) cost.
    local touchedChunks: {[string]: {chunk: any, bits: {boolean}}} = {}

    DigPerformance.measureSection("CellIteration", function()
        for y = yMax, yMin, -1 do
            for x = xMin, xMax do
                for z = zMin, zMax do
                    local chunkX, chunkY, chunkZ = GridMath.cellToChunk(x, y, z, CHUNK_SIZE)
                    local chunk = getOrCreateChunk(state, chunkX, chunkY, chunkZ)
                    local key = GridMath.chunkKey(chunkX, chunkY, chunkZ)
                    local entry = touchedChunks[key]
                    if not entry then
                        entry = { chunk = chunk, bits = ChunkCodec.unpack(chunk.dugBits, CELLS_PER_CHUNK) }
                        touchedChunks[key] = entry
                    end
                    local localX, localY, localZ = GridMath.cellToChunkLocal(x, y, z, CHUNK_SIZE)
                    local index = GridMath.chunkLocalToIndex(localX, localY, localZ, CHUNK_SIZE)
                    if not entry.bits[index] then
                        entry.bits[index] = true
                        chunk.dirty = true
                        chunk.lastModified = Time.unix()
                        state.totalDug = state.totalDug + 1
                        dugCount += 1; writeCount += 1
                        local cell = {x=x,y=y,z=z}
                        dugCells[dugCount] = cell
                        cellsToWrite[writeCount] = cell
                    end
                end
            end
        end
        -- Pack updated chunks once per chunk
        for _, e in pairs(touchedChunks) do
            e.chunk.dugBits = ChunkCodec.pack(e.bits, CELLS_PER_CHUNK)
        end
    end)

    if writeCount == 0 then return {} end
    for i = dugCount + 1, #dugCells do dugCells[i] = nil end
    for i = writeCount + 1, #cellsToWrite do cellsToWrite[i] = nil end

    local soundHint
    DigPerformance.measureSection("TerrainWrite", function()
        soundHint = DigEngine.WriteCellsToTerrain(cubeOrigin, cellsToWrite, state.materialId)
    end)
    if GameConfig.Digging.DEBUG_ISLAND_DIAG then
        log:debug("[IslandDiag] wrote cells=%d centerCell=%d,%d,%d", writeCount, cellX, cellY, cellZ)
    end
    return dugCells, soundHint
end

function DigEngine.WriteCellsToTerrain(
    cubeOrigin: CFrame,
    cells: {Cell},
    materialId: string
): SoundHint
    if not cells or #cells == 0 then return end

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
    local function worldCornerForCellMinCorner(cx, cy, cz)
        local center = GridMath.cellToWorld(cx, cy, cz, cubeOrigin, CELL_SIZE)
        return center - Vector3.new(CELL_SIZE/2, CELL_SIZE/2, CELL_SIZE/2)
    end
    local ex, ey, ez = {minX, maxX+1}, {minY, maxY+1}, {minZ, maxZ+1}
    local wmin = Vector3.new(math.huge, math.huge, math.huge)
    local wmax = Vector3.new(-math.huge, -math.huge, -math.huge)
    for _, cx in ipairs(ex) do for _, cy in ipairs(ey) do for _, cz in ipairs(ez) do
        local p = worldCornerForCellMinCorner(cx, cy, cz)
        if p.X < wmin.X then wmin = Vector3.new(p.X, wmin.Y, wmin.Z) end
        if p.Y < wmin.Y then wmin = Vector3.new(wmin.X, p.Y, wmin.Z) end
        if p.Z < wmin.Z then wmin = Vector3.new(wmin.X, wmin.Y, p.Z) end
        if p.X > wmax.X then wmax = Vector3.new(p.X, wmax.Y, wmax.Z) end
        if p.Y > wmax.Y then wmax = Vector3.new(wmax.X, p.Y, wmax.Z) end
        if p.Z > wmax.Z then wmax = Vector3.new(wmax.X, wmax.Y, p.Z) end
    end end end
    local function snapDown(v, s) return Vector3.new(math.floor(v.X/s)*s, math.floor(v.Y/s)*s, math.floor(v.Z/s)*s) end
    local function snapUp(v, s) return Vector3.new(math.ceil(v.X/s)*s, math.ceil(v.Y/s)*s, math.ceil(v.Z/s)*s) end
    local s = VOX
    local rmin = snapDown(wmin, s)
    local rmax = snapUp(wmax, s)
    local delta = rmax - rmin
    if delta.X <= 0 or delta.Y <= 0 or delta.Z <= 0 then return end

    local yLayers = maxY - minY + 1
    local SLICE_THRESHOLD_CELLS = 64
    local doSlice = (yLayers > 1 and #cells >= SLICE_THRESHOLD_CELLS)

    local materialCounts = {}
    local firstWorldPosForSound = nil
    local beforeOcc

    local function writeSlice(yMinCell: number, yMaxCell: number, cellsInSlice: {Cell})
        local sMinX, sMaxX = math.huge, -math.huge
        local sMinZ, sMaxZ = math.huge, -math.huge
        for _, c in ipairs(cellsInSlice) do
            if c.x < sMinX then sMinX = c.x end
            if c.z < sMinZ then sMinZ = c.z end
            if c.x > sMaxX then sMaxX = c.x end
            if c.z > sMaxZ then sMaxZ = c.z end
        end
        local exS, eyS, ezS = {sMinX, sMaxX+1}, {yMinCell, yMaxCell+1}, {sMinZ, sMaxZ+1}
        local wminS = Vector3.new(math.huge, math.huge, math.huge)
        local wmaxS = Vector3.new(-math.huge, -math.huge, -math.huge)
        for _, cx in ipairs(exS) do for _, cy in ipairs(eyS) do for _, cz in ipairs(ezS) do
            local p = worldCornerForCellMinCorner(cx, cy, cz)
            if p.X < wminS.X then wminS = Vector3.new(p.X, wminS.Y, wminS.Z) end
            if p.Y < wminS.Y then wminS = Vector3.new(wminS.X, p.Y, wminS.Z) end
            if p.Z < wminS.Z then wminS = Vector3.new(wminS.X, wminS.Y, p.Z) end
            if p.X > wmaxS.X then wmaxS = Vector3.new(p.X, wmaxS.Y, wmaxS.Z) end
            if p.Y > wmaxS.Y then wmaxS = Vector3.new(wmaxS.X, p.Y, wmaxS.Z) end
            if p.Z > wmaxS.Z then wmaxS = Vector3.new(wmaxS.X, wmaxS.Y, p.Z) end
        end end end
        local rminS = snapDown(wminS, s)
        local rmaxS = snapUp(wmaxS, s)
        local regionS = Region3.new(rminS, rmaxS):ExpandToGrid(s)

        local okS, voxS = ErrorService.safecall("Terrain:ReadVoxels", function()
            local mats, occ = DigPerformance.measureSection("ReadVoxels", function()
                return Terrain:ReadVoxels(regionS, VOX)
            end)
            return { materials = mats, occupancy = occ }
        end, { region = tostring(regionS) })
        if not okS then
            log:warn("WriteCellsToTerrain(slice): ReadVoxels failed (min=%s, max=%s): %s", tostring(rminS), tostring(rmaxS), tostring(voxS))
            return
        end
        local materialsS, occupancyS = voxS.materials, voxS.occupancy
        local sizeS = materialsS.Size
        local regionMinS = regionS.CFrame.Position - regionS.Size/2
        local maxVXS, maxVYS, maxVZS = sizeS.X, sizeS.Y, sizeS.Z
        local invVoxel = 1 / VOX

        for i = 1, #cellsInSlice do
            local c = cellsInSlice[i]
            local localPos = Vector3.new((c.x + 0.5) * CELL_SIZE, (c.y + 0.5) * CELL_SIZE, (c.z + 0.5) * CELL_SIZE)
            local world = cubeOrigin.Position + localPos
            local vx = math.clamp(math.floor((world.X - regionMinS.X) * invVoxel) + 1, 1, maxVXS)
            local vy = math.clamp(math.floor((world.Y - regionMinS.Y) * invVoxel) + 1, 1, maxVYS)
            local vz = math.clamp(math.floor((world.Z - regionMinS.Z) * invVoxel) + 1, 1, maxVZS)

            local mat = materialsS[vx][vy][vz]
            local key = MaterialKeys.KeyFromEnum[mat] or "rock"
            materialCounts[key] = (materialCounts[key] or 0) + 1
            if not firstWorldPosForSound then firstWorldPosForSound = world end

            materialsS[vx][vy][vz] = Enum.Material.Air
            occupancyS[vx][vy][vz] = 0
        end

        ErrorService.safecall("Terrain:WriteVoxels", function()
            DigPerformance.measureSection("WriteVoxels", function()
                Terrain:WriteVoxels(regionS, VOX, materialsS, occupancyS)
            end)
        end)
    end

    if doSlice then
        local byY: {[number]: {Cell}} = {}
        for _, c in ipairs(cells) do
            local group = byY[c.y]
            if not group then group = {}; byY[c.y] = group end
            table.insert(group, c)
        end
        for y = maxY, minY, -1 do
            local g = byY[y]
            if g and #g > 0 then writeSlice(y, y, g) end
        end
    else
        local region = Region3.new(rmin, rmax):ExpandToGrid(s)

        local ok, vox = ErrorService.safecall("Terrain:ReadVoxels", function()
            local mats, occ = DigPerformance.measureSection("ReadVoxels", function()
                return Terrain:ReadVoxels(region, VOX)
            end)
            return { materials = mats, occupancy = occ }
        end, { region = tostring(region) })
        if not ok then
            log:warn("WriteCellsToTerrain: ReadVoxels failed (min=%s, max=%s): %s", tostring(rmin), tostring(rmax), tostring(vox))
            return
        end
        local materials, occupancy = vox.materials, vox.occupancy
        local size = materials.Size
        local regionMin = region.CFrame.Position - region.Size/2
        local maxVX, maxVY, maxVZ = size.X, size.Y, size.Z
        local invVoxel = 1 / VOX

        for i = 1, #cells do
            local c = cells[i]
            local localPos = Vector3.new((c.x + 0.5) * CELL_SIZE, (c.y + 0.5) * CELL_SIZE, (c.z + 0.5) * CELL_SIZE)
            local world = cubeOrigin.Position + localPos
            local vx = math.clamp(math.floor((world.X - regionMin.X) * invVoxel) + 1, 1, maxVX)
            local vy = math.clamp(math.floor((world.Y - regionMin.Y) * invVoxel) + 1, 1, maxVY)
            local vz = math.clamp(math.floor((world.Z - regionMin.Z) * invVoxel) + 1, 1, maxVZ)

            local mat = materials[vx][vy][vz]
            local key = MaterialKeys.KeyFromEnum[mat] or "rock"
            materialCounts[key] = (materialCounts[key] or 0) + 1
            if not firstWorldPosForSound then firstWorldPosForSound = world end

            if i == 1 and GameConfig.Digging.DEBUG_ISLAND_DIAG then
                beforeOcc = occupancy[vx][vy][vz]
                log:debug("[IslandDiag] region=(%s -> %s) firstCellWorld=%s voxelIndex=%d,%d,%d occBefore=%.2f",
                    tostring(rmin), tostring(rmax), tostring(world), vx, vy, vz, beforeOcc)
            end
            materials[vx][vy][vz] = Enum.Material.Air
            occupancy[vx][vy][vz] = 0
        end

        ErrorService.safecall("Terrain:WriteVoxels", function()
            DigPerformance.measureSection("WriteVoxels", function()
                Terrain:WriteVoxels(region, VOX, materials, occupancy)
            end)
        end)
    end

    local bestKey, bestCount = "rock", -1
    for k, v in pairs(materialCounts) do
        if v > bestCount then bestKey, bestCount = k, v end
    end
    if GameConfig.Digging.DEBUG_ISLAND_DIAG and firstWorldPosForSound and beforeOcc ~= nil then
        log:debug("[IslandDiag] wrote region=(%s -> %s) soundAt=%s mat=%s", tostring(rmin), tostring(rmax), tostring(firstWorldPosForSound), bestKey)
    end
    return { materialKey = bestKey, worldPos = firstWorldPosForSound }
end

return DigEngine
