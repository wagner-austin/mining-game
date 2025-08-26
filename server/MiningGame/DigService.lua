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
    -- Wait for data to load
    local dataLoaded = player:GetAttribute("DataLoaded")
    if not dataLoaded then
        player:GetAttributeChangedSignal("DataLoaded"):Wait()
    end
    
    local profile = DataService:GetPlayerData(player)
    local cubeState = DataService:GetCubeData(player)
    
    if not profile or not cubeState then
        warn("[DigService] No data for player", player.Name)
        return
    end
    
    -- Calculate cube position (in neighborhood grid)
    local playerIndex = 0
    for i, p in ipairs(Players:GetPlayers()) do
        if p == player then
            playerIndex = i - 1
            break
        end
    end
    
    local spacing = GameConfig.Multiplayer.CUBE_SPACING
    local gridX = playerIndex % 3
    local gridZ = math.floor(playerIndex / 3)
    local cubeOrigin = CFrame.new(gridX * spacing, 0, gridZ * spacing)
    
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
    
    print("[DigService] Initialized cube for", player.Name)
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
    
    -- Check if position is within bounds
    if not GridMath.isInBounds(cellX, cellY, cellZ, GameConfig.Grid.CUBE_SIZE_STUDS) then
        return {
            ok = false,
            reason = "Out of bounds",
        }
    end
    
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
        return DigService:ProcessDigRequest(player, worldPos)
    end
    
    -- Handle profile requests
    Remotes.RF.GetProfile.OnServerInvoke = function(player: Player)
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
Players.PlayerAdded:Connect(function(player)
    -- Wait a frame for data to potentially load
    RunService.Heartbeat:Wait()
    
    spawn(function()
        DigService:InitializePlayerCube(player)
    end)
end)

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