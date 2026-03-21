--!strict
-- SimAgents.lua
-- Spawns N dummy "players" and N cube origins for testing multi-player scenarios
-- Studio-only by default, controllable via Debug UI

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local GameConfig = require(MiningGame:WaitForChild("GameConfig"))
local Logger = require(MiningGame:WaitForChild("Logger"))
local log = Logger.new("SimAgents")
local ErrorService = require(script.Parent:WaitForChild("ErrorService"))
local MathUtils = require(MiningGame:WaitForChild("MathUtils"))
-- local Remotes = require(MiningGame:WaitForChild("Remotes"))

local SpawnService = require(script.Parent:WaitForChild("SpawnService"))
local GridService = require(script.Parent:WaitForChild("GridService"))
local CubePositionService = require(script.Parent:WaitForChild("CubePositionService"))
local MixedMaterialService = require(script.Parent:WaitForChild("MixedMaterialService"))
local Types = require(MiningGame:WaitForChild("Types"))
type MaterialSwathe = { material: Enum.Material, weight: number, scale: number }
type MixedMaterialConfig = {
	swathes: { MaterialSwathe },
	blendMode: "hard" | "soft",
	seed: number,
	mode: ("noise" | "threshold")?,
	patchSize: number?,
}

local SpawnStrategies = require(script.Parent:WaitForChild("SpawnStrategies"))
local PCGConfig = require(MiningGame:WaitForChild("PCGConfig"))
local CubeThemes = require(MiningGame:WaitForChild("CubeThemes"))
local MaterialDefinitions = require(MiningGame:WaitForChild("MaterialDefinitions"))

local SimAgents = {}

-- Pick from real IDs in CubeThemes.Themes
local THEME_IDS = { "classic_mine", "volcanic_rift", "icy_cavern", "desert_oasis", "swamp_bog" }

local function themeConfigFor(ord: number, seed: number)
	local themeId = THEME_IDS[(ord % #THEME_IDS) + 1]
	local theme = CubeThemes.GetTheme(themeId) or CubeThemes.GetTheme("classic_mine")
	if not theme then
		return {
			seed = seed,
			blendMode = "hard" :: "hard",
			mode = "noise" :: "noise",
			patchSize = 12,
			swathes = {},
		}
	end

	-- convert theme.{materials, scales} -> swathes[]
	local swathes = {}
	for materialKey, weight in pairs(theme.materials) do
		local matEnum = MaterialDefinitions.GetEnum(materialKey)
		if matEnum then
			table.insert(swathes, {
				material = matEnum,
				weight = weight,
				scale = theme.scales[materialKey] or 25,
			})
		end
	end

	return {
		seed = seed,
		blendMode = "hard" :: "hard",
		mode = "noise" :: "noise",
		patchSize = 12,
		swathes = swathes,
	}
end

-- Future-proof respawn adapter (works even if SpawnService changes during refactor)
local function safeRespawn(character: Model, originCFrame: CFrame)
	-- Prefer the helper if it exists
	if SpawnService and SpawnService.RespawnCharacterAtOrigin then
		return SpawnService:RespawnCharacterAtOrigin(character, originCFrame, true) -- true = skip stream
	end
	-- Fallback if API changes: place the HRP directly (still testable)
	local hrpInst = character:FindFirstChild("HumanoidRootPart")
	if hrpInst and hrpInst:IsA("BasePart") then
		local hrp: BasePart = hrpInst
		hrp.CFrame = originCFrame
		log:warn("Using fallback spawn - SpawnService helper not available")
	end
end

-- Configuration
local CONFIG = {
	ENABLED = RunService:IsStudio(),
	CREATE_TERRAIN_CUBES = true, -- Default to terrain cubes for better testing
	CUBE_SIZE = GameConfig.Grid.CUBE_SIZE_STUDS,
	MAX_AGENTS = 25,
}

-- State
local agents: {
	[number]: {
		char: Model,
		cubeCFrame: CFrame,
		cubeModel: Model?,
		userId: number,
		ordinal: number?,
	},
} =
	{}
local nextId = 0
local agentFolder: Folder?

-- Ensure folder for organization
local function ensureFolder(): Folder
	if not agentFolder then
		local existing = Workspace:FindFirstChild("SimAgents")
		if existing and existing:IsA("Folder") then
			agentFolder = existing
		else
			local f = Instance.new("Folder")
			f.Name = "SimAgents"
			f.Parent = Workspace
			agentFolder = f
		end
	end
	return agentFolder :: Folder
end

-- Create a simple dummy character
local function createDummyChar(name: string, color: Color3): Model
	local model = Instance.new("Model")
	model.Name = name

	-- Create HumanoidRootPart
	local hrp = Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Size = Vector3.new(2, 2, 1)
	hrp.Anchored = false
	hrp.CanCollide = true
	hrp.Position = Vector3.new(0, 5, 0)
	hrp.Transparency = 1
	hrp.Parent = model

	-- Create Humanoid
	local humanoid = Instance.new("Humanoid")
	humanoid.Name = "Humanoid"
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.Parent = model

	-- Create visible torso
	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(2, 2, 1)
	torso.Color = color
	torso.Material = Enum.Material.Neon
	torso.Parent = model

	-- Create head
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(2, 1, 1)
	head.Color = color:Lerp(Color3.new(1, 1, 1), 0.3)
	head.Material = Enum.Material.Neon
	head.Parent = model

	-- Weld parts together
	local w1 = Instance.new("WeldConstraint")
	w1.Part0 = hrp
	w1.Part1 = torso
	w1.Parent = hrp

	local w2 = Instance.new("WeldConstraint")
	w2.Part0 = torso
	w2.Part1 = head
	w2.Parent = torso

	-- Add name display
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(4, 0, 1, 0)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = head

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = name
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Font = Enum.Font.SourceSansBold
	label.Parent = billboard

	-- Tag for identification
	CollectionService:AddTag(model, "SimAgent")

	model.PrimaryPart = hrp
	return model
end

-- Create visual cube bounds
local function createCubeGhost(cf: CFrame, size: number): BasePart
	local part = Instance.new("Part")
	part.Name = "CubeGhost"
	part.Size = Vector3.new(size, size, size)
	part.CFrame = cf
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false -- Prevent raycasts from hitting this
	part.CanTouch = false -- Prevent touch detection
	part.Transparency = 0.85
	part.Color = Color3.fromRGB(180, 220, 255)
	part.Material = Enum.Material.ForceField

	-- Add wireframe
	local selection = Instance.new("SelectionBox")
	selection.Adornee = part
	selection.Color3 = Color3.fromRGB(100, 200, 255)
	selection.LineThickness = 0.05
	selection.Transparency = 0.5
	selection.Parent = part

	return part
end

-- Spawn a single agent
local function spawnOne(index: number)
	nextId = nextId + 1
	local id = nextId
	local userId = 1000000 + id -- Fake userId

	-- Place SimAgents AFTER real players to avoid overlap
	local playerCount = #Players:GetPlayers()
	local ord = playerCount + index -- always after real players

	-- ALWAYS recalculate position with current strategy
	local cf = CubePositionService:ComputeDefaultOriginForOrdinal(ord)
	CubePositionService:RegisterSimulatedPosition(userId, cf)

	log:info(
		"Spawning SimAgent %d at ordinal %d with strategy '%s', pos %s",
		id,
		ord,
		SpawnStrategies.GetCurrentStrategyName(),
		tostring(cf.Position)
	)

	-- Create cube (terrain or ghost)
	local cubeModel
	if CONFIG.CREATE_TERRAIN_CUBES then
		-- Create real terrain cube with mixed materials (like real players)
		local cubeState: Types.CubeState = GridService:CreateCubeState(userId, "tier1")

		cubeModel = GridService:RestoreCube(cf, cubeState, Enum.Material.Grass)
		if cubeModel then
			cubeModel.Name = "SimCube_" .. id
			cubeModel.Parent = Workspace
		end

		-- Apply mixed materials with deterministic seed
		local seed = PCGConfig.Seeds.SIM_AGENTS + ord * 947 + 17
		log:debug("Applying mixed materials for agent %d with seed %d", id, seed)

		local cfg: MixedMaterialConfig = themeConfigFor(ord, seed)
		MixedMaterialService:ApplyMixedMaterials(cf, CONFIG.CUBE_SIZE, cfg)
	else
		-- Create ghost visualization
		local ghost = createCubeGhost(cf, CONFIG.CUBE_SIZE)
		cubeModel = Instance.new("Model")
		cubeModel.Name = "SimCube_" .. id
		cubeModel.PrimaryPart = ghost
		ghost.Parent = cubeModel -- Parent only once
		cubeModel.Parent = ensureFolder()
	end

	-- Create character with unique color
	local hue = ((id * 37) % 360) / 360
	local color = Color3.fromHSV(hue, 0.6, 0.9)
	local char = createDummyChar("SimPlayer_" .. id, color)
	char.Parent = ensureFolder()

	-- Spawn character at cube (using safe adapter)
	log:debug("Spawning character for agent %d...", id)
	safeRespawn(char, cf)

	-- Store agent data
	agents[id] = {
		char = char,
		cubeCFrame = cf,
		cubeModel = cubeModel,
		userId = userId,
		ordinal = ord, -- Store ordinal for consistent respawning
	}

	log:info("✓ Spawned SimAgent %d - position: %s", id, tostring(cf.Position))
end

-- Helper to erase terrain volume
local function eraseCubeVolume(cf: CFrame, size: number)
	local terrain = Workspace.Terrain
	-- Fill with air using FillBlock
	terrain:FillBlock(cf, Vector3.new(size, size, size), Enum.Material.Air)
	log:debug("Erased terrain volume at %s", tostring(cf.Position))
end

-- Clear all agents
local function clearAll()
	local currentCount = 0
	for _ in pairs(agents) do
		currentCount = currentCount + 1
	end
	log:debug("Clearing %d existing agents...", currentCount)

	for _, agent in pairs(agents) do
		if agent.char and agent.char.Parent then
			agent.char:Destroy()
		end
		if agent.cubeModel and agent.cubeModel.Parent then
			agent.cubeModel:Destroy()
		end
		-- Erase terrain if it was created
		if CONFIG.CREATE_TERRAIN_CUBES and agent.cubeCFrame then
			ErrorService.safecall("SimAgents.EraseCubeVolume", function()
				eraseCubeVolume(agent.cubeCFrame, CONFIG.CUBE_SIZE)
				return true
			end)
		end
		-- Unregister from CubePositionService
		CubePositionService:UnregisterSimulatedPosition(agent.userId)
	end

	agents = {}
	nextId = 0

	-- Clear folder
	if agentFolder then
		agentFolder:ClearAllChildren()
	end

	log:info("Cleared all SimAgents")
end

-- Repopulate with N agents
local function repopulate(count: number)
	log:info("Repopulate start: target=%d", count)
	clearAll()

	count = math.min(count, CONFIG.MAX_AGENTS)
	local placed = 0

	for i = 1, count do
		spawnOne(i)
		placed = placed + 1
	end

	log:info("Repopulate done: placed=%d agents", placed)
end

-- Public API
function SimAgents:SetCount(n: number)
	log:info("SimAgents:SetCount called with n=%d", n)

	if not CONFIG.ENABLED then
		log:warn("SimAgents is disabled outside Studio")
		return
	end

	local targetCount = MathUtils.nonNegative(math.floor(n))
	log:info("Repopulating with %d agents...", targetCount)
	repopulate(targetCount)
end

function SimAgents:GetCount(): number
	local count = 0
	for _ in pairs(agents) do
		count = count + 1
	end
	return count
end

function SimAgents:RespawnAll()
	if not CONFIG.ENABLED then
		return
	end

	log:info("RespawnAll: Recalculating positions with strategy '%s'", SpawnStrategies.GetCurrentStrategyName())

	local agentCount = 0

	for id, agent in pairs(agents) do
		agentCount = agentCount + 1

		-- Use stored ordinal for consistent positioning
		local ord = assert(agent.ordinal, "SimAgent missing ordinal")
		local newCf = CubePositionService:ComputeDefaultOriginForOrdinal(ord)

		-- Keep old position for terrain erase
		local oldCf = agent.cubeCFrame
		agent.cubeCFrame = newCf

		-- Update registration
		CubePositionService:RegisterSimulatedPosition(agent.userId, newCf)

		-- Recreate cube at new position (terrain doesn't move)
		if agent.cubeModel then
			agent.cubeModel:Destroy()
		end

		if CONFIG.CREATE_TERRAIN_CUBES then
			-- Erase old terrain
			if oldCf then
				ErrorService.safecall("SimAgents.EraseCubeVolumeOld", function()
					eraseCubeVolume(oldCf, CONFIG.CUBE_SIZE)
					return true
				end)
			end

			-- Create new terrain cube with mixed materials
			local cubeState: Types.CubeState = GridService:CreateCubeState(agent.userId, "tier1")

			agent.cubeModel = GridService:RestoreCube(newCf, cubeState, Enum.Material.Grass)
			local m = agent.cubeModel
			if m then
				m.Name = "SimCube_" .. id
				m.Parent = Workspace
			end

			-- Apply mixed materials with deterministic seed
			local seed = PCGConfig.Seeds.SIM_AGENTS + ord * 947 + 17
			log:debug("Applying mixed materials for agent %d with seed %d", id, seed)

			local cfg: MixedMaterialConfig = themeConfigFor(ord, seed)
			MixedMaterialService:ApplyMixedMaterials(newCf, CONFIG.CUBE_SIZE, cfg)
		else
			-- Create ghost visualization
			local ghost = createCubeGhost(newCf, CONFIG.CUBE_SIZE)
			local model: Model = Instance.new("Model")
			model.Name = "SimCube_" .. id
			model.PrimaryPart = ghost
			ghost.Parent = model
			model.Parent = ensureFolder()
			agent.cubeModel = model
		end

		-- Respawn character at new position
		safeRespawn(agent.char, newCf)

		log:debug("Respawned agent %d at new position %s", id, tostring(newCf.Position))
	end

	log:info("Respawned all %d SimAgents with updated positions", agentCount)
end

function SimAgents:Clear()
	if not CONFIG.ENABLED then
		return
	end
	clearAll()
end

function SimAgents:SetTerrainCubes(enabled: boolean)
	CONFIG.CREATE_TERRAIN_CUBES = enabled
	-- Respawn with new setting
	local count = self:GetCount()
	if count > 0 then
		repopulate(count)
	end
end

function SimAgents:GetAgents()
	return agents
end

function SimAgents:GetStatus()
	-- Return current status of SimAgents system
	local agentList = {}
	for id, agent in pairs(agents) do
		table.insert(agentList, {
			id = id,
			userId = agent.userId,
			ordinal = agent.ordinal,
			position = agent.cubeModel and agent.cubeModel:GetPivot().Position or Vector3.new(),
			hasCube = agent.cubeModel ~= nil,
		})
	end

	return {
		enabled = CONFIG.ENABLED,
		count = self:GetCount(),
		maxAgents = CONFIG.MAX_AGENTS,
		terrainCubes = CONFIG.CREATE_TERRAIN_CUBES,
		currentStrategy = SpawnStrategies.GetCurrentStrategyName(),
		agents = agentList,
	}
end

-- [MIGRATED TO SimAgentsRemotes.lua]
-- All remote handlers now use centralized RemoteManager pattern
local function setupRemotes()
	log:info("Remote handlers have been migrated to SimAgentsRemotes.lua")
end

function SimAgents:Init(_container)
	log:info(
		"SimAgents initializing... Studio: %s, Enabled: %s",
		tostring(RunService:IsStudio()),
		tostring(CONFIG.ENABLED)
	)

	if CONFIG.ENABLED then
		setupRemotes()
		log:info("SimAgents initialized (Studio mode) - Max agents: %d", CONFIG.MAX_AGENTS)
	else
		setupRemotes() -- Still setup remotes to return disabled status
		log:info("SimAgents disabled (not in Studio) but remotes available")
	end
end

return SimAgents
