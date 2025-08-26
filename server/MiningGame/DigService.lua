--!strict
-- DigService.server.lua
-- Core game loop handling dig requests

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

-- Shared modules
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Types = require(Shared:WaitForChild("Types"))
local GridMath = require(Shared:WaitForChild("Utils"):WaitForChild("GridMath"))

-- Server siblings
local DataService = require(script.Parent.DataService)
local GridService = require(script.Parent.GridService)
local LootService = require(script.Parent.LootService)
local UpgradeService = require(script.Parent.UpgradeService)
local InventoryService = require(script.Parent.InventoryService)
local CubePositionService = require(script.Parent.CubePositionService)

-- Shared remotes accessor
local Remotes = require(ReplicatedStorage.MiningGame.Remotes)

local DigService = {}

-- Track last dig times for rate limiting
local lastDigTime: {[number]: number} = {}
local digCooldowns: {[number]: number} = {}

-- Player cube references
local playerCubes: {[Player]: {origin: CFrame, model: Model}} = {}

-- Initialize player's cube
function DigService:InitializePlayerCube(player: Player)
    print("[DigService] Initializing cube for", player.Name)
    
    -- Wait for data to load
    local dataLoaded = player:GetAttribute("DataLoaded")
    if not dataLoaded then
        print("[DigService] Waiting for data to load for", player.Name)
        player:GetAttributeChangedSignal("DataLoaded"):Wait()
        print("[DigService] Data loaded signal received for", player.Name)
    end
    
    local profile = DataService:GetPlayerData(player)
    local cubeState = DataService:GetCubeData(player)
    
    print("[DigService] Profile:", profile and "exists" or "nil")
    print("[DigService] CubeState:", cubeState and "exists" or "nil")
    
    if not profile or not cubeState then
        warn("[DigService] No data for player", player.Name)
        return
    end
    
    -- Get cube position from service
    local cubeOrigin = CubePositionService:GetOrigin(player)
    
    -- Create or restore cube
    local model = GridService:RestoreCube(cubeOrigin, cubeState)
    model.Parent = workspace
    
    -- Store reference
    playerCubes[player] = {
        origin = cubeOrigin,
        model = model,
    }
    
    -- Set streaming mode for owner
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
    
    print(string.format("[DigService] Initialized cube for %s @ %s", player.Name, tostring(cubeOrigin.Position)))
end

-- Handle dig request
function DigService:ProcessDigRequest(player: Player, worldPos: Vector3): Types.DigResult
    local userId = player.UserId
    local now = tick()
    
    -- Get player data
    local profile = DataService:GetPlayerData(player)
    local cubeState = DataService:GetCubeData(player)
    local cubeData = playerCubes[player]
    
    if not profile or not cubeState or not cubeData then
        return {
            ok = false,
            reason = "No cube data",
        }
    end
    
    -- Get effective stats
    local gamepasses = UpgradeService:GetPlayerGamepasses(player)
    local activePets = UpgradeService:GetActivePets(profile)
    local effectiveStats = UpgradeService:ComputeEffectiveStats(profile, gamepasses, activePets)
    
    -- Check cooldown
    local lastDig = lastDigTime[userId] or 0
    local cooldown = digCooldowns[userId] or effectiveStats.delay
    
    if now - lastDig < cooldown then
        return {
            ok = false,
            reason = "On cooldown",
            nextAllowedAt = lastDig + cooldown,
        }
    end
    
    -- Convert world position to cell coordinates
    local cellX, cellY, cellZ = GridMath.worldToCell(worldPos, cubeData.origin, GameConfig.Grid.CELL_SIZE_STUDS)
    
    -- Check if click is within cube bounds BEFORE clamping
    local halfCells = (GameConfig.Grid.CUBE_SIZE_STUDS / 4) / 2
    if not GridMath.isInBounds(cellX, cellY, cellZ, GameConfig.Grid.CUBE_SIZE_STUDS) then
        -- Click is outside the cube - reject it
        return {
            ok = false,
            reason = "Outside cube bounds",
        }
    end
    
    -- Now clamp for safety (shouldn't be needed but keeps as failsafe)
    local function clampCell(n: number): number
        return math.clamp(n, -halfCells, halfCells - 1)
    end
    cellX = clampCell(cellX)
    cellY = clampCell(cellY)
    cellZ = clampCell(cellZ)
    
    -- Apply dig to grid
    local dugCells = GridService:ApplyDig(
        player,
        cubeData.origin,
        cubeState,
        cellX,
        cellY,
        cellZ,
        effectiveStats.radius,
        effectiveStats.depth
    )
    
    if #dugCells == 0 then
        return {
            ok = false,
            reason = "No cells dug",
        }
    end
    
    -- Roll for loot
    local lootDrops = LootService:RollCells(
        profile.materialId,
        dugCells,
        profile.cubeSeed,
        effectiveStats.luck
    )
    
    -- Grant loot to inventory
    local lootGranted = {}
    for _, drop in ipairs(lootDrops) do
        InventoryService:AddItem(player, drop.id, 1)
        table.insert(lootGranted, drop.id)
    end
    
    -- Update statistics
    profile.totalBlocksDug = profile.totalBlocksDug + #dugCells
    
    -- Update cooldown
    lastDigTime[userId] = now
    digCooldowns[userId] = effectiveStats.delay
    
    -- Queue save
    DataService:QueueSave(player)
    
    -- Send feedback to client
    Remotes.RE.OnDigFeedback:FireClient(player, {
        cells = dugCells,
        shake = GameConfig.Digging.ENABLE_CAMERA_SHAKE,
        particles = GameConfig.Digging.ENABLE_PARTICLES,
        sound = GameConfig.Digging.DIG_SOUND_ID,
    })
    
    -- Send loot notifications
    for _, drop in ipairs(lootDrops) do
        Remotes.RE.OnLootDropped:FireClient(player, {
            item = drop,
            worldPos = GridMath.cellToWorld(cellX, cellY, cellZ, cubeData.origin, GameConfig.Grid.CELL_SIZE_STUDS),
        })
    end
    
    -- Send visual poke for the center cell
    if #dugCells > 0 then
        local poke = dugCells[1]
        local worldCenter = GridMath.cellToWorld(poke.x, poke.y, poke.z, cubeData.origin, GameConfig.Grid.CELL_SIZE_STUDS)
        Remotes.RE.OnTerrainPoke:FireClient(player, { pos = worldCenter })
    end
    
    return {
        ok = true,
        cellsDug = #dugCells,
        lootGranted = lootGranted,
        nextAllowedAt = now + effectiveStats.delay,
        effectiveStats = effectiveStats,
    }
end

-- Setup remote handlers
local function setupRemotes()
    -- Handle dig requests
    Remotes.RF.RequestDig.OnServerInvoke = function(player: Player, worldPos: Vector3)
        print("[DigService] Dig request from", player.Name, "at", worldPos)
        
        -- Make absolutely sure we have data
        if not DataService:EnsureLoaded(player) then
            return {ok = false, reason = "No profile"}
        end
        
        return DigService:ProcessDigRequest(player, worldPos)
    end
    
    -- Handle profile requests
    Remotes.RF.GetProfile.OnServerInvoke = function(player: Player)
        print("[DigService] Profile request from", player.Name)
        
        -- Make absolutely sure we have data
        if not DataService:EnsureLoaded(player) then
            return nil -- client can retry
        end
        
        local profile = DataService:GetPlayerData(player)
        local cubeState = DataService:GetCubeData(player)
        
        if not profile or not cubeState then
            return nil
        end
        
        -- Calculate effective stats
        local gamepasses = UpgradeService:GetPlayerGamepasses(player)
        local activePets = UpgradeService:GetActivePets(profile)
        local effectiveStats = UpgradeService:ComputeEffectiveStats(profile, gamepasses, activePets)
        
        -- Get cube stats
        local cubeStats = GridService:GetChunkStats(cubeState)
        
        return {
            profile = profile,
            effectiveStats = effectiveStats,
            cubeStats = cubeStats,
            gamepasses = gamepasses,
        }
    end
end

-- Handle player joining
local function onPlayerAdded(player)
    print("[DigService] Player added:", player.Name)
    
    -- Wait a frame for data to potentially load
    RunService.Heartbeat:Wait()
    
    spawn(function()
        DigService:InitializePlayerCube(player)
    end)
end

Players.PlayerAdded:Connect(onPlayerAdded)

-- Handle players already in game (Studio test player)
for _, player in ipairs(Players:GetPlayers()) do
    onPlayerAdded(player)
end

-- Handle player leaving
Players.PlayerRemoving:Connect(function(player)
    -- Clean up cube
    local cubeData = playerCubes[player]
    if cubeData and cubeData.model then
        cubeData.model:Destroy()
    end
    
    -- Clean up references
    playerCubes[player] = nil
    lastDigTime[player.UserId] = nil
    digCooldowns[player.UserId] = nil
end)

-- Initialize
setupRemotes()

print("[DigService] Initialized")

return DigService