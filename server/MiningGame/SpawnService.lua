--!strict
-- SpawnService.lua
-- Spawns players in FRONT of their cube at ground level, facing the cube.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame", 30)
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

local function groundAtOrDefault(pos: Vector3): number
    -- raycast straight down from above pos; include Terrain + Baseplate
    local origin = pos + Vector3.new(0, GROUND_RAY_UP, 0)
    local dir    = Vector3.new(0, -GROUND_RAY_DOWN, 0)

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    -- include workspace root: Terrain + parts
    params.FilterDescendantsInstances = { Workspace }

    local hit = Workspace:Raycast(origin, dir, params)
    if hit then
        -- add a little clearance so feet aren't clipping
        return hit.Position.Y + 3
    end
    -- fallback if nothing hit
    return 5
end

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

    print(("[SpawnService] Spawned %s at (%.1f, %.1f, %.1f) facing cube")
        :format(player.Name, cf.Position.X, cf.Position.Y, cf.Position.Z))
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

print("[SpawnService] Initialized")

return SpawnService