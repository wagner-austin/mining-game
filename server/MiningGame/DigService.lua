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
local MaterialKeys = require(Shared:WaitForChild("MaterialKeys"))

-- Server siblings
local DataService = require(script.Parent.DataService)
local GridService = require(script.Parent.GridService)
local LootService = require(script.Parent.LootService)

-- Lazy-load UserMetricsService to avoid circular dependency
local UserMetricsService
local UpgradeService = require(script.Parent.UpgradeService)
local InventoryService = require(script.Parent.InventoryService)
local CubePositionService = require(script.Parent.CubePositionService)
local SoundBroadcast = require(script.Parent:WaitForChild("SoundBroadcast"))  -- ✅ Moved to top for performance

-- Shared remotes accessor
local Remotes = require(ReplicatedStorage.MiningGame.Remotes)

local DigService = {}

-- Track last dig times for rate limiting
local lastDigTime: {[number]: number} = {}
local digCooldowns: {[number]: number} = {}

-- Player cube references (exposed for debug reset)
local playerCubes: {[Player]: {origin: CFrame, model: Model}} = {}
DigService.playerCubes = playerCubes

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
    
    -- Load saved material preferences
    local materialPrefs = DataService:GetMaterialPrefs(player)
    local floorMaterial: Enum.Material? = nil
    if materialPrefs and materialPrefs.floorMaterial then
        local MaterialKeys = require(ReplicatedStorage.MiningGame:WaitForChild("MaterialKeys"))
        floorMaterial = MaterialKeys.EnumFromKey[string.lower(materialPrefs.floorMaterial)]
        print("[DigService] Loading saved floor material:", materialPrefs.floorMaterial, "->", tostring(floorMaterial))
    end
    
    -- Create or restore cube with saved floor material
    local model = GridService:RestoreCube(cubeOrigin, cubeState, floorMaterial)
    model.Parent = workspace
    
    -- Apply saved cube material if present
    if materialPrefs and materialPrefs.cubeMaterial then
        print("[DigService] Applying saved cube material:", materialPrefs.cubeMaterial)
        task.wait(0.1) -- Small delay to ensure cube is fully created
        local CubeMaterialService = require(script.Parent:WaitForChild("CubeMaterialService"))
        pcall(function()
            CubeMaterialService.ApplyCubeSurfaceMaterial(player, materialPrefs.cubeMaterial)
        end)
    end
    
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
    
    -- If cube isn't initialized yet, try to initialize it now
    if not cubeData and profile and cubeState then
        warn("[DigService] Cube not initialized for", player.Name, "- attempting late initialization")
        DigService:InitializePlayerCube(player)
        cubeData = playerCubes[player]
    end
    
    if not profile or not cubeState or not cubeData then
        warn("[DigService] Missing data - Profile:", profile ~= nil, "CubeState:", cubeState ~= nil, "CubeData:", cubeData ~= nil)
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
    
    -- Clamp cells to valid range (handles terrain texture overflow gracefully)
    local halfCells = (GameConfig.Grid.CUBE_SIZE_STUDS / GameConfig.Grid.CELL_SIZE_STUDS) / 2
    local function clampCell(n: number): number
        return math.clamp(n, -halfCells, halfCells - 1)
    end
    cellX = clampCell(cellX)
    cellY = clampCell(cellY)
    cellZ = clampCell(cellZ)
    
    -- No separate isInBounds check needed now; clamped values are valid
    
    -- Apply dig to grid
    local dugCells, soundHint = GridService:ApplyDig(
        player,
        cubeData.origin,
        cubeState,
        cellX,
        cellY,
        cellZ,
        effectiveStats.size
    )
    
    if #dugCells == 0 then
        return {
            ok = false,
            reason = "No cells dug",
        }
    end
    
    -- Broadcast mining sound based on actual terrain material
    -- Compute these OUTSIDE the do-end so we can return them
    local materialKey = (soundHint and soundHint.materialKey) or "rock"
    local soundPos = (soundHint and soundHint.worldPos)
    if not soundPos and #dugCells > 0 then
        local firstCell = dugCells[1]
        soundPos = GridMath.cellToWorld(firstCell.x, firstCell.y, firstCell.z, cubeData.origin, GameConfig.Grid.CELL_SIZE_STUDS)
    end
    
    -- Broadcast mining sound
    if #dugCells > 0 then
        SoundBroadcast.Mining(player, soundPos, materialKey, "hit")
    end
    
    -- Roll for loot
    local lootDrops = LootService:RollCells(
        profile.materialId,
        dugCells,
        profile.cubeSeed,
        effectiveStats.luck
    )
    
    -- Grant loot to inventory (aggregate counts for efficiency)
    local countsById = {}
    for _, drop in ipairs(lootDrops) do
        countsById[drop.id] = (countsById[drop.id] or 0) + 1
    end
    
    -- Add items in bulk (single operation, one save)
    local actuallyAdded = InventoryService:AddItemsBulk(player, countsById)
    
    -- Rebuild legacy flat list from actual adds (for backwards compat)
    local lootGranted = {}
    for itemId, count in pairs(actuallyAdded) do
        for i = 1, count do
            table.insert(lootGranted, itemId)
        end
    end
    
        -- Update statistics
        local wasFirstDig = profile.firstDigTime == nil
        profile.totalBlocksDug = profile.totalBlocksDug + #dugCells
        if profile.firstDigTime == nil then
            profile.firstDigTime = os.time()
        end
    
    -- Invalidate metrics cache for instant BPM updates
    if not UserMetricsService then
        UserMetricsService = require(script.Parent.UserMetricsService)
    end
    pcall(function() UserMetricsService:Invalidate(player) end)
    
    -- Update cooldown
    lastDigTime[userId] = now
    digCooldowns[userId] = effectiveStats.delay
    
    -- Queue save
    DataService:QueueSave(player)
    
    -- Send feedback to client (lightweight, no cell array)
    Remotes.RE.OnDigFeedback:FireClient(player, {
        size = effectiveStats.size,
        centerPos = GridMath.cellToWorld(cellX, cellY, cellZ, cubeData.origin, GameConfig.Grid.CELL_SIZE_STUDS),
        cellCount = #dugCells,  -- Just the count for telemetry
        shake = GameConfig.Digging.ENABLE_CAMERA_SHAKE,
        particles = GameConfig.Digging.ENABLE_PARTICLES,
        -- sound field removed: now handled by SoundBroadcast and local playback
    })
    
    -- Send batched loot notification (single network event for all drops)
    if next(actuallyAdded) ~= nil then
        Remotes.RE.OnLootDropped:FireClient(player, {
            counts = actuallyAdded,  -- Only what was actually added (respects caps)
            worldPos = GridMath.cellToWorld(cellX, cellY, cellZ, cubeData.origin, GameConfig.Grid.CELL_SIZE_STUDS),
            schema = 2,  -- Version flag for client compatibility
        })
    end
    
    -- Send visual poke for the center cell
    if #dugCells > 0 then
        local poke = dugCells[1]
        local worldCenter = GridMath.cellToWorld(poke.x, poke.y, poke.z, cubeData.origin, GameConfig.Grid.CELL_SIZE_STUDS)
        Remotes.RE.OnTerrainPoke:FireClient(player, { pos = worldCenter })
    end
    
    -- Fire first dig event if this was the player's first ever dig
    if wasFirstDig then
        Remotes.RE.OnFirstDig:FireClient(player, {
            timestamp = os.time(),
            totalBlocksDug = profile.totalBlocksDug,
        })
    end
    
    return {
        ok = true,
        cellsDug = #dugCells,
        lootGranted = lootGranted,    -- Legacy: flat array (rebuilt from actuallyAdded)
        lootCounts = actuallyAdded,    -- New: compact map (only what was actually added)
        nextAllowedAt = now + effectiveStats.delay,
        effectiveStats = effectiveStats,
        soundMaterialKey = materialKey,   -- ✅ new: exact material used by server
        soundWorldPos = soundPos,         -- ✅ new: exact position for sound
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
        
        -- Get player's cube origin (CFrame)
        local cubeOrigin = CubePositionService:GetOrigin(player)
        
        -- Inject session start time from SessionService
        local SessionService = require(script.Parent:WaitForChild("SessionService"))
        profile.sessionStartTime = SessionService.getSessionStartTime(player.UserId) or os.time()
        
        return {
            profile = profile,
            effectiveStats = effectiveStats,
            cubeStats = cubeStats,
            gamepasses = gamepasses,
            cubeOrigin = cubeOrigin,  -- Send CFrame directly
        }
    end
end

-- Handle player joining
local function onPlayerAdded(player)
    print("[DigService] Player added:", player.Name)
    
    -- Wait a frame for data to potentially load
    RunService.Heartbeat:Wait()
    
    spawn(function()
        -- Ensure data is loaded first
        if not DataService:EnsureLoaded(player) then
            warn("[DigService] Failed to ensure data loaded for", player.Name)
            -- Try again after a delay
            wait(1)
            DataService:EnsureLoaded(player)
        end
        
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
