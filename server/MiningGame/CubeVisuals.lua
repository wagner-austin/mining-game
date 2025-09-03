--!strict
--[[
    CubeVisuals.lua
    Creates and manages visual indicators for mining cubes.
    
    Features:
    - Neon floor glow outlines
    - Dynamic lighting effects
    - Material-aware positioning
    - Configurable colors and dimensions
    - CollectionService tagging for effects
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Logger = require(Shared:WaitForChild("Logger"))
local log = Logger.new("CubeVisuals")

local CubeVisuals = {}

-- Clear any existing indicators to prevent duplication
local function clearExistingIndicators(model: Model)
    local old = model:FindFirstChild("Indicators")
    if old then old:Destroy() end
end

--[[
    Create a glowing neon outline at the base of the cube.
    Adds visual appeal and helps players locate their cube.
    
    @param model: Model - The cube model to add visuals to
    @param cubeOrigin: CFrame - The cube's center position
    @param size: number - The cube size in studs
    @param floorMaterial: Enum.Material? - Optional floor material for positioning
]]
function CubeVisuals.CreateFloorGlow(model: Model, cubeOrigin: CFrame, size: number, floorMaterial: Enum.Material?)
    clearExistingIndicators(model)
    
    log:debug("Creating floor glow - Cube origin Y: %.2f, Size: %.2f, FloorMaterial: %s", 
        cubeOrigin.Position.Y, size, tostring(floorMaterial))
    
    -- Create folder for organization
    local indicators = Instance.new("Folder")
    indicators.Name = "Indicators"
    indicators.Parent = model
    
    -- Get config values or use defaults
    local config = GameConfig.Visuals
    local thickness = config and config.FLOOR_GLOW_THICKNESS or 0.5
    local width = config and config.FLOOR_GLOW_WIDTH or 4
    local marginMin = config and config.FLOOR_GLOW_MARGIN_MIN or 2
    local marginMax = config and config.FLOOR_GLOW_MARGIN_MAX or 4
    local glowColor = config and config.FLOOR_GLOW_COLOR or Color3.fromRGB(0, 255, 255)
    
    -- Slightly larger than the cube so the outline is visible
    local margin = math.clamp(math.floor(size * 0.1), marginMin, marginMax)  -- 10% of size for longer bars
    local glowSize = size + (margin * 2)
    
    -- Position the edges using the configured ground clearance
    local groundClearance = config and config.FLOOR_GLOW_GROUND_CLEARANCE or 9.83
    local edgeY = groundClearance
    local floorY = cubeOrigin.Position.Y - (size/2)
    local barBottomY = edgeY - (thickness/2)
    
    log:debug("Positions - CubeY: %.2f, FloorY: %.2f, BarBottomY: %.2f, EdgeY: %.2f", 
        cubeOrigin.Position.Y, floorY, barBottomY, edgeY)
    log:debug("Dimensions - Width: %.2f, Thickness: %.2f, margin: %d, glowSize: %.2f", 
        width, thickness, margin, glowSize)
    
    local function makeEdge(xOffset: number, zOffset: number, edgeSize: Vector3)
        local p = Instance.new("Part")
        p.Name = "GlowEdge"
        p.Size = edgeSize
        -- Position at the proper height above floor with X/Z offsets from cube center
        p.CFrame = CFrame.new(
            cubeOrigin.Position.X + xOffset,
            edgeY, -- Now properly elevated above the ground
            cubeOrigin.Position.Z + zOffset
        )
        p.Material = Enum.Material.Neon
        p.Color = glowColor
        p.Transparency = 0.3  -- Add some transparency to reduce brightness
        p.Anchored = true
        p.CanCollide = false
        p.CanTouch = false
        p.CanQuery = false
        p.CastShadow = false
        p.Parent = indicators
        
        -- Tag for MaterialManager to apply lighting
        CollectionService:AddTag(p, "GlowBar")
        
        -- More detailed logging
        log:debug("Created edge: Pos=(%.2f, %.2f, %.2f), Size=(%s), Parent=%s, Material=%s, Color=%s, Transparency=%.2f", 
            p.Position.X, p.Position.Y, p.Position.Z, 
            tostring(edgeSize), 
            tostring(p.Parent and p.Parent:GetFullName() or "nil"),
            tostring(p.Material),
            tostring(p.Color),
            p.Transparency)
        
        -- Check if part is actually in workspace
        local inWorkspace = p:IsDescendantOf(game.Workspace)
        log:debug("Edge in Workspace: %s", tostring(inWorkspace))
        
        return p
    end
    
    -- Create the four edges of the square outline
    -- Make the bars longer by increasing their actual size
    local barLength = glowSize + 2  -- Add extra length to the bars themselves
    
    -- Front and back edges (parallel to X axis) - width goes in Z direction
    log:debug("Creating front/back edges - Size: (%.2f, %.2f, %.2f)", barLength, thickness, width)
    local edge1 = makeEdge(0, glowSize/2, Vector3.new(barLength, thickness, width))
    local edge2 = makeEdge(0, -glowSize/2, Vector3.new(barLength, thickness, width))
    
    -- Left and right edges (parallel to Z axis) - width goes in X direction  
    log:debug("Creating left/right edges - Size: (%.2f, %.2f, %.2f)", width, thickness, barLength)
    local edge3 = makeEdge(glowSize/2, 0, Vector3.new(width, thickness, barLength))
    local edge4 = makeEdge(-glowSize/2, 0, Vector3.new(width, thickness, barLength))
    
    -- Swap terrain under each neon bar, preserving shape
    local Terrain = workspace.Terrain
    local RESOLUTION = GameConfig.Grid.CELL_SIZE_STUDS
    
    -- Get all terrain materials with fallback
    local MaterialDefinitions = require(Shared:WaitForChild("MaterialDefinitions"))
    local allTerrainMaterials = MaterialDefinitions.AllTerrainEnums
    if not allTerrainMaterials then
        -- Fallback: build from MaterialKeys if AllTerrainEnums is missing
        local MaterialKeys = require(Shared:WaitForChild("MaterialKeys"))
        allTerrainMaterials = {}
        for _, key in ipairs(MaterialKeys.TerrainKeys) do
            local em = MaterialKeys.EnumFromKey[key]
            if em then table.insert(allTerrainMaterials, em) end
        end
        log:warn("AllTerrainEnums missing, using fallback from MaterialKeys")
    end
    
    -- USE THE PASSED PARAM if provided; otherwise config default
    local replacementMat = floorMaterial or (config and config.FLOOR_GLOW_REPLACEMENT_MATERIAL) or Enum.Material.Concrete
    
    -- First, replace floor under the entire cube footprint at spawn
    local half = size / 2
    local floorDepth = RESOLUTION * 3 -- 12 studs deep to match glow bar depth
    local cubeFloorRegion = Region3.new(
        Vector3.new(cubeOrigin.Position.X - half, floorY - floorDepth, cubeOrigin.Position.Z - half),
        Vector3.new(cubeOrigin.Position.X + half, floorY, cubeOrigin.Position.Z + half)
    ):ExpandToGrid(RESOLUTION)
    
    log:debug("Replacing cube footprint with %s", tostring(replacementMat))
    
    if replacementMat == Enum.Material.Water then
        local mats, occs = Terrain:ReadVoxels(cubeFloorRegion, RESOLUTION)
        local sx, sy, sz = mats.Size.X, mats.Size.Y, mats.Size.Z
        for x = 1, sx do
            for y = 1, sy do
                for z = 1, sz do
                    if occs[x][y][z] > 0 and mats[x][y][z] ~= Enum.Material.Air then
                        mats[x][y][z] = Enum.Material.Water
                        if occs[x][y][z] < 0.3 then occs[x][y][z] = 0.3 end
                    end
                end
            end
        end
        Terrain:WriteVoxels(cubeFloorRegion, RESOLUTION, mats, occs)
    else
        for _, src in ipairs(allTerrainMaterials) do
            Terrain:ReplaceMaterial(cubeFloorRegion, RESOLUTION, src, replacementMat)
        end
    end
    
    -- Then, do each glow bar region with CONSISTENT depth and base Y
    local function replaceUnderEdge(edge: BasePart)
        local pad = 1
        local depth = RESOLUTION * 3 -- 12 studs deep to ensure no grass peeks through
        local y0 = barBottomY -- bottom of bar, consistent reference
        local region = Region3.new(
            Vector3.new(edge.Position.X - edge.Size.X/2 - pad, y0 - depth, edge.Position.Z - edge.Size.Z/2 - pad),
            Vector3.new(edge.Position.X + edge.Size.X/2 + pad, y0,         edge.Position.Z + edge.Size.Z/2 + pad)
        ):ExpandToGrid(RESOLUTION)
        
        log:debug("Replacing materials under edge at Y=%.2f (region Y: %.2f to %.2f)", 
            edge.Position.Y, y0 - depth, y0)
        
        -- Handle water specially, otherwise replace all terrain materials
        if replacementMat == Enum.Material.Water then
            local mats, occs = Terrain:ReadVoxels(region, RESOLUTION)
            local sx, sy, sz = mats.Size.X, mats.Size.Y, mats.Size.Z
            for x = 1, sx do
                for y = 1, sy do
                    for z = 1, sz do
                        if occs[x][y][z] > 0 and mats[x][y][z] ~= Enum.Material.Air then
                            mats[x][y][z] = Enum.Material.Water
                            if occs[x][y][z] < 0.3 then occs[x][y][z] = 0.3 end
                        end
                    end
                end
            end
            Terrain:WriteVoxels(region, RESOLUTION, mats, occs)
        else
            for _, src in ipairs(allTerrainMaterials) do
                Terrain:ReplaceMaterial(region, RESOLUTION, src, replacementMat)
            end
        end
    end
    
    -- Optional: Clear a thin layer above if needed for steep slopes
    local function clearAboveEdge(edge: BasePart)
        local pad = 0.5
        local height = 0.75
        local yTop = edge.Position.Y + (thickness/2)
        local region = Region3.new(
            Vector3.new(edge.Position.X - edge.Size.X/2 - pad, yTop,          edge.Position.Z - edge.Size.Z/2 - pad),
            Vector3.new(edge.Position.X + edge.Size.X/2 + pad, yTop + height, edge.Position.Z + edge.Size.Z/2 + pad)
        ):ExpandToGrid(RESOLUTION)
        Terrain:FillBlock(CFrame.new(region.CFrame.Position), region.Size, Enum.Material.Air)
    end
    
    -- Apply material replacement to all edges
    for _, edge in ipairs({edge1, edge2, edge3, edge4}) do
        replaceUnderEdge(edge)
        -- Uncomment if hillside clipping is still an issue:
        -- clearAboveEdge(edge)
    end
    
    log:info("Floor glow created with %d edges; floor=%s", 4, tostring(replacementMat))
    
    return indicators
end

-- Add centralized lighting to the cube
function CubeVisuals.AddCubeLight(bounds: BasePart, size: number)
    -- Get config values or use defaults
    local config = GameConfig.Visuals
    local rangeMult = config and config.LIGHT_RANGE_MULT or 1.25
    local rangeMin = config and config.LIGHT_RANGE_MIN or 24
    local brightness = config and config.LIGHT_BRIGHTNESS or 1.5
    local lightColor = config and config.LIGHT_COLOR or Color3.fromRGB(180, 255, 255)
    
    -- Single centralized light (cheaper than multiple per-edge lights)
    local att = Instance.new("Attachment")
    att.Parent = bounds
    
    local light = Instance.new("PointLight")
    light.Range = math.max(size * rangeMult, rangeMin) -- reaches into early digs at night
    light.Brightness = brightness
    light.Color = lightColor
    light.Shadows = false -- optional; set true if you like
    light.Parent = att
    
    return light
end

-- Create studio-only selection box for debugging
function CubeVisuals.CreateStudioSelectionBox(bounds: BasePart)
    if not RunService:IsStudio() then
        return nil
    end
    
    local selectionBox = Instance.new("SelectionBox")
    selectionBox.Adornee = bounds
    selectionBox.LineThickness = 0.1
    selectionBox.Transparency = 0.8
    selectionBox.Color3 = Color3.new(1, 1, 1)
    selectionBox.Parent = bounds
    
    return selectionBox
end

-- Create optional whole cube glow effect (for monetization/upgrades)
function CubeVisuals.CreateCubeGlow(model: Model, cubeOrigin: CFrame, size: number, enabled: boolean?)
    if not enabled then
        return nil
    end
    
    -- Get config values or use defaults
    local config = GameConfig.Visuals
    local cubeGlowColor = config and config.CUBE_GLOW_COLOR or Color3.fromRGB(100, 255, 255)
    local cubeGlowTransparency = config and config.CUBE_GLOW_TRANSPARENCY or 0.7
    
    log:debug("Creating cube glow effect - Size: %.2f", size)
    
    -- Create a semi-transparent neon cube overlay
    local glowCube = Instance.new("Part")
    glowCube.Name = "CubeGlow"
    glowCube.Size = Vector3.new(size + 0.5, size + 0.5, size + 0.5) -- Slightly larger than the actual cube
    glowCube.CFrame = cubeOrigin
    glowCube.Material = Enum.Material.ForceField -- ForceField gives a nice glow effect
    glowCube.Color = cubeGlowColor
    glowCube.Transparency = cubeGlowTransparency
    glowCube.CanCollide = false
    glowCube.CanTouch = false
    glowCube.CanQuery = false
    glowCube.CastShadow = false
    glowCube.Anchored = true
    
    -- Parent to indicators folder if it exists, otherwise to model
    local indicators = model:FindFirstChild("Indicators")
    if indicators then
        glowCube.Parent = indicators
    else
        glowCube.Parent = model
    end
    
    return glowCube
end

return CubeVisuals