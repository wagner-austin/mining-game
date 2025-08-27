--!strict
-- CubeVisuals.lua
-- Handles visual indicators for mining cubes (neon outlines, lights, etc.)

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local CubeVisuals = {}

-- Clear any existing indicators to prevent duplication
local function clearExistingIndicators(model: Model)
    local old = model:FindFirstChild("Indicators")
    if old then old:Destroy() end
end

-- Create the glowing neon floor outline with lighting
function CubeVisuals.CreateFloorGlow(model: Model, cubeOrigin: CFrame, size: number)
    clearExistingIndicators(model)
    
    print(string.format("[CubeVisuals] Creating floor glow - Cube origin Y: %.2f, Size: %.2f", cubeOrigin.Position.Y, size))
    
    -- Create folder for organization
    local indicators = Instance.new("Folder")
    indicators.Name = "Indicators"
    indicators.Parent = model
    
    -- Get config values or use defaults
    local config = GameConfig.Visuals
    local thickness = config and config.FLOOR_GLOW_THICKNESS or 0.5
    local width = config and config.FLOOR_GLOW_WIDTH or 4
    local clearance = config and config.FLOOR_GLOW_GROUND_CLEARANCE or 9.75
    local marginMin = config and config.FLOOR_GLOW_MARGIN_MIN or 2
    local marginMax = config and config.FLOOR_GLOW_MARGIN_MAX or 4
    local glowColor = config and config.FLOOR_GLOW_COLOR or Color3.fromRGB(0, 255, 255)
    
    -- Slightly larger than the cube so the outline is visible
    local margin = math.clamp(math.floor(size * 0.1), marginMin, marginMax)  -- 10% of size for longer bars
    local glowSize = size + (margin * 2)
    
    -- Position the edges at the specified clearance height
    local edgeY = clearance
    
    print(string.format("[CubeVisuals] Edge Y: %.2f, Width: %.2f, Thickness: %.2f, margin: %d, glowSize: %.2f", 
        edgeY, width, thickness, margin, glowSize))
    
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
        
        -- More detailed logging
        print(string.format("[CubeVisuals] Created edge: Pos=(%.2f, %.2f, %.2f), Size=(%s), Parent=%s, Material=%s, Color=%s, Transparency=%.2f", 
            p.Position.X, p.Position.Y, p.Position.Z, 
            tostring(edgeSize), 
            tostring(p.Parent and p.Parent:GetFullName() or "nil"),
            tostring(p.Material),
            tostring(p.Color),
            p.Transparency))
        
        -- Check if part is actually in workspace
        local inWorkspace = p:IsDescendantOf(game.Workspace)
        print(string.format("[CubeVisuals] Edge in Workspace: %s", tostring(inWorkspace)))
        
        return p
    end
    
    -- Create the four edges of the square outline
    -- Make the bars longer by increasing their actual size
    local barLength = glowSize + 2  -- Add extra length to the bars themselves
    
    -- Front and back edges (parallel to X axis) - width goes in Z direction
    print(string.format("[CubeVisuals] Creating front/back edges - Size: (%.2f, %.2f, %.2f)", barLength, thickness, width))
    local edge1 = makeEdge(0, glowSize/2, Vector3.new(barLength, thickness, width))
    local edge2 = makeEdge(0, -glowSize/2, Vector3.new(barLength, thickness, width))
    
    -- Left and right edges (parallel to Z axis) - width goes in X direction  
    print(string.format("[CubeVisuals] Creating left/right edges - Size: (%.2f, %.2f, %.2f)", width, thickness, barLength))
    local edge3 = makeEdge(glowSize/2, 0, Vector3.new(width, thickness, barLength))
    local edge4 = makeEdge(-glowSize/2, 0, Vector3.new(width, thickness, barLength))
    
    -- Swap terrain under each neon bar, preserving shape
    local Terrain = workspace.Terrain
    local RESOLUTION = 4
    local matsToSwap = (config and config.FLOOR_GLOW_REPLACE_MATERIALS) 
                        or { Enum.Material.Grass, Enum.Material.LeafyGrass, Enum.Material.Ground }
    local replacementMat = (config and config.FLOOR_GLOW_REPLACEMENT_MATERIAL)
                           or Enum.Material.Concrete
    
    local function replaceUnderEdge(edge: BasePart)
        -- A shallow slab that covers the bar footprint (slightly padded)
        local pad = 1
        local depth = 2 -- medium depth below the bar
        local y0 = edge.Position.Y - (thickness/2) -- bar bottom
        local region = Region3.new(
            Vector3.new(edge.Position.X - edge.Size.X/2 - pad, y0 - depth, edge.Position.Z - edge.Size.Z/2 - pad),
            Vector3.new(edge.Position.X + edge.Size.X/2 + pad, y0,         edge.Position.Z + edge.Size.Z/2 + pad)
        ):ExpandToGrid(RESOLUTION)
        
        print(string.format("[CubeVisuals] Replacing materials under edge at Y=%.2f (region Y: %.2f to %.2f)", 
            edge.Position.Y, y0 - depth, y0))
        
        -- Replace each material type with the replacement material
        for _, srcMaterial in ipairs(matsToSwap) do
            Terrain:ReplaceMaterial(region, RESOLUTION, srcMaterial, replacementMat)
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
    
    print(string.format("[CubeVisuals] Floor glow created with %d edges", 4))
    
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
    
    print(string.format("[CubeVisuals] Creating cube glow effect - Size: %.2f", size))
    
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