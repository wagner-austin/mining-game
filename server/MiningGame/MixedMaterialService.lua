--!strict
-- MixedMaterialService.lua
-- Generates mixed-material terrain cubes with deterministic noise patterns
-- Used by CompositionService to apply material compositions to cubes

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Terrain = workspace.Terrain

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(MiningGame:WaitForChild("Logger"))
local log = Logger.new("MixedMaterialService")
local GameConfig = require(MiningGame:WaitForChild("GameConfig"))
local VOX = GameConfig.Terrain.VOXEL_RESOLUTION
local MaterialDefinitions = require(MiningGame:WaitForChild("MaterialDefinitions"))
local ServiceValidator = require(MiningGame:WaitForChild("ServiceValidator"))

-- Services (injected via Init)
local GridService

local MixedMaterialService = {}

-- Initialize with DI container
function MixedMaterialService:Init(container)
	-- GridService is a soft dependency here; GridService depends on this service
	-- during its own Init/Start, so we must not require it strictly in Init.
	GridService = ServiceValidator.tryGet(container, "GridService")
	log:info("Initialized (GridService available=%s)", tostring(GridService ~= nil))
end

export type MaterialSwathe = {
	material: Enum.Material,
	weight: number,
	scale: number,
}

export type MixedMaterialConfig = {
	swathes: { MaterialSwathe },
	blendMode: "hard" | "soft",
	seed: number,
	mode: ("noise" | "threshold")?, -- Optional mode for material selection
	patchSize: number?, -- For threshold mode
}

-- Simple hash function for threshold mode
local function hash01_cell(pos: Vector3, cell: number, seed: number): number
	local qx = math.floor(pos.X / cell)
	local qy = math.floor(pos.Y / cell)
	local qz = math.floor(pos.Z / cell)
	local n = bit32.bxor(qx * 73856093, bit32.bxor(qy * 19349663, qz * 83492791))
	n = bit32.bxor(n, seed or 0)
	n = bit32.band(n, 0x7fffffff)
	return (n % 1000003) / 1000003 -- 0..1
end

-- Deterministic 3D noise using seed
local function noise3D(x: number, y: number, z: number, scale: number, seed: number): number
	local noiseScale = 1 / scale
	-- Use seed to offset the noise sampling position deterministically
	local sx = x * noiseScale + seed * 0.123
	local sy = y * noiseScale + seed * 0.456
	local sz = z * noiseScale + seed * 0.789
	return math.noise(sx, sy, sz)
end

-- Select material based on weighted noise values (deterministic)
local function selectMaterial(pos: Vector3, config: MixedMaterialConfig): Enum.Material
	-- Use simple threshold mode if requested
	if config.mode == "threshold" then
		local cell = config.patchSize or 12 -- studs; controls patch size
		local u = hash01_cell(pos, cell, math.floor(config.seed or 1))
		local acc = 0
		for i, s in ipairs(config.swathes) do
			acc = acc + s.weight -- weights are already normalized
			if u <= acc or i == #config.swathes then
				return s.material
			end
		end
	end

	-- Default noise-based selection
	local seed = config.seed
	local bestMaterial = config.swathes[1].material
	local bestValue = -math.huge

	for i, swathe in ipairs(config.swathes) do
		-- Use index as additional seed offset for variety
		local noiseValue = noise3D(pos.X, pos.Y, pos.Z, swathe.scale, seed + i * 1000)

		-- Weight the noise value
		local weightedValue = noiseValue * swathe.weight

		-- For hard boundaries, add deterministic variation based on position
		if config.blendMode == "hard" then
			-- Use a second noise octave as tiebreaker (not random)
			local tiebreaker = noise3D(pos.X, pos.Y, pos.Z, 5, seed + 9999) * 0.1
			weightedValue = weightedValue + tiebreaker
		end

		if weightedValue > bestValue then
			bestValue = weightedValue
			bestMaterial = swathe.material
		end
	end

	return bestMaterial
end

-- Apply mixed materials to an existing cube region
function MixedMaterialService:ApplyMixedMaterials(
	cubeOrigin: CFrame,
	size: number,
	config: MixedMaterialConfig,
	preserveAir: boolean?
)
	log:info(
		"Applying mixed materials with %d swathes, seed: %d, preserveAir: %s",
		#config.swathes,
		config.seed,
		tostring(preserveAir)
	)

	local halfSize = Vector3.new(size / 2, size / 2, size / 2)
	local regionMin = cubeOrigin.Position - halfSize
	local regionMax = cubeOrigin.Position + halfSize
	log:info("Original region: Min=%s, Max=%s", tostring(regionMin), tostring(regionMax))

	local region = Region3.new(regionMin, regionMax):ExpandToGrid(VOX)
	log:info("Expanded region: CFrame=%s, Size=%s", tostring(region.CFrame), tostring(region.Size))

	-- Read existing voxels
	local materials, occupancy = Terrain:ReadVoxels(region, VOX)
	local voxelSize = materials.Size

	-- Calculate region bounds for world position calculation
	local regionMin2 = region.CFrame.Position - region.Size / 2

	-- Track what we're replacing for logging
	local replacedCount = 0
	local materialCounts = {} -- Track how many voxels of each material

	-- Modify voxels based on composition
	for x = 1, voxelSize.X do
		for y = 1, voxelSize.Y do
			for z = 1, voxelSize.Z do
				-- Only modify non-air voxels if preserveAir is true
				if not preserveAir or (occupancy[x][y][z] > 0 and materials[x][y][z] ~= Enum.Material.Air) then
					-- Calculate world position of this voxel
					local voxelPos = regionMin2 + Vector3.new((x - 0.5) * VOX, (y - 0.5) * VOX, (z - 0.5) * VOX)

					-- Select material for this position
					local newMaterial = selectMaterial(voxelPos, config)

					-- Track material counts
					local materialName = tostring(newMaterial)
					materialCounts[materialName] = (materialCounts[materialName] or 0) + 1

					-- Apply the material
					if not preserveAir then
						-- Creating new terrain
						materials[x][y][z] = newMaterial
						-- Keep water visible on thin surfaces
						occupancy[x][y][z] = (newMaterial == Enum.Material.Water)
								and math.max(occupancy[x][y][z] or 0, 0.3)
							or 1
						replacedCount = replacedCount + 1
					elseif materials[x][y][z] ~= Enum.Material.Air then
						-- Replacing existing terrain only
						materials[x][y][z] = newMaterial
						-- Ensure water remains visible
						if newMaterial == Enum.Material.Water then
							occupancy[x][y][z] = math.max(occupancy[x][y][z], 0.3)
						end
						replacedCount = replacedCount + 1
					end
				end
			end
		end
	end

	-- Write modified voxels back
	Terrain:WriteVoxels(region, VOX, materials, occupancy)

	-- Log material distribution
	local materialList = {}
	for mat, count in pairs(materialCounts) do
		table.insert(materialList, string.format("%s: %d", mat, count))
	end

	log:info("Applied mixed materials to %d voxels at %s", replacedCount, tostring(cubeOrigin.Position))
	log:info("Material distribution: %s", table.concat(materialList, ", "))
end

-- Create material config from a composition
function MixedMaterialService:ConfigFromComposition(composition: any, seed: number): MixedMaterialConfig
	local swathes = {}

	for _, component in ipairs(composition.components) do
		local material = MaterialDefinitions.GetEnum(component.materialKey)
		if material then
			table.insert(swathes, {
				material = material,
				weight = component.weight,
				scale = component.scale,
			})
		else
			log:warn("Unknown material key in composition: %s", component.materialKey)
		end
	end

	-- Normalize weights to sum to 1.0
	local totalWeight = 0
	for _, swathe in ipairs(swathes) do
		totalWeight = totalWeight + swathe.weight
	end

	if totalWeight > 0 then
		for _, swathe in ipairs(swathes) do
			swathe.weight = swathe.weight / totalWeight
		end
	end

	return {
		swathes = swathes,
		blendMode = "hard", -- Default to hard boundaries for better visual distinction
		seed = seed,
	}
end

log:info("Initialized")

return MixedMaterialService
