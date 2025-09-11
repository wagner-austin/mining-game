--!strict
-- MaterialManager.lua
-- Handles material palette switching and visual themes

local CollectionService = game:GetService("CollectionService")
local MaterialService = game:GetService("MaterialService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MaterialPalettes = require(script.Parent.MaterialPalettes)
local GameConfig = require(script.Parent.GameConfig)
local MathUtils = require(script.Parent:WaitForChild("MathUtils"))

type Palette = {
    name: string,
    description: string,
    
    -- Floor material properties
    floorMaterial: Enum.Material,
    floorColor: Color3,
    
    -- Glow bar properties
    glowColor: Color3,
    glowEmissive: number,
    glowTransparency: number,
    
    -- Lighting properties
    lightColor: Color3,
    lightBrightness: number,
    
    -- Cube material properties
    cubeMaterial: Enum.Material?,
    cubeColor: Color3?,
    cubeEmissive: number?,
    cubeVariant: string?, -- Optional MaterialVariant name for adaptive materials
    
    -- Particle effect colors
    particleColors: {Color3},
    
    -- Optional material overrides for terrain
    materialOverrides: {[Enum.Material]: string}?,
}

local MaterialManager = {}
MaterialManager.__index = MaterialManager

-- Current active palette and cube material
local currentPaletteName: string = "default"
local currentPalette: Palette? = nil
local currentCubeMaterialKey: string = "stone"
local currentCubeMaterial = nil

-- Weak cache for created lights and highlights (prevents memory leaks)
local lightCache = setmetatable({}, {__mode = "k"}) :: {[Instance]: PointLight}
local highlightCache = setmetatable({}, {__mode = "k"}) :: {[Instance]: Highlight}
local spotlightCache = setmetatable({}, {__mode = "k"}) :: {[Instance]: SpotLight}

-- Chunked application to prevent frame spikes
local function applyToTaggedChunked(tag: string, fn: (Instance) -> (), batchSize: number?)
    local list = CollectionService:GetTagged(tag)
    local batch = batchSize or 30
    
    task.spawn(function()
        for i = 1, #list, batch do
            for j = i, math.min(i + batch - 1, #list) do
                local inst = list[j]
                if inst then
                    fn(inst)
                end
            end
            if i + batch <= #list then
                task.wait() -- Yield frame between batches
            end
        end
    end)
end

-- Helper functions
local function setPart(part: BasePart, material: Enum.Material, color: Color3, transparency: number?)
    part.Material = material
    part.Color = color
    if transparency then
        part.Transparency = transparency
    end
end

local function ensurePointLight(parent: Instance): PointLight
    local light = lightCache[parent] or parent:FindFirstChildOfClass("PointLight")
    if not light then
        light = Instance.new("PointLight")
        light.Parent = parent
        lightCache[parent] = light
    end
    return light
end

local function ensureSpotLight(parent: Instance): SpotLight
    local light = spotlightCache[parent] or parent:FindFirstChildOfClass("SpotLight")
    if not light then
        light = Instance.new("SpotLight")
        light.Parent = parent
        spotlightCache[parent] = light
    end
    return light
end

local function ensureSurfaceLight(parent: Instance, face: Enum.NormalId): SurfaceLight
    local lightName = "SurfaceLight_" .. face.Name
    local light = parent:FindFirstChild(lightName)
    if not light or not light:IsA("SurfaceLight") then
        light = Instance.new("SurfaceLight")
        light.Name = lightName
        light.Face = face
        light.Parent = parent
    end
    return light
end

local function ensureHighlight(model: Model): Highlight
    local highlight = highlightCache[model] or model:FindFirstChildOfClass("Highlight")
    if not highlight then
        highlight = Instance.new("Highlight")
        highlight.Parent = model
        highlight.DepthMode = Enum.HighlightDepthMode.Occluded
        highlightCache[model] = highlight
    end
    return highlight
end

local function calculateLightRange(part: BasePart): number
    local cfg = GameConfig.Visuals
    return math.max(cfg.LIGHT_RANGE_MIN or 24, part.Size.Magnitude * (cfg.LIGHT_RANGE_MULT or 1.25))
end

-- Apply emissive effects based on material
local function applyEmissiveEffects(part: BasePart, emissive: number, palette: Palette)
    if emissive <= 0 then
        -- Disable any existing lights
        local light = part:FindFirstChildOfClass("PointLight")
        if light then light.Enabled = false end
        return
    end
    
    -- Create or update point light
    local light = ensurePointLight(part)
    light.Color = palette.lightColor
    light.Brightness = math.min(palette.lightBrightness * emissive, 5) -- Clamp brightness
    light.Range = calculateLightRange(part) * (1 + emissive * 0.5)
    light.Enabled = true
    
    -- For Neon material, adjust transparency for glow effect
    if part.Material == Enum.Material.Neon then
        part.Transparency = MathUtils.nonNegative(1 - (1 / (1 + emissive * 0.2)))
    end
    
    -- Add highlight to parent model for additional glow
    local model = part:FindFirstAncestorOfClass("Model")
    if model and emissive > 1 then
        local highlight = ensureHighlight(model)
        highlight.FillColor = palette.glowColor
        highlight.FillTransparency = math.max(0.7, 1 - (emissive * 0.1))
        highlight.OutlineColor = palette.glowColor
        highlight.OutlineTransparency = math.max(0.3, 1 - (emissive * 0.2))
        highlight.Enabled = true
    end
end

-- Apply palette to cube parts
function MaterialManager.ApplyCubePart(part: BasePart)
    if not currentPalette then return end
    
    -- Use the separately selected cube material instead of palette's cube material
    if currentCubeMaterial then
        setPart(part, currentCubeMaterial.material, currentCubeMaterial.color)
        if currentCubeMaterial.transparency then
            part.Transparency = currentCubeMaterial.transparency
        end
        
        -- Apply emissive effects from cube material
        local emissive = currentCubeMaterial.emissive or 0
        applyEmissiveEffects(part, emissive, currentPalette)
    elseif currentPalette.cubeMaterial and currentPalette.cubeColor then
        -- Fallback to palette's default if no cube material selected
        setPart(part, currentPalette.cubeMaterial, currentPalette.cubeColor)
        local emissive = currentPalette.cubeEmissive or 0
        applyEmissiveEffects(part, emissive, currentPalette)
    end
end

-- Apply palette to entire model
function MaterialManager.ApplyCubeModel(model: Model)
    if not currentPalette then return end
    
    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BasePart") and CollectionService:HasTag(descendant, "CubeBlock") then
            MaterialManager.ApplyCubePart(descendant)
        end
    end
end

-- Apply palette to floor tiles
local function applyFloorTiles(palette: Palette)
    applyToTaggedChunked("FloorTile", function(inst)
        if inst:IsA("BasePart") then
            setPart(inst, palette.floorMaterial, palette.floorColor)
        end
    end)
end

-- Apply palette to glow bars
local function applyGlowBars(palette: Palette)
    applyToTaggedChunked("GlowBar", function(inst)
        if inst:IsA("BasePart") then
            -- Always use Neon for glow bars
            setPart(inst, Enum.Material.Neon, palette.glowColor, palette.glowTransparency)
            
            -- Remove old PointLight if exists (from previous system)
            local oldLight = inst:FindFirstChildOfClass("PointLight")
            if oldLight then oldLight:Destroy() end
            
            -- Add vertical emissive lighting with SurfaceLight
            if palette.glowEmissive > 0 then
                -- Upward light (main vertical emission)
                local upLight = ensureSurfaceLight(inst, Enum.NormalId.Top)
                upLight.Color = palette.glowColor
                upLight.Brightness = math.min(palette.glowEmissive * 1.5, 3)
                upLight.Angle = 120 -- Wide spread
                upLight.Range = 40 -- Good vertical reach
                upLight.Shadows = false
                upLight.Enabled = true
                
                -- Downward light (subtle floor illumination)
                local downLight = ensureSurfaceLight(inst, Enum.NormalId.Bottom)
                downLight.Color = palette.glowColor
                downLight.Brightness = math.min(palette.glowEmissive * 0.5, 1.5)
                downLight.Angle = 90
                downLight.Range = 15
                downLight.Shadows = false
                downLight.Enabled = true
            end
        end
    end)
end

-- Apply palette to scene lights
local function applySceneLights(palette: Palette)
    for _, inst in ipairs(CollectionService:GetTagged("PaletteLight")) do
        if inst:IsA("BasePart") then
            local light = ensurePointLight(inst)
            light.Color = palette.lightColor
            light.Brightness = palette.lightBrightness
            light.Range = calculateLightRange(inst)
            light.Enabled = true
            
            -- Make the light source itself glow
            if inst.Material == Enum.Material.Neon then
                inst.Color = palette.lightColor
            end
        end
    end
end

-- Apply palette to particle effects
local function applyParticleEffects(palette: Palette)
    for _, inst in ipairs(CollectionService:GetTagged("PaletteParticle")) do
        if inst:IsA("ParticleEmitter") then
            -- Create color sequence from palette colors
            local keypoints = {}
            for i, color in ipairs(palette.particleColors) do
                local time = (i - 1) / math.max(1, #palette.particleColors - 1)
                table.insert(keypoints, ColorSequenceKeypoint.new(time, color))
            end
            if #keypoints > 0 then
                inst.Color = ColorSequence.new(keypoints)
            end
        end
    end
end


-- Main palette switching function
function MaterialManager.SetPalette(paletteName: string)
    local palette = MaterialPalettes.GetPalette(paletteName)
    if not palette then
        warn("MaterialManager: Palette not found:", paletteName)
        return false
    end
    
    currentPaletteName = paletteName
    currentPalette = palette
    
    -- Apply to all tagged elements (using chunking for better performance)
    applyFloorTiles(palette)
    applyGlowBars(palette)
    applySceneLights(palette)
    applyParticleEffects(palette)
    
    -- Apply to all existing cube blocks (chunked to prevent lag)
    applyToTaggedChunked("CubeBlock", function(inst)
        if inst:IsA("BasePart") then
            MaterialManager.ApplyCubePart(inst)
        elseif inst:IsA("Model") then
            MaterialManager.ApplyCubeModel(inst)
        end
    end)
    
    print("MaterialManager: Applied palette", paletteName)
    return true
end

-- Get current palette information
function MaterialManager.GetCurrentPaletteName(): string
    return currentPaletteName
end

function MaterialManager.GetCurrentPalette(): Palette?
    return currentPalette
end

-- Set cube material independently from palette
function MaterialManager.SetCubeMaterial(materialKey: string)
    -- Skip if same material
    if currentCubeMaterialKey == materialKey then
        return true
    end
    
    currentCubeMaterialKey = materialKey
    
    -- Check for special visual-only materials from MaterialPalettes
    local specialMaterial = MaterialPalettes.GetSpecialMaterial(materialKey)
    if specialMaterial then
        currentCubeMaterial = specialMaterial
    else
        -- Default mapping for standard terrain materials
        currentCubeMaterial = {
            name = materialKey,
            material = Enum.Material.Rock, -- Default part material for visuals
            color = Color3.fromRGB(140, 140, 140),
            emissive = 0,
        }
    end
    
    -- Apply to all existing cube blocks (chunked to prevent lag)
    applyToTaggedChunked("CubeBlock", function(inst)
        if inst:IsA("BasePart") then
            MaterialManager.ApplyCubePart(inst)
        elseif inst:IsA("Model") then
            MaterialManager.ApplyCubeModel(inst)
        end
    end)
    
    print("MaterialManager: Applied cube material", materialKey)
    return true
end

-- Get current cube material
function MaterialManager.GetCurrentCubeMaterialKey(): string
    return currentCubeMaterialKey
end

function MaterialManager.GetCurrentCubeMaterial()
    return currentCubeMaterial
end

-- Set floor material independently (for testing)
function MaterialManager.SetFloorMaterial(material: Enum.Material, color: Color3?)
    applyToTaggedChunked("FloorTile", function(inst)
        if inst:IsA("BasePart") then
            inst.Material = material
            if color then
                inst.Color = color
            end
        end
    end)
end

-- Initialize with default palette
function MaterialManager.Initialize()
    -- Check if running on client (visuals should be client-side)
    if RunService:IsServer() then
        warn("MaterialManager: Visual effects should run on the client for better performance")
        -- Allow server to run for testing, but warn about it
    end
    
    -- Load default palette and cube material
    MaterialManager.SetPalette("default")
    MaterialManager.SetCubeMaterial("stone")
    
    -- Listen for new tagged objects and clean up removed ones
    local connections = {}
    
    -- CubeBlock handlers
    connections[#connections + 1] = CollectionService:GetInstanceAddedSignal("CubeBlock"):Connect(function(inst)
        if inst:IsA("BasePart") then
            MaterialManager.ApplyCubePart(inst)
        elseif inst:IsA("Model") then
            MaterialManager.ApplyCubeModel(inst)
        end
    end)
    
    connections[#connections + 1] = CollectionService:GetInstanceRemovedSignal("CubeBlock"):Connect(function(inst)
        -- Clean up caches
        lightCache[inst] = nil
        highlightCache[inst] = nil
        spotlightCache[inst] = nil
    end)
    
    -- GlowBar handlers  
    connections[#connections + 1] = CollectionService:GetInstanceAddedSignal("GlowBar"):Connect(function(inst)
        if inst:IsA("BasePart") and currentPalette then
            setPart(inst, Enum.Material.Neon, currentPalette.glowColor, currentPalette.glowTransparency)
            
            -- Remove old PointLight if exists
            local oldLight = inst:FindFirstChildOfClass("PointLight")
            if oldLight then oldLight:Destroy() end
            
            if currentPalette.glowEmissive > 0 then
                -- Upward light
                local upLight = ensureSurfaceLight(inst, Enum.NormalId.Top)
                upLight.Color = currentPalette.glowColor
                upLight.Brightness = math.min(currentPalette.glowEmissive * 1.5, 3)
                upLight.Angle = 120
                upLight.Range = 40
                upLight.Shadows = false
                upLight.Enabled = true
                
                -- Downward light
                local downLight = ensureSurfaceLight(inst, Enum.NormalId.Bottom)
                downLight.Color = currentPalette.glowColor
                downLight.Brightness = math.min(currentPalette.glowEmissive * 0.5, 1.5)
                downLight.Angle = 90
                downLight.Range = 15
                downLight.Shadows = false
                downLight.Enabled = true
            end
        end
    end)
    
    -- FloorTile handlers
    connections[#connections + 1] = CollectionService:GetInstanceAddedSignal("FloorTile"):Connect(function(inst)
        if inst:IsA("BasePart") and currentPalette then
            setPart(inst, currentPalette.floorMaterial, currentPalette.floorColor)
        end
    end)
    
    -- PaletteLight handlers
    connections[#connections + 1] = CollectionService:GetInstanceAddedSignal("PaletteLight"):Connect(function(inst)
        if inst:IsA("BasePart") and currentPalette then
            local light = ensurePointLight(inst)
            light.Color = currentPalette.lightColor
            light.Brightness = math.min(currentPalette.lightBrightness, 3)
            light.Range = calculateLightRange(inst)
            light.Enabled = true
            if inst.Material == Enum.Material.Neon then
                inst.Color = currentPalette.lightColor
            end
        end
    end)
    
    -- PaletteParticle handlers
    connections[#connections + 1] = CollectionService:GetInstanceAddedSignal("PaletteParticle"):Connect(function(inst)
        if inst:IsA("ParticleEmitter") and currentPalette then
            local keypoints = {}
            for i, color in ipairs(currentPalette.particleColors) do
                local time = (i - 1) / math.max(1, #currentPalette.particleColors - 1)
                table.insert(keypoints, ColorSequenceKeypoint.new(time, color))
            end
            if #keypoints > 0 then
                inst.Color = ColorSequence.new(keypoints)
            end
        end
    end)
    
    -- Store connections for cleanup
    MaterialManager._connections = connections
end

-- Create material variant for custom materials
function MaterialManager.CreateMaterialVariant(name: string, properties: {[string]: any}): MaterialVariant?
    local variant = MaterialService:FindFirstChild(name)
    if variant and variant:IsA("MaterialVariant") then
        return variant -- Already exists
    end
    
    variant = Instance.new("MaterialVariant")
    variant.Name = name
    variant.Parent = MaterialService
    
    -- Set properties
    for prop, value in pairs(properties) do
        if prop == "ColorMap" or prop == "MetalnessMap" or prop == "NormalMap" or prop == "RoughnessMap" then
            variant[prop] = value
        elseif prop == "BaseMaterial" then
            variant.BaseMaterial = value
        elseif prop == "StudsPerTile" then
            variant.StudsPerTile = value
        end
    end
    
    return variant
end

-- Cleanup function
function MaterialManager.Cleanup()
    -- Clear caches
    table.clear(lightCache)
    table.clear(highlightCache)
    table.clear(spotlightCache)
end

return MaterialManager