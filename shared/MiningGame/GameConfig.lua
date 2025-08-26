--!strict
-- GameConfig.lua
-- Central configuration for the mining game system
-- This module defines all tunable parameters for easy balancing and expansion

local GameConfig = {}

-- Grid System Configuration
GameConfig.Grid = {
    -- Must be 4 to match Terrain voxels for WriteVoxels optimization
    CELL_SIZE_STUDS = 4,
    
    -- Overall cube edge length in studs
    CUBE_SIZE_STUDS = 128,
    
    -- Chunk dimensions (16x16x16 cells = 4096 cells per chunk)
    CHUNK_CELLS = 16,
    
    -- Maximum visible neighbor cubes (mobile performance)
    MAX_NEIGHBOR_CUBES_VISIBLE = 6,
    
    -- Visual settings for terrain
    DEFAULT_MATERIAL = Enum.Material.Rock,
}

-- Digging Mechanics
GameConfig.Digging = {
    -- Base dig parameters
    BASE_DIG_DELAY = 1.0, -- Seconds between digs
    BASE_DIG_DEPTH_CELLS = 1, -- Cells deep per dig
    BASE_DIG_RADIUS_CELLS = 1, -- Cube radius (diameter = 2*radius+1)
    
    -- Dig shape (can expand to SPHERE later)
    DIG_SHAPE = "CUBE",
    
    -- Visual feedback
    ENABLE_CAMERA_SHAKE = true,
    CAMERA_SHAKE_INTENSITY = 0.1,
    CAMERA_SHAKE_DURATION = 0.15,
    
    -- Sound settings
    DIG_SOUND_ID = "rbxassetid://0", -- Replace with actual sound ID
    HIT_VOLUME = 0.5,
    
    -- Particle effects
    ENABLE_PARTICLES = true,
    PARTICLE_COUNT = 10,
}

-- Player Progression & Upgrades
GameConfig.Upgrades = {
    -- Dig speed (delay reduction) - diminishing returns
    SPEED_LEVELS = {
        {level = 0, cost = 0, multiplier = 1.0},
        {level = 1, cost = 50, multiplier = 0.92},
        {level = 2, cost = 150, multiplier = 0.85},
        {level = 3, cost = 350, multiplier = 0.78},
        {level = 4, cost = 750, multiplier = 0.72},
        {level = 5, cost = 1500, multiplier = 0.66},
        {level = 6, cost = 3000, multiplier = 0.60},
        {level = 7, cost = 6000, multiplier = 0.55},
        {level = 8, cost = 12000, multiplier = 0.50},
        {level = 9, cost = 25000, multiplier = 0.45},
        {level = 10, cost = 50000, multiplier = 0.40},
        {level = 11, cost = 100000, multiplier = 0.35},
        {level = 12, cost = 200000, multiplier = 0.30},
        {level = 13, cost = 400000, multiplier = 0.25},
        {level = 14, cost = 800000, multiplier = 0.20},
        {level = 15, cost = 1600000, multiplier = 0.15},
    },
    
    -- Dig strength (depth per dig)
    STRENGTH_LEVELS = {
        {level = 0, cost = 0, depth = 1},
        {level = 1, cost = 100, depth = 2},
        {level = 2, cost = 300, depth = 3},
        {level = 3, cost = 700, depth = 4},
        {level = 4, cost = 1500, depth = 5},
        {level = 5, cost = 3000, depth = 6},
        {level = 6, cost = 6000, depth = 7},
        {level = 7, cost = 12000, depth = 8},
        {level = 8, cost = 25000, depth = 9},
        {level = 9, cost = 50000, depth = 10},
        {level = 10, cost = 100000, depth = 12},
    },
    
    -- Dig radius (area of effect) - expensive for performance
    RADIUS_LEVELS = {
        {level = 0, cost = 0, radius = 1},
        {level = 1, cost = 200, radius = 2},
        {level = 2, cost = 800, radius = 3},
        {level = 3, cost = 3000, radius = 4},
        {level = 4, cost = 10000, radius = 5},
        {level = 5, cost = 30000, radius = 6},
        {level = 6, cost = 80000, radius = 7},
        {level = 7, cost = 200000, radius = 8},
        {level = 8, cost = 500000, radius = 9},
        {level = 9, cost = 1200000, radius = 10},
    },
}

-- Pet System
GameConfig.Pets = {
    -- Pet definitions with buff values
    PETS = {
        {id = "bunny", name = "Speed Bunny", rarity = "COMMON", 
         buffs = {speed = 0.05, luck = 0}},
        {id = "cat", name = "Lucky Cat", rarity = "UNCOMMON", 
         buffs = {speed = 0.03, luck = 0.1}},
        {id = "dog", name = "Strong Dog", rarity = "UNCOMMON", 
         buffs = {strength = 0.1, radius = 0}},
        {id = "eagle", name = "Golden Eagle", rarity = "RARE", 
         buffs = {speed = 0.08, strength = 0.08, luck = 0.05}},
        {id = "dragon", name = "Mining Dragon", rarity = "EPIC", 
         buffs = {strength = 0.15, radius = 0.1, luck = 0.1}},
        {id = "phoenix", name = "Phoenix", rarity = "LEGENDARY", 
         buffs = {speed = 0.15, strength = 0.15, luck = 0.2}},
        {id = "cosmic", name = "Cosmic Entity", rarity = "MYTHIC", 
         buffs = {speed = 0.25, strength = 0.25, radius = 0.15, luck = 0.3}},
    },
    
    -- Pet star levels (multiplicative with base buffs)
    STAR_MULTIPLIERS = {
        1.0,  -- 1 star (base)
        1.25, -- 2 stars
        1.5,  -- 3 stars
        1.8,  -- 4 stars
        2.2,  -- 5 stars
    },
    
    MAX_EQUIPPED = 3, -- Maximum pets equipped at once
}

-- Monetization (Robux purchases)
GameConfig.Monetization = {
    -- Developer Products (consumables)
    PRODUCTS = {
        -- Speed boosts
        {id = "SPEED_1HR", productId = 0, robux = 25, 
         effect = "speed", multiplier = 0.5, duration = 3600},
        {id = "SPEED_24HR", productId = 0, robux = 99, 
         effect = "speed", multiplier = 0.5, duration = 86400},
        
        -- Luck boosts
        {id = "LUCK_1HR", productId = 0, robux = 49, 
         effect = "luck", multiplier = 2.0, duration = 3600},
        {id = "LUCK_24HR", productId = 0, robux = 199, 
         effect = "luck", multiplier = 2.0, duration = 86400},
        
        -- Instant actions
        {id = "MEGA_DIG", productId = 0, robux = 49, 
         effect = "instant_dig", radius = 10, depth = 10},
        {id = "AUTO_DIGGER", productId = 0, robux = 299, 
         effect = "auto_dig", duration = 3600},
        
        -- Currency
        {id = "COINS_5K", productId = 0, robux = 99, coins = 5000},
        {id = "COINS_25K", productId = 0, robux = 399, coins = 25000},
        {id = "COINS_100K", productId = 0, robux = 1499, coins = 100000},
    },
    
    -- Game Passes (permanent)
    GAMEPASSES = {
        {id = "VIP", gamepassId = 0, robux = 399, 
         effects = {loot_multiplier = 2.0, exp_multiplier = 2.0}},
        {id = "MEGA_PICKAXE", gamepassId = 0, robux = 799, 
         effects = {radius_bonus = 2, strength_bonus = 2}},
        {id = "AUTO_COLLECT", gamepassId = 0, robux = 299, 
         effects = {auto_collect_radius = 50}},
        {id = "EXTRA_PETS", gamepassId = 0, robux = 499, 
         effects = {max_pets_bonus = 2}},
    },
}

-- Loot Tables and Items
GameConfig.Loot = {
    -- Base drop chance per cell dug
    BASE_DROP_CHANCE = 0.15, -- 15% chance per cell
    
    -- Rarity tiers with weights and colors
    RARITIES = {
        COMMON = {weight = 1000, color = Color3.fromRGB(150, 150, 150), value_mult = 1},
        UNCOMMON = {weight = 250, color = Color3.fromRGB(50, 200, 50), value_mult = 3},
        RARE = {weight = 50, color = Color3.fromRGB(50, 100, 255), value_mult = 10},
        EPIC = {weight = 10, color = Color3.fromRGB(150, 50, 200), value_mult = 50},
        LEGENDARY = {weight = 2, color = Color3.fromRGB(255, 200, 0), value_mult = 250},
        MYTHIC = {weight = 0.1, color = Color3.fromRGB(255, 50, 50), value_mult = 2500},
    },
    
    -- Item definitions
    ITEMS = {
        -- Resources (sellable)
        {id = "stone", name = "Stone", rarity = "COMMON", value = 1, type = "resource"},
        {id = "coal", name = "Coal", rarity = "COMMON", value = 5, type = "resource"},
        {id = "copper", name = "Copper Ore", rarity = "COMMON", value = 10, type = "resource"},
        {id = "iron", name = "Iron Ore", rarity = "UNCOMMON", value = 15, type = "resource"},
        {id = "silver", name = "Silver Ore", rarity = "UNCOMMON", value = 30, type = "resource"},
        {id = "gold", name = "Gold Ore", rarity = "RARE", value = 50, type = "resource"},
        {id = "crystal", name = "Crystal", rarity = "RARE", value = 75, type = "resource"},
        {id = "diamond", name = "Diamond", rarity = "EPIC", value = 200, type = "resource"},
        {id = "ruby", name = "Ruby", rarity = "EPIC", value = 250, type = "resource"},
        {id = "emerald", name = "Emerald", rarity = "LEGENDARY", value = 1000, type = "resource"},
        {id = "obsidian", name = "Obsidian Shard", rarity = "LEGENDARY", value = 1500, type = "resource"},
        {id = "void_crystal", name = "Void Crystal", rarity = "MYTHIC", value = 10000, type = "resource"},
        
        -- Pickaxes (equipment)
        {id = "iron_pickaxe", name = "Iron Pickaxe", rarity = "UNCOMMON", type = "pickaxe", 
         stats = {speed = 1.1, strength = 1.2, luck = 1.0}},
        {id = "gold_pickaxe", name = "Golden Pickaxe", rarity = "RARE", type = "pickaxe", 
         stats = {speed = 1.3, strength = 1.3, luck = 1.1}},
        {id = "diamond_pickaxe", name = "Diamond Pickaxe", rarity = "EPIC", type = "pickaxe", 
         stats = {speed = 1.5, strength = 1.5, luck = 1.2}},
        {id = "obsidian_pickaxe", name = "Obsidian Pickaxe", rarity = "LEGENDARY", type = "pickaxe", 
         stats = {speed = 2.0, strength = 2.0, luck = 1.5}},
        {id = "void_pickaxe", name = "Void Pickaxe", rarity = "MYTHIC", type = "pickaxe", 
         stats = {speed = 3.0, strength = 3.0, luck = 2.0, radius = 1.5}},
        
        -- Cosmetics
        {id = "miner_helmet", name = "Miner's Helmet", rarity = "UNCOMMON", type = "cosmetic", slot = "head"},
        {id = "glowing_aura", name = "Glowing Aura", rarity = "RARE", type = "cosmetic", slot = "aura"},
        {id = "angel_wings", name = "Angel Wings", rarity = "EPIC", type = "cosmetic", slot = "back"},
        {id = "demon_wings", name = "Demon Wings", rarity = "EPIC", type = "cosmetic", slot = "back"},
        {id = "fire_wings", name = "Fire Wings", rarity = "LEGENDARY", type = "cosmetic", slot = "back"},
        {id = "void_wings", name = "Void Wings", rarity = "MYTHIC", type = "cosmetic", slot = "back"},
        {id = "rainbow_trail", name = "Rainbow Trail", rarity = "LEGENDARY", type = "cosmetic", slot = "trail"},
        
        -- Consumable buffs
        {id = "speed_potion", name = "Speed Potion", rarity = "UNCOMMON", type = "consumable", 
         effect = "speed", multiplier = 0.8, duration = 300},
        {id = "strength_potion", name = "Strength Potion", rarity = "RARE", type = "consumable", 
         effect = "strength", bonus = 2, duration = 300},
        {id = "luck_potion", name = "Luck Potion", rarity = "EPIC", type = "consumable", 
         effect = "luck", multiplier = 1.5, duration = 600},
        {id = "mega_potion", name = "Mega Potion", rarity = "LEGENDARY", type = "consumable", 
         effect = "all", speed_mult = 0.7, strength_bonus = 3, luck_mult = 2.0, duration = 900},
    },
}

-- Cube Materials (progression system)
GameConfig.CubeMaterials = {
    -- Material tiers with better loot tables
    {
        id = "stone",
        name = "Stone",
        material = Enum.Material.Rock,
        color = Color3.fromRGB(140, 140, 140),
        lootMultiplier = 1.0,
        unlockCost = 0,
        hardness = 1.0, -- Affects dig time
    },
    {
        id = "sandstone",
        name = "Sandstone",
        material = Enum.Material.Sandstone,
        color = Color3.fromRGB(200, 180, 140),
        lootMultiplier = 1.5,
        unlockCost = 5000,
        hardness = 1.2,
    },
    {
        id = "granite",
        name = "Granite",
        material = Enum.Material.Granite,
        color = Color3.fromRGB(100, 100, 100),
        lootMultiplier = 2.0,
        unlockCost = 25000,
        hardness = 1.5,
    },
    {
        id = "obsidian",
        name = "Obsidian",
        material = Enum.Material.Slate,
        color = Color3.fromRGB(30, 30, 40),
        lootMultiplier = 3.0,
        unlockCost = 100000,
        hardness = 2.0,
    },
    {
        id = "crystal",
        name = "Crystal",
        material = Enum.Material.ForceField,
        color = Color3.fromRGB(150, 200, 255),
        lootMultiplier = 5.0,
        unlockCost = 500000,
        hardness = 2.5,
    },
    {
        id = "void",
        name = "Void",
        material = Enum.Material.Neon,
        color = Color3.fromRGB(20, 0, 50),
        lootMultiplier = 10.0,
        unlockCost = 2000000,
        hardness = 3.0,
    },
}

-- Create lookup table for materials
GameConfig.CubeMaterialsById = {}
for _, mat in ipairs(GameConfig.CubeMaterials) do
    GameConfig.CubeMaterialsById[mat.id] = mat
end

-- Multiplayer & Neighborhood
GameConfig.Multiplayer = {
    MAX_PLAYERS_PER_NEIGHBORHOOD = 6,
    CUBE_SPACING = 150, -- Studs between player cubes
    VISIT_PERMISSIONS = "FRIENDS", -- "ALL", "FRIENDS", "NONE"
    SHOW_PLAYER_NAMES = true,
    SHOW_PLAYER_STATS = true,
    TELEPORT_COOLDOWN = 5, -- Seconds between teleports
}

-- Mobile UI Settings
GameConfig.MobileUI = {
    -- Button sizes (in pixels)
    DIG_BUTTON_SIZE = 120,
    MENU_BUTTON_SIZE = 60,
    INVENTORY_BUTTON_SIZE = 50,
    
    -- UI scaling for different devices
    PHONE_SCALE = 1.0,
    TABLET_SCALE = 0.8,
    
    -- Touch controls
    ENABLE_TAP_TO_DIG = true,
    ENABLE_SWIPE_CAMERA = true,
    ENABLE_PINCH_ZOOM = true,
    
    -- UI positioning
    DIG_BUTTON_POSITION = UDim2.new(0.5, 0, 0.85, 0),
    INVENTORY_POSITION = UDim2.new(0, 10, 0, 10),
    SHOP_POSITION = UDim2.new(1, -70, 0, 10),
    STATS_POSITION = UDim2.new(0, 10, 1, -150),
}

-- Performance Settings
GameConfig.Performance = {
    -- LOD (Level of Detail) distances
    LOD_DISTANCES = {
        HIGH = 50,
        MEDIUM = 100,
        LOW = 200,
    },
    
    -- Mobile optimization
    MOBILE_PARTICLE_REDUCTION = 0.5,
    MOBILE_SHADOW_DISTANCE = 50,
    
    -- Update rates
    GRID_WRITE_THROTTLE = 0.05, -- Min seconds between terrain writes per player
    GRID_UPDATE_RATE = 0.1,
    UI_UPDATE_RATE = 0.033, -- 30 FPS for UI
    
    -- Memory management
    MAX_CACHED_CELLS = 5000,
    CLEANUP_INTERVAL = 30, -- Seconds
    
    -- Streaming settings (set in default.project.json)
    STREAMING_ENABLED = true,
    STREAMING_MIN_RADIUS = 64,
    STREAMING_TARGET_RADIUS = 128,
}

-- Data Persistence
GameConfig.DataStore = {
    -- DataStore keys
    PLAYER_DATA_KEY = "PlayerMiningData_v1",
    CUBE_DATA_KEY = "CubeData_v1",
    
    -- Auto-save intervals
    AUTO_SAVE_INTERVAL = 60, -- Seconds
    SAVE_ON_LEAVE = true,
    
    -- Data versioning for migrations
    DATA_VERSION = 1,
    
    -- Session locking
    SESSION_LOCK_TTL = 60, -- Seconds
}

-- Debug Settings
GameConfig.Debug = {
    ENABLED = false,
    SHOW_GRID_WIREFRAME = false,
    SHOW_PERFORMANCE_STATS = false,
    INSTANT_DIG = false,
    UNLIMITED_RESOURCES = false,
    FREE_UPGRADES = false,
    LOG_LEVEL = "INFO", -- "DEBUG", "INFO", "WARN", "ERROR"
}

return GameConfig