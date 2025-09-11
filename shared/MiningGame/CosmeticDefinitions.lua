--!strict
-- CosmeticDefinitions.lua
-- Comprehensive cosmetic item definitions with variations and themes

local CosmeticDefinitions = {}

-- Color palettes for easy reuse
local Colors = {
    -- Basic colors
    Red = Color3.fromRGB(255, 50, 50),
    Blue = Color3.fromRGB(50, 100, 255),
    Green = Color3.fromRGB(50, 200, 50),
    Yellow = Color3.fromRGB(255, 255, 0),
    Purple = Color3.fromRGB(150, 50, 200),
    Orange = Color3.fromRGB(255, 150, 0),
    Cyan = Color3.fromRGB(0, 255, 255),
    Pink = Color3.fromRGB(255, 100, 200),
    White = Color3.fromRGB(255, 255, 255),
    Black = Color3.fromRGB(20, 20, 20),
    
    -- Metallic colors
    Gold = Color3.fromRGB(255, 215, 0),
    Silver = Color3.fromRGB(192, 192, 192),
    Bronze = Color3.fromRGB(205, 127, 50),
    Copper = Color3.fromRGB(184, 115, 51),
    
    -- Special colors
    Rainbow = "rainbow", -- Special flag for rainbow effects
    Void = Color3.fromRGB(50, 0, 100),
    Cosmic = Color3.fromRGB(100, 50, 150),
    Neon = Color3.fromRGB(255, 0, 255),
    Ice = Color3.fromRGB(100, 200, 255),
    Fire = Color3.fromRGB(255, 100, 0),
    Nature = Color3.fromRGB(100, 200, 50),
    Shadow = Color3.fromRGB(30, 0, 50),
}

-- Material variations for visual diversity
local Materials = {
    Default = Enum.Material.Plastic,
    Neon = Enum.Material.Neon,
    Metal = Enum.Material.Metal,
    Glass = Enum.Material.Glass,
    ForceField = Enum.Material.ForceField,
    Ice = Enum.Material.Ice,
    Wood = Enum.Material.Wood,
    Fabric = Enum.Material.Fabric,
    Granite = Enum.Material.Granite,
    Marble = Enum.Material.Marble,
}

-- table.clone fallback for older Luau versions
local clone = table.clone or function(t)
    local c = {}
    for k, v in pairs(t) do
        c[k] = v
    end
    return c
end

-- Helper function to generate color variations
local function generateColorVariations(baseName: string, baseItem: table, colors: {[string]: any}): {[string]: any}
    local variations = {}
    for colorName, color in pairs(colors) do
        local id = string.lower(string.format("%s_%s", baseName, colorName))
        local item = clone(baseItem)
        item.id = id
        item.name = string.format("%s %s", colorName, baseItem.name or baseName)
        item.color = color
        variations[id] = item
    end
    return variations
end

-- Base templates for common cosmetic types
local Templates = {
    Aura = {
        type = "cosmetic",
        slot = "aura",
        particleTexture = "rbxasset://textures/particles/sparkles_main.dds",
        emissionRate = 50,
        lifetime = NumberRange.new(1, 2),
        speed = NumberRange.new(2, 4),
    },
    Trail = {
        type = "cosmetic",
        slot = "trail",
        lifetime = 1,
        minLength = 0,
        faceCamera = true,
    },
    Wings = {
        type = "cosmetic",
        slot = "back",
        animates = true,
    },
    Head = {
        type = "cosmetic",
        slot = "head",
    },
    PickaxeSkin = {
        type = "cosmetic",
        slot = "pickaxeSkin",
    },
}

-- Main cosmetic items database
CosmeticDefinitions.ITEMS = {}

-- ============================================
-- AURAS (Particle Effects)
-- ============================================

-- Fire Auras (multiple colors)
local fireAuras = generateColorVariations("aura_fire", {
    slot = "aura",
    type = "cosmetic",
    rarity = "RARE",
    value = 100,
    particleTexture = "rbxasset://textures/particles/fire_main.dds",
    emissionRate = 50,
    lightEmission = 1,
    effect = "fire",
}, {
    red = Colors.Red,
    blue = Colors.Blue,
    green = Colors.Green,
    purple = Colors.Purple,
    gold = Colors.Gold,
})

-- Ice/Frost Auras
local iceAuras = generateColorVariations("aura_ice", {
    slot = "aura",
    type = "cosmetic",
    rarity = "EPIC",
    value = 500,
    particleTexture = "rbxasset://textures/particles/smoke_main.dds",
    emissionRate = 40,
    lightEmission = 0.5,
    effect = "ice",
}, {
    cyan = Colors.Ice,
    white = Colors.White,
    blue = Colors.Blue,
})

-- Special Auras
CosmeticDefinitions.ITEMS["aura_rainbow"] = {
    id = "aura_rainbow",
    name = "Rainbow Aura",
    type = "cosmetic",
    slot = "aura",
    rarity = "LEGENDARY",
    value = 2500,
    effect = "rainbow",
    particleTexture = "rbxasset://textures/particles/sparkles_main.dds",
    emissionRate = 60,
}

CosmeticDefinitions.ITEMS["aura_void"] = {
    id = "aura_void",
    name = "Void Aura",
    type = "cosmetic",
    slot = "aura",
    rarity = "MYTHIC",
    value = 10000,
    color = Colors.Void,
    effect = "void",
    particleTexture = "rbxasset://textures/particles/smoke_main.dds",
    emissionRate = 100,
}

CosmeticDefinitions.ITEMS["aura_cosmic"] = {
    id = "aura_cosmic",
    name = "Cosmic Aura",
    type = "cosmetic",
    slot = "aura",
    rarity = "MYTHIC",
    value = 10000,
    color = Colors.Cosmic,
    effect = "cosmic",
    particleTexture = "rbxasset://textures/particles/sparkles_main.dds",
    emissionRate = 80,
}

-- Energy Auras
local energyAuras = generateColorVariations("aura_energy", {
    slot = "aura",
    type = "cosmetic",
    rarity = "RARE",
    value = 100,
    particleTexture = "rbxasset://textures/particles/sparkles_main.dds",
    emissionRate = 45,
    lightEmission = 0.8,
    effect = "energy",
}, {
    yellow = Colors.Yellow,
    cyan = Colors.Cyan,
    pink = Colors.Pink,
    orange = Colors.Orange,
})

-- Merge all aura variations
for id, item in pairs(fireAuras) do CosmeticDefinitions.ITEMS[id] = item end
for id, item in pairs(iceAuras) do CosmeticDefinitions.ITEMS[id] = item end
for id, item in pairs(energyAuras) do CosmeticDefinitions.ITEMS[id] = item end

-- ============================================
-- TRAILS (Movement Effects)
-- ============================================

-- Speed Trails (different colors)
local speedTrails = generateColorVariations("trail_speed", {
    slot = "trail",
    type = "cosmetic",
    rarity = "COMMON",
    value = 10,
    effect = "speed",
    lifetime = 0.5,
}, {
    yellow = Colors.Yellow,
    white = Colors.White,
    cyan = Colors.Cyan,
    red = Colors.Red,
})

-- Neon Trails
local neonTrails = generateColorVariations("trail_neon", {
    slot = "trail",
    type = "cosmetic",
    rarity = "RARE",
    value = 100,
    effect = "neon",
    lifetime = 1,
    lightEmission = 1,
}, {
    pink = Colors.Pink,
    cyan = Colors.Cyan,
    green = Colors.Green,
    purple = Colors.Purple,
})

-- Special Trails
CosmeticDefinitions.ITEMS["trail_star"] = {
    id = "trail_star",
    name = "Stardust Trail",
    type = "cosmetic",
    slot = "trail",
    rarity = "EPIC",
    value = 500,
    effect = "star",
    texture = "rbxasset://textures/particles/sparkles_main.dds",
    lifetime = 1.5,
}

CosmeticDefinitions.ITEMS["trail_cosmic"] = {
    id = "trail_cosmic",
    name = "Cosmic Trail",
    type = "cosmetic",
    slot = "trail",
    rarity = "LEGENDARY",
    value = 2500,
    effect = "cosmic",
    texture = "rbxasset://textures/particles/smoke_main.dds",
    lifetime = 2,
    lightEmission = 1,
}

CosmeticDefinitions.ITEMS["trail_rainbow"] = {
    id = "trail_rainbow",
    name = "Rainbow Trail",
    type = "cosmetic",
    slot = "trail",
    rarity = "LEGENDARY",
    value = 2500,
    effect = "rainbow",
    lifetime = 1.5,
    lightEmission = 1,
}

-- Merge trail variations
for id, item in pairs(speedTrails) do CosmeticDefinitions.ITEMS[id] = item end
for id, item in pairs(neonTrails) do CosmeticDefinitions.ITEMS[id] = item end

-- ============================================
-- WINGS & BACK ITEMS
-- ============================================

-- Wing Sets (different styles and colors)
local wingTypes = {
    angel = { name = "Angel Wings", rarity = "EPIC", value = 500 },
    demon = { name = "Demon Wings", rarity = "LEGENDARY", value = 2500 },
    fairy = { name = "Fairy Wings", rarity = "RARE", value = 100 },
    dragon = { name = "Dragon Wings", rarity = "LEGENDARY", value = 2500 },
    butterfly = { name = "Butterfly Wings", rarity = "UNCOMMON", value = 50 },
    mech = { name = "Mech Wings", rarity = "MYTHIC", value = 10000 },
    crystal = { name = "Crystal Wings", rarity = "EPIC", value = 500 },
    fire = { name = "Fire Wings", rarity = "LEGENDARY", value = 2500 },
    ice = { name = "Ice Wings", rarity = "EPIC", value = 500 },
    void = { name = "Void Wings", rarity = "MYTHIC", value = 10000 },
}

for wingType, wingData in pairs(wingTypes) do
    local id = "back_" .. wingType
    CosmeticDefinitions.ITEMS[id] = {
        id = id,
        name = wingData.name,
        type = "cosmetic",
        slot = "back",
        rarity = wingData.rarity,
        value = wingData.value,
        asset = wingType:gsub("^%l", string.upper) .. "Wings", -- AngelWings, DemonWings, etc.
        animates = true,
    }
end

-- Capes & Other Back Items
CosmeticDefinitions.ITEMS["back_cape_hero"] = {
    id = "back_cape_hero",
    name = "Hero Cape",
    type = "cosmetic",
    slot = "back",
    rarity = "UNCOMMON",
    value = 50,
    asset = "HeroCape",
}

CosmeticDefinitions.ITEMS["back_cape_royal"] = {
    id = "back_cape_royal",
    name = "Royal Cape",
    type = "cosmetic",
    slot = "back",
    rarity = "RARE",
    value = 100,
    asset = "RoyalCape",
}

CosmeticDefinitions.ITEMS["back_jetpack"] = {
    id = "back_jetpack",
    name = "Jetpack",
    type = "cosmetic",
    slot = "back",
    rarity = "LEGENDARY",
    value = 2500,
    asset = "Jetpack",
    hasEffects = true,
}

CosmeticDefinitions.ITEMS["back_backpack"] = {
    id = "back_backpack",
    name = "Explorer's Backpack",
    type = "cosmetic",
    slot = "back",
    rarity = "COMMON",
    value = 10,
    asset = "Backpack",
}

-- ============================================
-- HEAD ACCESSORIES
-- ============================================

local headItems = {
    crown_gold = { name = "Golden Crown", rarity = "LEGENDARY", value = 2500, asset = "GoldenCrown" },
    crown_silver = { name = "Silver Crown", rarity = "EPIC", value = 500, asset = "SilverCrown" },
    crown_bronze = { name = "Bronze Crown", rarity = "RARE", value = 100, asset = "BronzeCrown" },
    halo = { name = "Halo", rarity = "EPIC", value = 500, asset = "Halo", glows = true },
    horns_demon = { name = "Demon Horns", rarity = "RARE", value = 100, asset = "DemonHorns" },
    horns_dragon = { name = "Dragon Horns", rarity = "EPIC", value = 500, asset = "DragonHorns" },
    headphones = { name = "DJ Headphones", rarity = "RARE", value = 100, asset = "Headphones" },
    helmet_miner = { name = "Miner's Helmet", rarity = "COMMON", value = 10, asset = "MinerHelmet" },
    helmet_knight = { name = "Knight Helmet", rarity = "RARE", value = 100, asset = "KnightHelmet" },
    helmet_space = { name = "Space Helmet", rarity = "EPIC", value = 500, asset = "SpaceHelmet" },
    hat_wizard = { name = "Wizard Hat", rarity = "RARE", value = 100, asset = "WizardHat" },
    hat_pirate = { name = "Pirate Hat", rarity = "UNCOMMON", value = 50, asset = "PirateHat" },
    hat_cowboy = { name = "Cowboy Hat", rarity = "COMMON", value = 10, asset = "CowboyHat" },
    glasses_cool = { name = "Cool Shades", rarity = "UNCOMMON", value = 50, asset = "CoolShades" },
    glasses_nerd = { name = "Nerd Glasses", rarity = "COMMON", value = 10, asset = "NerdGlasses" },
    mask_ninja = { name = "Ninja Mask", rarity = "RARE", value = 100, asset = "NinjaMask" },
    mask_hero = { name = "Hero Mask", rarity = "EPIC", value = 500, asset = "HeroMask" },
}

for itemId, itemData in pairs(headItems) do
    local id = "head_" .. itemId
    CosmeticDefinitions.ITEMS[id] = {
        id = id,
        name = itemData.name,
        type = "cosmetic",
        slot = "head",
        rarity = itemData.rarity,
        value = itemData.value,
        asset = itemData.asset,
        glows = itemData.glows,
    }
end

-- ============================================
-- PICKAXE SKINS
-- ============================================

local pickaxeSkins = {
    -- Material-based skins
    golden = { name = "Golden", rarity = "EPIC", value = 500, tint = Colors.Gold, material = Materials.Metal },
    diamond = { name = "Diamond", rarity = "LEGENDARY", value = 2500, tint = Colors.Cyan, material = Materials.Glass },
    obsidian = { name = "Obsidian", rarity = "EPIC", value = 500, tint = Colors.Black, material = Materials.Granite },
    crystal = { name = "Crystal", rarity = "RARE", value = 100, tint = Colors.Purple, material = Materials.Glass },
    
    -- Effect-based skins
    rainbow = { name = "Rainbow", rarity = "LEGENDARY", value = 2500, effect = "rainbow" },
    neon = { name = "Neon", rarity = "RARE", value = 100, tint = Colors.Neon, material = Materials.Neon },
    fire = { name = "Blazing", rarity = "EPIC", value = 500, tint = Colors.Fire, effect = "fire" },
    ice = { name = "Frozen", rarity = "EPIC", value = 500, tint = Colors.Ice, effect = "ice" },
    void = { name = "Void", rarity = "MYTHIC", value = 10000, tint = Colors.Void, effect = "void" },
    cosmic = { name = "Cosmic", rarity = "MYTHIC", value = 10000, tint = Colors.Cosmic, effect = "cosmic" },
    
    -- Style-based skins
    retro = { name = "Retro", rarity = "UNCOMMON", value = 50, effect = "scanlines", tint = Color3.fromRGB(0, 255, 200) },
    steampunk = { name = "Steampunk", rarity = "RARE", value = 100, tint = Colors.Bronze, material = Materials.Metal },
    futuristic = { name = "Futuristic", rarity = "EPIC", value = 500, tint = Colors.Cyan, effect = "hologram" },
    wooden = { name = "Wooden", rarity = "COMMON", value = 10, tint = Color3.fromRGB(139, 69, 19), material = Materials.Wood },
    stone = { name = "Stone", rarity = "COMMON", value = 10, tint = Color3.fromRGB(128, 128, 128), material = Materials.Granite },
}

for skinId, skinData in pairs(pickaxeSkins) do
    local id = "pickaxe_skin_" .. skinId
    CosmeticDefinitions.ITEMS[id] = {
        id = id,
        name = skinData.name .. " Pickaxe",
        type = "cosmetic",
        slot = "pickaxeSkin",
        rarity = skinData.rarity,
        value = skinData.value,
        tint = skinData.tint,
        material = skinData.material,
        effect = skinData.effect,
    }
end

-- ============================================
-- MODEL SWAPS / COSTUMES
-- ============================================

local modelSwaps = {
    robot = { name = "Robot Suit", rarity = "LEGENDARY", value = 2500 },
    knight = { name = "Knight Armor", rarity = "EPIC", value = 500 },
    ninja = { name = "Shadow Ninja", rarity = "LEGENDARY", value = 2500 },
    dragon = { name = "Dragon Warrior", rarity = "MYTHIC", value = 10000 },
    astronaut = { name = "Astronaut Suit", rarity = "EPIC", value = 500 },
    pirate = { name = "Pirate Outfit", rarity = "RARE", value = 100 },
    wizard = { name = "Wizard Robes", rarity = "RARE", value = 100 },
    viking = { name = "Viking Armor", rarity = "EPIC", value = 500 },
    samurai = { name = "Samurai Armor", rarity = "LEGENDARY", value = 2500 },
    superhero = { name = "Superhero Suit", rarity = "EPIC", value = 500 },
}

for swapId, swapData in pairs(modelSwaps) do
    local id = "swap_" .. swapId
    CosmeticDefinitions.ITEMS[id] = {
        id = id,
        name = swapData.name,
        type = "cosmetic",
        slot = "modelSwap",
        rarity = swapData.rarity,
        value = swapData.value,
        costume = swapId:gsub("^%l", string.upper) .. "Costume", -- RobotCostume, KnightCostume, etc.
    }
end

-- ============================================
-- TERRAIN THEMES
-- ============================================

local terrainThemes = {
    industrial = { name = "Industrial", rarity = "RARE", value = 100, palette = "industrial" },
    neon = { name = "Neon City", rarity = "EPIC", value = 500, palette = "neon" },
    nature = { name = "Nature", rarity = "UNCOMMON", value = 50, palette = "nature" },
    void = { name = "Void", rarity = "LEGENDARY", value = 2500, palette = "void" },
    crystal = { name = "Crystal Cave", rarity = "EPIC", value = 500, palette = "crystal" },
    lava = { name = "Lava Core", rarity = "LEGENDARY", value = 2500, palette = "lava" },
    ice = { name = "Frozen Tundra", rarity = "EPIC", value = 500, palette = "ice" },
    desert = { name = "Desert Sands", rarity = "UNCOMMON", value = 50, palette = "desert" },
    ocean = { name = "Ocean Depths", rarity = "RARE", value = 100, palette = "ocean" },
    space = { name = "Space Station", rarity = "LEGENDARY", value = 2500, palette = "space" },
    abyss = { name = "Abyss", rarity = "MYTHIC", value = 5000, palette = "abyss" },
}

for themeId, themeData in pairs(terrainThemes) do
    local id = "terrain_" .. themeId
    CosmeticDefinitions.ITEMS[id] = {
        id = id,
        name = themeData.name .. " Theme",
        type = "cosmetic",
        slot = "terrainTheme",
        rarity = themeData.rarity,
        value = themeData.value,
        palette = themeData.palette,
    }
end

-- ============================================
-- HELPER FUNCTIONS
-- ============================================

-- Get cosmetic by ID
function CosmeticDefinitions.Get(id: string)
    return CosmeticDefinitions.ITEMS[id]
end

-- Get all items in a category
function CosmeticDefinitions.GetByCategory(category: string): {[string]: any}
    local items = {}
    for id, item in pairs(CosmeticDefinitions.ITEMS) do
        if item.slot == category then
            items[id] = item
        end
    end
    return items
end

-- Get all items of a rarity
function CosmeticDefinitions.GetByRarity(rarity: string): {[string]: any}
    local items = {}
    for id, item in pairs(CosmeticDefinitions.ITEMS) do
        if item.rarity == rarity then
            items[id] = item
        end
    end
    return items
end

-- Get all items with a specific effect
function CosmeticDefinitions.GetByEffect(effect: string): {[string]: any}
    local items = {}
    for id, item in pairs(CosmeticDefinitions.ITEMS) do
        if item.effect == effect then
            items[id] = item
        end
    end
    return items
end

-- Count total cosmetics
function CosmeticDefinitions.GetTotalCount(): number
    local count = 0
    for _ in pairs(CosmeticDefinitions.ITEMS) do
        count = count + 1
    end
    return count
end

-- Get random cosmetic of rarity
function CosmeticDefinitions.GetRandomOfRarity(rarity: string): any
    local items = CosmeticDefinitions.GetByRarity(rarity)
    local keys = {}
    for id in pairs(items) do
        table.insert(keys, id)
    end
    if #keys > 0 then
        local randomKey = keys[Random.new():NextInteger(1, #keys)]
        return items[randomKey]
    end
    return nil
end

return CosmeticDefinitions