--!strict
-- DigService.server.lua
-- Core game loop handling dig requests

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

-- Shared modules
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Time = require(Shared:WaitForChild("Time"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local VOX = GameConfig.Terrain.VOXEL_RESOLUTION
local Types = require(Shared:WaitForChild("Types"))
local GridMath = require(Shared:WaitForChild("Utils"):WaitForChild("GridMath"))
local MaterialKeys = require(Shared:WaitForChild("MaterialKeys"))
local Logger = require(Shared:WaitForChild("Logger"))
local MathUtils = require(Shared:WaitForChild("MathUtils"))
local ServiceValidator = require(Shared:WaitForChild("ServiceValidator"))
local ErrorService = require(script.Parent.ErrorService)  -- Foundation service
local EventBus = require(Shared:WaitForChild("EventBus"))
local EventNames = require(Shared:WaitForChild("EventNames"))
local EventContracts = require(Shared:WaitForChild("EventContracts"))
local Bus = EventBus.global()

-- Server siblings - resolved via DI
local DataService
local GridService
local LootService
local ItemService
local AchievementService
local UpgradeService
local InventoryService
local CubePositionService
local UserMetricsService
local CharacterStateManager  -- Optional dependency
local CompositionService  -- Optional dependency
local SoundBroadcast = require(script.Parent:WaitForChild("SoundBroadcast"))  -- Not a service, just a module
local CubeVolume = require(script.Parent:WaitForChild("CubeVolume"))
local DigFolder = script.Parent:WaitForChild("Dig")
local Snapper = require(DigFolder:WaitForChild("Snapper"))
local Picker = require(DigFolder:WaitForChild("Picker"))
local VolumeRegistry = require(DigFolder:WaitForChild("VolumeRegistry"))
local SurfaceSolver = require(DigFolder:WaitForChild("SurfaceSolver"))

-- Forward declare handlers (defined after Start)
local onPlayerAdded: (Player) -> ()
local onPlayerRemoving: (Player) -> ()

-- Shared remotes accessor
local Remotes = require(ReplicatedStorage.MiningGame.Remotes)

-- Mark fast-path for frequent dig feedback events
Bus:markFastPath(EventNames.DIG_FEEDBACK)

local DigService = {}
local log = Logger.new("DigService")

-- Player cube references (exposed for debug reset). Declared early for closure capture.
local playerCubes: {[Player]: {origin: CFrame, model: Model}} = {}
DigService.playerCubes = playerCubes

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
    DataService         = ServiceValidator.get(container, "DataService")  -- used widely; methods vary
    GridService         = ServiceValidator.get(container, "GridService")  -- core terrain ops
    LootService         = ServiceValidator.get(container, "LootService")  -- drops/defs
    ItemService         = ServiceValidator.get(container, "ItemService")  -- item creation/ops
    AchievementService  = ServiceValidator.get(container, "AchievementService")  -- achievement hooks
    UpgradeService      = ServiceValidator.get(container, "UpgradeService", {"ComputeEffectiveStats"})
    InventoryService    = ServiceValidator.get(container, "InventoryService", {"AddItemsBulk"})
    CubePositionService = ServiceValidator.get(container, "CubePositionService", {"GetOrigin"})
    
    -- Soft/optional deps
    UserMetricsService  = ServiceValidator.tryGet(container, "UserMetricsService", {"Invalidate"})
    CharacterStateManager = ServiceValidator.tryGet(container, "CharacterStateManager", {"SetNextDigAllowedAt"})
    CompositionService = ServiceValidator.tryGet(container, "CompositionService", {"ApplyComposition"})
    
    -- Set up event listeners for monetization-driven dig events
    Bus:on(EventNames.AUTO_DIG_START, function(msg)
        local ok, p = ErrorService.safecall("EventContracts.AUTO_DIG_START", function()
            return EventContracts.AUTO_DIG_START(msg.payload)
        end)
        if ok and p.player then
            DigService:StartAutoDig(p.player)
        end
    end)
    
    Bus:on(EventNames.MEGA_DIG_REQUEST, function(msg)
        local ok, p = ErrorService.safecall("EventContracts.MEGA_DIG_REQUEST", function()
            return EventContracts.MEGA_DIG_REQUEST(msg.payload)
        end)
        if not ok then return end
        local profile = DataService:GetPlayerData(p.player)
        if not (profile and p.position) then return end
        
        -- Apply a scoped boost just for this dig
        local oldSize = (profile.upgrades and profile.upgrades.size) or 0
        local boost = MathUtils.nonNegative(p.sizeBoost or 0)
        profile.upgrades.size = math.min(15, oldSize + boost)
        
        ErrorService.safecall("DigService:ProcessDigRequest(mega)", function()
            DigService:ProcessDigRequest(p.player, p.position)
        end, { uid = p.player.UserId })
        
        -- Restore original size
        profile.upgrades.size = oldSize
    end)
    
    self._container = container
    log:info("Initialized with dependencies and event listeners")
end

-- Start method to connect player events after all services are initialized
function DigService:Start(container)
    -- Only cleanup - SpawnService handles all cube creation
    -- Define lightweight cleanup handler and connect
    onPlayerRemoving = function(player: Player)
        -- Stop any active dig loops and clear refs
        local HoldLoop = require(DigFolder:WaitForChild("HoldLoop"))
        local AutoLoop = require(DigFolder:WaitForChild("AutoLoop"))
        pcall(function() HoldLoop.CleanupOnRemoving(DigService, player) end)
        pcall(function() AutoLoop.CleanupOnRemoving(DigService, player) end)
        playerCubes[player] = nil
        VolumeRegistry.SetPlayerCubeVolumeId(player, nil)
    end
    Players.PlayerRemoving:Connect(onPlayerRemoving)
    
    log:info("Started with player connections")
end

-- Track last dig times for rate limiting
local lastDigTime: {[number]: number} = {}
local digCooldowns: {[number]: number} = {}

-- Track continuous/hold dig states with version control for clean shutdown
-- Moved to Dig/HoldLoop.lua

-- Track auto-dig states
-- Moved to Dig/AutoLoop.lua

-- Player cube references declared above for closure capture

-- Generic AABB snap helper (axis-aligned)
-- (moved to Dig/Snapper.lua)

-- Register a mineable volume
function DigService:RegisterVolume(init: { id: string?, kind: string, origin: CFrame, sizeStuds: Vector3, permissions: { public: boolean, ownerUserId: number? }?, meta: any?, state: Types.CubeState? }): Types.Volume
    return VolumeRegistry.Register(self._container, init)
end

function DigService:UnregisterVolume(id: string): boolean
    return VolumeRegistry.Unregister(id)
end

-- Pick a volume for a world position. Prefers player's cube.
function DigService:PickVolume(worldPos: Vector3, player: Player?): Types.Volume?
    local vols = VolumeRegistry.GetVolumes()
    local hash = VolumeRegistry.GetHash()
    local cubeVolId = player and VolumeRegistry.GetPlayerCubeVolumeId(player) or nil
    return Picker.pickVolume(worldPos, player, vols, cubeVolId, hash)
end

--[[
    Initialize a player's mining cube when they join or respawn.
    Creates or restores the cube terrain, applies saved materials, and notifies the client.
    
    @param player: Player - The player whose cube to initialize
]]
function DigService:InitializePlayerCube(player: Player)
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
        log:debug("Loading saved floor material: %s -> %s", tostring(materialPrefs.floorMaterial), tostring(floorMaterial))
    end
    
    -- Use CubeVolume to restore + register in one place
    local cubeSize = GameConfig.Grid.CUBE_SIZE_STUDS
    local id = cubeVolumeIdFor(player)
    local volData = CubeVolume.create(self._container, {
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
        payload = { origin = cubeOrigin }
    })

    -- Ensure player base floor (ring) AFTER cube is restored (we will pass the cubeOrigin directly)
    do
        local PBS = ServiceValidator.tryGet(self._container, "PlayerBaseService", {"Ensure"})
        if PBS then
            pcall(function()
                PBS:Ensure(player, cubeOrigin)
            end)
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
            log:warn("Origin changed significantly for %s: %s -> %s", 
                player.Name, tostring(cube.origin.Position), tostring(origin.Position))
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
    return require(script.Parent.Dig.Processor).Process(self, player, worldPos)
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
