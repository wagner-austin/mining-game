--!strict
-- GlowBarService.lua
-- Centralized factory for creating standardized neon glow bars used across the game.
-- Bars are tagged as `GlowBar` so MaterialManager applies palette/theme automatically.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Logger = require(Shared:WaitForChild("Logger"))
local ServiceValidator = require(Shared:WaitForChild("ServiceValidator"))

local VIS = GameConfig.Visuals

local Service = {}
Service.__index = Service
local log = Logger.new("GlowBarService")

-- DI lifecycle
function Service:Init(container)
    -- no deps; keep for consistency and tracing
    log:info("Init")
end

function Service:Start(container)
    log:info("Start")
end

-- Compute the standard glow edge Y given a cube origin and size.
-- Uses the same height for all perimeter/cube glow bars to keep visuals consistent.
function Service.GetStandardGlowY(cubeOrigin: CFrame, cubeSize: number): number
    -- Height spec from config: offset above the cube's bottom face
    local bottomY = cubeOrigin.Position.Y - (cubeSize * 0.5)
    local offset = VIS.GLOW_BAR_OFFSET_FROM_BOTTOM or 20
    local y = bottomY + offset
    log:debug("StandardGlowY bottom=%.2f offset=%.2f -> y=%.2f", bottomY, offset, y)
    return y
end

-- Create a rectangle of glow bars at a specific Y.
-- Params:
--  parent: Instance to parent parts under
--  center: Vector3 of rectangle center (X/Z used)
--  size: Vector3 where X=width, Z=depth of the rectangle
--  y: number world height for the bar centers
--  opts: {name: string?, extraLength: number?, width: number?, thickness: number?}
function Service.CreateRectAtY(parent: Instance, center: Vector3, size: Vector3, y: number, opts: {name: string?, extraLength: number?, width: number?, thickness: number?}?)
    local thickness = (opts and opts.thickness) or VIS.FLOOR_GLOW_THICKNESS
    local width = (opts and opts.width) or VIS.FLOOR_GLOW_WIDTH
    local overlapFactor = VIS.GLOW_CORNER_OVERLAP_FACTOR or 0.24
    local standardOverlap = width * overlapFactor
    local extra = (opts and opts.extraLength) or 0
    local extraLen = extra + standardOverlap

    local folder = Instance.new("Folder")
    folder.Name = (opts and opts.name) or "GlowRect"
    folder.Parent = parent

    local w = size.X
    local d = size.Z

    local function makeEdge(offset: Vector3, edgeSize: Vector3)
        local p = Instance.new("Part")
        p.Name = "GlowEdge"
        p.Size = edgeSize
        p.CFrame = CFrame.new(Vector3.new(center.X + offset.X, y, center.Z + offset.Z))
        p.Material = Enum.Material.Neon
        p.Anchored = true
        p.CanCollide = false
        p.CanTouch = false
        p.CanQuery = false
        p.CastShadow = false
        p.Parent = folder
        CollectionService:AddTag(p, "GlowBar")
        return p
    end

    -- Place centers inset by half bar width to avoid outward protrusion
    local zInset = (d * 0.5) - (width * 0.5)
    local xInset = (w * 0.5) - (width * 0.5)

    -- Front/back bars (long along X)
    makeEdge(Vector3.new(0, 0, -zInset), Vector3.new(w + extraLen, thickness, width))
    makeEdge(Vector3.new(0, 0,  zInset), Vector3.new(w + extraLen, thickness, width))
    -- Left/right bars (long along Z)
    makeEdge(Vector3.new(-xInset, 0, 0), Vector3.new(width, thickness, d + extraLen))
    makeEdge(Vector3.new( xInset, 0, 0), Vector3.new(width, thickness, d + extraLen))

    log:debug("CreateRectAtY name=%s center=(%.1f,%.1f,%.1f) size=(%.1f,%.1f) y=%.2f extra=%.2f overlap=%.2f factor=%.3f width=%.2f thick=%.2f",
        folder.Name, center.X, center.Y, center.Z, size.X, size.Z, y, extra, standardOverlap, overlapFactor, width, thickness)
    return folder
end

-- Create a perimeter rectangle at the standardized cube-based height.
function Service.CreatePerimeterAtCube(parent: Instance, cubeOrigin: CFrame, rectCenter: Vector3, rectSize: Vector3, opts: {name: string?, extraLength: number?}?)
    local y = Service.GetStandardGlowY(cubeOrigin, GameConfig.Grid.CUBE_SIZE_STUDS)
    return Service.CreateRectAtY(parent, rectCenter, rectSize, y, opts)
end

-- Create a square outline around a cube using the standardized height.
-- margin: how far beyond cube edge the outline sits (total size = cube + margin*2)
function Service.CreateSquareAroundCube(parent: Instance, cubeOrigin: CFrame, cubeSize: number, margin: number, opts: {name: string?, extraLength: number?}?)
    local y = Service.GetStandardGlowY(cubeOrigin, cubeSize)
    local glowSize = cubeSize + (margin * 2)
    local center = cubeOrigin.Position
    return Service.CreateRectAtY(parent, center, Vector3.new(glowSize, 0, glowSize), y, opts)
end

return Service
