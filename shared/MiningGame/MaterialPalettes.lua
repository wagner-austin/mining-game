--!strict
-- MaterialPalettes.lua
-- Configuration for visual material themes with emissive properties

local MaterialPalettes = {}

-- Material palette definitions with emissive and visual properties
MaterialPalettes.Palettes = {
    -- Default cyan tech palette
    default = {
        name = "Default",
        description = "Clean tech aesthetic",
        
        -- Floor material under neon bars
        floorMaterial = Enum.Material.Concrete,
        floorColor = Color3.fromRGB(80, 80, 80),
        
        -- Neon bar properties
        glowColor = Color3.fromRGB(0, 255, 255),
        glowEmissive = 2.0, -- Emissive multiplier
        glowTransparency = 0.3,
        
        -- Lighting
        lightColor = Color3.fromRGB(180, 255, 255),
        lightBrightness = 1.5,
        
        -- Cube material (when unlocked)
        cubeMaterial = Enum.Material.Rock,
        cubeColor = Color3.fromRGB(140, 140, 140),
        cubeEmissive = 0, -- No emission for basic rock
        cubeVariant = nil, -- Optional MaterialVariant name
        
        -- Particle colors
        particleColors = {
            Color3.fromRGB(0, 200, 200),
            Color3.fromRGB(0, 255, 255),
            Color3.fromRGB(100, 255, 255),
        },
    },
    
    -- Industrial amber/yellow palette
    industrial = {
        name = "Industrial",
        description = "Heavy machinery and warning lights",
        
        floorMaterial = Enum.Material.DiamondPlate,
        floorColor = Color3.fromRGB(100, 100, 100),
        
        glowColor = Color3.fromRGB(255, 200, 0),
        glowEmissive = 1.8,
        glowTransparency = 0.25,
        
        lightColor = Color3.fromRGB(255, 220, 100),
        lightBrightness = 1.8,
        
        cubeMaterial = Enum.Material.CorrodedMetal,
        cubeColor = Color3.fromRGB(104, 140, 173),
        cubeEmissive = 0,
        cubeVariant = nil,
        
        particleColors = {
            Color3.fromRGB(255, 180, 0),
            Color3.fromRGB(255, 200, 50),
            Color3.fromRGB(255, 220, 100),
        },
    },
    
    -- Natural forest/earth palette
    natural = {
        name = "Natural",
        description = "Organic earth tones",
        
        floorMaterial = Enum.Material.Slate,
        floorColor = Color3.fromRGB(88, 89, 86),
        
        glowColor = Color3.fromRGB(200, 255, 150),
        glowEmissive = 1.2,
        glowTransparency = 0.4,
        
        lightColor = Color3.fromRGB(220, 255, 200),
        lightBrightness = 1.3,
        
        cubeMaterial = Enum.Material.Ground,
        cubeColor = Color3.fromRGB(140, 130, 104),
        cubeEmissive = 0,
        cubeVariant = nil,
        
        particleColors = {
            Color3.fromRGB(180, 220, 140),
            Color3.fromRGB(200, 255, 150),
            Color3.fromRGB(150, 200, 100),
        },
    },
    
    -- Ice cave palette
    ice = {
        name = "Ice Cave",
        description = "Frozen caverns with crystalline glow",
        
        floorMaterial = Enum.Material.Ice,
        floorColor = Color3.fromRGB(204, 210, 223),
        
        glowColor = Color3.fromRGB(150, 200, 255),
        glowEmissive = 2.5,
        glowTransparency = 0.2,
        
        lightColor = Color3.fromRGB(200, 220, 255),
        lightBrightness = 2.0,
        
        cubeMaterial = Enum.Material.Glacier,
        cubeColor = Color3.fromRGB(221, 228, 229),
        cubeEmissive = 0.5, -- Slight ice glow
        cubeVariant = nil,
        
        particleColors = {
            Color3.fromRGB(150, 200, 255),
            Color3.fromRGB(200, 220, 255),
            Color3.fromRGB(180, 210, 255),
        },
    },
    
    -- Volcanic/lava palette
    volcanic = {
        name = "Volcanic",
        description = "Molten rock and magma flows",
        
        floorMaterial = Enum.Material.Basalt,
        floorColor = Color3.fromRGB(75, 74, 74),
        
        glowColor = Color3.fromRGB(255, 100, 0),
        glowEmissive = 3.0, -- Very bright
        glowTransparency = 0.15,
        
        lightColor = Color3.fromRGB(255, 150, 50),
        lightBrightness = 2.5,
        
        cubeMaterial = Enum.Material.CrackedLava,
        cubeColor = Color3.fromRGB(255, 24, 67),
        cubeEmissive = 2.0, -- Lava glow
        cubeVariant = nil, -- Optional: "Cube_Lava" for animated lava effect
        
        particleColors = {
            Color3.fromRGB(255, 100, 0),
            Color3.fromRGB(255, 50, 0),
            Color3.fromRGB(255, 150, 50),
        },
    },
    
    -- Mystic/magic purple palette
    mystic = {
        name = "Mystic",
        description = "Arcane energies and mystical crystals",
        
        floorMaterial = Enum.Material.Marble,
        floorColor = Color3.fromRGB(122, 122, 122),
        
        glowColor = Color3.fromRGB(200, 100, 255),
        glowEmissive = 2.2,
        glowTransparency = 0.25,
        
        lightColor = Color3.fromRGB(220, 150, 255),
        lightBrightness = 1.8,
        
        cubeMaterial = Enum.Material.ForceField,
        cubeColor = Color3.fromRGB(150, 100, 200),
        cubeEmissive = 1.0, -- Magical glow
        cubeVariant = nil,
        
        particleColors = {
            Color3.fromRGB(200, 100, 255),
            Color3.fromRGB(150, 50, 200),
            Color3.fromRGB(255, 150, 255),
        },
    },
    
    -- Desert/sandstone palette
    desert = {
        name = "Desert",
        description = "Ancient sand-swept ruins",
        
        floorMaterial = Enum.Material.Sand,
        floorColor = Color3.fromRGB(207, 203, 167),
        
        glowColor = Color3.fromRGB(255, 220, 100),
        glowEmissive = 1.5,
        glowTransparency = 0.35,
        
        lightColor = Color3.fromRGB(255, 230, 150),
        lightBrightness = 1.6,
        
        cubeMaterial = Enum.Material.Sandstone,
        cubeColor = Color3.fromRGB(148, 124, 95),
        cubeEmissive = 0,
        cubeVariant = nil,
        
        particleColors = {
            Color3.fromRGB(255, 220, 100),
            Color3.fromRGB(255, 200, 80),
            Color3.fromRGB(255, 230, 150),
        },
    },
    
    -- Ocean/underwater palette
    ocean = {
        name = "Ocean Depths",
        description = "Deep sea bioluminescence",
        
        floorMaterial = Enum.Material.Salt,
        floorColor = Color3.fromRGB(255, 255, 254),
        
        glowColor = Color3.fromRGB(0, 150, 255),
        glowEmissive = 2.0,
        glowTransparency = 0.3,
        
        lightColor = Color3.fromRGB(100, 200, 255),
        lightBrightness = 1.4,
        
        cubeMaterial = Enum.Material.Glass, -- Glass works well for water effect
        cubeColor = Color3.fromRGB(138, 167, 168),
        cubeEmissive = 0.3, -- Slight underwater glow
        cubeVariant = nil, -- Optional: "Cube_Water" for custom water material
        
        particleColors = {
            Color3.fromRGB(0, 150, 255),
            Color3.fromRGB(0, 200, 255),
            Color3.fromRGB(100, 200, 255),
        },
    },
    
    -- Futuristic neon palette
    futuristic = {
        name = "Cyberpunk",
        description = "Neon-lit future cityscape",
        
        floorMaterial = Enum.Material.Metal,
        floorColor = Color3.fromRGB(168, 175, 176),
        
        glowColor = Color3.fromRGB(255, 0, 255),
        glowEmissive = 3.5, -- Super bright neon
        glowTransparency = 0.1,
        
        lightColor = Color3.fromRGB(255, 100, 255),
        lightBrightness = 2.5,
        
        cubeMaterial = Enum.Material.Neon,
        cubeColor = Color3.fromRGB(100, 0, 100),
        cubeEmissive = 2.0, -- Neon cube
        cubeVariant = nil, -- Optional: "Cube_Cyberpunk" if you create a MaterialVariant
        
        particleColors = {
            Color3.fromRGB(255, 0, 255),
            Color3.fromRGB(255, 0, 150),
            Color3.fromRGB(200, 0, 255),
        },
    },
    
    -- Ancient ruins palette
    ancient = {
        name = "Ancient Ruins",
        description = "Weathered stone temples",
        
        floorMaterial = Enum.Material.Limestone,
        floorColor = Color3.fromRGB(255, 243, 192),
        
        glowColor = Color3.fromRGB(255, 200, 150),
        glowEmissive = 1.0,
        glowTransparency = 0.45,
        
        lightColor = Color3.fromRGB(255, 220, 180),
        lightBrightness = 1.2,
        
        cubeMaterial = Enum.Material.Cobblestone,
        cubeColor = Color3.fromRGB(134, 134, 118),
        cubeEmissive = 0,
        cubeVariant = nil,
        
        particleColors = {
            Color3.fromRGB(255, 200, 150),
            Color3.fromRGB(255, 180, 120),
            Color3.fromRGB(255, 220, 180),
        },
    },
    
    -- Void/space palette
    void = {
        name = "Void",
        description = "Dark matter and cosmic energy",
        
        floorMaterial = Enum.Material.Slate,
        floorColor = Color3.fromRGB(20, 20, 30),
        
        glowColor = Color3.fromRGB(100, 0, 200),
        glowEmissive = 4.0, -- Extremely bright
        glowTransparency = 0.05,
        
        lightColor = Color3.fromRGB(150, 50, 255),
        lightBrightness = 3.0,
        
        cubeMaterial = Enum.Material.Neon,
        cubeColor = Color3.fromRGB(20, 0, 50),
        cubeEmissive = 3.0, -- Dark energy glow
        cubeVariant = nil,
        
        particleColors = {
            Color3.fromRGB(100, 0, 200),
            Color3.fromRGB(50, 0, 150),
            Color3.fromRGB(150, 50, 255),
        },
    },
    
    -- Emerald/jade palette
    emerald = {
        name = "Emerald",
        description = "Precious gemstone cavern",
        
        floorMaterial = Enum.Material.Granite,
        floorColor = Color3.fromRGB(149, 146, 139),
        
        glowColor = Color3.fromRGB(0, 255, 100),
        glowEmissive = 2.5,
        glowTransparency = 0.2,
        
        lightColor = Color3.fromRGB(100, 255, 150),
        lightBrightness = 2.0,
        
        cubeMaterial = Enum.Material.Glass,
        cubeColor = Color3.fromRGB(0, 200, 100),
        cubeEmissive = 1.5, -- Gem glow
        cubeVariant = nil,
        
        particleColors = {
            Color3.fromRGB(0, 255, 100),
            Color3.fromRGB(0, 200, 80),
            Color3.fromRGB(50, 255, 150),
        },
    },
}

-- Get palette by name
function MaterialPalettes.GetPalette(name: string)
    return MaterialPalettes.Palettes[name] or MaterialPalettes.Palettes.default
end

-- Get list of all palette names
function MaterialPalettes.GetPaletteNames(): {string}
    local names = {}
    for key, _ in pairs(MaterialPalettes.Palettes) do
        table.insert(names, key)
    end
    table.sort(names)
    return names
end

-- Check if palette exists
function MaterialPalettes.PaletteExists(name: string): boolean
    return MaterialPalettes.Palettes[name] ~= nil
end

-- Special visual-only cube materials (not in GameConfig progression)
MaterialPalettes.SpecialMaterials = {
    water = {
        name = "Water",
        material = Enum.Material.Glass,
        color = Color3.fromRGB(82, 124, 174),
        emissive = 0.6,
        transparency = 0.4,
    },
    lava = {
        name = "Lava",
        material = Enum.Material.CrackedLava,
        color = Color3.fromRGB(255, 24, 67),
        emissive = 2.0,
    },
    ice = {
        name = "Ice",
        material = Enum.Material.Ice,
        color = Color3.fromRGB(204, 210, 223),
        emissive = 0.5,
    },
    glass = {
        name = "Glass",
        material = Enum.Material.Glass,
        color = Color3.fromRGB(138, 167, 168),
        emissive = 0.4,
        transparency = 0.3,
    },
    neon = {
        name = "Neon",
        material = Enum.Material.Neon,
        color = Color3.fromRGB(255, 0, 255),
        emissive = 2.0,
    },
    wood = {
        name = "Wood",
        material = Enum.Material.Wood,
        color = Color3.fromRGB(172, 148, 108),
        emissive = 0,
    },
    metal = {
        name = "Metal",
        material = Enum.Material.Metal,
        color = Color3.fromRGB(168, 175, 176),
        emissive = 0.2,
    },
}

-- Get special material by key
function MaterialPalettes.GetSpecialMaterial(key: string)
    return MaterialPalettes.SpecialMaterials[key]
end

return MaterialPalettes