--!strict
-- GameConfig.lua
-- Central configuration for the mining game system
-- This module defines all tunable parameters for easy balancing and expansion

local GameConfig = {}

-- ============================================
-- PROCEDURAL WORLD GENERATION CONFIGURATION
-- ============================================

-- Master World Generation Control
GameConfig.WorldGen = {
    ENABLED = true, -- Master switch for ALL world generation (decorations + islands)
    STUDIO_ONLY = false, -- Set true to only generate in Studio
    SPAWN_MARGIN = 160, -- Distance from map edge to avoid spawning (studs) (reduced)
    LOG_VERBOSE = true, -- Set true for detailed spawn logging
    -- Consistency mode for decoration categories (trees/rocks/fireflies)
    -- "independent" = spawn each enabled category independently
    -- "all_or_none" = if any enabled category fails (spawns 0), clear all spawned decorations
    -- "guarantee_min" = ensure at least one of each enabled category spawns
    CONSISTENT_MODE = "all_or_none",
    -- Schedule/cleanup controls
    DESPAWN_WHEN_INACTIVE = true, -- If no categories are active, clear BlockDecorations
    SCHEDULE_CHECK_INTERVAL = 15, -- Seconds between schedule checks (day/night)
}

-- Ground Decorations (trees, rocks, fireflies)
GameConfig.Decorations = {
    TREES_ENABLED = true,
    ROCKS_ENABLED = true,
    FIREFLIES_ENABLED = true,
    -- Optional time-of-day activation lists (use values from WorldTime.getTimePeriod)
    -- e.g. {"Dusk","Night"} or {"Morning","Afternoon"}
    TREES_ACTIVE_PERIODS = nil,
    ROCKS_ACTIVE_PERIODS = nil,
    FIREFLIES_ACTIVE_PERIODS = nil,
    
    -- Density settings (per 10,000 square studs)
    TREES_PER_100x100 = 0.5,      -- ~50 trees on 1000x1000 map (reduced)
    ROCKS_PER_100x100 = 0.65,     -- ~65 rocks on 1000x1000 map
    FIREFLIES_PER_100x100 = 0.6,  -- ~60 firefly groups on 1000x1000 map
    
    -- Count limits
    MIN_TREES = 40,
    MAX_TREES = 300,
    MIN_ROCKS = 30,
    MAX_ROCKS = 200,
    MIN_FIREFLIES = 15,
    MAX_FIREFLIES = 120,
    
    -- Water placement policy (future-proof; all false for now)
    ALLOW_WATER_TREES = false,
    ALLOW_WATER_ROCKS = false,
    ALLOW_WATER_FIREFLIES = false,
}

-- Floating Islands Configuration
GameConfig.FloatingIslands = {
    -- Manual spawning (via debug commands)
    ENABLED = true, -- Allow manual island spawning
    STUDIO_ONLY = true, -- Only allow manual spawning in Studio (for FloatingIslandHandler)
    RATE_LIMIT_SECONDS = 2, -- Cooldown between manual spawns per player
    MAX_ISLANDS_PER_SESSION = 100, -- Maximum manual islands per session
    ALLOW_IN_DEBUG_TAB = true, -- Show in debug tab
    
    -- Automatic procedural spawning
    PROCEDURAL_ENABLED = true, -- Auto-spawn islands at server start
    ISLANDS_PER_100x100 = 0.015, -- 0.015 per 10k sq studs = ~6 islands on 2000x2000 map
    MIN_ISLANDS = 3, -- Minimum islands regardless of map size
    MAX_ISLANDS = 12, -- Maximum islands to prevent overload
    
    -- Positioning
    HEIGHT_MIN = 120, -- Minimum Y coordinate for islands (lowered)
    HEIGHT_MAX = 350, -- Maximum Y coordinate for islands (lowered)
    HEIGHT_VARIATION = 100, -- Y variation within clusters
    MIN_SPACING = 350, -- Minimum distance between islands (studs)
    
    -- Liquids/material controls
    LIQUID_WEIGHT_CAP = 0.45, -- Max fraction for liquid components on islands (tunable)
    
    -- Clustering
    CLUSTER_CHANCE = 0.3, -- 30% chance of spawning 2-3 islands together
    CLUSTER_SPACING = 200, -- Distance between islands in a cluster
    
    -- Visual variety
    PRESET_WEIGHTS = {
        tiny = 15,    -- 15% chance
        small = 40,   -- 40% chance
        medium = 35,  -- 35% chance
        large = 10,   -- 10% chance
    },
    TREE_COUNT = {0, 0, 1, 1, 2}, -- Random tree counts per island
    TREE_SCALE = 0.8, -- Slightly smaller trees on islands
}

-- Announcements config
GameConfig.Announcements = {
    MIN_GLOBAL_INTERVAL = 1,  -- seconds
}

-- Sound broadcast defaults  
GameConfig.Sound = {
    DEFAULT_RADIUS = 150,     -- studs
    MAX_SOUND_DISTANCE = 150, -- Maximum 3D sound range
    MIN_SOUND_DISTANCE = 10,  -- Minimum distance for full volume
    SOUND_COOLDOWN = 0.5,     -- Cooldown between same sound plays (seconds)
}

-- Feature Flags (for testing and rollout)
GameConfig.Features = {
    -- Mixed material composition system (always enabled now)
    ENABLE_COMPOSITIONS = true,  -- Always true - single composition removed
    
    -- Composition system settings
    COMPOSITIONS_ENABLED_BY_DEFAULT = true,  -- Always start with compositions
    ALLOW_COMPOSITION_UNLOCK = false,  -- No unlocking needed - all themes available by tier
    SHOW_COMPOSITION_UI = true,  -- Always show the composition UI
    
    -- Enable/disable the upgrade system
    ENABLE_UPGRADES = true,  -- Set to false to completely disable upgrades
    SHOW_UPGRADE_TAB = true,  -- Whether to show the Upgrades tab in settings
    
    -- NEW COSMETICS SYSTEM
    COSMETICS_ENABLED = true,        -- Master switch for cosmetic drops and equipment
    COSMETICS_IN_LOOT = true,        -- Include cosmetics in loot drops
    COSMETIC_WEIGHT_MULT = 0.1,      -- Multiplier for cosmetic drop rates (0.1 = 10x rarer)
    
    -- ACHIEVEMENT SYSTEM
    ACHIEVEMENTS_ENABLED = true,      -- Enable/disable achievement system
    ACHIEVEMENT_NOTIFICATIONS = true, -- Show achievement popup notifications
    
    -- ANNOUNCEMENTS SYSTEM
    ANNOUNCEMENTS_ENABLED = true,     -- Enable/disable server-wide announcements
    MYTHIC_GLOBAL_ANNOUNCE = true,   -- Send mythic finds globally via MessagingService
    EPIC_SERVER_ANNOUNCE = true,     -- Send epic+ finds to server
    
    -- DEBUG/TESTING OPTIONS
    DEBUG_HIGH_COSMETIC_RATE = false,  -- Set to true to make cosmetics 10x more common for testing
    DEBUG_FORCE_RARITY = false, -- Set to "MYTHIC", "LEGENDARY", etc to force drops
    DEBUG_ALWAYS_ACHIEVEMENT = false,  -- Always grant achievements even if already unlocked
}

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
    -- Valid upgrade types (used for validation)
    speed = "SPEED_LEVELS",
    size = "SIZE_LEVELS",
    
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

-- Character State Configuration
GameConfig.Character = {
    Health = {
        BASE = 100,         -- Base health
        REGEN_RATE = 5,     -- Health per second
        REGEN_DELAY = 3,    -- Seconds after damage before regen starts
    },
    Stamina = {
        BASE = 100,         -- Base stamina
        REGEN_RATE = 10,    -- Stamina per second
        JUMP_COST = 10,     -- Stamina cost per jump (future use)
        DIG_COST = 5,       -- Stamina cost per dig (future use)
    },
    Effects = {
        TICK_RATE = 1,      -- How often to check/update effects (seconds)
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
    
    -- Surface detection tuning parameters
    SurfaceDetect = {
        ENABLED = false,           -- Master toggle for surface detection feature (DISABLED FOR TESTING)
        AIR_THRESHOLD = 0.05,      -- Below this occupancy = air
        SOLID_THRESHOLD = 0.30,    -- Above this occupancy = solid (raise to 0.35 for thin shells)
        SAMPLE_BIAS = 0.55,        -- Front/back sample distance multiplier
        CACHE_LIFETIME = 0.10,     -- Cache TTL in seconds
        CACHE_MAX = 256,           -- Maximum cache entries before LRU eviction
    },
}

-- Loot Tables and Items
GameConfig.Loot = {
    -- Base drop chance per cell dug
    BASE_DROP_CHANCE = 0.15, -- 15% chance per cell
    
    -- Item drop behavior
    ITEM_LIFETIME = 300,           -- 5 minutes before despawn attempt
    DESPAWN_RETRY_DELAY = 10,      -- Seconds after lifetime to retry collection
    OWNER_GRACE_SECONDS = 5,       -- Seconds before drops become public
    ALLOW_PUBLIC_ON_STACK_CAP = true, -- Let others pickup stack-capped items
    
    -- Pickup/visual tunables for ItemService
    PICKUP_RANGE = 12,
    AUTO_COLLECT_RANGE = 50,
    ROTATION_SPEED = 1,
    MAX_DROPS_PER_PLAYER = 20,
    MAX_DROPS_PER_DIG = 5,
    
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
        
        -- Composition-exclusive materials (only drop with specific compositions)
        {id = "glass_shard", name = "Glass Shard", rarity = "COMMON", value = 8, type = "resource", exclusive = true},
        {id = "quartz", name = "Quartz", rarity = "UNCOMMON", value = 25, type = "resource", exclusive = true},
        {id = "volcanic_glass", name = "Volcanic Glass", rarity = "RARE", value = 80, type = "resource", exclusive = true},
        {id = "ice_crystal", name = "Ice Crystal", rarity = "RARE", value = 60, type = "resource", exclusive = true},
        {id = "frozen_gem", name = "Frozen Gem", rarity = "EPIC", value = 300, type = "resource", exclusive = true},
        {id = "prismatic_shard", name = "Prismatic Shard", rarity = "LEGENDARY", value = 2000, type = "resource", exclusive = true},
        {id = "void_essence", name = "Void Essence", rarity = "MYTHIC", value = 5000, type = "resource", exclusive = true},
        {id = "dark_matter", name = "Dark Matter", rarity = "MYTHIC", value = 7500, type = "resource", exclusive = true},
        {id = "cosmic_fragment", name = "Cosmic Fragment", rarity = "MYTHIC", value = 12000, type = "resource", exclusive = true},
        {id = "rainbow_gem", name = "Rainbow Gem", rarity = "LEGENDARY", value = 3000, type = "resource", exclusive = true},
        {id = "chromatic_ore", name = "Chromatic Ore", rarity = "EPIC", value = 500, type = "resource", exclusive = true},
        
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
        
        -- Cosmetics removed - now defined in CosmeticDefinitions.lua to avoid duplicates
        
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
    CUBE_SPACING = 225, -- Base spacing for spiral calculation
    MIN_GAP_STUDS = 300, -- Minimum gap between cube edges
    MAX_GAP_STUDS = 400, -- Optional maximum gap between cubes
    SPAWN_STRATEGY = "random_dispersed", -- Poisson-like distribution with enforced spacing
    SPAWN_BOUNDS_PART = "SpawnBounds", -- Named part for spawn area (optional)
    EDGE_MARGIN = 200, -- Keep spawns this far from map edges
    GRID_COLS = 3, -- Columns in the grid (for legacy grid strategy)
    ALTITUDE_AMPLITUDE = 24, -- Used by grid_altitude_noise strategy
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

-- Client Settings (extracted from TestClient and ClientErrorHandler)
GameConfig.Client = {
    -- Input & polling
    DIG_POLL_INTERVAL = 0.05,           -- Seconds between continuous dig checks
    INITIAL_DIG_COOLDOWN = 1,           -- Default cooldown before server sync
    VISUAL_STARTUP_DELAY = 0.1,         -- Delay before starting visual feedback
    PROFILE_LOAD_WAIT = 2,              -- Wait for data to load on startup
    
    -- Error tracking
    CLIENT_ERROR_RING_SIZE = 20,        -- Max client errors to keep in ring buffer
    
    -- Terrain interaction
    CUBE_TOLERANCE_STUDS = 2,           -- Tolerance for terrain texture beyond voxel boundaries
    CONTINUOUS_DIG_RAY_LENGTH = 2000,   -- Max ray length for mouse->terrain
}

-- Scheduler Settings
GameConfig.Scheduler = {
    MORNING_HOUR   = 6,   -- 6 AM
    EVENING_HOUR   = 18,  -- 6 PM
    CHECK_INTERVAL = 30,  -- seconds
}

-- Performance Settings
GameConfig.Performance = {
    -- Heartbeat monitoring
    HEARTBEAT_WARN_DT = 0.066,  -- ~15 FPS spike threshold
    
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
    DATA_LOAD_TIMEOUT = 2.0, -- Studio data load timeout (seconds)
    SHUTDOWN_SAVE_WAIT = 2,  -- Wait time on shutdown for saves
    
    -- Data versioning for migrations
    DATA_VERSION = 1,
    
    -- Session locking
    SESSION_LOCK_TTL = 60, -- Seconds
}

-- Cache Configuration
GameConfig.Cache = {
    TTL_SHORT = 5,          -- 5 seconds for frequently changing data
    TTL_MEDIUM = 30,        -- 30 seconds for moderate data  
    TTL_LONG = 300,         -- 5 minutes for stable data
    GAMEPASS_TTL = 120,     -- 2 minutes for gamepass ownership
    PRICE_CACHE_EXPIRY = 300, -- 5 minutes for product prices
    METRICS_TTL = 5,        -- User metrics cache TTL
}

-- System Limits
GameConfig.Limits = {
    MAX_RECEIPT_CACHE = 500,     -- Max cached receipt IDs per player
    MAX_PURCHASE_LOG = 20,       -- Max purchase history entries
    MAX_PENDING_GRANTS = 300,    -- Max pending monetization grants
    MAX_SIM_AGENTS = 25,         -- Max simulation agents in Studio
    MAX_INVENTORY_STACK = 999,   -- Max items per stack
    MAX_SOUND_INSTANCES = 10,    -- Max concurrent sounds per type
}

-- Terrain and Material Settings
GameConfig.Terrain = {
    -- Water visibility threshold for voxel occupancy
    MIN_WATER_OCCUPANCY = 0.3,   -- Minimum occupancy for water to be visible
    
    -- Voxel resolution for terrain operations
    VOXEL_RESOLUTION = 4,        -- Standard voxel size in studs
}

-- Audio Settings
GameConfig.Audio = {
    -- Default volume levels (0.0 to 1.0)
    DEFAULT_MUSIC_VOLUME = 0.5,
    DEFAULT_SFX_VOLUME = 0.5,
    MIN_VOLUME = 0.0,
    MAX_VOLUME = 1.0,
}

-- Timing Constants
GameConfig.Timing = {
    -- Service delays and waits
    SERVICE_INIT_DELAY = 0.1,    -- Delay after service initialization
    AUTO_DIG_INITIAL_DELAY = 0.1, -- Initial delay for auto-dig
    AUTO_DIG_DEFAULT_INTERVAL = 0.2, -- Default interval between auto-digs
    DATA_LOAD_RETRY_DELAY = 0.1, -- Delay between data load retries
    
    -- Rate limiting
    COMPOSITION_APPLY_RATE = 5/60,  -- 5 applies per minute (tokens/sec)
    COMPOSITION_APPLY_BURST = 2,     -- Burst capacity of 2
    
    -- Time units (for clarity in code)
    SECONDS_PER_MINUTE = 60,
    SECONDS_PER_HOUR = 3600,
    SECONDS_PER_DAY = 86400,
    SECONDS_PER_WEEK = 604800,
    
    -- Common durations
    ONE_HOUR = 3600,
    ONE_DAY = 86400,
    ONE_WEEK = 604800,
}

-- Debug Settings
GameConfig.Debug = {
    ENABLED = true,  -- TEMPORARILY ENABLED FOR TESTING
    SHOW_GRID_WIREFRAME = false,
    SHOW_PERFORMANCE_STATS = false,
    INSTANT_DIG = false,
    UNLIMITED_RESOURCES = false,
    FREE_UPGRADES = false,
    -- SINGLE SOURCE OF TRUTH for log level across entire game
    LOG_LEVEL = "DEBUG", -- "DEBUG", "INFO", "WARN", "ERROR"
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
    
    -- Additional visual constants
    FLOOR_DEPTH_MULT = 3,        -- Voxel layers for floor cleanout (VOX * 3)
    EDGE_TRANSPARENCY = 0.3,     -- Selection/edge transparency
    BAR_EXTRA_LENGTH = 2,        -- Extra length beyond edge
    SELECTION_PAD = 1,           -- Selection bounds pad (studs)
    MARGIN_PERCENT = 0.10,       -- 10% margin for glow bar calc
}

return GameConfig
