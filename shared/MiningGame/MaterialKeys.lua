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

return MaterialKeys