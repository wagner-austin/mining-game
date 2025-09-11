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
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame", 30)
local Logger = require(MiningGame:WaitForChild("Logger"))
local log = Logger.new("SpawnService")
local GameConfig = require(MiningGame:WaitForChild("GameConfig"))
local ServiceValidator = require(MiningGame:WaitForChild("ServiceValidator"))
local EventBus = require(MiningGame:WaitForChild("EventBus"))
local EventNames = require(MiningGame:WaitForChild("EventNames"))
local Time = require(MiningGame:WaitForChild("Time"))
local Bus = EventBus.global()

-- Services (injected via Init)
local CubePositionService
local GridService
local DigService

-- Forward declare handler (defined after Start)
local onCharacterAdded: (Model) -> ()

local SpawnService = {}
SpawnService.__index = SpawnService

-- Respawn throttling to prevent spam
local lastRespawnAt: {[Player]: number} = {}
-- Forensics: last committed spawn time and origin to analyze duplicate spawns
local lastCommittedSpawnAt: {[Player]: number} = {}
local lastCommittedOrigin: {[Player]: CFrame} = {}
local DEBUG_SPAWN_LOGS = false
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
    GridService = ServiceValidator.get(container, "GridService")
    CubePositionService = ServiceValidator.get(container, "CubePositionService", {"GetOrigin", "SetOrigin"})
    DigService = ServiceValidator.get(container, "DigService", {"SetPlayerOrigin"})
    log:info("Initialized with dependencies")
end

-- Start method to connect player events after all services are initialized
function SpawnService:Start(container)
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
    end)
    
    -- Reposition when DigService announces the origin
    Bus:on(EventNames.CUBE_ORIGIN_CHANGED, function(evt)
        local to = evt and evt.to
        local player = to and to.player
        if not player or not player.Parent or not player.Character then return end
        
        local payload = evt and evt.payload
        local origin = payload and payload.origin
        
        -- Skip if we're already at the right origin to prevent double-spawning
        local currentOrigin = CubePositionService:GetOrigin(player)
        if currentOrigin and origin and (currentOrigin.Position - origin.Position).Magnitude < 1 then
            log:debug("Already at correct origin, skipping respawn")
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
local HALF  = (GameConfig.Grid.CUBE_SIZE_STUDS / CELL) / 2 -- cells
local HALF_STUDS = HALF * CELL                              -- studs
local FRONT_PADDING = 20                                    -- extra studs in front of face
local GROUND_RAY_UP   = 200                                 -- ray up distance before casting down
local GROUND_RAY_DOWN = 1000                                -- ray down distance

--[[
    Find the ground height at a given position using raycast.
    Excludes procedural content and special folders.
    
    @param pos: Vector3 - The position to check
    @return number - The Y coordinate of the ground
]]
local function groundAtOrDefault(pos: Vector3): number
    -- raycast straight down from above pos
    local origin = pos + Vector3.new(0, GROUND_RAY_UP, 0)
    local dir    = Vector3.new(0, -GROUND_RAY_DOWN, 0)

    -- Build exclude list without nils
    local excludes = {}
    local folderNames = {"SimAgents", "ItemDrops", "ProceduralResources", "PCG_Deco", "PCG_Resources"}
    for _, name in ipairs(folderNames) do
        local folder = Workspace:FindFirstChild(name)
        if folder then
            table.insert(excludes, folder)
        end
    end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = excludes
    params.IgnoreWater = true -- Ignore water to find solid ground

    local hit = Workspace:Raycast(origin, dir, params)
    if hit then
        -- add a little clearance so feet aren't clipping
        return hit.Position.Y + 3
    end
    -- fallback if nothing hit
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
    local target   = cubeOrigin.Position
    
    -- place player (half cube + padding) away from cube center, on ground
    local spawnFlat = target + frontDir * (HALF_STUDS + FRONT_PADDING)
    local y = groundAtOrDefault(spawnFlat)
    local spawnPos = Vector3.new(spawnFlat.X, y, spawnFlat.Z)

    -- face the cube horizontally (keep player upright)
    local lookAt = Vector3.new(target.X, y, target.Z)
    local cf = CFrame.lookAt(spawnPos, lookAt)
    log:debug("computeSpawnCFrame: spawnPos=(%.1f, %.1f, %.1f), lookAt=(%.1f, %.1f, %.1f)",
        spawnPos.X, spawnPos.Y, spawnPos.Z,
        lookAt.X, lookAt.Y, lookAt.Z)
    
    return cf
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
    local hrp = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not hrp then 
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
    CubePositionService:SetOrigin(player, cubeOrigin)   -- authoritative source of truth
    DigService:SetPlayerOrigin(player, cubeOrigin)      -- keep DigService cache in sync
    
    
    -- SpawnService is the sole owner of cube creation timing
    DigService:InitializePlayerCube(player)

    -- request streaming around the spawn (helps with streaming-enabled worlds)
    task.spawn(function()
        pcall(function() Workspace:RequestStreamAroundAsync(cubeOrigin.Position, 64) end)
    end)

    local cf = computeSpawnCFrame(cubeOrigin)


    if DEBUG_SPAWN_LOGS then
        local expected = HALF_STUDS + FRONT_PADDING
        local delta = cf.Position - cubeOrigin.Position
        local horiz = math.sqrt(delta.X*delta.X + delta.Z*delta.Z)
        local now = Time.mono()
        local dt = lastCommittedSpawnAt[player] and (now - lastCommittedSpawnAt[player]) or -1
        local prevOrigin = lastCommittedOrigin[player]
        local originChanged = (prevOrigin ~= nil) and (prevOrigin.Position - cubeOrigin.Position).Magnitude > 0.1
        log:debug(
            "spawn_forensics | src=%s | origin=(%.1f,%.1f,%.1f) -> spawn=(%.1f,%.1f,%.1f) | delta=(%.1f,%.1f,%.1f) | horiz=%.1f | expected=%.1f | dtPrev=%.2f | originChanged=%s",
            tostring(source or "(unknown)"),
            cubeOrigin.Position.X, cubeOrigin.Position.Y, cubeOrigin.Position.Z,
            cf.Position.X, cf.Position.Y, cf.Position.Z,
            delta.X, delta.Y, delta.Z,
            horiz, expected,
            dt,
            tostring(originChanged)
        )
    end
    hrp.CFrame = cf

    -- small nudge to settle
    local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid:Move(Vector3.zero, true)
    end

    log:info("Spawned %s at (%.1f, %.1f, %.1f) facing cube",
        player.Name, cf.Position.X, cf.Position.Y, cf.Position.Z)


    -- Update forensics state after a successful spawn
    lastCommittedSpawnAt[player] = Time.mono()
    lastCommittedOrigin[player] = cubeOrigin
end

-- hook character spawns (called from Start method after dependencies are ready)
onCharacterAdded = function(char: Model)
    local plr = Players:GetPlayerFromCharacter(char)
    if not plr then return end
    
    
    
    -- wait for HRP
    local hrp = char:WaitForChild("HumanoidRootPart", 10)
    if not hrp then
        log:error("No HumanoidRootPart found for %s", plr.Name)
        return
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
function SpawnService:RespawnCharacterAtOrigin(character: Model, cubeOrigin: CFrame, skipStream: boolean?)
    if not character then return end
    local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not hrp then return end

    -- Only request streaming if not skipped (prevents thrashing when spawning many SimAgents)
    if not skipStream then
        task.spawn(function()
            pcall(function() Workspace:RequestStreamAroundAsync(cubeOrigin.Position, 64) end)
        end)
    end

    local cf = computeSpawnCFrame(cubeOrigin)
    hrp.CFrame = cf

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid:Move(Vector3.zero, true)
    end

    log:info("SimSpawned char %s at (%.1f, %.1f, %.1f) facing cube",
        character.Name, cf.Position.X, cf.Position.Y, cf.Position.Z)
end

log:info("Initialized")

return SpawnService
