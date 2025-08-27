--!strict
-- CubeMaterialService.lua
-- Handles server-side terrain material changes for cube surfaces and floor

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Terrain = workspace.Terrain

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local ServerMiningGame = ServerScriptService:WaitForChild("MiningGame")
local GameConfig = require(MiningGame:WaitForChild("GameConfig"))
local Remotes = require(ServerMiningGame:WaitForChild("Remotes"))

local Service = {}

-- Single unified material map (lowercase keys) - ALL 22 terrain materials
local MATERIAL_KEY_MAP: {[string]: Enum.Material} = {
    -- All valid terrain materials
    asphalt = Enum.Material.Asphalt,
    basalt = Enum.Material.Basalt,
    brick = Enum.Material.Brick,
    cobblestone = Enum.Material.Cobblestone,
    concrete = Enum.Material.Concrete,
    crackedlava = Enum.Material.CrackedLava,
    glacier = Enum.Material.Glacier,
    grass = Enum.Material.Grass,
    ground = Enum.Material.Ground,
    ice = Enum.Material.Ice,
    leafygrass = Enum.Material.LeafyGrass,
    limestone = Enum.Material.Limestone,
    mud = Enum.Material.Mud,
    pavement = Enum.Material.Pavement,
    rock = Enum.Material.Rock,
    salt = Enum.Material.Salt,
    sand = Enum.Material.Sand,
    sandstone = Enum.Material.Sandstone,
    slate = Enum.Material.Slate,
    snow = Enum.Material.Snow,
    water = Enum.Material.Water,
    woodplanks = Enum.Material.WoodPlanks,
    
}

-- Single function to get terrain material from any key
local function getTerrainMaterial(key: string): Enum.Material
    key = string.lower(key or "")
    local mat = MATERIAL_KEY_MAP[key]
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
    
    -- List of ALL valid terrain materials from Roblox docs (excluding Air)
    local materialsToReplace = {
        Enum.Material.Asphalt,
        Enum.Material.Basalt,
        Enum.Material.Brick,
        Enum.Material.Cobblestone,
        Enum.Material.Concrete,
        Enum.Material.CrackedLava,
        Enum.Material.Glacier,
        Enum.Material.Grass,
        Enum.Material.Ground,
        Enum.Material.Ice,
        Enum.Material.LeafyGrass,
        Enum.Material.Limestone,
        Enum.Material.Mud,
        Enum.Material.Pavement,
        Enum.Material.Rock,
        Enum.Material.Salt,
        Enum.Material.Sand,
        Enum.Material.Sandstone,
        Enum.Material.Slate,
        Enum.Material.Snow,
        Enum.Material.Water,
        Enum.Material.WoodPlanks,
    }
    
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

-- Replace floor material under the neon bars
local function replaceFloorMaterial(player: Player, mat: Enum.Material)
    local model = workspace:FindFirstChild("MiningCube_" .. tostring(player.UserId))
    if not model then
        warn("[CubeMaterialService] Could not find player's cube model")
        return
    end
    
    local indicators = model:FindFirstChild("Indicators", true) -- recursive search
    if not indicators then
        warn("[CubeMaterialService] No indicators folder found")
        return
    end
    
    print(string.format("[CubeMaterialService] Replacing floor material under neon bars with %s", tostring(mat)))
    
    local RESOLUTION = GameConfig.Grid.CELL_SIZE_STUDS -- Use grid size (4)
    local replacedCount = 0
    
    -- Process each glow bar (identify by Neon material)
    for _, edge in ipairs(indicators:GetChildren()) do
        if edge:IsA("BasePart") and edge.Material == Enum.Material.Neon then
            -- Calculate region under the bar
            local pad = 1
            local depth = RESOLUTION -- Use grid-aligned depth (4 studs)
            local thickness = edge.Size.Y
            local y0 = edge.Position.Y - (thickness/2)
            
            local region = Region3.new(
                Vector3.new(edge.Position.X - edge.Size.X/2 - pad, y0 - depth, edge.Position.Z - edge.Size.Z/2 - pad),
                Vector3.new(edge.Position.X + edge.Size.X/2 + pad, y0, edge.Position.Z + edge.Size.Z/2 + pad)
            ):ExpandToGrid(RESOLUTION)
            
            -- Replace ALL valid terrain materials from Roblox docs
            local materials = {
                Enum.Material.Asphalt,
                Enum.Material.Basalt,
                Enum.Material.Brick,
                Enum.Material.Cobblestone,
                Enum.Material.Concrete,
                Enum.Material.CrackedLava,
                Enum.Material.Glacier,
                Enum.Material.Grass,
                Enum.Material.Ground,
                Enum.Material.Ice,
                Enum.Material.LeafyGrass,
                Enum.Material.Limestone,
                Enum.Material.Mud,
                Enum.Material.Pavement,
                Enum.Material.Rock,
                Enum.Material.Salt,
                Enum.Material.Sand,
                Enum.Material.Sandstone,
                Enum.Material.Slate,
                Enum.Material.Snow,
                Enum.Material.Water,
                Enum.Material.WoodPlanks,
            }
            
            for _, srcMaterial in ipairs(materials) do
                Terrain:ReplaceMaterial(region, RESOLUTION, srcMaterial, mat)
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
    return true
end

-- Bind remote functions
Remotes.RF.ApplyCubeSurfaceMaterial.OnServerInvoke = Service.ApplyCubeSurfaceMaterial
Remotes.RF.ApplyFloorMaterial.OnServerInvoke = Service.ApplyFloorMaterial

print("[CubeMaterialService] Initialized")

return Service