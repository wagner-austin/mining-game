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

local CubePositionService = require(script.Parent.CubePositionService)

local SpawnService = {}

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
    return CFrame.lookAt(spawnPos, lookAt)
end

--[[
    Respawn a player at their designated spawn point.
    Handles streaming and position settling.
    
    @param player: Player - The player to respawn
]]
function SpawnService:Respawn(player: Player)
    if not player.Character then return end
    local hrp = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not hrp then return end

    -- ensure we have an origin for this player
    local cubeOrigin = CubePositionService:GetOrigin(player)
    if not cubeOrigin then return end

    -- request streaming around the spawn (helps with streaming-enabled worlds)
    task.spawn(function()
        pcall(function() Workspace:RequestStreamAroundAsync(cubeOrigin.Position, 64) end)
    end)

    local cf = computeSpawnCFrame(cubeOrigin)
    hrp.CFrame = cf

    -- small nudge to settle
    local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid:Move(Vector3.zero, true)
    end

    log:info("Spawned {} at ({:.1f}, {:.1f}, {:.1f}) facing cube",
        player.Name, cf.Position.X, cf.Position.Y, cf.Position.Z)
end

-- hook character spawns
local function onCharacterAdded(char: Model)
    local plr = Players:GetPlayerFromCharacter(char)
    if not plr then return end
    -- wait for HRP
    char:WaitForChild("HumanoidRootPart", 10)
    SpawnService:Respawn(plr)
end

Players.PlayerAdded:Connect(function(plr)
    plr.CharacterAdded:Connect(onCharacterAdded)
end)

-- handle players already present (Studio)
for _, plr in ipairs(Players:GetPlayers()) do
    plr.CharacterAdded:Connect(onCharacterAdded)
    if plr.Character then onCharacterAdded(plr.Character) end
end

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

    log:info("SimSpawned char {} at ({:.1f}, {:.1f}, {:.1f}) facing cube",
        character.Name, cf.Position.X, cf.Position.Y, cf.Position.Z)
end

log:info("Initialized")

return SpawnService