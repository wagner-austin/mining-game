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
local Remotes = require(MiningGame:WaitForChild("Remotes"))

local SpawnService = require(script.Parent:WaitForChild("SpawnService"))
local GridService = require(script.Parent:WaitForChild("GridService"))
local CubePositionService = require(script.Parent:WaitForChild("CubePositionService"))

local SimAgents = {}

-- Future-proof respawn adapter (works even if SpawnService changes during refactor)
local function safeRespawn(character: Model, originCFrame: CFrame)
    -- Prefer the helper if it exists
    if SpawnService and SpawnService.RespawnCharacterAtOrigin then
        return SpawnService:RespawnCharacterAtOrigin(character, originCFrame, true) -- true = skip stream
    end
    -- Fallback if API changes: place the HRP directly (still testable)
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if hrp then 
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
local agents: {[number]: {
    char: Model,
    cubeCFrame: CFrame,
    cubeModel: Model?,
    userId: number,
}} = {}
local nextId = 0
local agentFolder: Folder?

-- Ensure folder for organization
local function ensureFolder(): Folder
    if not agentFolder then
        agentFolder = Workspace:FindFirstChild("SimAgents")
        if not agentFolder then
            agentFolder = Instance.new("Folder")
            agentFolder.Name = "SimAgents"
            agentFolder.Parent = Workspace
        end
    end
    return agentFolder
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
    local ord = playerCount + index  -- always after real players
    local cf = CubePositionService:ComputeDefaultOriginForOrdinal(ord)
    CubePositionService:RegisterSimulatedPosition(userId, cf)
    
    log:debug("Spawning SimAgent {} at ordinal {}, pos {}", id, ord, tostring(cf.Position))
    
    -- Create cube (terrain or ghost)
    local cubeModel
    if CONFIG.CREATE_TERRAIN_CUBES then
        -- Create real terrain cube
        cubeModel = GridService:CreateTerrainCube(
            cf,
            CONFIG.CUBE_SIZE,
            Enum.Material.Rock,
            Enum.Material.Grass
        )
        cubeModel.Name = "SimCube_" .. id
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
    log:debug("Spawning character for agent {}...", id)
    safeRespawn(char, cf)
    
    -- Store agent data
    agents[id] = {
        char = char,
        cubeCFrame = cf,
        cubeModel = cubeModel,
        userId = userId,
    }
    
    log:info("✓ Spawned SimAgent {} - position: {}", id, tostring(cf.Position))
end

-- Clear all agents
local function clearAll()
    local currentCount = 0
    for _ in pairs(agents) do
        currentCount = currentCount + 1
    end
    log:debug("Clearing {} existing agents...", currentCount)
    
    for _, agent in pairs(agents) do
        if agent.char and agent.char.Parent then
            agent.char:Destroy()
        end
        if agent.cubeModel and agent.cubeModel.Parent then
            agent.cubeModel:Destroy()
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
    log:info("Repopulate start: target={}", count)
    clearAll()
    
    count = math.min(count, CONFIG.MAX_AGENTS)
    local placed = 0
    
    for i = 1, count do
        spawnOne(i)
        placed = placed + 1
    end
    
    log:info("Repopulate done: placed={} agents", placed)
end

-- Public API
function SimAgents:SetCount(n: number)
    log:info("SimAgents:SetCount called with n={}", n)
    
    if not CONFIG.ENABLED then
        log:warn("SimAgents is disabled outside Studio")
        return
    end
    
    local targetCount = math.max(0, math.floor(n))
    log:info("Repopulating with {} agents...", targetCount)
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
    if not CONFIG.ENABLED then return end
    
    for _, agent in pairs(agents) do
        safeRespawn(agent.char, agent.cubeCFrame)
    end
    
    log:info("Respawned all SimAgents")
end

function SimAgents:Clear()
    if not CONFIG.ENABLED then return end
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

-- Remote handlers for UI control
local function setupRemotes()
    log:info("Setting up remote handlers...")
    
    -- Handle UI requests
    Remotes.RF.SimAgents_SetCount.OnServerInvoke = function(player: Player, count: number)
        log:info("SimAgents_SetCount called by {} with count: {}", player.Name, count)
        
        if not CONFIG.ENABLED then
            log:warn("SimAgents disabled - not in Studio")
            return false, "SimAgents only available in Studio"
        end
        
        SimAgents:SetCount(count)
        local newCount = SimAgents:GetCount()
        log:info("SimAgents count set to: {}", newCount)
        return true, newCount
    end
    
    Remotes.RF.SimAgents_GetStatus.OnServerInvoke = function(player: Player)
        log:debug("SimAgents_GetStatus called by {}", player.Name)
        local status = {
            enabled = CONFIG.ENABLED,
            count = SimAgents:GetCount(),
            maxCount = CONFIG.MAX_AGENTS,
            useTerrainCubes = CONFIG.CREATE_TERRAIN_CUBES,
            -- Added fields for UI display
            playerCount = #Players:GetPlayers(),
            strategy = (GameConfig.Multiplayer and GameConfig.Multiplayer.SPAWN_STRATEGY) or "grid",
        }
        log:debug("Returning status: enabled={}, count={}, maxCount={}", status.enabled, status.count, status.maxCount)
        return status
    end
    
    Remotes.RF.SimAgents_RespawnAll.OnServerInvoke = function(player: Player)
        log:info("SimAgents_RespawnAll called by {}", player.Name)
        
        if not CONFIG.ENABLED then
            log:warn("SimAgents disabled - not in Studio")
            return false, "SimAgents only available in Studio"
        end
        
        SimAgents:RespawnAll()
        log:info("Respawned all {} agents", SimAgents:GetCount())
        return true
    end
    
    Remotes.RF.SimAgents_Clear.OnServerInvoke = function(player: Player)
        if not CONFIG.ENABLED then
            return false, "SimAgents only available in Studio"
        end
        
        SimAgents:Clear()
        return true
    end
    
    Remotes.RF.SimAgents_SetTerrainCubes.OnServerInvoke = function(player: Player, enabled: boolean)
        if not CONFIG.ENABLED then
            return false, "SimAgents only available in Studio"
        end
        
        SimAgents:SetTerrainCubes(enabled)
        return true
    end
    
    log:info("Remote handlers ready.")
end

-- Initialize
log:info("SimAgents initializing... Studio: {}, Enabled: {}", tostring(RunService:IsStudio()), tostring(CONFIG.ENABLED))

if CONFIG.ENABLED then
    setupRemotes()
    log:info("SimAgents initialized (Studio mode) - Max agents: {}", CONFIG.MAX_AGENTS)
else
    setupRemotes() -- Still setup remotes to return disabled status
    log:info("SimAgents disabled (not in Studio) but remotes available")
end

return SimAgents