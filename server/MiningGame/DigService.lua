--!strict
-- DigService.server.lua
-- Core game loop handling dig requests

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Shared modules
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Time = require(Shared:WaitForChild("Time"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Types = require(Shared:WaitForChild("Types"))
local MathUtils = require(Shared:WaitForChild("MathUtils"))
local MaterialKeys = require(Shared:WaitForChild("MaterialKeys"))
local Logger = require(Shared:WaitForChild("Logger"))
local ServiceValidator = require(Shared:WaitForChild("ServiceValidator"))
local ErrorService = require(script.Parent.ErrorService) -- Foundation service
local EventBus = require(Shared:WaitForChild("EventBus"))
local EventNames = require(Shared:WaitForChild("EventNames"))
local EventContracts = require(Shared:WaitForChild("EventContracts"))
local Bus = EventBus.global()

-- Server siblings - resolved via DI
local DataService
local _GridService
local _LootService
local _ItemService
local _AchievementService
local UpgradeService
local _InventoryService
local CubePositionService
local _UserMetricsService
local _CharacterStateManager -- Optional dependency
local _CompositionService -- Optional dependency
local _SoundBroadcast = require(script.Parent:WaitForChild("SoundBroadcast")) -- Not a service, just a module
local CubeVolume = require(script.Parent:WaitForChild("CubeVolume"))
local DigFolder = script.Parent:WaitForChild("Dig")
local Picker = require(DigFolder:WaitForChild("Picker"))
local VolumeRegistry = require(DigFolder:WaitForChild("VolumeRegistry"))
local RemoteManager = require(script.Parent.RemoteManager)

-- Forward declare handlers (defined after Start)
local onPlayerRemoving: (Player) -> ()

-- Shared remotes accessor

-- Mark fast-path for frequent dig feedback events
Bus:markFastPath(EventNames.DIG_FEEDBACK)

type ContainerI = any

export type DigServiceT = {
	_container: ContainerI?,
	_digCooldowns: { [number]: number },
	_lastDigTime: { [number]: number },
	playerCubes: { [Player]: { origin: CFrame, model: Model? } },
	_autoTargets: { [Player]: Vector3 },

	-- lifecycle
	Init: (self: DigServiceT, container: ContainerI) -> (),
	Start: (self: DigServiceT, _container: ContainerI?) -> (),

	-- volumes
	RegisterVolume: (
		self: DigServiceT,
		init: {
			id: string?,
			kind: string,
			origin: CFrame,
			sizeStuds: Vector3,
			permissions: { public: boolean, ownerUserId: number? }?,
			meta: Types.VolumeMeta?,
			state: Types.CubeState?,
		}
	) -> Types.Volume,
	UnregisterVolume: (self: DigServiceT, id: string) -> boolean,
	PickVolume: (self: DigServiceT, worldPos: Vector3, player: Player) -> Types.Volume?,

	-- cube management
	InitializePlayerCube: (self: DigServiceT, player: Player, opts: { skipEnsureBase: boolean? }?) -> (),
	HasCube: (self: DigServiceT, player: Player) -> boolean,
	SetPlayerOrigin: (self: DigServiceT, player: Player, origin: CFrame) -> (),

	-- dig ops
	ProcessDigRequest: (self: DigServiceT, player: Player, worldPos: Vector3) -> Types.DigResult,
	StartHoldDig: (self: DigServiceT, player: Player, initialWorldPos: Vector3) -> (),
	StopHoldDig: (self: DigServiceT, player: Player) -> (),
	StartAutoDig: (self: DigServiceT, player: Player) -> (),
	StopAutoDig: (self: DigServiceT, player: Player) -> (),

	-- telemetry accessors
	GetTelemetry: () -> TelemetrySnapshot,
	ResetTelemetry: () -> (),
}

type TelemetrySnapshot = {
	picks: { cube: number, island: number, fallback: number },
	rejects: {
		out_of_range: number,
		outside_cube: number,
		outside_volume: number,
		invalid_terrain: number,
		not_owner: number,
		locked: number,
	},
	successes: number,
	last: { pick: string?, volId: string?, kind: string?, reason: string? },
}

local DigService = {} :: DigServiceT
DigService._container = nil
DigService._digCooldowns = {}
DigService._lastDigTime = {}
DigService.playerCubes = {}
DigService._autoTargets = {}
local log = Logger.new("DigService")

-- Player cube references (exposed for debug reset). Declared early for closure capture.
-- Use the maps from the typed service table to avoid sealed-table mutations.
local playerCubes = DigService.playerCubes

-- Client-provided targets for auto-dig (optional). Keyed by Player.
local autoTargets = DigService._autoTargets

-- Pending auto-dig starts for players whose cube isn't ready yet
local pendingAutoStart: { [number]: boolean } = {}

-- Volume registry moved to Dig/VolumeRegistry.lua

-- Lightweight telemetry for QA (non-persistent)
function DigService.GetTelemetry()
	return require(script.Parent.Dig.Telemetry).get()
end

function DigService.ResetTelemetry()
	require(script.Parent.Dig.Telemetry).reset()
end

-- Helpers for IDs
local function cubeVolumeIdFor(player: Player): string
	return string.format("cube:%d", player.UserId)
end

-- Initialize with dependency injection
function DigService:Init(container)
	-- Hard deps (fail fast). Validate only known methods to avoid brittle wiring.
	DataService = ServiceValidator.get(container, "DataService") -- used widely; methods vary
	_GridService = ServiceValidator.get(container, "GridService") -- core terrain ops
	_LootService = ServiceValidator.get(container, "LootService") -- drops/defs
	_ItemService = ServiceValidator.get(container, "ItemService") -- item creation/ops
	_AchievementService = ServiceValidator.get(container, "AchievementService") -- achievement hooks
	UpgradeService = ServiceValidator.get(container, "UpgradeService", { "ComputeEffectiveStats" })
	_InventoryService = ServiceValidator.get(container, "InventoryService", { "AddItemsBulk" })
	CubePositionService = ServiceValidator.get(container, "CubePositionService", { "GetOrigin" })

	-- Soft/optional deps
	_UserMetricsService = ServiceValidator.tryGet(container, "UserMetricsService", { "Invalidate" })
	_CharacterStateManager = ServiceValidator.tryGet(container, "CharacterStateManager", { "SetNextDigAllowedAt" })
	_CompositionService = ServiceValidator.tryGet(container, "CompositionService", { "ApplyComposition" })

	-- Set up event listeners for monetization-driven dig events
	Bus:on(EventNames.AUTO_DIG_START, function(msg)
		local ok, p = ErrorService.safecall("EventContracts.AUTO_DIG_START", function()
			return EventContracts.AUTO_DIG_START(msg.payload)
		end)
		if ok and type(p) == "table" then
			local payload: { player: Player } = p
			local plr = payload.player
			if DigService:HasCube(plr) then
				DigService:StartAutoDig(plr)
			else
				pendingAutoStart[plr.UserId] = true
				log:debug("Queued AUTO_DIG_START for %s (cube not ready)", plr.Name)
			end
		end
	end)

	Bus:on(EventNames.MEGA_DIG_REQUEST, function(msg)
		local ok, p = ErrorService.safecall("EventContracts.MEGA_DIG_REQUEST", function()
			return EventContracts.MEGA_DIG_REQUEST(msg.payload)
		end)
		if not ok then
			return
		end
		if type(p) ~= "table" then
			return
		end
		local payload: { player: Player, position: Vector3, sizeBoost: number } = p
		local profile = DataService:GetPlayerData(payload.player)
		if not profile then
			return
		end

		-- Apply a scoped boost just for this dig
		local oldSize = (profile.upgrades and profile.upgrades.size) or 0
		local boost = MathUtils.nonNegative(payload.sizeBoost)
		profile.upgrades.size = math.min(15, oldSize + boost)

		ErrorService.safecall("DigService:ProcessDigRequest(mega)", function()
			DigService:ProcessDigRequest(payload.player, payload.position)
			return true
		end)

		-- Restore original size
		profile.upgrades.size = oldSize
	end)

	-- RemoteEvent: client updates the preferred auto-dig target (mouse world position)
	RemoteManager.registerRE("AutoDig_SetTarget", function(ctx, position: Vector3)
		-- Simple deadzone & clamp via range; Processor enforces full validation
		local player = ctx.player
		if not player or not player.Character then
			return
		end
		local hrpInst = player.Character:FindFirstChild("HumanoidRootPart")
		if not (hrpInst and hrpInst:IsA("BasePart")) then
			return
		end
		local hrp: BasePart = hrpInst
		-- Apply minimal filtering: ignore absurdly distant targets
		if
			(hrp.Position - position).Magnitude > ((GameConfig.Digging and GameConfig.Digging.MAX_RANGE_STUDS) or 200)
		then
			return
		end
		autoTargets[player] = position
	end, {
		schema = function(position)
			return typeof(position) == "Vector3", "Vector3 required"
		end,
		rateLimitSec = 0.08, -- ~12.5 Hz; cheap: sets a table value only
		requireProfile = true,
	})

	-- When a player's cube becomes ready/changes origin, auto-start dig if eligible
	Bus:on(EventNames.CUBE_ORIGIN_CHANGED, function(msg)
		local to = msg and msg.to
		local player = to and to.player
		if not player then
			return
		end
		-- Check permanent pass
		local hasPermanent = false
		do
			local ok, gps = ErrorService.safecall("UpgradeService.GetPlayerGamepasses", function()
				return UpgradeService
						and UpgradeService.GetPlayerGamepasses
						and UpgradeService:GetPlayerGamepasses(player)
					or nil
			end)
			if ok and type(gps) == "table" then
				local g: { [string]: boolean } = gps
				hasPermanent = g["AUTO_DIGGER"] == true
			end
		end
		if not hasPermanent then
			-- Check temporary boost
			local profile = DataService and DataService:GetPlayerData(player)
			local boostActive = profile
				and profile.boosts
				and profile.boosts.auto_dig
				and (Time.unix() < profile.boosts.auto_dig)
			if not boostActive then
				return
			end
		end
		-- Start auto-dig now that cube exists
		DigService:StartAutoDig(player)
		pendingAutoStart[player.UserId] = nil
	end)

	self._container = container
	log:info("Initialized with dependencies and event listeners")
end

-- Start method to connect player events after all services are initialized
function DigService:Start(_container)
	-- Only cleanup - SpawnService handles all cube creation
	-- Define lightweight cleanup handler and connect
	onPlayerRemoving = function(player: Player)
		-- Stop any active dig loops and clear refs
		local HoldLoop = require(DigFolder:WaitForChild("HoldLoop"))
		local AutoLoop = require(DigFolder:WaitForChild("AutoLoop"))
		ErrorService.safecall("HoldLoop.CleanupOnRemoving", function()
			HoldLoop.CleanupOnRemoving(DigService, player)
			return true
		end)
		ErrorService.safecall("AutoLoop.CleanupOnRemoving", function()
			AutoLoop.CleanupOnRemoving(DigService, player)
			return true
		end)
		DigService.playerCubes[player] = nil
		VolumeRegistry.SetPlayerCubeVolumeId(player, nil)
		DigService._autoTargets[player] = nil
		pendingAutoStart[player.UserId] = nil
	end
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	log:info("Started with player connections")
end

-- Track last dig times for rate limiting

-- Track continuous/hold dig states with version control for clean shutdown
-- Moved to Dig/HoldLoop.lua

-- Track auto-dig states
-- Moved to Dig/AutoLoop.lua

-- Player cube references declared above for closure capture

-- Generic AABB snap helper (axis-aligned)
-- (moved to Dig/Snapper.lua)

-- Register a mineable volume
function DigService:RegisterVolume(init: {
	id: string?,
	kind: string,
	origin: CFrame,
	sizeStuds: Vector3,
	permissions: { public: boolean, ownerUserId: number? }?,
	meta: Types.VolumeMeta?,
	state: Types.CubeState?,
}): Types.Volume
	local container = self._container
	if not container then
		error("DigService container not initialized")
	end
	return VolumeRegistry.Register(container, init)
end

function DigService:UnregisterVolume(id: string): boolean
	return VolumeRegistry.Unregister(id)
end

-- Pick a volume for a world position. Prefers player's cube.
function DigService:PickVolume(worldPos: Vector3, player: Player): Types.Volume?
	local vols = VolumeRegistry.GetVolumes()
	local hash = VolumeRegistry.GetHash()
	local cubeVolId = VolumeRegistry.GetPlayerCubeVolumeId(player)
	return Picker.pickVolume(worldPos, player, vols, cubeVolId, hash)
end

--[[
    Initialize a player's mining cube when they join or respawn.
    Creates or restores the cube terrain, applies saved materials, and notifies the client.
    
    @param player: Player - The player whose cube to initialize
]]
function DigService:InitializePlayerCube(player: Player, opts)
	-- SpawnService ensures this is only called once per player
	-- No guards needed since we have single ownership

	log:info("Initializing cube for %s", player.Name)

	-- Wait for data to load
	local dataLoaded = player:GetAttribute("DataLoaded")
	if not dataLoaded then
		log:debug("Waiting for data to load for %s", player.Name)
		player:GetAttributeChangedSignal("DataLoaded"):Wait()
		log:debug("Data loaded signal received for %s", player.Name)
	end

	local profile = DataService:GetPlayerData(player)
	local cubeState = DataService:GetCubeData(player)

	log:debug("Profile: %s, CubeState: %s", profile and "exists" or "nil", cubeState and "exists" or "nil")

	if not profile or not cubeState then
		log:warn("No data for player %s", player.Name)
		return
	end

	-- Get cube position from service
	local cubeOrigin = CubePositionService:GetOrigin(player)

	-- Load saved material preferences
	local materialPrefs = DataService:GetMaterialPrefs(player)
	local floorMaterial: Enum.Material? = nil
	if materialPrefs and materialPrefs.floorMaterial then
		floorMaterial = MaterialKeys.EnumFromKey[string.lower(materialPrefs.floorMaterial)]
		log:debug(
			"Loading saved floor material: %s -> %s",
			tostring(materialPrefs.floorMaterial),
			tostring(floorMaterial)
		)
	end

	-- Use CubeVolume to restore + register in one place
	local cubeSize = GameConfig.Grid.CUBE_SIZE_STUDS
	local id = cubeVolumeIdFor(player)
	local container = self._container
	if not container then
		error("DigService container not initialized")
	end
	local volData = CubeVolume.create(container, {
		id = id,
		kind = "cube",
		origin = cubeOrigin,
		sizeStuds = Vector3.new(cubeSize, cubeSize, cubeSize),
		ownerUserId = player.UserId,
		state = cubeState,
		themeId = materialPrefs and materialPrefs.activeThemeId or nil,
		floorMaterial = floorMaterial,
	})

	-- Store reference
	playerCubes[player] = {
		origin = cubeOrigin,
		model = volData and volData.model or nil,
	}
	VolumeRegistry.SetPlayerCubeVolumeId(player, id)

	-- Notify client of cube origin
	Bus:emit(EventNames.CUBE_ORIGIN_CHANGED, {
		to = { kind = "player", player = player },
		payload = { origin = cubeOrigin },
	})

	-- Ensure player base floor (ring) AFTER cube is restored (we will pass the cubeOrigin directly)
	do
		local skipBase = (opts and opts.skipEnsureBase) == true
		if not skipBase then
			local svcContainer = self._container
			if not svcContainer then
				error("DigService container not initialized")
			end
			local PBS = ServiceValidator.tryGet(svcContainer, "PlayerBaseService", { "Ensure" })
			if PBS then
				ErrorService.safecall("DigService.PlayerBaseEnsure", function()
					PBS:Ensure(player, cubeOrigin)
					return true
				end)
			end
		end
	end

	-- Set streaming mode for owner (already applied in CubeVolume, but harmless to reinforce)
	local model = volData and volData.model
	if model then
		model:SetAttribute("OwnerId", player.UserId)

		-- Set persistent streaming for owner
		for _, descendant in ipairs(model:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant:SetAttribute("StreamingMode", "PersistentPerPlayer")
				descendant:SetAttribute("StreamingPlayerId", player.UserId)
			end
		end
	end

	log:info("Initialized cube for %s @ %s", player.Name, tostring(cubeOrigin.Position))
end

-- Helper to check if player has an initialized cube
function DigService:HasCube(player: Player): boolean
	local c = playerCubes[player]
	return c ~= nil and c.model ~= nil
end

-- Update stored origin for a player (call when cube origin changes)
function DigService:SetPlayerOrigin(player: Player, origin: CFrame)
	local cube = playerCubes[player]
	if cube then
		-- If origin changed significantly, clear the model to force recreation
		if cube.origin and (cube.origin.Position - origin.Position).Magnitude > 1 then
			log:warn(
				"Origin changed significantly for %s: %s -> %s",
				player.Name,
				tostring(cube.origin.Position),
				tostring(origin.Position)
			)
			if cube.model then
				cube.model:Destroy()
				cube.model = nil
			end
		end
		cube.origin = origin
	else
		playerCubes[player] = { origin = origin, model = nil }
	end
	-- Keep volume origin in sync
	local vid = VolumeRegistry.GetPlayerCubeVolumeId(player)
	if vid then
		VolumeRegistry.UpdateOrigin(vid, origin)
	end
	log:info("DigService:SetPlayerOrigin %s -> %s", player.Name, tostring(origin.Position))
end

-- (legacy cube-specific helpers removed; unified AABB helpers are used instead)

--[[
    Process a dig request from a client at the specified world position.
    Validates the position, checks cooldowns, destroys terrain, and grants loot.
    
    @param player: Player - The player making the dig request
    @param worldPos: Vector3 - The world position to dig at
    @return Types.DigResult - Result containing success status, loot, and next allowed time
]]
function DigService:ProcessDigRequest(player: Player, worldPos: Vector3): Types.DigResult
	local Processor = require(script.Parent.Dig.Processor)
	local res = Processor.Process(self, player, worldPos)
	return res :: Types.DigResult
end

-- Hold-dig wrappers
function DigService:StartHoldDig(player: Player, initialWorldPos: Vector3)
	local HoldLoop = require(DigFolder:WaitForChild("HoldLoop"))
	HoldLoop.Start(self, player, initialWorldPos)
end

function DigService:StopHoldDig(player: Player)
	local HoldLoop = require(DigFolder:WaitForChild("HoldLoop"))
	HoldLoop.Stop(self, player)
end

-- Auto-dig wrappers
function DigService:StartAutoDig(player: Player)
	local AutoLoop = require(DigFolder:WaitForChild("AutoLoop"))
	AutoLoop.Start(self, player)
end

function DigService:StopAutoDig(player: Player)
	local AutoLoop = require(DigFolder:WaitForChild("AutoLoop"))
	AutoLoop.Stop(self, player)
end
return DigService
