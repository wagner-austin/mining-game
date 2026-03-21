--!strict
-- CubeVolume.lua
-- Unified creation/registration of mineable volumes (player cubes and islands)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Terrain = Workspace.Terrain

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Time = require(Shared:WaitForChild("Time"))
local Logger = require(Shared:WaitForChild("Logger"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local ServiceValidator = require(Shared:WaitForChild("ServiceValidator"))
local CubeThemes = require(Shared:WaitForChild("CubeThemes"))
local MaterialDefinitions = require(Shared:WaitForChild("MaterialDefinitions"))
local WorldGenUtils = require(Shared:WaitForChild("WorldGenUtils"))

local log = Logger.new("CubeVolume")

local CELL = GameConfig.Grid.CELL_SIZE_STUDS

local function qCell(n: number): number
	return math.floor(n / CELL + 0.5) * CELL
end

local function quantize(v: Vector3): Vector3
	return Vector3.new(qCell(v.X), qCell(v.Y), qCell(v.Z))
end

local function halfExtentsCells(sizeStuds: Vector3): Vector3
	return Vector3.new(
		math.floor((sizeStuds.X / CELL) / 2),
		math.floor((sizeStuds.Y / CELL) / 2),
		math.floor((sizeStuds.Z / CELL) / 2)
	)
end

local CubeVolume = {}

export type CreateSpec = {
	id: string?,
	kind: string, -- "cube" | "island"
	origin: CFrame, -- Center (axis-aligned for now)
	sizeStuds: Vector3, -- Full extents
	ownerUserId: number?,
	public: boolean?,
	themeId: string?,
	preset: string?,
	state: any?, -- Types.CubeState
	floorMaterial: Enum.Material?,
}

-- Builds mixed-material components from a theme with optional water cap for islands
local function buildComponentsForTheme(
	themeId: string,
	waterCap: number?
): { { materialKey: string, weight: number, scale: number } }
	local comps = CubeThemes.GetThemeComponents(themeId)
	local out = {}
	if not comps then
		return out
	end
	local cap = waterCap or 1.0
	for _, c in ipairs(comps) do
		local weight = c.weight
		local props = MaterialDefinitions.GetProperties(c.materialKey)
		if props and props.isLiquid then
			weight = math.min(weight, cap)
		end
		table.insert(out, { materialKey = c.materialKey, weight = weight, scale = c.scale })
	end
	return out
end

-- Create a mineable volume. Uses container to resolve services (DI-friendly).
function CubeVolume.create(container, spec: CreateSpec)
	assert(container ~= nil, "CubeVolume.create requires DI container")
	assert(type(spec) == "table", "spec must be a table")
	assert(type(spec.kind) == "string", "spec.kind required")
	assert(typeof(spec.origin) == "CFrame", "spec.origin required")
	assert(typeof(spec.sizeStuds) == "Vector3", "spec.sizeStuds required")

	local GridService = ServiceValidator.get(container, "GridService")
	local MixedMaterialService = ServiceValidator.get(container, "MixedMaterialService")
	local DigService = ServiceValidator.get(container, "DigService")

	local kind = spec.kind
	local src = spec.origin
	local qpos = quantize(src.Position)
	-- IMPORTANT: Dig/grid math assumes axis-aligned volumes. Do NOT preserve rotation.
	local origin = CFrame.new(qpos)
	local sizeStuds = Vector3.new(qCell(spec.sizeStuds.X), qCell(spec.sizeStuds.Y), qCell(spec.sizeStuds.Z))

	local volId = spec.id
		or (kind .. ":" .. tostring(Time.mono()):gsub("%.", "") .. ":" .. tostring(math.random(1, 1e9)))
	local perms = { public = (spec.public == true), ownerUserId = spec.ownerUserId }

	-- Prepare state with per-axis half-extents in cells
	local state = spec.state or GridService:CreateCubeState(spec.ownerUserId or 0, "tier1")
	-- Note: For islands, extentsCells will be updated after terrain snapping
	local initialExtents = halfExtentsCells(sizeStuds)
	state.extentsCells = initialExtents

	local model: Model? = nil

	if kind == "cube" then
		-- Player cube: restore from state and saved prefs handled by GridService:RestoreCube
		local floorMaterial: Enum.Material? = spec.floorMaterial
		model = GridService:RestoreCube(origin, state, floorMaterial)
		if model then
			model.Parent = workspace
		end
		-- Streaming attributes for owner
		if spec.ownerUserId and model then
			model:SetAttribute("OwnerId", spec.ownerUserId)
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					d:SetAttribute("StreamingMode", "PersistentPerPlayer")
					d:SetAttribute("StreamingPlayerId", spec.ownerUserId)
				end
			end
		end
	else
		-- Island: Align to Terrain voxel grid exactly so dig AABB matches written terrain
		local VOX = GameConfig.Terrain.VOXEL_RESOLUTION
		local function snapDown(v: Vector3)
			return Vector3.new(math.floor(v.X / VOX) * VOX, math.floor(v.Y / VOX) * VOX, math.floor(v.Z / VOX) * VOX)
		end
		local function snapUp(v: Vector3)
			return Vector3.new(math.ceil(v.X / VOX) * VOX, math.ceil(v.Y / VOX) * VOX, math.ceil(v.Z / VOX) * VOX)
		end

		local half = sizeStuds * 0.5
		local wmin = origin.Position - half
		local wmax = origin.Position + half
		local rmin = snapDown(wmin)
		local rmax = snapUp(wmax)
		local regSize = rmax - rmin
		local regCenter = (rmin + rmax) * 0.5
		local regOrigin = CFrame.new(regCenter)

		-- Write terrain strictly to this snapped Region3 so extents and dig volume match
		Terrain:FillBlock(regOrigin, regSize, Enum.Material.Rock)

		local themeId = spec.themeId or "mixed_geology"
		local components = buildComponentsForTheme(
			themeId,
			(GameConfig.FloatingIslands and GameConfig.FloatingIslands.LIQUID_WEIGHT_CAP) or 0.45
		)
		local seed = math.abs(bit32.bxor(math.floor(regCenter.X), math.floor(regCenter.Y), math.floor(regCenter.Z)))
		local cfg = MixedMaterialService:ConfigFromComposition({ components = components }, seed)
		cfg.mode = "threshold"
		local maxDim = math.max(regSize.X, regSize.Y, regSize.Z)
		cfg.patchSize = math.clamp(maxDim / 10, 6, 24)
		MixedMaterialService:ApplyMixedMaterials(regOrigin, maxDim, cfg, true)

		-- Create invisible anchor model to tag island and allow cleanup/streaming
		local m = Instance.new("Model")
		m.Name = "FloatingCube"
		local anchor = Instance.new("Part")
		anchor.Name = "Anchor"
		anchor.Size = regSize
		anchor.CFrame = regOrigin
		anchor.Anchored = true
		anchor.CastShadow = false
		anchor.Transparency = 1
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Parent = m
		m.PrimaryPart = anchor

		-- Add visual indicators for islands (similar to player cubes)
		local CubeVisuals = require(script.Parent:WaitForChild("CubeVisuals"))
		-- Add cube light for visibility
		CubeVisuals.AddCubeLight(anchor, math.max(regSize.X, regSize.Y, regSize.Z))
		-- Add cube glow effect for islands
		CubeVisuals.CreateCubeGlow(m, regOrigin, math.max(regSize.X, regSize.Y, regSize.Z), true)

		m.Parent = WorldGenUtils.getIslandsFolder()
		model = m

		-- Override origin/sizeStuds to the exact terrain-written region
		origin = regOrigin
		sizeStuds = regSize
		-- Update state.extentsCells to match the actual terrain region
		state.extentsCells = halfExtentsCells(regSize)
	end

	-- Register volume in DigService (records state.extentsCells for GridService clamp)
	local vol = DigService:RegisterVolume({
		id = volId,
		kind = kind,
		origin = origin,
		sizeStuds = sizeStuds,
		permissions = perms,
		meta = { themeId = spec.themeId, preset = spec.preset },
		state = state,
	})

	if model then
		model:SetAttribute("VolumeId", vol and vol.id or volId)
	end

	log:info(
		"CubeVolume created kind=%s id=%s origin=%s size=%s",
		kind,
		tostring(volId),
		tostring(origin.Position),
		tostring(sizeStuds)
	)

	return { id = volId, model = model, state = state, origin = origin }
end

function CubeVolume.destroy(container, id: string)
	assert(container ~= nil, "CubeVolume.destroy requires DI container")
	assert(type(id) == "string", "id must be string")
	local DigService = ServiceValidator.get(container, "DigService")
	local ok = DigService:UnregisterVolume(id)
	if ok then
		log:info("CubeVolume destroyed id=%s", id)
	end
	return ok
end

return CubeVolume
