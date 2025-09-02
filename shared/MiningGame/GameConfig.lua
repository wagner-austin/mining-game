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
    BASE_DIG_SIZE_CELLS = 1, -- Base size of dig cube (1 = 3x3x3 cube)
    
    -- Dig shape
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
    
    -- Dig size (cube size) - Size increases come FIRST as exciting milestones!
    SIZE_LEVELS = {
        {level = 0, cost = 0, size = 1},         -- 3x3x3 base
        {level = 1, cost = 100, size = 2},       -- 5x5x5 - First big upgrade!
        {level = 2, cost = 300, size = 2},       -- Still 5x5x5
        {level = 3, cost = 700, size = 2},       -- Still 5x5x5
        {level = 4, cost = 1500, size = 2},      -- Still 5x5x5
        {level = 5, cost = 3000, size = 2},      -- Still 5x5x5
        {level = 6, cost = 6000, size = 3},      -- 7x7x7 - Second big upgrade!
        {level = 7, cost = 12000, size = 3},     -- Still 7x7x7
        {level = 8, cost = 25000, size = 3},     -- Still 7x7x7
        {level = 9, cost = 50000, size = 3},     -- Still 7x7x7
        {level = 10, cost = 100000, size = 3},   -- Still 7x7x7
        {level = 11, cost = 200000, size = 3},   -- Still 7x7x7
        {level = 12, cost = 400000, size = 3},   -- Still 7x7x7
        {level = 13, cost = 800000, size = 3},   -- Still 7x7x7
        {level = 14, cost = 1600000, size = 3},  -- Still 7x7x7
        {level = 15, cost = 3200000, size = 3},  -- Still 7x7x7 (MAX)
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
         buffs = {size = 0.1, luck = 0}},
        {id = "eagle", name = "Golden Eagle", rarity = "RARE", 
         buffs = {speed = 0.08, size = 0.08, luck = 0.05}},
        {id = "dragon", name = "Mining Dragon", rarity = "EPIC", 
         buffs = {size = 0.15, luck = 0.1}},
        {id = "phoenix", name = "Phoenix", rarity = "LEGENDARY", 
         buffs = {speed = 0.15, size = 0.15, luck = 0.2}},
        {id = "cosmic", name = "Cosmic Entity", rarity = "MYTHIC", 
         buffs = {speed = 0.25, size = 0.25, luck = 0.3}},
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
         effect = "instant_dig", size = 10},
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
         effects = {size_bonus = 3}},
        {id = "AUTO_COLLECT", gamepassId = 0, robux = 299, 
         effects = {auto_collect_range = 50}},
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
         stats = {speed = 1.1, size = 1, luck = 1.0}},
        {id = "gold_pickaxe", name = "Golden Pickaxe", rarity = "RARE", type = "pickaxe", 
         stats = {speed = 1.3, size = 1, luck = 1.1}},
        {id = "diamond_pickaxe", name = "Diamond Pickaxe", rarity = "EPIC", type = "pickaxe", 
         stats = {speed = 1.5, size = 2, luck = 1.2}},
        {id = "obsidian_pickaxe", name = "Obsidian Pickaxe", rarity = "LEGENDARY", type = "pickaxe", 
         stats = {speed = 2.0, size = 3, luck = 1.5}},
        {id = "void_pickaxe", name = "Void Pickaxe", rarity = "MYTHIC", type = "pickaxe", 
         stats = {speed = 3.0, size = 2.0, luck = 2.0}},
        
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
        {id = "size_potion", name = "Size Potion", rarity = "RARE", type = "consumable", 
         effect = "size", bonus = 2, duration = 300},
        {id = "luck_potion", name = "Luck Potion", rarity = "EPIC", type = "consumable", 
         effect = "luck", multiplier = 1.5, duration = 600},
        {id = "mega_potion", name = "Mega Potion", rarity = "LEGENDARY", type = "consumable", 
         effect = "all", speed_mult = 0.7, size_bonus = 3, luck_mult = 2.0, duration = 900},
    },
}

-- Cube Materials (progression system)
-- Progression tiers ONLY - not for visual materials
GameConfig.CubeMaterials = {
    {
        id = "tier1",
        name = "Tier 1",
        terrainKey = "rock",
        lootMultiplier = 1.0,
        unlockCost = 0,
        hardness = 1.0,
    },
    {
        id = "tier2",
        name = "Tier 2",
        terrainKey = "sandstone",
        lootMultiplier = 1.5,
        unlockCost = 5000,
        hardness = 1.2,
    },
    {
        id = "tier3",
        name = "Tier 3",
        terrainKey = "basalt",
        lootMultiplier = 2.0,
        unlockCost = 25000,
        hardness = 1.5,
    },
    {
        id = "tier4",
        name = "Tier 4",
        terrainKey = "slate",
        lootMultiplier = 3.0,
        unlockCost = 100000,
        hardness = 2.0,
    },
    {
        id = "tier5",
        name = "Tier 5",
        terrainKey = "glacier",
        lootMultiplier = 5.0,
        unlockCost = 500000,
        hardness = 2.5,
    },
    {
        id = "tier6",
        name = "Tier 6",
        terrainKey = "crackedlava",
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
    CUBE_SPACING = 225, -- Studs between player cubes (balanced proximity)
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
    RECEIPT_QUEUE_KEY = "ReceiptQueue_v1", -- Durable purchase queue
    
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

-- Visual Settings for cube indicators
GameConfig.Visuals = {
    -- Floor glow outline settings
    FLOOR_GLOW_COLOR = Color3.fromRGB(0, 255, 255), -- Cyan neon
    FLOOR_GLOW_THICKNESS = 0.5, -- Flatter strip
    FLOOR_GLOW_GROUND_CLEARANCE = 9.83, -- Position at Y=9.83
    FLOOR_GLOW_WIDTH = 2, -- Thinner strips
    FLOOR_GLOW_MARGIN_MIN = 2, -- Minimum margin around cube
    FLOOR_GLOW_MARGIN_MAX = 4, -- Maximum margin around cube
    FLOOR_GLOW_REPLACE_MATERIALS = { Enum.Material.Grass, Enum.Material.LeafyGrass, Enum.Material.Ground }, -- Materials to swap
    FLOOR_GLOW_REPLACEMENT_MATERIAL = Enum.Material.Concrete, -- What to replace them with
    
    -- Cube lighting settings
    LIGHT_COLOR = Color3.fromRGB(180, 255, 255), -- Soft cyan
    LIGHT_RANGE_MULT = 1.25, -- Multiplier for light range based on cube size
    LIGHT_RANGE_MIN = 24, -- Minimum light range
    LIGHT_BRIGHTNESS = 1.5, -- Light brightness
    
    -- Whole cube glow settings (for monetization/upgrades)
    CUBE_GLOW_ENABLED = false, -- Default off, can be enabled via upgrade/purchase
    CUBE_GLOW_COLOR = Color3.fromRGB(100, 255, 255), -- Cyan forcefield glow
    CUBE_GLOW_TRANSPARENCY = 0.7, -- Semi-transparent overlay
}

return GameConfig