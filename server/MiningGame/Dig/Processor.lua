--!strict
-- Dig/Processor.lua
-- Implements the dig request flow with explicit DI via service._container.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(Shared:WaitForChild("Logger"))
local EventBus = require(Shared:WaitForChild("EventBus"))
local EventNames = require(Shared:WaitForChild("EventNames"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local GridMath = require(Shared:WaitForChild("Utils"):WaitForChild("GridMath"))
local Time = require(Shared:WaitForChild("Time"))
local MathUtils = require(Shared:WaitForChild("MathUtils"))
local MaterialKeys = require(Shared:WaitForChild("MaterialKeys"))
local MaterialDefinitions = require(Shared:WaitForChild("MaterialDefinitions"))
local SoundCategories = require(Shared:WaitForChild("SoundCategories"))
local Snapper = require(script.Parent:WaitForChild("Snapper"))
local Picker = require(script.Parent:WaitForChild("Picker"))
local VolumeRegistry = require(script.Parent:WaitForChild("VolumeRegistry"))
local SurfaceSolver = require(script.Parent:WaitForChild("SurfaceSolver"))

local log = Logger.new("DigProcessor")
local Telemetry = require(script.Parent:WaitForChild("Telemetry"))

local Processor = {}

function Processor.Process(service, player: Player, worldPos: Vector3)
    local container = service._container
    local DataService = container:Get("DataService")
    local UpgradeService = container:Get("UpgradeService")
    local GridService = container:Get("GridService")
    local LootService = container:Get("LootService")
    local ItemService = container:Get("ItemService")

    local userId = player.UserId
    -- Use high-resolution monotonic time for server-side gating
    local now = Time.mono()
    log:debug("ProcessDig START:\n  Player: %s\n  Input Position: %s", player.Name, tostring(worldPos))

    -- Profile/cube data
    local profile = DataService:GetPlayerData(player)
    local cubeState = DataService:GetCubeData(player)
    local cubeData = service.playerCubes[player]
    if not profile or not cubeState or not cubeData then
        log:error("Missing data - Profile: {}, CubeState: {}, CubeData: {}", profile ~= nil, cubeState ~= nil, cubeData ~= nil)
        return { ok = false, reason = "No cube data" }
    end

    -- Anti-cheat range check will be performed after snap to use adjusted position

    -- Pick volume (cube preferred), then snap inside
    local pickedVol = service:PickVolume(worldPos, player)
    local volOrigin: CFrame
    local volSizeHalf: Vector3
    local volState
    local isCube = false
    if pickedVol and pickedVol.origin and pickedVol.sizeStuds then
        volOrigin = pickedVol.origin
        volSizeHalf = pickedVol.sizeStuds * 0.5
        volState = pickedVol.state
        isCube = pickedVol.kind == "cube"
        if isCube then Telemetry.pickCube(pickedVol.id) else Telemetry.pickIsland(pickedVol.id) end
    else
        volOrigin = cubeData.origin
        volSizeHalf = Vector3.new(GameConfig.Grid.CUBE_SIZE_STUDS, GameConfig.Grid.CUBE_SIZE_STUDS, GameConfig.Grid.CUBE_SIZE_STUDS) * 0.5
        volState = cubeState
        isCube = true
        Telemetry.pickFallback("cube:" .. tostring(player.UserId))
    end

    local cellSize = GameConfig.Grid.CELL_SIZE_STUDS
    local faceEps = math.max(3.0, cellSize * GameConfig.Digging.VOLUME_CLAMP_FACE_TOLERANCE)
    local edgeEps = math.max(2.0, cellSize * GameConfig.Digging.VOLUME_EDGE_TOLERANCE)
    local cornerEps = math.max(1.5, cellSize * GameConfig.Digging.VOLUME_CORNER_TOLERANCE)

    local originalPos = worldPos
    local okNear, adjustedWorldPos = Snapper.snapInsideIfNearAABB(worldPos, volOrigin, volSizeHalf, faceEps, edgeEps, cornerEps)
    if not okNear and isCube then
        local altVol = Picker.pickIsland(worldPos, VolumeRegistry.GetVolumes(), VolumeRegistry.GetHash())
        if altVol then
            volOrigin = altVol.origin
            volSizeHalf = altVol.sizeStuds * 0.5
            volState = altVol.state
            isCube = false
            local ok2
            ok2, adjustedWorldPos = Snapper.snapInsideIfNearAABB(worldPos, volOrigin, volSizeHalf, faceEps, edgeEps, cornerEps)
            okNear = ok2
        end
    end
    if not okNear then
        local reason = isCube and "Outside your cube" or "Outside mineable volume"
        Telemetry.reject(isCube and "outside_cube" or "outside_volume", reason)
        return { ok = false, reason = reason }
    end

    -- Anti-cheat range check (post-snap) using adjusted position; require HRP present
    do
        local maxRange = GameConfig.Digging.MAX_RANGE_STUDS
        if maxRange and maxRange > 0 then
            local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            if not hrp then
                return { ok = false, reason = "Character not available" }
            end
            local dist = (adjustedWorldPos - (hrp :: BasePart).Position).Magnitude
            if dist > maxRange then
                log:error("DIG REJECTED - OUT OF RANGE: player=%s dist=%.1f limit=%.1f pos=%s hrp=%s",
                    player.Name, dist, maxRange, tostring(adjustedWorldPos), tostring((hrp :: BasePart).Position))
                service.ResetTelemetry()
                return { ok = false, reason = "Out of range" }
            end
        end
    end

    -- Surface validation (for cubes); for islands we'll reliably pick a face by geometry
    local hasSurface, surfacePos, surfaceNormal = SurfaceSolver.find(originalPos, adjustedWorldPos, cellSize)

    -- Effective stats and cooldowns
    local gamepasses = UpgradeService:GetPlayerGamepasses(player)
    local activePets = UpgradeService:GetActivePets(profile)
    local effectiveStats = UpgradeService:ComputeEffectiveStats(profile, gamepasses, activePets)

    local lastDigTime = service._lastDigTime or {}
    service._lastDigTime = lastDigTime
    local digCooldowns = service._digCooldowns or {}
    service._digCooldowns = digCooldowns
    local lastDig = lastDigTime[userId] or 0
    local cooldown = digCooldowns[userId] or effectiveStats.delay
    if now - lastDig < cooldown then
        local nextAt = lastDig + cooldown
        return { ok = false, reason = "On cooldown", nextAllowedAt = nextAt, cooldownSec = math.max(0, nextAt - now) }
    end

    -- Compute cell and clamp (use adjusted snapped position to align dig with picked volume)
    local cellX, cellY, cellZ = GridMath.worldToCell(adjustedWorldPos, volOrigin, cellSize)
    local cellCenterWorld = GridMath.cellToWorld(cellX, cellY, cellZ, volOrigin, cellSize)
    -- Use the volume's actual extents, not hardcoded cube size
    local halfCellsX, halfCellsY, halfCellsZ
    if volState and volState.extentsCells then
        halfCellsX = volState.extentsCells.X
        halfCellsY = volState.extentsCells.Y
        halfCellsZ = volState.extentsCells.Z
    else
        local fallback = (GameConfig.Grid.CUBE_SIZE_STUDS / cellSize) / 2
        halfCellsX, halfCellsY, halfCellsZ = fallback, fallback, fallback
    end
    cellX = math.clamp(cellX, -halfCellsX, halfCellsX - 1)
    cellY = math.clamp(cellY, -halfCellsY, halfCellsY - 1)
    cellZ = math.clamp(cellZ, -halfCellsZ, halfCellsZ - 1)
    local centerCell = {x = cellX, y = cellY, z = cellZ}

    -- Use the same cube dig shape for both cubes and islands
    local digOptions = nil

    -- Optional island diagnostics
    if (not isCube) and GameConfig.Digging.DEBUG_ISLAND_DIAG then
        local halfCells = (GameConfig.Grid.CUBE_SIZE_STUDS / cellSize) / 2
        if volState and volState.extentsCells then
            halfCells = math.floor(volState.extentsCells.Y)
        end
        local minX, maxX = -halfCells, halfCells - 1
        local minY, maxY = -halfCells, halfCells - 1
        local minZ, maxZ = -halfCells, halfCells - 1
        log:debug("[IslandDiag] volOrigin=%s size=%s halfCells=%d",
            tostring(volOrigin.Position), tostring(volSizeHalf*2), halfCells)
        log:debug("[IslandDiag] click orig=%s snapped=%s cell=%d,%d,%d bounds=[%d..%d,%d..%d,%d..%d]",
            tostring(originalPos), tostring(adjustedWorldPos), cellX, cellY, cellZ,
            minX, maxX, minY, maxY, minZ, maxZ)
    end

    local dugCells, soundHint = GridService:ApplyDig(
        player,
        volOrigin,
        volState,
        cellX, cellY, cellZ,
        effectiveStats.size,
        digOptions
    )
    if #dugCells == 0 then
        return { ok = false, reason = "No cells dug", centerCell = centerCell }
    end

    -- Roll and spawn loot (delegate to ItemService to avoid duplication)
    local countsById = {}
    do
        local themeId = (pickedVol and pickedVol.meta and pickedVol.meta.themeId) or nil
        local terrainKey = soundHint and soundHint.materialKey or nil
        local compositionInfo = { miner = player, ownerId = volState.ownerId, compositionId = themeId, terrainKey = terrainKey }
        local drops = LootService:RollCells(volState.materialId, dugCells, player.UserId, effectiveStats.luck, compositionInfo)

        -- Aggregate counts and build entries with world positions
        local entries = {}
        for _, d in ipairs(drops) do
            countsById[d.id] = (countsById[d.id] or 0) + 1
            local cx, cy, cz = d.cellX or cellX, d.cellY or cellY, d.cellZ or cellZ
            local pos = GridMath.cellToWorld(cx, cy, cz, volOrigin, cellSize)
            table.insert(entries, { itemId = d.id, position = pos })
        end

        if #entries > 0 then
            ItemService:SpawnLootEntriesFromDig(entries, player)
        end
    end

    -- Success; update times and compose result
    lastDigTime[userId] = now
    local materialKey = (soundHint and soundHint.materialKey) or "rock"
    -- Anchor SFX at the center of the dig
    local soundPos = cellCenterWorld

    -- Choose a mining subtype server-side so all clients hear the same variant
    local chosenSubtype = "hit"
    do
        local def = MaterialDefinitions.Materials[materialKey]
        local category = (def and def.properties and def.properties.soundCategory) or "rock"
        local events = SoundCategories.GetMiningEvents(category)
        local r = (Random.new() :: Random):NextNumber()
        if #events >= 3 then
            if r < 0.7 then chosenSubtype = events[1]
            elseif r < 0.9 then chosenSubtype = events[2]
            else chosenSubtype = events[3] end
        elseif #events == 2 then
            chosenSubtype = (r < 0.75) and events[1] or events[2]
        elseif #events == 1 then
            chosenSubtype = events[1]
        end
    end

    -- Broadcast mining sound to nearby players as local (2D) audio (no position in payload)
    pcall(function()
        local SoundBroadcast = require(script.Parent.Parent.SoundBroadcast)
        SoundBroadcast.MiningLocal(player, soundPos, materialKey, chosenSubtype)
    end)
    -- Reflect cooldown timestamp (server wall time) so UI can read Char_NextDigAllowedAt
    pcall(function()
        local CSM = container:Get("CharacterStateManager")
        if CSM and type(CSM.SetNextDigAllowedAt) == "function" then
            CSM:SetNextDigAllowedAt(player, Time.unix() + effectiveStats.delay)
        end
    end)

    Telemetry.success()
    local nextAtMono = now + effectiveStats.delay
    -- Emit dig feedback event for listeners (UI, analytics). Keep payload stable for clients.
    pcall(function()
        EventBus.global():emit(EventNames.DIG_FEEDBACK, {
            to = { kind = "player", player = player },
            payload = {
                size = effectiveStats.size,
                cellCount = #dugCells,
                centerPos = soundPos,
                shake = (GameConfig.Digging and GameConfig.Digging.ENABLE_CAMERA_SHAKE) ~= false,
                particles = (GameConfig.Digging and GameConfig.Digging.ENABLE_PARTICLES) ~= false,
                cooldownSec = effectiveStats.delay,
            }
        })
    end)
    return {
        ok = true,
        cellsDug = #dugCells,
        lootGranted = {},
        lootCounts = countsById,
        nextAllowedAt = nextAtMono,
        cooldownSec = effectiveStats.delay,
        effectiveStats = effectiveStats,
        soundMaterialKey = materialKey,
        soundWorldPos = soundPos,
        soundSubtype = chosenSubtype,
        centerCell = centerCell,
        volumeId = pickedVol and pickedVol.id or ("cube:" .. tostring(player.UserId)),
        volumeOrigin = volOrigin,
    }
end

return Processor
