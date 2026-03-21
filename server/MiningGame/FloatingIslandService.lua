--!strict
-- FloatingIslandService.lua
-- Generates floating cube islands using mixed composition system
-- Integration with MixedMaterialService and CubeThemes

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Workspace = workspace
local Terrain = Workspace.Terrain

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Time = require(MiningGame:WaitForChild("Time"))
local Logger = require(MiningGame:WaitForChild("Logger"))
local CubeThemes = require(MiningGame:WaitForChild("CubeThemes"))
local GameConfig = require(MiningGame:WaitForChild("GameConfig"))
local ServiceValidator = require(MiningGame:WaitForChild("ServiceValidator"))
local EventBus = require(MiningGame:WaitForChild("EventBus"))
local EventNames = require(MiningGame:WaitForChild("EventNames"))
local EventContracts = require(MiningGame:WaitForChild("EventContracts"))
local WorldGenUtils = require(MiningGame:WaitForChild("WorldGenUtils"))

local log = Logger.new("FloatingIslandService")
local CubeVolume = require(script.Parent:WaitForChild("CubeVolume"))
local ErrorService = require(script.Parent.ErrorService)
local Bus = EventBus.global()

-- Services (injected via Init)
local _MixedMaterialService
local _GridService
local _DigService -- optional (for registering volumes)
local _eventsRegistered = false

-- Get PCG seed for deterministic island generation
local BASE_ISLAND_SEED = 0
ErrorService.safecall("FloatingIsland:LoadPCGSeeds", function()
	local PCG = require(MiningGame:WaitForChild("PCGConfig"))
	BASE_ISLAND_SEED = (PCG.Seeds and PCG.Seeds.ISLAND_SPAWN) or 0
	return true
end)

-- Service configuration
local CUBE_SIZE = GameConfig.Grid.CUBE_SIZE_STUDS or 50 -- Use game's cube size
local PRESETS = {
	tiny = { size = 0.4 },
	small = { size = 0.7 },
	medium = { size = 1.0 },
	large = { size = 1.3 },
	massive = { size = 1.6 },
}

-- No mapping needed - we use CubeTheme IDs directly

-- Grid alignment helpers
local function q4(n: number): number
	return math.floor(n / 4 + 0.5) * 4
end

local function quantize(v: Vector3): Vector3
	return Vector3.new(q4(v.X), q4(v.Y), q4(v.Z))
end

-- Get or create floating islands folder
local function getIslandsFolder()
	return WorldGenUtils.getIslandsFolder()
end

-- Generate deterministic seed from position
local function generateSeed(position: Vector3): number
	-- Hash position components to create deterministic seed
	local x = math.floor(position.X / 100)
	local y = math.floor(position.Y / 100)
	local z = math.floor(position.Z / 100)

	-- Simple hash combining
	local hash = x * 73856093 + y * 19349663 + z * 83492791
	return math.abs(hash % 2147483647)
end

-- Helper: random point on top face with a small margin
local function randomTopPoint(primary: BasePart, rng: Random): Vector3
	local half = primary.Size.X * 0.5
	local margin = math.min(half * 0.25, 6)
	local ox = rng:NextNumber(-half + margin, half - margin)
	local oz = rng:NextNumber(-half + margin, half - margin)
	return primary.Position + Vector3.new(ox, half, oz)
end

-- Tree spawning utility (copied from WorldGenerationService to avoid dependency)
local TreeFactory = require(MiningGame:WaitForChild("TreeFactory"))

-- Service module
-- Time-based yielding helper to prevent frame spikes
local function budgetYield(lastTick: number, slice: number?): number
	return WorldGenUtils.budgetYield(lastTick, slice)
end

local FloatingIslandService = {}
FloatingIslandService._lastGeneratedCount = 0

-- Initialize with DI container
function FloatingIslandService:Init(container)
	self._container = container
	_GridService = ServiceValidator.get(container, "GridService") -- Required by ServiceManager
	_MixedMaterialService = ServiceValidator.get(container, "MixedMaterialService") -- Required by ServiceManager
	-- Optional: DigService for volume registration (guarded by feature flag)
	_DigService = ServiceValidator.tryGet(container, "DigService", { "RegisterVolume", "UnregisterVolume" })

	-- Register event listeners (only once)
	if not _eventsRegistered then
		Bus:on(EventNames.ISLAND_SPAWN_REQUEST, function(msg)
			local ok, _ = ErrorService.safecall("Contracts.ISLAND_SPAWN_REQUEST", function()
				EventContracts.ISLAND_SPAWN_REQUEST(msg.payload)
				return true
			end)
			if not ok then
				log:warn("Invalid ISLAND_SPAWN_REQUEST payload")
				return
			end
			local payload = EventContracts.ISLAND_SPAWN_REQUEST(msg.payload)
			ErrorService.safecall("Island:SpawnRequest", function()
				self:GenerateIsland(
					payload.position,
					payload.preset,
					payload.theme,
					payload.customSize,
					payload.elevation,
					payload.treeCount,
					payload.treeScale
				)
				return true
			end)
		end)

		Bus:on(EventNames.ISLAND_REMOVE_REQUEST, function(msg)
			local ok, _ = ErrorService.safecall("Contracts.ISLAND_REMOVE_REQUEST", function()
				EventContracts.ISLAND_REMOVE_REQUEST(msg.payload)
				return true
			end)
			if not ok then
				log:warn("Invalid ISLAND_REMOVE_REQUEST payload")
				return
			end
			local payload = EventContracts.ISLAND_REMOVE_REQUEST(msg.payload)
			ErrorService.safecall("Island:RemoveRequest", function()
				if payload.all then
					self:ClearAllIslands()
				elseif payload.position then
					-- Find and remove island at position (implement if needed)
					log:warn("Remove island at position not yet implemented")
				end
				return true
			end)
		end)

		_eventsRegistered = true
	end

	log:info("Initialized with dependencies and event listeners")
end

-- Generate single floating cube island
function FloatingIslandService:GenerateIsland(
	position: Vector3,
	preset: string?,
	theme: string?,
	customSize: Vector3?, -- Optional custom dimensions (x, y, z)
	elevation: number?, -- Optional height above position
	treeCount: number?, -- Optional number of trees (0 = none, nil = 1)
	treeScale: number? -- Optional tree size multiplier
): boolean
	preset = preset or "medium"
	theme = theme or "earth"

	local presetData = PRESETS[preset]
	if not presetData then
		log:warn("Unknown preset: " .. tostring(preset))
		return false
	end

	-- Validate theme ID directly from CubeThemes
	local cubeThemeId = theme or "underwater_cave"
	if not CubeThemes.GetTheme(cubeThemeId) then
		log:warn(("Theme '%s' not found, falling back to underwater_cave"):format(tostring(cubeThemeId)))
		cubeThemeId = "underwater_cave"
	end

	-- Islands folder ensured by WorldGenUtils when needed

	log:info(("Generating %s %s island at %s"):format(tostring(preset), tostring(theme), tostring(position)))

	-- Generate seed from position and base seed for consistency
	local seed = bit32.bxor(generateSeed(position), BASE_ISLAND_SEED)
	local rng = Random.new(seed)

	-- Handle custom dimensions or use preset
	local cubeSize: Vector3
	if customSize then
		-- Use custom dimensions, grid-aligned
		cubeSize = Vector3.new(q4(customSize.X), q4(customSize.Y), q4(customSize.Z))
		log:info("Custom size: %s", tostring(cubeSize))
	else
		-- Use preset uniform size
		local uniformSize = q4(CUBE_SIZE * presetData.size)
		cubeSize = Vector3.new(uniformSize, uniformSize, uniformSize)
		log:info("Preset size multiplier: %.2f, Size: %d", presetData.size, uniformSize)
	end

	-- Apply elevation if specified
	local cubePos = position
	if elevation then
		cubePos = cubePos + Vector3.new(0, elevation, 0)
	end
	cubePos = quantize(cubePos) -- Grid-aligned

	log:info("Creating island: Pos=%s, Size=%s", tostring(cubePos), tostring(cubeSize))

	-- Create and register via CubeVolume
	local volId = string.format(
		"island:%d:%d:%d:%d",
		generateSeed(cubePos),
		math.floor(cubePos.X),
		math.floor(cubePos.Y),
		math.floor(cubePos.Z)
	)
	local volData = CubeVolume.create(self._container, {
		id = volId,
		kind = "island",
		origin = CFrame.new(cubePos),
		sizeStuds = cubeSize,
		public = true,
		themeId = cubeThemeId,
		preset = preset,
	})
	local cubeModel = volData and volData.model

	ErrorService.safecall("AddTag.FloatingIsland", function()
		if cubeModel then
			CollectionService:AddTag(cubeModel, "FloatingIsland")
		end
		return true
	end)

	-- Set atomic streaming for the island model
	ErrorService.safecall("Model:SetStreamingMode(island)", function()
		if cubeModel then
			cubeModel.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		end
		return true
	end)

	-- Add trees based on treeCount parameter
	local actualTreeCount: number = treeCount or 1

	if actualTreeCount > 0 then
		local anchor = cubeModel and (cubeModel.PrimaryPart or cubeModel:FindFirstChild("Anchor"))
		if not anchor or (not anchor:IsA("BasePart")) then
			log:warn("Island anchor not found; skipping tree placement")
		else
			local anchorPart: BasePart = anchor
			for _ = 1, actualTreeCount do
				local topPos = randomTopPoint(anchorPart, rng)
				-- Spawn procedural blocky trees on islands for consistency
				local rng2 = Random.new(rng:NextInteger(1, 2 ^ 30))
				local tree = TreeFactory.SpawnBlocky(topPos, rng2, { scale = treeScale or 1 })
				-- Parent to BlockDecorations so TreeClimbing can detect them consistently
				local decoFolder = WorldGenUtils.getDecorationFolder()
				if tree and decoFolder then
					tree.Parent = decoFolder
				end
				-- Tag it as island tree for tracking
				if tree then
					CollectionService:AddTag(tree, "IslandTree")
				end
			end
			log:info("Added %d tree(s) with scale %.2f", actualTreeCount, treeScale or 1.0)
		end
	end

	log:info("Generated island successfully")
	return true
end

-- Generate archipelago of cube islands
function FloatingIslandService:GenerateArchipelago(
	center: Vector3,
	count: number,
	spread: number,
	preset: string?,
	theme: string?
): {}
	local islands = {}
	local seed = generateSeed(center)
	local rng = Random.new(seed)
	local lastTick = Time.mono()

	-- Use smaller presets for archipelago
	preset = preset or "small"

	for i = 1, count do
		-- Smooth server frame time
		lastTick = budgetYield(lastTick)
		local angle = (i / count) * math.pi * 2 + rng:NextNumber(-0.5, 0.5)
		local distance = rng:NextNumber(spread * 0.3, spread)
		local height = rng:NextNumber(0, spread / 2) -- Current height and higher

		local offset = Vector3.new(math.cos(angle) * distance, height, math.sin(angle) * distance)

		local islandPos = center + offset

		-- Vary the preset for visual interest
		local presets = { "tiny", "small", "medium" }
		local islandPreset = presets[rng:NextInteger(1, #presets)]

		local success = self:GenerateIsland(islandPos, islandPreset, theme)

		if success then
			table.insert(islands, islandPos)
		end
	end

	return islands
end

-- Generate random cube islands in area using current player height
function FloatingIslandService:GenerateRandomIslands(
	center: Vector3,
	radius: number,
	count: number,
	minHeight: number?,
	maxHeight: number?
): {}
	-- Use center.Y as base height (player's current height)
	local baseHeight = center.Y
	local minH: number = minHeight or 0 -- Relative to player
	local maxH: number = maxHeight or 100 -- Up to 100 studs above player

	local islands = {}
	local themes = self:GetThemes()
	local presets = self:GetPresets()

	local seed = generateSeed(center)
	local rng = Random.new(seed)
	local lastTick = Time.mono()

	for _ = 1, count do
		-- Smooth server frame time
		lastTick = budgetYield(lastTick)
		local angle = rng:NextNumber() * math.pi * 2
		local distance = rng:NextNumber(radius * 0.2, radius)
		local height = baseHeight + rng:NextNumber(minH, maxH)

		local position =
			Vector3.new(center.X + math.cos(angle) * distance, height, center.Z + math.sin(angle) * distance)

		local theme = themes[rng:NextInteger(1, #themes)]
		local preset = presets[rng:NextInteger(1, #presets)]

		local success = self:GenerateIsland(position, preset, theme)

		if success then
			table.insert(islands, position)
		end
	end

	return islands
end

-- Get available themes directly from CubeThemes
function FloatingIslandService:GetThemes(): { string }
	local themes = {}
	for themeId in pairs(CubeThemes.Themes) do
		table.insert(themes, themeId)
	end
	table.sort(themes)
	return themes
end

-- Get available presets
function FloatingIslandService:GetPresets(): { string }
	local presets = {}
	for name in pairs(PRESETS) do
		table.insert(presets, name)
	end
	-- Sort by size
	local order = { tiny = 1, small = 2, medium = 3, large = 4, massive = 5 }
	table.sort(presets, function(a, b)
		return (order[a] or 99) < (order[b] or 99)
	end)
	return presets
end

-- Expose defaults (for admin/debug tooling)
function FloatingIslandService:GetDefaults()
	local cfg = GameConfig.FloatingIslands
	return {
		islandsPer100x100 = (cfg and cfg.ISLANDS_PER_100x100) or 0.015,
		minIslands = (cfg and cfg.MIN_ISLANDS) or 3,
		maxIslands = (cfg and cfg.MAX_ISLANDS) or 12,
		heightMin = (cfg and cfg.HEIGHT_MIN) or 150,
		heightMax = (cfg and cfg.HEIGHT_MAX) or 400,
		liquidWeightCap = (cfg and cfg.LIQUID_WEIGHT_CAP) or 0.35,
	}
end

function FloatingIslandService:GetStats()
	return { lastGeneratedCount = self._lastGeneratedCount or 0 }
end

-- Clear all floating cube islands (including terrain)
function FloatingIslandService:ClearAllIslands()
	local folder = getIslandsFolder()

	-- Clear terrain for each island before destroying models
	for _, model in ipairs(folder:GetChildren()) do
		if model:IsA("Model") then
			local pp = model.PrimaryPart
			if pp then
				-- Clear the terrain where the cube was
				Terrain:FillBlock(pp.CFrame, pp.Size, Enum.Material.Air)
			end
			-- Unregister associated volume if present
			local vid = model:GetAttribute("VolumeId")
			if _DigService and type(vid) == "string" then
				ErrorService.safecall("FloatingIsland.UnregisterVolume", function()
					_DigService:UnregisterVolume(vid)
					return true
				end)
			end
			model:Destroy()
			RunService.Heartbeat:Wait() -- Prevent lag when clearing many islands
		end
	end

	-- Clear surface detection cache if it exists
	ErrorService.safecall("TerrainSurfaceDetector.ClearCache", function()
		local TerrainSurfaceDetector = require(MiningGame:WaitForChild("TerrainSurfaceDetector"))
		TerrainSurfaceDetector.ClearCache()
		return true
	end)

	log:info("Cleared all floating islands and terrain")
end

-- Start method for procedural island spawning
function FloatingIslandService:Start()
	local config = GameConfig.FloatingIslands
	if not config or not config.PROCEDURAL_ENABLED then
		log:info("Procedural floating islands disabled")
		return
	end

	-- Check if we should spawn in this environment
	if config.STUDIO_ONLY and not RunService:IsStudio() then
		log:info("Floating islands disabled outside Studio")
		return
	end

	-- Optional phase gating removed from strict typing path

	log:info("Starting procedural floating island generation...")

	-- Register any pre-existing islands in the folder (e.g., from previous runs)
	local folder = getIslandsFolder()
	for _, model in ipairs(folder:GetChildren()) do
		if model:IsA("Model") and model.Name == "FloatingCube" then
			local ppInst = model.PrimaryPart or model:FindFirstChild("Anchor")
			if ppInst and ppInst:IsA("BasePart") and _DigService then
				local volId = model:GetAttribute("VolumeId")
				if not volId then
					local size = ppInst.Size
					local pos = ppInst.Position
					local id = string.format(
						"island:%d:%d:%d:%d",
						generateSeed(pos),
						math.floor(pos.X),
						math.floor(pos.Y),
						math.floor(pos.Z)
					)
					local vol = _DigService:RegisterVolume({
						id = id,
						kind = "island",
						origin = CFrame.new(pos),
						sizeStuds = size,
						permissions = { public = true },
						meta = { themeId = "unknown", preset = "unknown" },
					})
					model:SetAttribute("VolumeId", vol and vol.id or id)
					log:info(
						"Registered existing island volume id=%s at %s size=%s",
						tostring(id),
						tostring(pos),
						tostring(size)
					)
				end
			end
		end
	end

	-- Calculate spawn area and count
	local mapBounds = Workspace:FindFirstChild("SpawnBounds") or Workspace:FindFirstChild("Baseplate")
	local mapSizeX = 2000
	local mapSizeZ = 2000

	if mapBounds and mapBounds:IsA("BasePart") then
		mapSizeX = mapBounds.Size.X
		mapSizeZ = mapBounds.Size.Z
	end

	local area = mapSizeX * mapSizeZ
	local tiles = area / 10000

	local islandsPerTile = config.ISLANDS_PER_100x100 or 0.015
	local targetCount = math.floor(tiles * islandsPerTile)
	targetCount = math.clamp(targetCount, config.MIN_ISLANDS or 3, config.MAX_ISLANDS or 12)

	log:info("Target island count: %d (area=%.0f, tiles=%.1f)", targetCount, area, tiles)

	-- Use the existing batch spawning method
	local centerX = 0
	local centerZ = 0
	local heightMin = config.HEIGHT_MIN or 150
	local heightMax = config.HEIGHT_MAX or 400

	-- Use GenerateRandomIslands which already handles themes, presets, and budget yielding
	local islands = self:GenerateRandomIslands(
		Vector3.new(centerX, (heightMin + heightMax) / 2, centerZ), -- Center at mid-height
		math.min(mapSizeX, mapSizeZ) * 0.4, -- Radius (40% of smallest map dimension)
		targetCount,
		heightMin - (heightMin + heightMax) / 2, -- Min relative height
		heightMax - (heightMin + heightMax) / 2 -- Max relative height
	)

	self._lastGeneratedCount = #islands
	log:info("Floating islands complete: %d spawned", #islands)
end

log:info("Initialized")

return FloatingIslandService
