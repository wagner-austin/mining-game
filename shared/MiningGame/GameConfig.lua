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
    LOG_VERBOSE = false, -- Default off to reduce startup spam; enable when needed
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
    STUDIO_ONLY = false, -- Allow islands outside Studio as well
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
    -- Volume for item pickup/collect ping (0..1)
    PICKUP_VOLUME = 0.3,
    -- Volume for mining hit broadcasts (others' digs) (0..1)
    MINING_HIT_VOLUME = 0.6, -- matches Mining category default unless changed
}

-- Spawn Orchestration (feature-gated)
GameConfig.Spawn = {
    ORCHESTRATED = true,        -- Enable server/client spawn handshake
    CLIENT_STREAM_RADIUS = 128, -- Fallback stream radius if Workspace target radius not available
    SAFETY_PAD_DURATION = 12,   -- Seconds to keep temporary safety pad on timeout
    SPAWN_AT_MAP_ON_FIRST_JOIN = false, -- If true, first finalize uses map spawn bounds instead of cube
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
    COSMETIC_WEIGHT_MULT = 0.01,     -- Multiplier for cosmetic drop rates (0.01 = 100x rarer)
    -- Auto-equip newly acquired cosmetics into empty slots (loot, grants, shop)
    AUTO_EQUIP_COSMETICS_ON_ACQUIRE = true,
    
    -- SHOP / ENHANCED COSMETICS (release-day flags)
    SHOP_ENABLED = true,             -- Server RF gate for Cash Shop (dev default on; UI toggled separately)
    SHOW_LEFT_NAV = true,            -- UI gate for left-side nav (Shop/Inventory/Index)
    SHOW_SHOP_TAB = true,            -- UI gate for Cash Shop (enabled when Shop RF is live)
    SHOW_ITEM_INDEX = true,          -- UI gate for Item Index panel
    ENHANCED_COSMETICS_ENABLED = true, -- Include enhanced cosmetics in catalogs
    ENHANCED_PERKS_ENABLED = true,     -- Apply movement perks granted by enhanced cosmetics

    -- MOVEMENT BOOSTS (speed potion / movement-only)
    SPEED_POTION_MOVEMENT_ONLY = true, -- If true, speed potions affect movement (not dig speed)
    
    -- ITEM DROPS RELIABILITY (QA toggles)
    LOOT_MAGNET_ENABLED = true,        -- Enable owner magnet behavior for drops
    FORCED_CLAIM_ENABLED = true,       -- Enable forced-claim safety for lingering drops
    
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

    -- Mining volumes rollout (Phase 1)
    ENABLE_ISLAND_MINING = true,  -- Enable volume-aware dig and island registration for QA
    ENABLE_VOLUME_HASH = true,    -- Use spatial hash for island volume picking

    -- (deduplicated flags moved above)
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
    
    -- Volume tolerance values (for terrain overhang)
    VOLUME_PICK_FACE_TOLERANCE = 1.10, -- Multiplier for CELL_SIZE when picking volumes
    VOLUME_CLAMP_FACE_TOLERANCE = 0.75, -- Multiplier for CELL_SIZE when clamping positions
    VOLUME_EDGE_TOLERANCE = 0.45, -- Multiplier for CELL_SIZE for edge tolerance
    VOLUME_CORNER_TOLERANCE = 0.35, -- Multiplier for CELL_SIZE for corner tolerance
    
    -- Dig shape
    DIG_SHAPE = "CUBE",
    
    -- Visual feedback
    ENABLE_CAMERA_SHAKE = true,
    CAMERA_SHAKE_INTENSITY = 0.1,
    CAMERA_SHAKE_DURATION = 0.15,
    
    -- Sound settings (per-material mining sounds are configured in SoundConfig)
    HIT_VOLUME = 0.5,
    
    -- Particle effects
    ENABLE_PARTICLES = true,
    PARTICLE_COUNT = 10,

    -- Anti-cheat / request validation
    MAX_RANGE_STUDS = 200, -- Max allowed distance from player HRP to dig target

    -- Diagnostics (server-side). When true, island digs will log
    -- volume extents, cell conversions, and voxel write regions.
    DEBUG_ISLAND_DIAG = false,
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
        -- Developer Products (consumables, can be purchased repeatedly)
        {id = "DONATE", name = "Donate", productId = 3411959603, robux = 100, description = "Support the game"},
    },
    
    -- Game Passes (permanent)
    GAMEPASSES = {
        {id = "VIP", name = "VIP", gamepassId = 1481633877, robux = 1000, 
         effects = {loot_multiplier = 2.0}},
        {id = "BIGGER_DIG", name = "Bigger Dig", gamepassId = 1481773901, robux = 300, 
         effects = {size_bonus = 3}},
        {id = "AUTO_DIGGER", name = "Auto Dig", gamepassId = 1481997949, robux = 500},
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

-- Movement boosts (single source of truth)
GameConfig.MovementBoosts = {
    SpeedPotion = {
        STACK_MAX = 4,
        DURATION_SEC = 300,
        TIER_MULTS = {1.10, 1.20, 1.30, 1.40},
    },
    SpeedCharm = {
        DEFAULT_MULT = 1.10,
    }
}

-- Loot Tables and Items
GameConfig.Loot = {
    -- Loot mode:
    --  "WEIGHTED_TABLE" = original rarity-weighted system
    --  "TERRAIN_SIMPLE" = one resource per terrain/material
    MODE = "WEIGHTED_TABLE",
    -- Base drop chance per cell dug
    -- Per-cell base drop chance. 0.02 ≈ 0.54 items/dig at size=1, luck=1.0.
    -- Upper cap note: 0.05 felt too frequent during testing; avoid going above ~0.04–0.05.
    BASE_DROP_CHANCE = 0.04,
    
    -- Item drop behavior
    ITEM_LIFETIME = 300,           -- 5 minutes before despawn attempt
    DESPAWN_RETRY_DELAY = 10,      -- Seconds after lifetime to retry collection
    OWNER_GRACE_SECONDS = 5,       -- Seconds before drops become public
    ALLOW_PUBLIC_ON_STACK_CAP = true, -- Let others pickup stack-capped items
    
    -- Pickup/visual tunables for ItemService
    PICKUP_RANGE = 12,
    AUTO_COLLECT_RANGE = 50,
    -- Owner magnet tuning (W4)
    MAGNET_START_DELAY = 0.8,     -- Seconds after spawn before magnet begins
    MAGNET_START_RANGE = 12,      -- Initial magnet radius for owner (studs)
    MAGNET_MAX_RANGE = 35,        -- Max magnet radius (studs)
    MAGNET_GROWTH_SECONDS = 3,    -- Time from start to reach max (seconds)
    ROTATION_SPEED = 1,
    MAX_DROPS_PER_PLAYER = 20,
    MAX_DROPS_PER_DIG = 5,

    -- Drop spawn presentation
    -- "per_cell" = spawn at each dropped cell's world position (scattered)
    -- "ring"     = spawn around the dig center in a small jittered ring
    SPAWN_MODE = "per_cell",
    RING_RADIUS = 6,            -- studs
    RING_JITTER = 1.5,          -- random variance around ring
    RING_VERTICAL_OFFSET = 0.0, -- offset from dig center Y

    -- Visibility distance for floating nameplates (studs)
    LABEL_MAX_DISTANCE = 200,

    -- Drop visuals (gate extra VFX here; defaults favor simpler look)
    VISUALS = {
        USE_RARITY_TINT = true,      -- Color part/label by rarity
        USE_NEON = false,            -- Neon material vs smooth plastic
        USE_SELECTION_BOX = false,   -- Outline box
        USE_POINT_LIGHT = false,     -- Glow point light
        USE_PARTICLES = false,       -- Ambient particle sparkle
        USE_MYTHIC_BEAM = false,     -- Beam on MYTHIC
        USE_HOVER_BOB = false,       -- Hovering up/down tween
        USE_FLY_TRAIL = false,       -- Short trail during fly-to-player
    },
    
    -- Rarity tiers with weights and colors
    RARITIES = {
        COMMON = {weight = 1000, color = Color3.fromRGB(150, 150, 150), value_mult = 1},
        UNCOMMON = {weight = 250, color = Color3.fromRGB(50, 200, 50), value_mult = 3},
        RARE = {weight = 50, color = Color3.fromRGB(50, 100, 255), value_mult = 10},
        EPIC = {weight = 10, color = Color3.fromRGB(150, 50, 200), value_mult = 50},
        LEGENDARY = {weight = 2, color = Color3.fromRGB(255, 200, 0), value_mult = 250},
        MYTHIC = {weight = 0.1, color = Color3.fromRGB(255, 50, 50), value_mult = 2500},
    },

    -- Terrain-dependent resource mapping (used when MODE = "TERRAIN_SIMPLE")
    -- Map by cube material id (tier) to a single resource item id.
    -- See GameConfig.CubeMaterials below for available material ids.
    TERRAIN_RESOURCE_MAP = {
        byMaterialId = {
            tier1 = "stone",           -- rock
            tier2 = "sandstone",       -- sandstone
            tier3 = "basalt",          -- basalt
            tier4 = "slate",           -- slate
            tier5 = "glacier_shard",   -- glacier
            tier6 = "lava_rock",       -- cracked lava
        },
        -- One unique resource per terrain key (MaterialDefinitions)
        byTerrainKey = {
            rock = "stone",
            sandstone = "sandstone",
            basalt = "basalt",
            slate = "slate",
            limestone = "limestone",
            glacier = "glacier_shard",
            ice = "ice_shard",
            snow = "snow_chunk",
            sand = "sand_clump",
            mud = "mud_clod",
            ground = "soil",
            grass = "grass_fiber",
            leafygrass = "leafy_fiber",
            concrete = "concrete_rubble",
            cobblestone = "cobble_chunk",
            brick = "brick_piece",
            asphalt = "asphalt_chunk",
            pavement = "pavement_chip",
            salt = "salt_crystal",
            woodplanks = "plank_scrap",
            water = "water_drop",
            crackedlava = "lava_rock",
        }
    },
    
    -- Item definitions
    ITEMS = {
        -- Terrain resources (one per terrain), normalized sell value
        {id = "stone", name = "Stone", rarity = "COMMON", value = 10, type = "resource"},
        {id = "sandstone", name = "Sandstone", rarity = "COMMON", value = 10, type = "resource"},
        {id = "basalt", name = "Basalt", rarity = "COMMON", value = 10, type = "resource"},
        {id = "slate", name = "Slate", rarity = "COMMON", value = 10, type = "resource"},
        {id = "glacier_shard", name = "Glacial Shard", rarity = "COMMON", value = 10, type = "resource"},
        {id = "lava_rock", name = "Lava Rock", rarity = "COMMON", value = 10, type = "resource"},
        {id = "limestone", name = "Limestone", rarity = "COMMON", value = 10, type = "resource"},
        {id = "ice_shard", name = "Ice Shard", rarity = "COMMON", value = 10, type = "resource"},
        {id = "snow_chunk", name = "Snow Chunk", rarity = "COMMON", value = 10, type = "resource"},
        {id = "sand_clump", name = "Sand Clump", rarity = "COMMON", value = 10, type = "resource"},
        {id = "mud_clod", name = "Mud Clod", rarity = "COMMON", value = 10, type = "resource"},
        {id = "soil", name = "Soil", rarity = "COMMON", value = 10, type = "resource"},
        {id = "grass_fiber", name = "Grass Fiber", rarity = "COMMON", value = 10, type = "resource"},
        {id = "leafy_fiber", name = "Leafy Fiber", rarity = "COMMON", value = 10, type = "resource"},
        {id = "concrete_rubble", name = "Concrete Rubble", rarity = "COMMON", value = 10, type = "resource"},
        {id = "cobble_chunk", name = "Cobblestone Chunk", rarity = "COMMON", value = 10, type = "resource"},
        {id = "brick_piece", name = "Brick Piece", rarity = "COMMON", value = 10, type = "resource"},
        {id = "asphalt_chunk", name = "Asphalt Chunk", rarity = "COMMON", value = 10, type = "resource"},
        {id = "pavement_chip", name = "Pavement Chip", rarity = "COMMON", value = 10, type = "resource"},
        {id = "salt_crystal", name = "Salt Crystal", rarity = "COMMON", value = 10, type = "resource"},
        {id = "plank_scrap", name = "Plank Scrap", rarity = "COMMON", value = 10, type = "resource"},
        {id = "water_drop", name = "Water Drop", rarity = "COMMON", value = 10, type = "resource"},

        -- Consumable buffs
        {id = "speed_potion", name = "Speed Potion", rarity = "UNCOMMON", type = "consumable", 
         effect = "speed", multiplier = 0.8, duration = 300, dropWeight = 125},
        {id = "size_potion", name = "Size Potion", rarity = "RARE", type = "consumable", 
         effect = "size", bonus = 2, duration = 300},
        {id = "luck_potion", name = "Luck Potion", rarity = "EPIC", type = "consumable", 
         effect = "luck", multiplier = 1.5, duration = 600},
        {id = "jump_potion", name = "Jump Potion", rarity = "LEGENDARY", type = "consumable", 
         effect = "jumps", jumps = 4, duration = 900},
    },

    -- Optional type multipliers to adjust selection share without changing total drop volume
    -- 1.0 = baseline; <1.0 reduces frequency; >1.0 increases
        TYPE_MULTIPLIER = {
        resource = 0.6,
        consumable = 0.045,
        cosmetic = 1.0,
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
    HEARTBEAT_WARN_DT = 0.066,  -- ~15 FPS threshold for spike diagnostics
    
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
    MAX_COSMETIC_STACK = 99999,      -- Cap for cosmetics (including hand tools)
    MAX_RESOURCE_STACK = 99999,      -- Cap for resource stacks
    MAX_CONSUMABLE_STACK = 99999,    -- Cap for consumable stacks
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
    LOG_LEVEL = "INFO", -- Default to INFO; raise to DEBUG when actively debugging
}

-- Reset/Respawn thresholds (tunable)
GameConfig.Reset = {
    -- Player-initiated reset (pedestal): allow only when mined fraction >= this value
    -- Example: 0.05 means you must mine at least 5% to enable manual reset
    MANUAL_RESET_MIN_MINED_FRAC = 0.05,
    -- Auto reset (server): trigger when mined fraction >= this value
    AUTO_RESET_MINED_FRAC = 0.99,
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
    BASE_GLOW_LIFT = 3,           -- studs added to floor glow height for base perimeter (legacy; unified by standard offset when using GlowBarService)
    GLOW_BAR_OFFSET_FROM_BOTTOM = 12, -- Standard height of glow bars above cube bottom face (studs)
    GLOW_CORNER_OVERLAP_FACTOR = 0.22, -- Fraction of bar width added to length for clean corner overlap
    FLOOR_DEPTH_MULT = 3,        -- Voxel layers for floor cleanout (VOX * 3)
    EDGE_TRANSPARENCY = 0.3,     -- Selection/edge transparency
    BAR_EXTRA_LENGTH = 2,        -- Extra length beyond edge
    SELECTION_PAD = 1,           -- Selection bounds pad (studs)
    MARGIN_PERCENT = 0.10,       -- 10% margin for glow bar calc
    GLOWBAR_APPLY_BATCH = 512,   -- Batch size for initial client application to reduce visible delay
    BASE_GLOW_WIDTH = 5,         -- Base perimeter glow visual width (studs); cube uses FLOOR_GLOW_WIDTH
}

return GameConfig
