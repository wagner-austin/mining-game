--!strict
-- CubeMaterialService.lua
-- Handles server-side terrain material changes for cube surfaces and floor

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Terrain = workspace.Terrain

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(MiningGame:WaitForChild("Logger"))
local log = Logger.new("CubeMaterialService")
local ServerMiningGame = ServerScriptService:WaitForChild("MiningGame")
local GameConfig = require(MiningGame:WaitForChild("GameConfig"))
local MaterialKeys = require(MiningGame:WaitForChild("MaterialKeys"))
local MaterialDefinitions = require(MiningGame:WaitForChild("MaterialDefinitions"))
local Remotes = require(ServerMiningGame:WaitForChild("Remotes"))
local DataService = require(ServerMiningGame:WaitForChild("DataService"))

local Service = {}

-- Precomputed list of all terrain materials
local ALL_TERRAIN_ENUMS = MaterialDefinitions.AllTerrainEnums

-- Get terrain material from MaterialKeys module
local function getTerrainMaterial(key: string): Enum.Material
    key = string.lower(key or "")
    local mat = MaterialKeys.EnumFromKey[key]
    if not mat then
        warn("[CubeMaterialService] Unknown material key:", key, "-> defaulting to Rock")
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
    warn("[CubeMaterialService] Could not find cube for player", player.Name)
    return Vector3.new(0, 10, 0)
end

-- Paint the entire cube volume - preserve existing shape (don't fill air)
local function paintCubeVolume(player: Player, mat: Enum.Material)
    local RESOLUTION = GameConfig.Grid.CELL_SIZE_STUDS
    local size = GameConfig.Grid.CUBE_SIZE_STUDS
    local half = size / 2
    local shell = RESOLUTION -- 1 voxel thick (4 studs) to preserve dig patterns
    local origin = getCubeOrigin(player)
    
    print(string.format("[CubeMaterialService] Painting cube volume for %s at %s with %s", 
        player.Name, tostring(origin), tostring(mat)))
    
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
                        if occupancies[x][y][z] < 0.3 then
                            occupancies[x][y][z] = 0.3
                        end
                    end
                end
            end
        end
        
        -- Write back the modified voxels
        Terrain:WriteVoxels(region, RESOLUTION, materials, occupancies)
        print("[CubeMaterialService] Cube volume painted with Water (preserving shape)")
    else
        -- Standard replacement for non-water materials - replace ALL terrain in the cube
        for _, srcMaterial in ipairs(materialsToReplace) do
            Terrain:ReplaceMaterial(region, RESOLUTION, srcMaterial, mat)
        end
        print("[CubeMaterialService] Cube volume painted successfully with", tostring(mat))
    end
end

-- Replace floor material under the neon bars AND under the entire cube
local function replaceFloorMaterial(player: Player, mat: Enum.Material)
    local model = workspace:FindFirstChild("MiningCube_" .. tostring(player.UserId), true)
    if not model then
        warn("[CubeMaterialService] Could not find player's cube model")
        return
    end
    
    local indicators = model:FindFirstChild("Indicators", true)
    if not indicators then
        warn("[CubeMaterialService] No indicators folder found")
        return
    end
    
    print(string.format("[CubeMaterialService] Replacing floor material under neon bars and cube with %s", tostring(mat)))
    
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
                        if occupancies[x][y][z] < 0.3 then
                            occupancies[x][y][z] = 0.3
                        end
                    end
                end
            end
        end
        Terrain:WriteVoxels(cubeFloorRegion, RESOLUTION, materials, occupancies)
    else
        for _, srcMaterial in ipairs(allTerrainMaterials) do
            Terrain:ReplaceMaterial(cubeFloorRegion, RESOLUTION, srcMaterial, mat)
        end
    end
    
    print(string.format("[CubeMaterialService] Replaced floor material under cube at %s", tostring(origin)))
    
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
                                if occs[x][y][z] < 0.3 then occs[x][y][z] = 0.3 end
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
    
    print(string.format("[CubeMaterialService] Replaced floor material under %d neon bars", replacedCount))
end

-- Remote function handlers
function Service.ApplyCubeSurfaceMaterial(player: Player, key: string)
    if type(key) ~= "string" then
        warn("[CubeMaterialService] Invalid material key type")
        return false
    end
    
    local mat = getTerrainMaterial(key)
    print(string.format("[CubeMaterialService] Player %s requesting cube material: %s -> %s", 
        player.Name, key, tostring(mat)))
    
    paintCubeVolume(player, mat)  -- Paint entire volume, not just shell
    
    -- Save the preference
    pcall(function() 
        DataService:UpdateMaterialPrefs(player, { cubeMaterial = string.lower(key) }) 
    end)
    
    return true
end

function Service.ApplyFloorMaterial(player: Player, key: string)
    if type(key) ~= "string" then
        warn("[CubeMaterialService] Invalid floor material key type")
        return false
    end
    
    local mat = getTerrainMaterial(key)
    
    print(string.format("[CubeMaterialService] Player %s requesting floor material: %s -> %s", 
        player.Name, key, tostring(mat)))
    
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

-- Bind remote functions
Remotes.RF.ApplyCubeSurfaceMaterial.OnServerInvoke = Service.ApplyCubeSurfaceMaterial
Remotes.RF.ApplyFloorMaterial.OnServerInvoke = Service.ApplyFloorMaterial
Remotes.RF.GetMaterialPreferences.OnServerInvoke = Service.GetMaterialPreferences
Remotes.RF.SetPalettePreference.OnServerInvoke = Service.SetPalettePreference

log:info("Initialized")

return Service