--!strict
--[[
    SpawnService.lua
    Manages player spawn positions relative to their mining cubes.
    
    Features:
    - Spawns players in front of their cube facing it
    - Ground detection with raycast
    - Streaming support for large worlds
    - Automatic respawn handling
    - PCG-aware spawn positioning
]]

local Players = game:GetService("Players")
-- local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame", 30)
local Logger = require(MiningGame:WaitForChild("Logger"))
local log = Logger.new("SpawnService")
local GameConfig = require(MiningGame:WaitForChild("GameConfig"))
local ServiceValidator = require(MiningGame:WaitForChild("ServiceValidator"))
local EventBus = require(MiningGame:WaitForChild("EventBus"))
local EventNames = require(MiningGame:WaitForChild("EventNames"))
local Time = require(MiningGame:WaitForChild("Time"))
local WorldGenUtils = require(MiningGame:WaitForChild("WorldGenUtils"))
local SpawnOrchestrator = require(script.Parent:WaitForChild("SpawnOrchestrator"))
-- local ErrorService = require(script.Parent:WaitForChild("ErrorService"))
local Bus = EventBus.global()

-- Services (injected via Init)
local CubePositionService
local _GridService
local DigService

-- Forward declare handler (defined after Start)
local onCharacterAdded: (Model) -> ()

local SpawnService = {}
SpawnService.__index = SpawnService

-- Respawn throttling to prevent spam
local lastRespawnAt: { [Player]: number } = {}
-- Forensics: last committed spawn time and origin to analyze duplicate spawns
local lastCommittedSpawnAt: { [Player]: number } = {}
local lastCommittedOrigin: { [Player]: CFrame } = {}
local DEBUG_SPAWN_LOGS = false

-- Orchestration handled by SpawnOrchestrator
local function canRespawn(player: Player): boolean
	local now = Time.mono()
	if lastRespawnAt[player] and now - lastRespawnAt[player] < 1.0 then
		return false
	end
	lastRespawnAt[player] = now
	return true
end

-- Initialize with DI container
function SpawnService:Init(container)
	_GridService = ServiceValidator.get(container, "GridService")
	CubePositionService = ServiceValidator.get(container, "CubePositionService", { "GetOrigin", "SetOrigin" })
	DigService = ServiceValidator.get(container, "DigService", { "SetPlayerOrigin" })
	log:info("Initialized with dependencies")
end

-- Start method to connect player events after all services are initialized
function SpawnService:Start(_container)
	-- Connect player events now that dependencies are ready
	Players.PlayerAdded:Connect(function(plr)
		plr.CharacterAdded:Connect(onCharacterAdded)
	end)

	-- Handle players already present (Studio)
	for _, plr in ipairs(Players:GetPlayers()) do
		plr.CharacterAdded:Connect(onCharacterAdded)
		-- Check if character already exists and handle it
		if plr.Character then
			log:debug("Player %s already has character on Start", plr.Name)
			onCharacterAdded(plr.Character)
		end
	end

	-- Clean up throttle table when player leaves
	Players.PlayerRemoving:Connect(function(player)
		lastRespawnAt[player] = nil
		lastCommittedSpawnAt[player] = nil
		lastCommittedOrigin[player] = nil
		SpawnOrchestrator.Cleanup(player)
	end)

	-- Reposition when DigService announces the origin
	Bus:on(EventNames.CUBE_ORIGIN_CHANGED, function(evt)
		local to = evt and evt.to
		local player = to and to.player
		if not player or not player.Parent or not player.Character then
			return
		end

		local payload = evt and evt.payload
		local origin = payload and payload.origin

		-- Skip if we're already at the right origin to prevent double-spawning
		local currentOrigin = CubePositionService:GetOrigin(player)
		if currentOrigin and origin and (currentOrigin.Position - origin.Position).Magnitude < 1 then
			log:debug("Already at correct origin, skipping respawn")
			SpawnOrchestrator.IncDuplicateSkipped()
			return
		end

		if not canRespawn(player) then
			log:debug("Spawn throttled for %s", player.Name)
			return
		end

		SpawnService:Respawn(player, "CUBE_ORIGIN_CHANGED")
	end)

	log:info("Started with player connections and event listeners")
end

-- tunables
local CELL = GameConfig.Grid.CELL_SIZE_STUDS or 4
local HALF = (GameConfig.Grid.CUBE_SIZE_STUDS / CELL) / 2 -- cells
local HALF_STUDS = HALF * CELL -- studs
local FRONT_PADDING = 20 -- extra studs in front of face

--[[
    Find the ground height at a given position using raycast.
    Excludes procedural content and special folders.
    
    @param pos: Vector3 - The position to check
    @return number - The Y coordinate of the ground
]]
local function groundAtOrDefault(pos: Vector3): number
	-- Prefer shared utility to stay DRY with other systems
	local groundPos = WorldGenUtils.findGroundPosition(pos.X, pos.Z, { allowWater = false })
	if groundPos then
		return groundPos.Y
	end
	local center, _, _ = WorldGenUtils.getSpawnBounds()
	if center then
		return center.Y
	end
	return 5
end

--[[
    Compute the spawn position and orientation for a player.
    Places them in front of their cube, on the ground, facing the cube.
    
    @param cubeOrigin: CFrame - The cube's origin CFrame
    @return CFrame - The spawn position and orientation
]]
local function computeSpawnCFrame(cubeOrigin: CFrame): CFrame
	-- "front" = opposite of cube's forward vector (so player looks toward cube)
	local frontDir = -cubeOrigin.LookVector.Unit
	local target = cubeOrigin.Position

	-- place player (half cube + padding) away from cube center, on ground
	local spawnFlat = target + frontDir * (HALF_STUDS + FRONT_PADDING)
	local y = groundAtOrDefault(spawnFlat)
	-- Add a small clearance above ground to avoid clipping
	y += 15
	local spawnPos = Vector3.new(spawnFlat.X, y, spawnFlat.Z)

	-- face the cube horizontally (keep player upright)
	local lookAt = Vector3.new(target.X, y, target.Z)
	local cf = CFrame.lookAt(spawnPos, lookAt)
	log:debug(
		"computeSpawnCFrame: spawnPos=(%.1f, %.1f, %.1f), lookAt=(%.1f, %.1f, %.1f)",
		spawnPos.X,
		spawnPos.Y,
		spawnPos.Z,
		lookAt.X,
		lookAt.Y,
		lookAt.Z
	)

	return cf
end

-- Internal: finalize spawn if all conditions are met (or by timeout)
-- Finalization handled by SpawnOrchestrator

-- Public: mark a player as client-ready (handshake from client)
function SpawnService:MarkClientReady(player: Player)
	SpawnOrchestrator.MarkClientReady(player)
end

--[[
    Respawn a player at their designated spawn point.
    Handles streaming and position settling.
    
    @param player: Player - The player to respawn
]]
function SpawnService:Respawn(player: Player, source: string?)
	if not player.Character then
		log:warn("No character for %s", player.Name)
		return
	end
	local hrpInst = player.Character:FindFirstChild("HumanoidRootPart")
	if not (hrpInst and hrpInst:IsA("BasePart")) then
		log:warn("No HRP for %s", player.Name)
		return
	end

	-- ensure we have an origin for this player
	local cubeOrigin = CubePositionService and CubePositionService:GetOrigin(player)
	if not cubeOrigin then
		log:warn("GetOrigin returned nil; skipping respawn for %s", player.Name)
		return
	end

	-- Set origin in both services (authoritative source)
	CubePositionService:SetOrigin(player, cubeOrigin) -- authoritative source of truth
	DigService:SetPlayerOrigin(player, cubeOrigin) -- keep DigService cache in sync

	-- SpawnService is the sole owner of cube creation timing
	DigService:InitializePlayerCube(player)

	-- Client handles streaming via SpawnGuard; server does not request streaming

	local cf = computeSpawnCFrame(cubeOrigin)

	if DEBUG_SPAWN_LOGS then
		local expected = HALF_STUDS + FRONT_PADDING
		local delta = cf.Position - cubeOrigin.Position
		local horiz = math.sqrt(delta.X * delta.X + delta.Z * delta.Z)
		local now = Time.mono()
		local dt = lastCommittedSpawnAt[player] and (now - lastCommittedSpawnAt[player]) or -1
		local prevOrigin = lastCommittedOrigin[player]
		local originChanged = false
		if prevOrigin then
			originChanged = (((prevOrigin :: CFrame).Position - cubeOrigin.Position).Magnitude > 0.1)
		end
		log:debug(
			"spawn_forensics | src=%s | origin=(%.1f,%.1f,%.1f) -> spawn=(%.1f,%.1f,%.1f) | delta=(%.1f,%.1f,%.1f) | horiz=%.1f | expected=%.1f | dtPrev=%.2f | originChanged=%s",
			tostring(source or "(unknown)"),
			cubeOrigin.Position.X,
			cubeOrigin.Position.Y,
			cubeOrigin.Position.Z,
			cf.Position.X,
			cf.Position.Y,
			cf.Position.Z,
			delta.X,
			delta.Y,
			delta.Z,
			horiz,
			expected,
			dt,
			tostring(originChanged)
		)
	end
	if SpawnOrchestrator.IsEnabled() and SpawnOrchestrator.IsActive(player) then
		-- Defer final placement until client signals ready (or timeout)
		SpawnOrchestrator.OnOriginReady(player, cf)
		return
	end

	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		hrp.CFrame = cf
	end

	-- small nudge to settle
	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:Move(Vector3.zero, true)
	end

	log:info("Spawned %s at (%.1f, %.1f, %.1f) facing cube", player.Name, cf.Position.X, cf.Position.Y, cf.Position.Z)

	-- Update forensics state after a successful spawn
	lastCommittedSpawnAt[player] = Time.mono()
	lastCommittedOrigin[player] = cubeOrigin
end

--[[
    Teleport the player to their base's SpawnAnchor (no respawn or cube init).
    Requires PlayerBaseService to have created PlayerBase_<userId>/SpawnAnchor_Anchor.
]]
function SpawnService:TeleportHome(player: Player): (boolean, string?, string?)
	if not player or not player.Parent then
		return false, "NO_PLAYER"
	end
	local char = player.Character
	if not char then
		return false, "NO_CHARACTER"
	end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return false, "NO_HRP"
	end

	local origin = CubePositionService and CubePositionService:GetOrigin(player)
	if not origin then
		log:warn("TeleportHome: cube origin missing for %s", player.Name)
		return false, "NO_ORIGIN"
	end

	-- Use the exact same placement logic as Respawn for parity
	local cf = computeSpawnCFrame(origin)

	hrp.CFrame = cf
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:Move(Vector3.zero, true)
	end
	log:info("TeleportHome: moved %s to base spawn", player.Name)
	return true
end

-- hook character spawns (called from Start method after dependencies are ready)
onCharacterAdded = function(char: Model)
	local plr = Players:GetPlayerFromCharacter(char)
	if not plr then
		return
	end

	-- wait for HRP
	local hrpInst = char:WaitForChild("HumanoidRootPart", 10)
	if not hrpInst or not hrpInst:IsA("BasePart") then
		log:error("No HumanoidRootPart found for %s", plr.Name)
		return
	end
	local hrp = hrpInst :: BasePart

	-- Initialize orchestration state and anchor
	if SpawnOrchestrator.IsEnabled() then
		SpawnOrchestrator.StartForCharacter(plr, hrp)
	end

	-- If we already know an origin (e.g., cube finished first), snap now.
	local origin = CubePositionService and CubePositionService:GetOrigin(plr)
	if origin and canRespawn(plr) then
		log:debug("Cube ready on CharacterAdded, spawning %s immediately", plr.Name)
		SpawnService:Respawn(plr, "CharacterAdded")
	else
		log:debug("Waiting for CUBE_ORIGIN_CHANGED for %s", plr.Name)
	end
end

-- Player events moved to Start method

-- Helper for testing with simulated characters (no Player instance required)
function SpawnService:RespawnCharacterAtOrigin(character: Model, cubeOrigin: CFrame, _skipStream: boolean?)
	if not character then
		return
	end
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end

	-- Client handles streaming; skip server-side RequestStreamAroundAsync

	local cf = computeSpawnCFrame(cubeOrigin)
	hrp.CFrame = cf

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:Move(Vector3.zero, true)
	end

	log:info(
		"SimSpawned char %s at (%.1f, %.1f, %.1f) facing cube",
		character.Name,
		cf.Position.X,
		cf.Position.Y,
		cf.Position.Z
	)
end

log:info("Initialized")

return SpawnService
