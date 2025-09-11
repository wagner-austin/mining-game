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
local TerrainSurfaceDetector = require(Shared:WaitForChild("TerrainSurfaceDetector"))
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

-- Forward declare handlers (defined after Start)
local onPlayerAdded: (Player) -> ()
local onPlayerRemoving: (Player) -> ()

-- Shared remotes accessor
local Remotes = require(ReplicatedStorage.MiningGame.Remotes)

-- Event Bus for decoupled communication
local EventBus = require(Shared:WaitForChild("EventBus"))
local EventNames = require(Shared:WaitForChild("EventNames"))
local Bus = EventBus.global()
-- Mark fast-path for frequent dig feedback events
Bus:markFastPath(EventNames.DIG_FEEDBACK)

local DigService = {}
local log = Logger.new("DigService")

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
        local ok, p = ErrorService.safecall("Contracts.AUTO_DIG_START", function()
            return Contracts.AUTO_DIG_START(msg.payload)
        end)
        if ok and p.player then
            DigService:StartAutoDig(p.player)
        end
    end)
    
    Bus:on(EventNames.MEGA_DIG_REQUEST, function(msg)
        local ok, p = ErrorService.safecall("Contracts.MEGA_DIG_REQUEST", function()
            return Contracts.MEGA_DIG_REQUEST(msg.payload)
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
    
    log:info("Initialized with dependencies and event listeners")
end

-- Start method to connect player events after all services are initialized
function DigService:Start(container)
    -- Only cleanup - SpawnService handles all cube creation
    Players.PlayerRemoving:Connect(onPlayerRemoving)
    
    log:info("Started with player connections")
end

-- Track last dig times for rate limiting
local lastDigTime: {[number]: number} = {}
local digCooldowns: {[number]: number} = {}

-- Track continuous/hold dig states with version control for clean shutdown
local holdState: {[Player]: {active: boolean, target: Vector3, version: number}} = {}
local loopVersion: {[Player]: number} = {}

-- Track auto-dig states
local autoDigState: {[Player]: {active: boolean, version: number}} = {}
local autoDigVersion: {[Player]: number} = {}

-- Player cube references (exposed for debug reset)
local playerCubes: {[Player]: {origin: CFrame, model: Model}} = {}

DigService.playerCubes = playerCubes

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
        log:debug("Waiting for data to load for {}", player.Name)
        player:GetAttributeChangedSignal("DataLoaded"):Wait()
        log:debug("Data loaded signal received for {}", player.Name)
    end
    
    local profile = DataService:GetPlayerData(player)
    local cubeState = DataService:GetCubeData(player)
    
    log:debug("Profile: {}, CubeState: {}", profile and "exists" or "nil", cubeState and "exists" or "nil")
    
    if not profile or not cubeState then
        log:warn("No data for player {}", player.Name)
        return
    end
    
    -- Get cube position from service
    local cubeOrigin = CubePositionService:GetOrigin(player)
    
    -- Load saved material preferences
    local materialPrefs = DataService:GetMaterialPrefs(player)
    local floorMaterial: Enum.Material? = nil
    if materialPrefs and materialPrefs.floorMaterial then
        floorMaterial = MaterialKeys.EnumFromKey[string.lower(materialPrefs.floorMaterial)]
        log:debug("Loading saved floor material: {} -> {}", materialPrefs.floorMaterial, tostring(floorMaterial))
    end
    
    -- Create or restore cube with saved floor material
    -- GridService:RestoreCube already applies the theme if player has mode="composition"
    local model = GridService:RestoreCube(cubeOrigin, cubeState, floorMaterial)
    model.Parent = workspace
    
    -- Log what theme was applied
    if materialPrefs and materialPrefs.mode == "composition" then
        log:debug("Theme '{}' applied by RestoreCube for {}", 
            materialPrefs.activeThemeId or "underwater_cave", player.Name)
    end
    
    -- Store reference
    playerCubes[player] = {
        origin = cubeOrigin,
        model = model,
    }
    
    -- Notify client of cube origin
    Bus:emit(EventNames.CUBE_ORIGIN_CHANGED, {
        to = { kind = "player", player = player },
        payload = { origin = cubeOrigin }
    })
    
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
    
    log:info("Initialized cube for {} @ {}", player.Name, tostring(cubeOrigin.Position))
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
    log:info("DigService:SetPlayerOrigin %s -> %s", player.Name, tostring(origin.Position))
end

-- Helper to check if a world position is inside a cube
local function isInsideCube(worldPos: Vector3, cubeOrigin: CFrame, cubeSize: number): boolean
    local localPos = cubeOrigin:PointToObjectSpace(worldPos)
    local h = cubeSize * 0.5
    return math.abs(localPos.X) <= h and math.abs(localPos.Y) <= h and math.abs(localPos.Z) <= h
end

--[[
    Validate that a dig request targets exposed, diggable terrain.
    Defense-in-depth against spoofed requests.
    
    @param player - The player making the request
    @param worldPos - The requested dig position
    @return boolean - True if the dig is valid
]]
local function isValidDig(player: Player, worldPos: Vector3): boolean
    local cubeData = playerCubes[player]
    if not cubeData then return false end
    
    -- Must be inside cube bounds (with tolerance)
    local tolerance = 2.5
    local localPos = cubeData.origin:PointToObjectSpace(worldPos)
    local h = GameConfig.Grid.CUBE_SIZE_STUDS * 0.5
    if math.abs(localPos.X) > (h + tolerance) or
       math.abs(localPos.Y) > (h + tolerance) or
       math.abs(localPos.Z) > (h + tolerance) then
        return false
    end
    
    -- Check if the position has exposed, diggable terrain (no extra debug reads)
    local CELL = GameConfig.Grid.CELL_SIZE_STUDS
    local hasSurface, _checkType = TerrainSurfaceDetector.CheckCellSurface(worldPos, CELL)
    return hasSurface == true
end

--[[
    Snaps a world position to inside the cube if it's within tolerance.
    
    Terrain rendering in Roblox extends beyond voxel boundaries, causing legitimate
    clicks to appear outside the mathematical cube bounds. This function handles
    those cases while maintaining security.
    
    @param worldPos - The world position to check (usually from a raycast)
    @param cubeOrigin - The CFrame origin of the player's cube
    @param cubeSize - The size of the cube in studs (typically 128)
    @param faceEps - Tolerance for face clicks (terrain extends ~2.5 studs)
    @param edgeEps - Tolerance for edge clicks (slightly less extension)
    @param cornerEps - Tolerance for corner clicks (minimal extension)
    
    @return success: boolean - Whether the position is acceptable
    @return adjustedPos: Vector3 - The snapped position if successful, original if not
]]
local function snapInsideIfNearCube(worldPos: Vector3, cubeOrigin: CFrame, cubeSize: number, 
                                    faceEps: number, edgeEps: number, cornerEps: number)
    -- Use ONLY position for bounds check - terrain cube is axis-aligned, not rotated!
    local cubeCenter = cubeOrigin.Position
    local localPos = worldPos - cubeCenter  -- Simple offset, no rotation
    local h = cubeSize * 0.5
    
    -- Calculate how much we're outside on each axis
    local function over(v) return MathUtils.nonNegative(math.abs(v) - h) end
    local ox, oy, oz = over(localPos.X), over(localPos.Y), over(localPos.Z)
    
    log:debug("SNAP CHECK: local=%s, h=%d, over=(%.2f,%.2f,%.2f)", tostring(localPos), h, ox, oy, oz)
    
    -- Count how many axes we're outside on
    local outsideAxes = (ox > 0 and 1 or 0) + (oy > 0 and 1 or 0) + (oz > 0 and 1 or 0)
    local maxOver = math.max(ox, oy, oz)
    
    if outsideAxes == 0 then
        return true, worldPos -- already inside
    end
    
    -- Check if we're within tolerance based on how many axes we're outside
    local allow = false
    local snapType = ""
    
    if outsideAxes == 1 and maxOver <= faceEps then
        allow = true
        snapType = "face"
    elseif outsideAxes == 2 and maxOver <= edgeEps then
        allow = true
        snapType = "edge"
    elseif outsideAxes == 3 and maxOver <= cornerEps then
        allow = true
        snapType = "corner"
    end
    
    if allow then
        -- Clamp to just inside the cube
        local tiny = 1e-3
        localPos = Vector3.new(
            math.clamp(localPos.X, -h + tiny, h - tiny),
            math.clamp(localPos.Y, -h + tiny, h - tiny),
            math.clamp(localPos.Z, -h + tiny, h - tiny)
        )
        
        log:debug("Snapped from outside {} ({}), overhang: X={}, Y={}, Z={}", 
            snapType, outsideAxes, ox, oy, oz)
        
        -- Convert back to world space (no rotation, just add position)
        return true, cubeCenter + localPos
    end
    
    return false, worldPos -- rejected: too far outside
end

--[[
    Process a dig request from a client at the specified world position.
    Validates the position, checks cooldowns, destroys terrain, and grants loot.
    
    @param player: Player - The player making the dig request
    @param worldPos: Vector3 - The world position to dig at
    @return Types.DigResult - Result containing success status, loot, and next allowed time
]]
function DigService:ProcessDigRequest(player: Player, worldPos: Vector3): Types.DigResult
    local userId = player.UserId
    local now = Time.mono()
    
    -- Get player data
    local profile = DataService:GetPlayerData(player)
    local cubeState = DataService:GetCubeData(player)
    local cubeData = playerCubes[player]
    
    -- Late init removed; owner is SpawnService
    
    if not profile or not cubeState or not cubeData then
        log:error("Missing data - Profile: {}, CubeState: {}, CubeData: {}", profile ~= nil, cubeState ~= nil, cubeData ~= nil)
        return {
            ok = false,
            reason = "No cube data",
        }
    end
    
    -- Use STORED origin, don't recalculate
    local storedOrigin = cubeData.origin
    
    -- Check if the click is inside or near the player's own cube
    -- Use tolerances to account for terrain mesh extending beyond voxel boundaries
    local cellSize = GameConfig.Grid.CELL_SIZE_STUDS
    local faceEps = 2.5  -- Terrain can extend ~2 studs on faces
    local edgeEps = math.max(2.0, cellSize * 0.45)  -- Slightly less for edges
    local cornerEps = math.max(1.5, cellSize * 0.35)  -- Even less for corners
    
    log:debug("Tolerance - Face: %.1f, Edge: %.1f, Corner: %.1f", faceEps, edgeEps, cornerEps)
    
    local okNear, adjustedWorldPos = snapInsideIfNearCube(worldPos, cubeData.origin, GameConfig.Grid.CUBE_SIZE_STUDS, 
                                                          faceEps, edgeEps, cornerEps)
    
    log:debug("Snap result: %s, Adjusted=%s", tostring(okNear), tostring(adjustedWorldPos))
    
    if not okNear then
        -- Calculate how far outside we are for debugging
        local cubeCenter = cubeData.origin.Position
        local localPos = worldPos - cubeCenter  -- No rotation, axis-aligned check
        local h = GameConfig.Grid.CUBE_SIZE_STUDS * 0.5
        local dx = MathUtils.nonNegative(math.abs(localPos.X) - h)
        local dy = MathUtils.nonNegative(math.abs(localPos.Y) - h)
        local dz = MathUtils.nonNegative(math.abs(localPos.Z) - h)
        
        log:error("DIG REJECTED - OUTSIDE CUBE:")
        log:error("  Outside by X=%.2f, Y=%.2f, Z=%.2f", dx, dy, dz)
        log:error("  Player=%s", player.Name)
        
        return {
            ok = false,
            reason = "Outside your cube",
        }
    end
    
    -- Use the adjusted position for all subsequent calculations
    worldPos = adjustedWorldPos
    
    -- Server-side validation: ensure this is actually exposed terrain
    if not isValidDig(player, worldPos) then
        log:error("DIG REJECTED - INVALID TERRAIN:")
        log:error("  World pos: %s", tostring(worldPos))
        log:error("  Adjusted pos: %s", tostring(adjustedWorldPos))
        log:error("  Player: %s", player.Name)
        log:error("  Reason: Not exposed/diggable terrain at this position")
        return {
            ok = false,
            reason = "Invalid terrain",
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
    
    -- Store the actual clamped cell we're digging
    local centerCell = {x = cellX, y = cellY, z = cellZ}
    
    -- No separate isInBounds check needed now; clamped values are valid
    
    -- Apply dig to grid
    log:debug("Applying dig: player={}, cellPos=({},{},{}), size={}", 
        player.Name, cellX, cellY, cellZ, effectiveStats.size)
    
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
            centerCell = centerCell,  -- Still return the cell position for stepping
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
    
    -- Get composition info for loot modifiers
    local ownerId = cubeState.ownerId
    local ownerPlayer = game:GetService("Players"):GetPlayerByUserId(ownerId)
    local prefs = ownerPlayer and DataService:GetMaterialPrefs(ownerPlayer) or {}
    -- Always use composition mode now
    local activeCompId = prefs.activeThemeId or "underwater_cave"
    
    -- Roll for loot with composition modifiers
    local lootDrops = LootService:RollCells(
        profile.materialId,
        dugCells,
        profile.cubeSeed,
        effectiveStats.luck,
        {
            miner = player,
            ownerId = ownerId,
            materialKey = materialKey,
            compositionId = activeCompId,
        }
    )
    
    -- Build a summary for the UI toast (but we now spawn per cell)
    local countsById = {}
    for _, drop in ipairs(lootDrops) do
        if drop and drop.id then
            countsById[drop.id] = (countsById[drop.id] or 0) + 1
        else
            log:warn("Loot drop missing id; drop=%s", tostring(drop))
        end
    end
    
    -- Defer 1 tick so Terrain WriteVoxels completes visually
    task.defer(function()
        -- Spawn each drop at its own cell center
        local spawned = 0
        for _, drop in ipairs(lootDrops) do
            -- Safety check: ensure drop has required id field
            if drop and drop.id then
                local cx, cy, cz = drop.cellX, drop.cellY, drop.cellZ
                local spawnPos
                
                if cx and cy and cz then
                    spawnPos = GridMath.cellToWorld(cx, cy, cz, cubeData.origin, GameConfig.Grid.CELL_SIZE_STUDS)
                else
                    -- Fallback: use dig center if cell coords missing (backward compatibility)
                    spawnPos = soundPos or GridMath.cellToWorld(cellX, cellY, cellZ, cubeData.origin, GameConfig.Grid.CELL_SIZE_STUDS)
                end
                
                -- One per voxel; no sideways jitter that might re-enter rock
                ItemService:SpawnStackedDrop(drop.id, 1, spawnPos, player)
                spawned = spawned + 1
            else
                log:warn("Skipping malformed drop in spawn loop: %s", tostring(drop))
            end
        end
        
        -- Log per-cell spawn results
        log:debug("Per-cell spawn complete: %d items across %d cells (mat=%s, size=%d)",
            spawned, #dugCells, profile.materialId, effectiveStats.size)
        
        -- Optional: toast summarizing what dropped this dig (not yet collected)
        if next(countsById) then
            Bus:emit(EventNames.LOOT_DROPPED, {
                to = { kind = "player", player = player },
                payload = {
                    counts = countsById,
                    position = soundPos,
                    schema = 4,           -- schema bump to indicate per-cell spawn
                    mode = "per_cell",    -- UI can show a "collect near you" note
                }
            })
        end
    end)
    
        -- Update statistics
        local wasFirstDig = profile.firstDigTime == nil
        profile.totalBlocksDug = profile.totalBlocksDug + #dugCells
        if profile.firstDigTime == nil then
            profile.firstDigTime = math.floor(Time.unix())
        end
    
        -- Log dig event for analytics
        log:event("dig_performed", {
            uid = player.UserId,
            cellsDug = #dugCells,
            lootDropped = #lootDrops,
            materialId = profile.materialId,
            size = effectiveStats.size,
            luck = effectiveStats.luck,
            delay = effectiveStats.delay
        })
    
    -- Invalidate metrics cache for instant BPM updates
    if UserMetricsService then
        ErrorService.safecall("UserMetricsService:Invalidate(dig)", function()
            UserMetricsService:Invalidate(player, "dig")
        end, { uid = player.UserId })
    end
    
    -- Update cooldown
    lastDigTime[userId] = now
    digCooldowns[userId] = effectiveStats.delay
    
    -- Update UI cooldown display via CharacterStateManager
    if CharacterStateManager then
        CharacterStateManager:SetNextDigAllowedAt(player, now + effectiveStats.delay)
    end
    
    -- Queue save
    DataService:QueueSave(player)
    
    -- Send feedback to client (lightweight, no cell array)
    Bus:emit(EventNames.DIG_FEEDBACK, {
        to = { kind = "player", player = player },
        payload = {
            size = effectiveStats.size,
            centerPos = GridMath.cellToWorld(cellX, cellY, cellZ, cubeData.origin, GameConfig.Grid.CELL_SIZE_STUDS),
            cellCount = #dugCells,  -- Just the count for telemetry
            shake = GameConfig.Digging.ENABLE_CAMERA_SHAKE,
            particles = GameConfig.Digging.ENABLE_PARTICLES,
            -- sound field removed: now handled by SoundBroadcast and local playback
        }
    })
    
    -- Loot notification is now handled in the spawn drops section above
    
    -- Send visual poke for the center cell (disabled)
    -- if #dugCells > 0 then
    --     local poke = dugCells[1]
    --     local worldCenter = GridMath.cellToWorld(poke.x, poke.y, poke.z, cubeData.origin, GameConfig.Grid.CELL_SIZE_STUDS)
    --     Remotes.RE.OnTerrainPoke:FireClient(player, { pos = worldCenter })
    -- end
    
    -- Fire first dig event if this was the player's first ever dig
    if wasFirstDig then
        log:event("first_dig", {
            uid = player.UserId,
            timestamp = math.floor(Time.unix()),
            totalBlocksDug = profile.totalBlocksDug
        })
        Bus:emit(EventNames.ACHIEVEMENT_UNLOCKED, {
            to = { kind = "player", player = player },
            payload = {
                id = "first_dig",
                timestamp = math.floor(Time.unix()),
                totalBlocksDug = profile.totalBlocksDug,
            }
        })
        -- Record achievement for first dig
        AchievementService.RecordFirstDig(player)
    end
    
    -- Check block milestones
    AchievementService.RecordBlocksDug(player, #dugCells)
    
    return {
        ok = true,
        cellsDug = #dugCells,
        lootGranted = {},              -- Legacy: empty (items not granted until pickup)
        lootCounts = countsById or {},  -- Return what was dropped (not collected yet)
        nextAllowedAt = now + effectiveStats.delay,
        effectiveStats = effectiveStats,
        soundMaterialKey = materialKey,
        soundWorldPos = soundPos,
        centerCell = centerCell,        -- The actual cell coordinates we dug (after clamping)
    }
end

--[[
    Internal continuous dig loop that handles drilling down.
    Uses version tokens for cooperative shutdown.
]]
local function runHoldLoop(self, player: Player)
    loopVersion[player] = (loopVersion[player] or 0) + 1
    local myVer = loopVersion[player]
    local iterationCount = 0
    
    
    while holdState[player] and holdState[player].active and myVer == loopVersion[player] and player.Parent do
        iterationCount = iterationCount + 1
        local target = holdState[player].target
        
        
        local result = self:ProcessDigRequest(player, target)
        
        
        local sleepSec = GameConfig.Timing.AUTO_DIG_INITIAL_DELAY
        
        if result and result.ok then
            -- Success! Step one cell deeper in cube space for drilling effect
            local cube = self.playerCubes[player]
            if cube then
                -- Use the actual cell the server dug (after clamping)
                local baseX, baseY, baseZ
                if result.centerCell then
                    baseX = result.centerCell.x
                    baseY = result.centerCell.y
                    baseZ = result.centerCell.z
                else
                    -- Fallback if centerCell not available (shouldn't happen)
                    local cx, cy, cz = GridMath.worldToCell(target, cube.origin, GameConfig.Grid.CELL_SIZE_STUDS)
                    baseX, baseY, baseZ = cx, cy, cz
                end
                
                local nextY = baseY - 1 -- Go one cell deeper
                
                -- Check if we're still within bounds
                local halfCells = (GameConfig.Grid.CUBE_SIZE_STUDS / GameConfig.Grid.CELL_SIZE_STUDS) / 2
                
                if nextY >= -halfCells then
                    holdState[player].target = GridMath.cellToWorld(baseX, nextY, baseZ, cube.origin, GameConfig.Grid.CELL_SIZE_STUDS)
                    -- Use the server's exact next allowed time
                    sleepSec = (result.nextAllowedAt and math.max(result.nextAllowedAt - Time.mono(), 0)) or (digCooldowns[player.UserId] or GameConfig.Timing.AUTO_DIG_DEFAULT_INTERVAL)
                else
                    -- Hit bottom, stop digging
                    break
                end
            else
                -- Cube not ready yet (e.g., after respawn), wait briefly
                sleepSec = GameConfig.Timing.AUTO_DIG_DEFAULT_INTERVAL
            end
            
        elseif result and result.reason == "On cooldown" then
            -- Just wait for cooldown, don't stop
            sleepSec = math.max((result.nextAllowedAt or Time.mono()) - Time.mono(), 0.05)
            
        elseif result and result.reason == "No cells dug" then
            -- Already empty, try stepping deeper anyway
            local cube = self.playerCubes[player]
            if cube then
                -- Use the actual cell position from the server
                local baseX, baseY, baseZ
                if result.centerCell then
                    baseX = result.centerCell.x
                    baseY = result.centerCell.y
                    baseZ = result.centerCell.z
                else
                    -- Fallback if centerCell not available
                    local cx, cy, cz = GridMath.worldToCell(target, cube.origin, GameConfig.Grid.CELL_SIZE_STUDS)
                    baseX, baseY, baseZ = cx, cy, cz
                end
                
                local nextY = baseY - 1 -- Go one cell deeper
                
                local halfCells = (GameConfig.Grid.CUBE_SIZE_STUDS / GameConfig.Grid.CELL_SIZE_STUDS) / 2
                
                if nextY >= -halfCells then
                    holdState[player].target = GridMath.cellToWorld(baseX, nextY, baseZ, cube.origin, GameConfig.Grid.CELL_SIZE_STUDS)
                    sleepSec = 0.05 -- Quick retry at new position
                else
                    -- Hit bottom on an empty layer; stop
                    break
                end
            else
                -- Cube not ready, wait briefly
                sleepSec = 0.2
            end
            -- Don't fall through to the else clause!
            
        elseif result and result.reason then
            -- Hard error (outside cube, no profile, etc) - stop
            log:debug("Hold dig stopped for {}: {}", player.Name, result and result.reason or "unknown")
            break
        end
        
        task.wait(math.max(sleepSec, 0.05))
    end
    
    -- Loop ended
    
    log:info("Hold loop ended for {} after {} iterations. holdState.active={}, versionMatch={}, player.Parent={}", 
        player.Name, 
        iterationCount,
        tostring(holdState[player] and holdState[player].active),
        tostring(holdState[player] and holdState[player].version == myVer),
        tostring(player.Parent ~= nil))
    
    -- Cleanup
    if holdState[player] and holdState[player].version == myVer then
        holdState[player] = nil
    end
end

--[[
    Start continuous digging at a position. Will drill downward automatically.
]]
function DigService:StartHoldDig(player: Player, initialWorldPos: Vector3)
    self:StopHoldDig(player) -- Stop any existing hold
    
    holdState[player] = {
        active = true,
        target = initialWorldPos,
        version = (loopVersion[player] or 0) + 1
    }
    
    log:debug("Starting hold dig for {} at {}", player.Name, tostring(initialWorldPos))
    task.spawn(function() runHoldLoop(self, player) end)
end

--[[
    Update the target position for an active hold dig.
]]
function DigService:UpdateHoldDigTarget(player: Player, worldPos: Vector3)
    if holdState[player] then
        holdState[player].target = worldPos
    end
end

--[[
    Stop continuous digging for a player.
]]
function DigService:StopHoldDig(player: Player)
    if holdState[player] then
        log:debug("Stopping hold dig for {}", player.Name)
        holdState[player].active = false
    end
    loopVersion[player] = (loopVersion[player] or 0) + 1
end

--[[
    Internal auto-dig loop for monetization.
]]
local function runAutoDigLoop(self, player: Player)
    autoDigVersion[player] = (autoDigVersion[player] or 0) + 1
    local myVer = autoDigVersion[player]
    
    while autoDigState[player] and autoDigState[player].active and myVer == autoDigVersion[player] and player.Parent do
        local profile = DataService:GetPlayerData(player)
        
        -- Check if auto-dig boost is still active
        if not profile or not profile.boosts or not profile.boosts.auto_dig or Time.unix() >= profile.boosts.auto_dig then
            log:debug("Auto-dig expired for {}", player.Name)
            break
        end
        
        -- Get player position for auto-dig
        local character = player.Character
        if character then
            local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
            if humanoidRootPart then
                -- Dig below player
                local digPos = humanoidRootPart.Position - Vector3.new(0, 5, 0)
                local result = self:ProcessDigRequest(player, digPos)
                
                -- Wait based on result
                local sleepSec = 1.0
                if result and result.nextAllowedAt then
                    sleepSec = math.max(result.nextAllowedAt - Time.mono(), 0.5)
                else
                    sleepSec = digCooldowns[player.UserId] or 1.0
                end
                
                task.wait(math.max(sleepSec, 0.5)) -- At least 0.5s between auto-digs
            else
                task.wait(1) -- No HRP, wait before retry
            end
        else
            task.wait(1) -- No character, wait before retry
        end
    end
    
    -- Cleanup
    if autoDigState[player] and autoDigState[player].version == myVer then
        autoDigState[player] = nil
    end
    
    log:info("Auto-dig stopped for {}", player.Name)
end

--[[
    Start auto-digging for a player (requires active boost).
]]
function DigService:StartAutoDig(player: Player)
    local profile = DataService:GetPlayerData(player)
    if not profile then 
        log:warn("Cannot start auto-dig: no profile for {}", player.Name)
        return false 
    end
    
    -- Check if they have auto-dig boost active
    if not profile.boosts or not profile.boosts.auto_dig or Time.unix() >= profile.boosts.auto_dig then
        log:debug("Cannot start auto-dig: no active boost for {}", player.Name)
        return false
    end
    
    self:StopAutoDig(player) -- Stop any existing auto-dig
    
    autoDigState[player] = {
        active = true,
        version = (autoDigVersion[player] or 0) + 1
    }
    
    log:info("Starting auto-dig for {} (expires at {})", player.Name, profile.boosts.auto_dig)
    task.spawn(function() runAutoDigLoop(self, player) end)
    
    return true
end

--[[
    Stop auto-digging for a player.
]]
function DigService:StopAutoDig(player: Player)
    if autoDigState[player] then
        log:debug("Stopping auto-dig for {}", player.Name)
        autoDigState[player].active = false
    end
    autoDigVersion[player] = (autoDigVersion[player] or 0) + 1
end

-- Remote handlers moved to RemoteFns/Dig.rf.lua via RFRegistry

-- Player connection handlers (cleanup only - SpawnService handles initialization)

-- Handle player leaving (called from Start method after dependencies are ready)
onPlayerRemoving = function(player: Player)
    log:debug("Player {} leaving, cleaning up cube", player.Name)
    
    -- Stop any active digging
    DigService:StopHoldDig(player)
    DigService:StopAutoDig(player)
    
    -- Clean up cube
    local cubeData = playerCubes[player]
    if cubeData and cubeData.model then
        cubeData.model:Destroy()
    end
    
    -- Clean up references
    playerCubes[player] = nil
    lastDigTime[player.UserId] = nil
    digCooldowns[player.UserId] = nil
    holdState[player] = nil
    autoDigState[player] = nil
    loopVersion[player] = nil
    autoDigVersion[player] = nil
end

-- Initialize (remotes now handled by DigServiceRemotes.lua)
-- Remotes handled via RemoteManager and RFRegistry

log:info("Initialized")

return DigService
