--!strict
-- CubeMaterialService.lua
-- Handles server-side terrain material changes for cube surfaces and floor

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Terrain = workspace.Terrain

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(MiningGame:WaitForChild("Logger"))
local ErrorService = require(script.Parent.ErrorService)  -- Foundation service
local log = Logger.new("CubeMaterialService")
local ServiceValidator = require(MiningGame:WaitForChild("ServiceValidator"))
local TerrainSurfaceDetector = require(MiningGame:WaitForChild("TerrainSurfaceDetector"))
local GameConfig = require(MiningGame:WaitForChild("GameConfig"))
local MaterialKeys = require(MiningGame:WaitForChild("MaterialKeys"))
local MaterialDefinitions = require(MiningGame:WaitForChild("MaterialDefinitions"))
local Remotes = require(MiningGame:WaitForChild("Remotes"))
local EventBus = require(MiningGame:WaitForChild("EventBus"))
local EventNames = require(MiningGame:WaitForChild("EventNames"))
local EventContracts = require(MiningGame:WaitForChild("EventContracts"))
local Bus = EventBus.global()

-- Services (injected via Init)
local DataService
local GridService

local Service = {}
Service.__index = Service

-- Initialize with DI container
function Service:Init(container)
    GridService = ServiceValidator.get(container, "GridService")
    DataService = ServiceValidator.get(container, "DataService", {"GetPlayerData", "GetMaterialPrefs", "QueueSave"})
    log:info("Initialized with dependencies")
end

-- Constants from GameConfig
local VOX = GameConfig.Terrain.VOXEL_RESOLUTION
local MIN_WATER = GameConfig.Terrain.MIN_WATER_OCCUPANCY

-- Precomputed list of all terrain materials
local ALL_TERRAIN_ENUMS = MaterialDefinitions.AllTerrainEnums

-- Get terrain material from MaterialKeys module
local function getTerrainMaterial(key: string): Enum.Material
    key = string.lower(key or "")
    local mat = MaterialKeys.EnumFromKey[key]
    if not mat then
        log:warn("Unknown material key: {} -> defaulting to Rock", key)
        return Enum.Material.Rock
    end
    return mat
end

-- Get player's cube origin position
local function getCubeOrigin(player: Player): Vector3
    -- Find the model anywhere under Workspace (handles streaming)
    local userId = player.UserId
    local model = workspace:FindFirstChild("MiningCube_" .. tostring(userId), true)
    
    if model and model:IsA("Model") then
        -- Use pivot for model center
        return model:GetPivot().Position
    end
    
    -- Fallback to default position
    log:warn("Could not find cube for player {}", player.Name)
    return Vector3.new(0, 10, 0)
end

-- Paint the entire cube volume - preserve existing shape (don't fill air)
local function paintCubeVolume(player: Player, mat: Enum.Material)
    local RESOLUTION = GameConfig.Grid.CELL_SIZE_STUDS
    local size = GameConfig.Grid.CUBE_SIZE_STUDS
    local half = size / 2
    local shell = RESOLUTION -- 1 voxel thick (4 studs) to preserve dig patterns
    local origin = getCubeOrigin(player)
    
    log:info("Painting cube volume for {} at {} with {}", 
        player.Name, tostring(origin), tostring(mat))
    
    -- Use precomputed list of all terrain materials
    local materialsToReplace = ALL_TERRAIN_ENUMS
    
    -- Paint the entire cube volume (not just shell)
    local region = Region3.new(
        origin - Vector3.new(half, half, half),
        origin + Vector3.new(half, half, half)
    ):ExpandToGrid(RESOLUTION)
    
    -- Special handling for water
    if mat == Enum.Material.Water then
        -- Read current voxels for the entire cube
        local materials, occupancies = Terrain:ReadVoxels(region, RESOLUTION)
        local sx, sy, sz = materials.Size.X, materials.Size.Y, materials.Size.Z
        
        for x = 1, sx do
            for y = 1, sy do
                for z = 1, sz do
                    -- Only modify non-air voxels (preserves dug shape)
                    if occupancies[x][y][z] > 0 and materials[x][y][z] ~= Enum.Material.Air then
                        materials[x][y][z] = Enum.Material.Water
                        -- Ensure water is visible even on thin surfaces
                        if occupancies[x][y][z] < MIN_WATER then
                            occupancies[x][y][z] = MIN_WATER
                        end
                    end
                end
            end
        end
        
        -- Write back the modified voxels
        Terrain:WriteVoxels(region, RESOLUTION, materials, occupancies)
        log:debug("Cube volume painted with Water (preserving shape)")
        -- Clear surface detection cache after terrain change
        ErrorService.safecall("TerrainSurfaceDetector.ClearCache", function()
            TerrainSurfaceDetector.ClearCache()
        end)
    else
        -- Standard replacement for non-water materials - replace ALL terrain in the cube
        for _, srcMaterial in ipairs(materialsToReplace) do
            Terrain:ReplaceMaterial(region, RESOLUTION, srcMaterial, mat)
        end
        log:debug("Cube volume painted successfully with {}", tostring(mat))
        -- Clear surface detection cache after terrain change
        ErrorService.safecall("TerrainSurfaceDetector.ClearCache", function()
            TerrainSurfaceDetector.ClearCache()
        end)
    end
end

-- Replace floor material under the neon bars AND under the entire cube
local function replaceFloorMaterial(player: Player, mat: Enum.Material)
    local model = workspace:FindFirstChild("MiningCube_" .. tostring(player.UserId), true)
    if not model then
        log:warn("Could not find player's cube model")
        return
    end
    
    local indicators = model:FindFirstChild("Indicators", true)
    if not indicators then
        log:warn("No indicators folder found")
        return
    end
    
    log:info("Replacing floor material under neon bars and cube with {}", tostring(mat))
    
    local RESOLUTION = GameConfig.Grid.CELL_SIZE_STUDS
    local replacedCount = 0
    
    -- Compute cube footprint
    local origin = getCubeOrigin(player)
    local bounds = model:FindFirstChild("Bounds", true)
    local cubeSize = GameConfig.Grid.CUBE_SIZE_STUDS
    if bounds and bounds:IsA("BasePart") then
        cubeSize = bounds.Size.X -- trust the actual cube
    end
    local half = cubeSize / 2
    local floorDepth = RESOLUTION * 2 -- 8 studs
    
    local cubeFloorRegion = Region3.new(
        Vector3.new(origin.X - half, origin.Y - half - floorDepth, origin.Z - half),
        Vector3.new(origin.X + half, origin.Y - half, origin.Z + half)
    ):ExpandToGrid(RESOLUTION)
    
    -- Replace across footprint (with Water special-case)
    local allTerrainMaterials = ALL_TERRAIN_ENUMS
    
    if mat == Enum.Material.Water then
        local materials, occupancies = Terrain:ReadVoxels(cubeFloorRegion, RESOLUTION)
        local sx, sy, sz = materials.Size.X, materials.Size.Y, materials.Size.Z
        for x = 1, sx do
            for y = 1, sy do
                for z = 1, sz do
                    -- fill only where something already exists (don't build new floor here)
                    if occupancies[x][y][z] > 0 and materials[x][y][z] ~= Enum.Material.Air then
                        materials[x][y][z] = Enum.Material.Water
                        if occupancies[x][y][z] < MIN_WATER then
                            occupancies[x][y][z] = MIN_WATER
                        end
                    end
                end
            end
        end
        Terrain:WriteVoxels(cubeFloorRegion, RESOLUTION, materials, occupancies)
        ErrorService.safecall("TerrainSurfaceDetector.ClearCache", function()
            TerrainSurfaceDetector.ClearCache()
        end)
    else
        for _, srcMaterial in ipairs(allTerrainMaterials) do
            Terrain:ReplaceMaterial(cubeFloorRegion, RESOLUTION, srcMaterial, mat)
        end
    end
    
    log:debug("Replaced floor material under cube at {}", tostring(origin))
    
    -- Then process each glow bar (reuse allTerrainMaterials)
    for _, edge in ipairs(indicators:GetChildren()) do
        if edge:IsA("BasePart") and edge.Material == Enum.Material.Neon then
            local pad = 1
            local depth = RESOLUTION
            local thickness = edge.Size.Y
            local y0 = edge.Position.Y - (thickness/2)
            
            local region = Region3.new(
                Vector3.new(edge.Position.X - edge.Size.X/2 - pad, y0 - depth, edge.Position.Z - edge.Size.Z/2 - pad),
                Vector3.new(edge.Position.X + edge.Size.X/2 + pad, y0, edge.Position.Z + edge.Size.Z/2 + pad)
            ):ExpandToGrid(RESOLUTION)
            
            if mat == Enum.Material.Water then
                local mats, occs = Terrain:ReadVoxels(region, RESOLUTION)
                local sx, sy, sz = mats.Size.X, mats.Size.Y, mats.Size.Z
                for x = 1, sx do
                    for y = 1, sy do
                        for z = 1, sz do
                            if occs[x][y][z] > 0 and mats[x][y][z] ~= Enum.Material.Air then
                                mats[x][y][z] = Enum.Material.Water
                                if occs[x][y][z] < MIN_WATER then occs[x][y][z] = MIN_WATER end
                            end
                        end
                    end
                end
                Terrain:WriteVoxels(region, RESOLUTION, mats, occs)
            else
                for _, srcMaterial in ipairs(allTerrainMaterials) do
                    Terrain:ReplaceMaterial(region, RESOLUTION, srcMaterial, mat)
                end
            end
            
            replacedCount = replacedCount + 1
        end
    end
    
    log:debug("Replaced floor material under {} neon bars", replacedCount)
    -- Clear cache after all floor changes
    ErrorService.safecall("TerrainSurfaceDetector.ClearCache", function()
        TerrainSurfaceDetector.ClearCache()
    end)
end

-- Remote function handlers
function Service.ApplyCubeSurfaceMaterial(player: Player, key: string)
    -- DEPRECATED: Single material mode removed - redirect to composition
    log:info("Single material mode deprecated - applying default theme instead")
    
    local prefs = DataService:GetMaterialPrefs(player) or {}
    
    -- Force composition mode with underwater cave theme
    DataService:UpdateMaterialPrefs(player, {
        mode = "composition",
        activeThemeId = prefs.activeThemeId or "underwater_cave",
        compositionSeed = prefs.compositionSeed or Random.new():NextInteger(1, 1000000),
        variationMode = "PER_REGEN",
    })
    
    -- Emit event to apply the composition (decoupled from CompositionService)
    Bus:emit(EventNames.COMPOSITION_APPLY_REQUEST, {
        to = { kind = "server" },
        payload = EventContracts.COMPOSITION_APPLY_REQUEST({
            userId = player.UserId,
            variationMode = prefs.variationMode or "PER_REGEN",
            preserveAir = true,
        })
    })
    
    -- Return success (application happens asynchronously via event)
    return true, nil
end

function Service.ApplyFloorMaterial(player: Player, key: string)
    if type(key) ~= "string" then
        log:warn("Invalid floor material key type")
        return false
    end
    
    local mat = getTerrainMaterial(key)
    
    log:info("Player {} requesting floor material: {} -> {}", 
        player.Name, key, tostring(mat))
    
    replaceFloorMaterial(player, mat)
    
    -- Save the preference
    pcall(function() 
        DataService:UpdateMaterialPrefs(player, { floorMaterial = string.lower(key) }) 
    end)
    
    return true
end

-- Handle material preference requests
function Service.GetMaterialPreferences(player: Player)
    return DataService:GetMaterialPrefs(player)
end

function Service.SetPalettePreference(player: Player, paletteKey: string)
    if type(paletteKey) ~= "string" then return false end
    return DataService:UpdateMaterialPrefs(player, { palette = string.lower(paletteKey) })
end

-- [MIGRATED TO CubeMaterialServiceRemotes.lua]
-- All remote handlers now use centralized RemoteManager pattern

log:info("Initialized")

return Service