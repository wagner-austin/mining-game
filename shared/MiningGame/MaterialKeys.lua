--!strict
-- MaterialKeys.lua
-- Shared material key definitions to ensure client/server synchronization

local MaterialKeys = {}

-- Canonical terrain materials list (lowercase keys) - ALL 22 terrain materials
MaterialKeys.TerrainKeys = {
    "asphalt",
    "basalt",
    "brick",
    "cobblestone",
    "concrete",
    "crackedlava",
    "glacier",
    "grass",
    "ground",
    "ice",
    "leafygrass",
    "limestone",
    "mud",
    "pavement",
    "rock",
    "salt",
    "sand",
    "sandstone",
    "slate",
    "snow",
    "water",
    "woodplanks",
}

-- Use the same list for both (they're both terrain!)
MaterialKeys.CubeMaterials = MaterialKeys.TerrainKeys
MaterialKeys.FloorMaterials = MaterialKeys.TerrainKeys

-- Display names for materials (lowercase keys)
MaterialKeys.DisplayNames = {
    -- Terrain materials
    rock = "Rock",
    sandstone = "Sandstone",
    basalt = "Basalt",
    slate = "Slate",
    limestone = "Limestone",
    glacier = "Glacier",
    ice = "Ice",
    snow = "Snow",
    sand = "Sand",
    mud = "Mud",
    ground = "Ground",
    grass = "Grass",
    leafygrass = "Leafy Grass",
    concrete = "Concrete",
    cobblestone = "Cobblestone",
    water = "Water",
    asphalt = "Asphalt",
    pavement = "Pavement",
    brick = "Brick",
    salt = "Salt",
    woodplanks = "Wood Planks",
    crackedlava = "Cracked Lava",
    
}

-- Canonical bidirectional mapping between our terrain keys and Enum.Material.
-- This covers every key in MaterialKeys.TerrainKeys (22 items), including water.
MaterialKeys.EnumFromKey = {
    asphalt     = Enum.Material.Asphalt,
    basalt      = Enum.Material.Basalt,
    brick       = Enum.Material.Brick,
    cobblestone = Enum.Material.Cobblestone,
    concrete    = Enum.Material.Concrete,
    crackedlava = Enum.Material.CrackedLava,
    glacier     = Enum.Material.Glacier,
    grass       = Enum.Material.Grass,
    ground      = Enum.Material.Ground,
    ice         = Enum.Material.Ice,
    leafygrass  = Enum.Material.LeafyGrass,
    limestone   = Enum.Material.Limestone,
    mud         = Enum.Material.Mud,
    pavement    = Enum.Material.Pavement,
    rock        = Enum.Material.Rock,
    salt        = Enum.Material.Salt,
    sand        = Enum.Material.Sand,
    sandstone   = Enum.Material.Sandstone,
    slate       = Enum.Material.Slate,
    snow        = Enum.Material.Snow,
    water       = Enum.Material.Water,      -- ✅ WATER COVERED
    woodplanks  = Enum.Material.WoodPlanks,
}

MaterialKeys.KeyFromEnum = {}
for key, enumMat in pairs(MaterialKeys.EnumFromKey) do
    MaterialKeys.KeyFromEnum[enumMat] = key
end

-- Dev-guard: ensure every listed TerrainKey has a mapping (no dupes or misses).
do
    local seen = {}
    for _, k in ipairs(MaterialKeys.TerrainKeys) do
        assert(MaterialKeys.EnumFromKey[k] ~= nil, ("[MaterialKeys] Missing EnumFromKey for '%s'"):format(k))
        assert(not seen[k], ("[MaterialKeys] Duplicate key '%s' in TerrainKeys"):format(k))
        seen[k] = true
    end
end

return MaterialKeys