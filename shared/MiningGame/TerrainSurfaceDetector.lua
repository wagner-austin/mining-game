--!strict
--[[
    TerrainSurfaceDetector.lua
    High-performance terrain surface detection for identifying only exposed, diggable terrain.
    
    Features:
    - Front/behind occupancy testing with sample distance optimization
    - Grid-aware caching with LRU eviction
    - Occupancy thresholds for partial voxel handling  
    - Optimized radius filtering with dot products
    - Proper world position calculation from voxel indices
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(MiningGame:WaitForChild("Logger"))
local MaterialDefinitions = require(MiningGame:WaitForChild("MaterialDefinitions"))
local GameConfig = require(MiningGame:WaitForChild("GameConfig"))
local Time = require(MiningGame:WaitForChild("Time"))
local log = Logger.new("TerrainSurfaceDetector")

local TerrainSurfaceDetector = {}

local Terrain = workspace.Terrain

-- Load tuning parameters from config (with fallbacks)
local cfg: any = GameConfig.SurfaceDetect or {}
local ENABLED = cfg.ENABLED ~= false -- Default true if not specified
local AIR_THRESHOLD = cfg.AIR_THRESHOLD or 0.05 -- Below this = effectively air
local SOLID_THRESHOLD = cfg.SOLID_THRESHOLD or 0.30 -- Above this = solid terrain
local SAMPLE_BIAS = cfg.SAMPLE_BIAS or 0.55 -- Front/back sample multiplier
local CACHE_LIFETIME = cfg.CACHE_LIFETIME or 0.10 -- Cache TTL
local MAX_CACHE_SIZE = cfg.CACHE_MAX or 256 -- Max cache entries

--[[
    Check if a material is diggable.
    Materials with zero or undefined dig difficulty are not diggable.
    
    @param mat - Material enum
    @return boolean - True if diggable
]]
local function isDiggable(mat: Enum.Material): boolean
	local key = MaterialDefinitions.KeyFromEnum[mat]
	if not key then
		return false
	end
	local difficulty = MaterialDefinitions.GetProperty(key, "digDifficulty")
	-- Water and other materials with 0 or nil difficulty aren't diggable
	return (difficulty or 0) > 0
end

-- Direction vectors for neighbor checking (6 faces of a voxel)
local NEIGHBOR_DIRECTIONS = {
	Vector3.new(1, 0, 0), -- Right
	Vector3.new(-1, 0, 0), -- Left
	Vector3.new(0, 1, 0), -- Up
	Vector3.new(0, -1, 0), -- Down
	Vector3.new(0, 0, 1), -- Forward
	Vector3.new(0, 0, -1), -- Back
}

-- Cache for repeated exposure checks with LRU eviction
local exposureCache = {} :: { [string]: { exposed: boolean, timestamp: number, lastAccess: number } }
local cacheOrder = {} :: { string } -- Track insertion order for LRU eviction

--[[
    Get grid-aligned cache key for a position.
    Quantizes to voxel coordinates for stable caching.
    
    @param pos - World position
    @param cellSize - Cell size
    @return string - Cache key
]]
local function getCellKey(pos: Vector3, cellSize: number): string
	return string.format(
		"%d,%d,%d",
		math.floor(pos.X / cellSize),
		math.floor(pos.Y / cellSize),
		math.floor(pos.Z / cellSize)
	)
end

--[[
    Get major axis and sign from a normal vector.
    Reduces normal to one of 6 cardinal directions.
    
    @param normal - Normal vector
    @return string - Axis and sign (e.g., "X+", "Y-", "Z+")
]]
local function getMajorAxisSign(normal: Vector3): string
	local absX, absY, absZ = math.abs(normal.X), math.abs(normal.Y), math.abs(normal.Z)

	if absX >= absY and absX >= absZ then
		return "X" .. (normal.X >= 0 and "+" or "-")
	elseif absY >= absZ then
		return "Y" .. (normal.Y >= 0 and "+" or "-")
	else
		return "Z" .. (normal.Z >= 0 and "+" or "-")
	end
end

--[[
    Evict oldest cache entries when at capacity.
]]
local function evictOldestCache()
	if #cacheOrder <= MAX_CACHE_SIZE then
		return
	end

	-- Remove oldest 10% by last access time (true LRU)
	local toRemove = math.max(1, math.floor(MAX_CACHE_SIZE * 0.1))
	log:debug("Evicting %d old cache entries (cache at capacity: %d)", toRemove, MAX_CACHE_SIZE)

	for _ = 1, toRemove do
		local oldestKey, oldestTime = nil, math.huge

		-- Find the least recently accessed entry
		for key, entry in pairs(exposureCache) do
			if entry.lastAccess < oldestTime then
				oldestTime = entry.lastAccess
				oldestKey = key
			end
		end

		if oldestKey then
			exposureCache[oldestKey] = nil
			-- Remove from cacheOrder array
			for i = #cacheOrder, 1, -1 do
				if cacheOrder[i] == oldestKey then
					table.remove(cacheOrder, i)
					break
				end
			end
		else
			break
		end
	end
end

--[[
    Get voxel data at a specific world position.
    Returns material and occupancy for a single voxel.
    
    @param pos - World position
    @param cellSize - Voxel cell size
    @return Enum.Material, number - Material and occupancy
]]
local function getVoxelAt(pos: Vector3, cellSize: number): (Enum.Material, number)
	-- Snap to voxel grid
	local min = Vector3.new(
		math.floor(pos.X / cellSize) * cellSize,
		math.floor(pos.Y / cellSize) * cellSize,
		math.floor(pos.Z / cellSize) * cellSize
	)

	local region = Region3.new(min, min + Vector3.new(cellSize, cellSize, cellSize))
	region = region:ExpandToGrid(cellSize)

	local materials, occupancies = Terrain:ReadVoxels(region, cellSize)

	-- Should always be 1x1x1 but check to be safe
	if materials.Size.X > 0 and materials.Size.Y > 0 and materials.Size.Z > 0 then
		return materials[1][1][1], occupancies[1][1][1]
	end

	return Enum.Material.Air, 0
end

--[[
    Check if a position has exposed terrain using front/behind sampling.
    This is the PRIMARY method for checking if terrain is diggable.
    
    @param worldPos - The hit position from raycast
    @param normal - The surface normal from raycast
    @param cellSize - Voxel cell size
    @return boolean - True if this is exposed, diggable terrain
]]
function TerrainSurfaceDetector.IsExposedAt(worldPos: Vector3, normal: Vector3, cellSize: number): boolean
	-- Quick bypass if feature is disabled
	if not ENABLED then
		return true -- Allow all terrain when disabled
	end

	-- Sample positions slightly further to avoid edge cases
	local frontPos = worldPos + normal * (cellSize * SAMPLE_BIAS)
	local backPos = worldPos - normal * (cellSize * SAMPLE_BIAS)

	-- Debug logging for surface detection issues (only when result is false)
	local DEBUG_FAILURES = true

	-- Grid-aware cache key includes both sample positions and normal axis
	local cacheKey = getCellKey(frontPos, cellSize)
		.. "|"
		.. getCellKey(backPos, cellSize)
		.. "|"
		.. getMajorAxisSign(normal)

	local now = Time.mono()
	local cached = exposureCache[cacheKey]

	if cached and (now - cached.timestamp) < CACHE_LIFETIME then
		cached.lastAccess = now
		return cached.exposed
	end

	local frontMat, frontOcc = getVoxelAt(frontPos, cellSize)
	local backMat, backOcc = getVoxelAt(backPos, cellSize)

	-- For floating cubes with hollow/water interiors, only check if there's air in front
	-- The back can be air (hollow) or water (swimmable) - we don't need solid behind
	local airAhead = (frontMat == Enum.Material.Air) or (frontOcc <= AIR_THRESHOLD)

	-- We're on a surface if there's air ahead - don't require solid behind
	-- This handles floating cubes with hollow interiors or water-filled areas
	local isExposed = airAhead

	-- Only log failures to reduce noise
	if DEBUG_FAILURES and not isExposed then
		log:debug("IsExposedAt FAILED: pos=%s, normal=%s", tostring(worldPos), tostring(normal))
		log:debug("  Front sample: %s", tostring(frontPos))
		log:debug("  Back sample: %s", tostring(backPos))
		log:debug("  Front: mat=%s, occ=%.2f, airAhead=%s", tostring(frontMat), frontOcc, tostring(airAhead))
		log:debug("  Back: mat=%s, occ=%.2f", tostring(backMat), backOcc)
	end

	-- Cache result with LRU tracking
	if not cached then
		table.insert(cacheOrder, cacheKey)
		evictOldestCache()
	end

	exposureCache[cacheKey] = {
		exposed = isExposed,
		timestamp = now,
		lastAccess = now,
	}

	-- Occasionally clean up orphaned entries in cacheOrder
	if Random.new():NextNumber() < 0.01 then
		for i = #cacheOrder, 1, -1 do
			if not exposureCache[cacheOrder[i]] then
				table.remove(cacheOrder, i)
			end
		end
	end

	return isExposed
end

--[[
    Check if a voxel has solid terrain.
    
    @param materials - 3D array from ReadVoxels
    @param occupancies - 3D array from ReadVoxels
    @param x, y, z - Voxel indices
    @return boolean - True if solid terrain
]]
local function hasTerrainAt(materials: any, occupancies: any, x: number, y: number, z: number): boolean
	local sx, sy, sz = materials.Size.X, materials.Size.Y, materials.Size.Z

	-- Bounds check
	if x < 1 or x > sx or y < 1 or y > sy or z < 1 or z > sz then
		return false
	end

	local mat = materials[x][y][z]
	local occ = occupancies[x][y][z]

	-- Use lower threshold for liquids
	local key = MaterialDefinitions.KeyFromEnum[mat]
	local isLiquid = key and MaterialDefinitions.GetProperty(key, "isLiquid") == true
	local solidThreshold = isLiquid and math.min(0.15, SOLID_THRESHOLD) or SOLID_THRESHOLD

	-- Must be non-air, solid enough, and diggable
	return mat ~= Enum.Material.Air and occ >= solidThreshold and isDiggable(mat)
end

--[[
    Check if a voxel is air or air-like.
    
    @param materials - 3D array from ReadVoxels
    @param occupancies - 3D array from ReadVoxels
    @param x, y, z - Voxel indices
    @return boolean - True if air or nearly air
]]
local function isAirAt(materials: any, occupancies: any, x: number, y: number, z: number): boolean
	local sx, sy, sz = materials.Size.X, materials.Size.Y, materials.Size.Z

	-- Out of bounds = treat as air
	if x < 1 or x > sx or y < 1 or y > sy or z < 1 or z > sz then
		return true
	end

	local mat = materials[x][y][z]
	local occ = occupancies[x][y][z]

	-- Treat thin water as air-like for surface detection
	if mat == Enum.Material.Water then
		return occ <= 0.20
	end

	return mat == Enum.Material.Air or occ <= AIR_THRESHOLD
end

--[[
    Check if a voxel is a surface voxel using neighbor checking.
    
    @param materials - 3D array from ReadVoxels
    @param occupancies - 3D array from ReadVoxels
    @param x, y, z - Voxel indices
    @return boolean - True if surface voxel
]]
local function isSurfaceVoxel(materials: any, occupancies: any, x: number, y: number, z: number): boolean
	-- Must be solid
	if not hasTerrainAt(materials, occupancies, x, y, z) then
		return false
	end

	-- Check if any face neighbor is air
	for _, dir in ipairs(NEIGHBOR_DIRECTIONS) do
		local nx = x + dir.X
		local ny = y + dir.Y
		local nz = z + dir.Z

		if isAirAt(materials, occupancies, nx, ny, nz) then
			return true
		end
	end

	return false
end

--[[
    Get the surface normal for a surface voxel.
    
    @param materials - 3D array from ReadVoxels
    @param occupancies - 3D array from ReadVoxels
    @param x, y, z - Voxel indices
    @return Vector3 - Surface normal
]]
local function getSurfaceNormal(materials: any, occupancies: any, x: number, y: number, z: number): Vector3
	local normal = Vector3.new(0, 0, 0)
	local weight = 0

	-- Sum directions pointing toward air, weighted by how "air-like" they are
	for _, dir in ipairs(NEIGHBOR_DIRECTIONS) do
		local nx = x + dir.X
		local ny = y + dir.Y
		local nz = z + dir.Z

		if isAirAt(materials, occupancies, nx, ny, nz) then
			-- Weight by how much air (1.0 for pure air, less for partial)
			local airness = 1.0
			local sx, sy, sz = materials.Size.X, materials.Size.Y, materials.Size.Z

			if nx >= 1 and nx <= sx and ny >= 1 and ny <= sy and nz >= 1 and nz <= sz then
				local occ = occupancies[nx][ny][nz]
				airness = 1.0 - math.clamp(occ / SOLID_THRESHOLD, 0, 1)
			end

			normal = normal + dir * airness
			weight = weight + airness
		end
	end

	-- Normalize (guard against zero vector)
	if weight > 0 and normal.Magnitude > 0 then
		return normal.Unit
	else
		return Vector3.new(0, 1, 0) -- Default up
	end
end

--[[
    Get the minimum corner of a Region3.
    
    @param region - The Region3
    @return Vector3 - Minimum corner position
]]
local function getRegionMin(region: Region3): Vector3
	return region.CFrame.Position - (region.Size * 0.5)
end

--[[
    Detect all surface terrain voxels in a region.
    Used for area-of-effect previews.
    
    @param region - Region3 to scan (should be expanded to grid)
    @param resolution - Voxel resolution
    @return Array of surface data
]]
function TerrainSurfaceDetector.DetectSurfaces(
	region: Region3,
	resolution: number
): {
	{
		position: Vector3,
		normal: Vector3,
		material: Enum.Material,
		occupancy: number,
	}
}
	-- Return all voxels as surfaces if disabled
	if not ENABLED then
		return {} -- Or could return simplified results
	end

	local materials, occupancies = Terrain:ReadVoxels(region, resolution)
	local sx, sy, sz = materials.Size.X, materials.Size.Y, materials.Size.Z
	local minPos = getRegionMin(region)

	local surfaces = {}

	for x = 1, sx do
		for y = 1, sy do
			for z = 1, sz do
				if isSurfaceVoxel(materials, occupancies, x, y, z) then
					-- Convert voxel index to world position
					local worldPos = minPos
						+ Vector3.new((x - 0.5) * resolution, (y - 0.5) * resolution, (z - 0.5) * resolution)

					local normal = getSurfaceNormal(materials, occupancies, x, y, z)

					table.insert(surfaces, {
						position = worldPos,
						normal = normal,
						material = materials[x][y][z],
						occupancy = occupancies[x][y][z],
					})
				end
			end
		end
	end

	return surfaces
end

--[[
    Quick check if a cell likely has surface terrain.
    Optimized for single-cell cursor checks.
    
    @param worldPos - World position to check
    @param cellSize - Cell size in studs
    @return boolean, Vector3?, Vector3?, Enum.Material? - hasSurface, position, normal, material
]]
function TerrainSurfaceDetector.CheckCellSurface(
	worldPos: Vector3,
	cellSize: number
): (boolean, Vector3?, Vector3?, Enum.Material?)
	-- Quick bypass if feature is disabled
	if not ENABLED then
		return true, worldPos, Vector3.new(0, 1, 0), Enum.Material.Rock -- Allow all terrain when disabled
	end

	-- First do a simple check: is there ANY terrain at this position?
	-- This handles mixed composition surfaces better
	local simpleRegion = Region3.new(
		worldPos - Vector3.new(cellSize * 0.1, cellSize * 0.1, cellSize * 0.1),
		worldPos + Vector3.new(cellSize * 0.1, cellSize * 0.1, cellSize * 0.1)
	):ExpandToGrid(cellSize)

	local simpleMats, simpleOccs = Terrain:ReadVoxels(simpleRegion, cellSize)
	if simpleMats.Size.X > 0 and simpleMats.Size.Y > 0 and simpleMats.Size.Z > 0 then
		local mat = simpleMats[1][1][1]
		local occ = simpleOccs[1][1][1]
		-- If there's terrain here (even partial), consider it valid for surface mining
		if mat ~= Enum.Material.Air and occ > 0.1 then
			-- Estimate normal by doing a simple raycast downward
			local rayResult =
				workspace:Raycast(worldPos + Vector3.new(0, cellSize, 0), Vector3.new(0, -cellSize * 2, 0))
			local normal = rayResult and rayResult.Normal or Vector3.new(0, 1, 0)
			return true, worldPos, normal, mat
		end
	end

	-- Fall back to original detection for more complex cases
	-- Expand slightly to catch edges
	local half = cellSize * 0.75
	local region = Region3.new(worldPos - Vector3.new(half, half, half), worldPos + Vector3.new(half, half, half))
		:ExpandToGrid(cellSize)

	local materials, occupancies = Terrain:ReadVoxels(region, cellSize)
	local sx, sy, sz = materials.Size.X, materials.Size.Y, materials.Size.Z
	local minPos = getRegionMin(region)

	-- Helper to convert voxel index to world position
	local function indexToWorld(ix: number, iy: number, iz: number): Vector3
		return minPos + Vector3.new((ix - 0.5) * cellSize, (iy - 0.5) * cellSize, (iz - 0.5) * cellSize)
	end

	-- Check center voxel
	local cx = math.floor(sx / 2) + 1
	local cy = math.floor(sy / 2) + 1
	local cz = math.floor(sz / 2) + 1

	if isSurfaceVoxel(materials, occupancies, cx, cy, cz) then
		local normal = getSurfaceNormal(materials, occupancies, cx, cy, cz)
		local material = materials[cx][cy][cz]
		local surfacePos = indexToWorld(cx, cy, cz) + (normal * (cellSize * 0.25))

		return true, surfacePos, normal, material
	end

	-- Check immediate neighbors
	for _, dir in ipairs(NEIGHBOR_DIRECTIONS) do
		local nx = cx + dir.X
		local ny = cy + dir.Y
		local nz = cz + dir.Z

		if isSurfaceVoxel(materials, occupancies, nx, ny, nz) then
			local normal = getSurfaceNormal(materials, occupancies, nx, ny, nz)
			local material = materials[nx][ny][nz]
			local pos = indexToWorld(nx, ny, nz) + (normal * (cellSize * 0.25))

			return true, pos, normal, material
		end
	end

	return false, nil, nil, nil
end

--[[
    Get surface terrain in a radius around a point.
    
    @param center - Center position
    @param radius - Radius in cells
    @param cellSize - Cell size
    @param cubeOrigin - Optional cube origin for bounds
    @param cubeSize - Optional cube size for bounds
    @return Array of surface data
]]
function TerrainSurfaceDetector.GetSurfacesInRadius(
	center: Vector3,
	radius: number,
	cellSize: number,
	cubeOrigin: CFrame?,
	cubeSize: number?
)
	local worldRadius = radius * cellSize + cellSize
	local regionMin = center - Vector3.new(worldRadius, worldRadius, worldRadius)
	local regionMax = center + Vector3.new(worldRadius, worldRadius, worldRadius)

	-- Apply cube bounds
	if cubeOrigin and cubeSize then
		local half = cubeSize / 2
		local cubeMin = cubeOrigin.Position - Vector3.new(half, half, half)
		local cubeMax = cubeOrigin.Position + Vector3.new(half, half, half)

		regionMin = Vector3.new(
			math.max(regionMin.X, cubeMin.X),
			math.max(regionMin.Y, cubeMin.Y),
			math.max(regionMin.Z, cubeMin.Z)
		)
		regionMax = Vector3.new(
			math.min(regionMax.X, cubeMax.X),
			math.min(regionMax.Y, cubeMax.Y),
			math.min(regionMax.Z, cubeMax.Z)
		)
	end

	-- Guard against empty regions after clipping
	if regionMin.X > regionMax.X or regionMin.Y > regionMax.Y or regionMin.Z > regionMax.Z then
		return {}
	end

	local region = Region3.new(regionMin, regionMax):ExpandToGrid(cellSize)
	local allSurfaces = TerrainSurfaceDetector.DetectSurfaces(region, cellSize)

	-- Filter to radius using dot product (faster than Magnitude)
	local radiusSquared = (radius * cellSize) * (radius * cellSize)
	local filtered = {}

	for _, surface in ipairs(allSurfaces) do
		local delta = surface.position - center
		if delta:Dot(delta) <= radiusSquared then
			table.insert(filtered, surface)
		end
	end

	return filtered
end

--[[
    Clear the exposure cache.
    Useful for testing or when terrain changes significantly.
]]
--[[
    Check if surface detection is currently enabled.
    @return boolean - True if enabled
]]
function TerrainSurfaceDetector.IsEnabled(): boolean
	return ENABLED
end

--[[
    Temporarily override the enabled state (useful for testing).
    @param enabled - New enabled state
]]
function TerrainSurfaceDetector.SetEnabled(enabled: boolean)
	local wasEnabled = ENABLED
	ENABLED = enabled

	if wasEnabled ~= enabled then
		log:info(
			"Surface detection %s (was %s)",
			enabled and "enabled" or "disabled",
			wasEnabled and "enabled" or "disabled"
		)
		-- Clear cache when toggling to avoid stale data
		TerrainSurfaceDetector.ClearCache()
	end
end

function TerrainSurfaceDetector.ClearCache()
	local cacheSize = 0
	for _ in pairs(exposureCache) do
		cacheSize = cacheSize + 1
	end

	if cacheSize > 0 then
		log:debug("Clearing surface detection cache (%d entries)", cacheSize)
	end

	exposureCache = {}
	cacheOrder = {}
end

return TerrainSurfaceDetector
