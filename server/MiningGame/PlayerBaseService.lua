--!strict
-- PlayerBaseService.lua
-- Creates an axis-aligned player base area adjacent to the player's cube:
--  - Base floor (Part) tagged as "FloorTile" so palettes/theme recolor it
--  - Perimeter glow bars (Parts) tagged as "GlowBar" for theme-driven neon
--  - Named anchors (Attachments) for future modules: HighScore, Teleporter, Shop, Pets, Trophy

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Terrain = Workspace.Terrain
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(Shared:WaitForChild("Logger"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local WorldGenUtils = require(Shared:WaitForChild("WorldGenUtils"))
local MathUtils = require(Shared:WaitForChild("MathUtils"))
local MaterialKeys = require(Shared:WaitForChild("MaterialKeys"))
local CubeVisuals = require(script.Parent:WaitForChild("CubeVisuals"))
local ServiceValidator = require(Shared:WaitForChild("ServiceValidator"))
local EventBus = require(Shared:WaitForChild("EventBus"))
local EventNames = require(Shared:WaitForChild("EventNames"))
local Bus = EventBus.global()
local DataService -- resolved in Init
local CubeMaterialService -- resolved in Init
local GlowBarService -- resolved in Init

local log = Logger.new("PlayerBaseService")

local PlayerBaseService = {}
PlayerBaseService.__index = PlayerBaseService

-- Per-player base cache
local _bases: {[Player]: Model} = {}
local _pending: {[Player]: {center: Vector3, size: Vector3}} = {}
local _worldgenReady = false

-- Folder for bases
local function getBasesFolder(): Folder
    local f = Workspace:FindFirstChild("PlayerBases")
    if not f then
        f = Instance.new("Folder")
        f.Name = "PlayerBases"
        f.Parent = Workspace
    end
    return f
end

-- Compute base rectangle relative to a cube origin (axis-aligned)
local function computeBaseRect(cubeOrigin: CFrame)
    local cubeSize = GameConfig.Grid.CUBE_SIZE_STUDS or 128
    local half = cubeSize * 0.5

    -- Desired base: cube occupies a corner; extend along +front and +right from the cube's front-left corner.
    local extendRight = math.floor(cubeSize * 0.75 + 0.5) -- configurable extension
    local extendFront = math.floor(cubeSize * 1.00 + 0.5)
    -- Add padding so perimeter glow bars don't clip the cube at back/left edges
    local pad = ((GameConfig.Visuals and GameConfig.Visuals.FLOOR_GLOW_MARGIN_MAX) or 4) + 2
    local baseWidth = cubeSize + extendRight + pad
    local baseDepth = cubeSize + extendFront + pad
    local baseThickness = 2

    -- Axis vectors (do not rotate the base, but use these to compute position)
    local up = Vector3.new(0, 1, 0)
    local frontDir = (-cubeOrigin.LookVector).Unit
    if frontDir.Magnitude < 0.5 then frontDir = Vector3.new(0, 0, 1) end
    -- Right-handed basis: right = up x front (so positive right goes screen-left when looking from front)
    local rightDir = up:Cross(frontDir).Unit
    if rightDir.Magnitude < 0.5 then rightDir = Vector3.new(1, 0, 0) end

    -- Base inner corner at the cube's BACK-LEFT corner, with extra padding so glow bars clear the cube
    local corner = cubeOrigin.Position - frontDir * (half + pad) - rightDir * (half + pad)

    -- Base center lies half-extents away from the inner corner along +right and +front
    local centerFlat = corner + rightDir * (baseWidth * 0.5) + frontDir * (baseDepth * 0.5)

    -- Vertical placement: top surface of base equals the cube's bottom face Y
    local bottomY = cubeOrigin.Position.Y - half
    local centerY = bottomY - (baseThickness * 0.5)
    local center = Vector3.new(centerFlat.X, centerY, centerFlat.Z)

    return {
        center = center,
        size = Vector3.new(baseWidth, baseThickness, baseDepth),
        topY = bottomY,
    }
end

local function tagOwner(part: BasePart, userId: number)
    part:SetAttribute("OwnerId", userId)
    part:SetAttribute("StreamingMode", "PersistentPerPlayer")
    part:SetAttribute("StreamingPlayerId", userId)
end

local function ensureAnchors(parent: Instance, rectCenter: Vector3, rectSize: Vector3, topY: number)
    local function anchor(name: string, pos: Vector3)
        local p = Instance.new("Part")
        p.Name = name .. "_Anchor"
        p.Anchored = true
        p.CanCollide = false
        p.CanTouch = false
        p.CanQuery = false
        p.Transparency = 1
        p.Size = Vector3.new(1, 1, 1)
        p.CFrame = CFrame.new(pos)
        p.Parent = parent
        return p
    end
    local halfX, halfZ = rectSize.X * 0.5, rectSize.Z * 0.5
    -- Place anchors at intuitive spots (local space)
    anchor("SpawnAnchor", Vector3.new(rectCenter.X, topY, rectCenter.Z - halfZ + 2))
    anchor("HighScoreAnchor", Vector3.new(rectCenter.X - halfX + 4, topY, rectCenter.Z - halfZ + 4))
    anchor("TeleporterAnchor", Vector3.new(rectCenter.X, topY, rectCenter.Z))
    anchor("ShopAnchor", Vector3.new(rectCenter.X + halfX - 4, topY, rectCenter.Z - halfZ + 4))
    anchor("PetsAnchor", Vector3.new(rectCenter.X - halfX + 6, topY, rectCenter.Z + halfZ - 6))
    anchor("TrophyAnchor", Vector3.new(rectCenter.X + halfX - 6, topY, rectCenter.Z + halfZ - 6))
end

local function buildGlowBars(parent: Model, rectCenter: Vector3, rectSize: Vector3, userId: number)
    local bars = Instance.new("Folder")
    bars.Name = "GlowBars"
    bars.Parent = parent
    local w, d = rectSize.X, rectSize.Z
    local t = 8 -- bar height
    local inset = 0.5
    local edgeY = (GameConfig.Visuals and GameConfig.Visuals.FLOOR_GLOW_GROUND_CLEARANCE) or 10

    local function makeBar(size: Vector3, offset: Vector3)
        local p = Instance.new("Part")
        p.Name = "GlowBar"
        p.Anchored = true
        p.CanCollide = false
        p.CanQuery = false
        p.CanTouch = false
        p.Size = size
        -- Center the bar at the same Y used by cube floor glow
        p.CFrame = CFrame.new(rectCenter + offset + Vector3.new(0, edgeY, 0))
        p.Transparency = 0
        p.Parent = bars
        CollectionService:AddTag(p, "GlowBar")
        tagOwner(p, userId)
        return p
    end

    -- Front/back bars (width along X)
    makeBar(Vector3.new(w - inset * 2, t, t), Vector3.new(0, 0, -(d * 0.5 - inset)))
    makeBar(Vector3.new(w - inset * 2, t, t), Vector3.new(0, 0, (d * 0.5 - inset)))
    -- Left/right bars (depth along Z)
    makeBar(Vector3.new(t, t, d - inset * 2), Vector3.new(-(w * 0.5 - inset), 0, 0))
    makeBar(Vector3.new(t, t, d - inset * 2), Vector3.new((w * 0.5 - inset), 0, 0))
end

-- Build a low wall around the cube footprint area within the base
local function buildCubeCurb(parent: Model, cubeOrigin: CFrame, userId: number)
    local cubeSize = GameConfig.Grid.CUBE_SIZE_STUDS or 128
    local half = cubeSize * 0.5
    local curbGap = 1 -- 1 stud away from cube faces
    local wallThick = 1
    local WALL_HEIGHT = 4 -- exactly cube bottom face + 4 studs top

    -- Basis
    local up = Vector3.new(0, 1, 0)
    local frontDir = (-cubeOrigin.LookVector).Unit
    if frontDir.Magnitude < 0.5 then frontDir = Vector3.new(0, 0, 1) end
    local rightDir = up:Cross(frontDir).Unit
    if rightDir.Magnitude < 0.5 then rightDir = Vector3.new(1, 0, 0) end

    local bottomY = cubeOrigin.Position.Y - half
    local centerY = bottomY + (WALL_HEIGHT * 0.5)

    -- Compute four wall segments around the cube footprint
    local function makeWall(size: Vector3, center: Vector3)
        local p = Instance.new("Part")
        p.Name = "CubeCurb"
        p.Anchored = true
        p.CanCollide = true
        p.Size = size
        p.CFrame = CFrame.new(center)
        -- style via MaterialManager
        CollectionService:AddTag(p, "FloorTile")
        p.Parent = parent
        tagOwner(p, userId)
    end

    -- Top edge (back side relative to front)
    do
        local length = cubeSize + curbGap * 2
        local center = cubeOrigin.Position - frontDir * (half + curbGap) + Vector3.new(0, centerY - cubeOrigin.Position.Y, 0)
        local size = Vector3.new(length, WALL_HEIGHT, wallThick)
        makeWall(size, center)
    end

    -- Bottom edge (front side)
    do
        local length = cubeSize + curbGap * 2
        local center = cubeOrigin.Position + frontDir * (half + curbGap) + Vector3.new(0, centerY - cubeOrigin.Position.Y, 0)
        local size = Vector3.new(length, WALL_HEIGHT, wallThick)
        makeWall(size, center)
    end

    -- Left edge
    do
        local length = cubeSize + curbGap * 2
        local center = cubeOrigin.Position - rightDir * (half + curbGap) + Vector3.new(0, centerY - cubeOrigin.Position.Y, 0)
        local size = Vector3.new(wallThick, WALL_HEIGHT, length)
        makeWall(size, center)
    end

    -- Right edge
    do
        local length = cubeSize + curbGap * 2
        local center = cubeOrigin.Position + rightDir * (half + curbGap) + Vector3.new(0, centerY - cubeOrigin.Position.Y, 0)
        local size = Vector3.new(wallThick, WALL_HEIGHT, length)
        makeWall(size, center)
    end
end

local function buildTerrainFloorAndModel(player: Player, cubeOrigin: CFrame)
    local rect = computeBaseRect(cubeOrigin)
    local basesFolder = getBasesFolder()

    local m = Instance.new("Model")
    m.Name = string.format("PlayerBase_%d", player.UserId)
    m.Parent = basesFolder

    -- Extend floor via CubeMaterialService (ring-only, excludes cube footprint)
    if not _worldgenReady then
        _pending[player] = { center = rect.center, size = rect.size }
    else
        if CubeMaterialService and CubeMaterialService.ExtendFloorAroundCube then
            pcall(function()
                CubeMaterialService:ExtendFloorAroundCube(player, cubeOrigin, rect.center, rect.size)
            end)
        end
    end

    -- Anchors for future modules (use invisible holders)
    ensureAnchors(m, rect.center, rect.size, rect.topY)
    -- Set a stable PrimaryPart so callers can reliably test existence
    local spawnAnchor = m:FindFirstChild("SpawnAnchor_Anchor")
    if spawnAnchor and spawnAnchor:IsA("BasePart") then
        m.PrimaryPart = spawnAnchor
    end

    -- Perimeter glow bars at standardized height (theme-managed via MaterialManager tags)
    if GlowBarService and GlowBarService.CreatePerimeterAtCube then
        local vis = GameConfig.Visuals
        GlowBarService.CreatePerimeterAtCube(m, cubeOrigin, rect.center, rect.size, { name = "BasePerimeterGlow", width = (vis and vis.BASE_GLOW_WIDTH) or nil })
    else
        -- Fallback to legacy implementation if service not available
        CubeVisuals.CreatePerimeterGlowRect(m, rect.center, rect.size)
    end
    -- Build cube curb from floor to cube bottom + 4 studs
    buildCubeCurb(m, cubeOrigin, player.UserId)

    return m
end

function PlayerBaseService:Init(container)
    -- Resolve DataService for prefs
    DataService = ServiceValidator.tryGet(container, "DataService", {"GetMaterialPrefs"})
    CubeMaterialService = ServiceValidator.tryGet(container, "CubeMaterialService", {"ExtendFloorAroundCube"})
    GlowBarService = ServiceValidator.tryGet(container, "GlowBarService", {})
    log:info("Initialized")
end

function PlayerBaseService:Start(container)
    -- Clean up on player leave
    Players.PlayerRemoving:Connect(function(player)
        self:Destroy(player)
    end)
    log:info("Started")

    -- Subscribe to worldgen completion to run floor ops afterwards
    Bus:on(EventNames.WORLDGEN_DONE, function()
        _worldgenReady = true
        for player, data in pairs(_pending) do
            if CubeMaterialService and CubeMaterialService.ExtendFloorAroundCube then
                -- We don't have cubeOrigin stored here; recompute from player cube model if needed later.
                -- For now, skip deferred application without cubeOrigin to avoid wrong placement.
            end
            _pending[player] = nil
        end
    end)
end

function PlayerBaseService:Ensure(player: Player, cubeOrigin: CFrame)
    local existing = _bases[player]
    if existing then
        -- Move/resize if needed (rebuild for simplicity)
        self:Destroy(player)
    end
    -- Also clean up any stray models with the same name under the folder (defensive)
    local folder = getBasesFolder()
    local expectedName = string.format("PlayerBase_%d", player.UserId)
    for _, ch in ipairs(folder:GetChildren()) do
        if ch:IsA("Model") and ch.Name == expectedName then
            pcall(function() ch:Destroy() end)
        end
    end
    local ok, model = pcall(function()
        return buildTerrainFloorAndModel(player, cubeOrigin)
    end)
    if ok and model then
        _bases[player] = model
        log:info("Ensured base for %s", player.Name)
        -- Announce via EventBus so dependent services (e.g., BannerService) can react
        pcall(function()
            Bus:emit(EventNames.PLAYER_BASE_READY, { to = { kind = "player", player = player }, payload = { baseModel = model } })
        end)
    else
        log:warn("Failed to build base for %s: %s", player.Name, tostring(model))
    end
end

function PlayerBaseService:Destroy(player: Player)
    local m = _bases[player]
    if not m then return end
    _bases[player] = nil
    pcall(function() m:Destroy() end)
end

return PlayerBaseService
