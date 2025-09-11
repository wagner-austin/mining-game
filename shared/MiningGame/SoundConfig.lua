--!strict
-- SoundConfig.lua
-- Sound configuration with lowercase keys and proper structure

local MaterialKeys = require(script.Parent.MaterialKeys)
local MaterialDefinitions = require(script.Parent.MaterialDefinitions)
local SoundCategories = require(script.Parent.SoundCategories)

local SoundConfig = {}

-- ===========================================================================
-- SOUND ASSET DICTIONARY
-- ===========================================================================
-- Central location for all sound asset IDs
-- Using verified Creator Store audio (public, free-to-use)
local SOUND_ASSETS = {
    -- UI (verified Creator Store assets)
    UI_BUTTON_CLICK  = "rbxassetid://9120410355", -- Video Game Buttons 10
    UI_NOTIFICATION  = "rbxassetid://7128958209", -- Bell Ding (nice for success/pickups)

    -- Mining (baseline set for all rocky materials; you can specialize later)
    MINING_ROCK_HIT   = "rbxassetid://9118628948", -- Rock Impacts 13
    MINING_ROCK_CRACK = "rbxassetid://9125931990", -- Shale Burst Smashing Rock 1
    MINING_ROCK_BREAK = "rbxassetid://9119046189", -- Shale Break 9
    
    -- Mining (metal variant for ores/ingots)
    MINING_METAL_HIT   = "rbxassetid://9116680684", -- Metal Impact Railroad Hammer 28
    MINING_METAL_CRACK = "rbxassetid://9116460378", -- Manacles Metal Clangs 1
    MINING_METAL_BREAK = "rbxassetid://9125664705", -- Metal Clatter Clanking Falls

    -- Ambient beds (loop these; your category defaults already set Looped/rolloff)
    AMBIENT_WIND          = "rbxassetid://9114228918", -- Eerie Wind Constant 4
    AMBIENT_WATERFLOW     = "rbxassetid://9120549564", -- Waterfall Background Water Roar 1
    AMBIENT_BIRDS_MORNING = "rbxassetid://9116968963", -- Morning Birds 9
    
    -- Night / Cave ambience
    AMBIENT_CRICKETS   = "rbxassetid://9126205087", -- Weber Bbq Lid On Off Distant Birds Crickets 5
    AMBIENT_CAVE_WIND  = "rbxassetid://9114228918", -- Eerie Wind Constant 4 (36s loop)
    AMBIENT_CAVE_WATER = "rbxassetid://9120549564", -- Waterfall Background Water Roar 1 (56s loop)
    AMBIENT_CAVE_DRIPS = "rbxassetid://9120533442", -- Water Drip Single Drops Into Tin Bucket 17
    
    -- Reward stingers (rarity-based)
    REWARD_RARE      = "rbxassetid://9120414823", -- Video Game Effects 2
    REWARD_EPIC      = "rbxassetid://9120142683", -- Tone Clusters Mostly High Pitch Tones 16
    REWARD_LEGENDARY = "rbxassetid://9119872487", -- Synth Whomps 4
    
    -- Music tracks (verified Creator Store music)
    MUSIC_MAIN    = "rbxassetid://1835878163", -- Calm
    MUSIC_MINING  = "rbxassetid://9048375035", -- All Dropping 8 Bit Beats (energetic, retro)
    MUSIC_CAVE    = "rbxassetid://1837075763", -- Ambient Layers (floaty ambient bed)
    MUSIC_SHOP    = "rbxassetid://1844872472", -- Think (light lounge vibe)
    MUSIC_BOSS    = "rbxassetid://1839961091", -- Fearless Destruction (epic hybrid/orchestral)
    MUSIC_VICTORY = "rbxassetid://9048816189", -- Lounge Lizard Sting C (short victory sting)
    MUSIC_ICE     = "rbxassetid://1836542585", -- Frozen Horizon (cold ambient)
    MUSIC_DESERT  = "rbxassetid://1843277044", -- Desert Race (world/ethnic pulse)
    
    -- Keep test sound as fallback
    TEST_CLICK = "rbxassetid://9120386436",  -- Fallback/test sound
}

-- ===========================================================================
-- BUILD MINING SOUNDS DYNAMICALLY
-- ===========================================================================
-- Generate mining sounds from MaterialDefinitions + SoundCategories
local miningSounds = {}
for materialKey, def in pairs(MaterialDefinitions.Materials) do
    local category = string.lower(def.properties.soundCategory or "rock")
    local events = SoundCategories.GetMiningEvents(def.properties.soundCategory)
    
    -- Pick variant set per material/category
    local variantSets = {
        metal = {
            hit   = SOUND_ASSETS.MINING_METAL_HIT,
            crack = SOUND_ASSETS.MINING_METAL_CRACK,
            ["break"] = SOUND_ASSETS.MINING_METAL_BREAK,
        },
        -- Add more variants later: sand = {...}, ice = {...}
    }
    
    local defaultSet = {
        hit   = SOUND_ASSETS.MINING_ROCK_HIT,
        crack = SOUND_ASSETS.MINING_ROCK_CRACK,
        ["break"] = SOUND_ASSETS.MINING_ROCK_BREAK,
    }
    
    local useSet = variantSets[category] or defaultSet
    
    local soundSet = {}
    for _, event in ipairs(events) do
        soundSet[event] = useSet[event] or defaultSet.hit
    end
    
    miningSounds[materialKey] = soundSet
end

-- ===========================================================================
-- SOUND CONFIGURATION  
-- ===========================================================================
SoundConfig.SoundIDs = {
    -- Mining sounds (dynamically generated from materials)
    mining = miningSounds,
    
    -- Movement sounds (footsteps use soundCategory from MaterialDefinitions)
    -- NOTE: Currently using default Roblox movement sounds
    movement = {
        footstep = {
            rock  = SOUND_ASSETS.TEST_CLICK,  -- Maps to rock-category materials
            sand  = SOUND_ASSETS.TEST_CLICK,
            grass = SOUND_ASSETS.TEST_CLICK,
            dirt  = SOUND_ASSETS.TEST_CLICK,  -- Added: used by "ground" material
            wood  = SOUND_ASSETS.TEST_CLICK,
            ice   = SOUND_ASSETS.TEST_CLICK,
            mud   = SOUND_ASSETS.TEST_CLICK,
            snow  = SOUND_ASSETS.TEST_CLICK,
            water = SOUND_ASSETS.TEST_CLICK,
            -- metal = SOUND_ASSETS.TEST_CLICK,  -- Reserved for non-terrain BasePart surfaces
        },
        -- These are not currently implemented - using default Roblox sounds
        jump       = SOUND_ASSETS.TEST_CLICK,
        doublejump = SOUND_ASSETS.TEST_CLICK,
        land       = SOUND_ASSETS.TEST_CLICK,
        landhard   = SOUND_ASSETS.TEST_CLICK,
        dash       = nil,  -- Not implemented
        slide      = nil,  -- Not implemented
    },
    
    -- UI sounds (actively used by UI components)
    ui = {
        buttonclick  = SOUND_ASSETS.UI_BUTTON_CLICK,
        buttonhover  = SOUND_ASSETS.UI_BUTTON_CLICK,  -- reuse for now
        openmenu     = SOUND_ASSETS.UI_BUTTON_CLICK,
        closemenu    = SOUND_ASSETS.UI_BUTTON_CLICK,
        tabswitch    = SOUND_ASSETS.UI_BUTTON_CLICK,
        notification = SOUND_ASSETS.UI_NOTIFICATION,
        error        = SOUND_ASSETS.UI_BUTTON_CLICK,
        success      = SOUND_ASSETS.UI_NOTIFICATION,
        purchase     = SOUND_ASSETS.UI_NOTIFICATION,
        upgrade      = SOUND_ASSETS.UI_NOTIFICATION,
    },
    
    -- Ambient sounds (time-based, see TimeRules below)
    ambient = {
        wind           = SOUND_ASSETS.AMBIENT_WIND,
        birds_morning  = SOUND_ASSETS.AMBIENT_BIRDS_MORNING,  -- Plays 6am-6pm
        birds_evening  = SOUND_ASSETS.AMBIENT_BIRDS_MORNING,  -- Plays 5pm-8pm (temp reuse)
        trees_rustling = SOUND_ASSETS.AMBIENT_WIND,           -- temp reuse
        cave           = SOUND_ASSETS.AMBIENT_CAVE_WIND,      -- Cave wind ambience (36s loop)
        cave_water     = SOUND_ASSETS.AMBIENT_CAVE_WATER,     -- Cave water flow (56s loop)
        cave_drips     = SOUND_ASSETS.AMBIENT_CAVE_DRIPS,     -- Cave water drips (detail layer)
        waterflow      = SOUND_ASSETS.AMBIENT_WATERFLOW,
        crickets       = SOUND_ASSETS.AMBIENT_CRICKETS,       -- Night crickets loop
        desertwind     = SOUND_ASSETS.AMBIENT_WIND,           -- temp reuse
        oceanwaves     = SOUND_ASSETS.AMBIENT_WATERFLOW,      -- temp reuse water sound
        lavaflow       = SOUND_ASSETS.TEST_CLICK,             -- TODO: needs lava/fire loop
        icecracking    = SOUND_ASSETS.TEST_CLICK,             -- TODO: needs ice ambient
    },
    
    -- Music tracks
    music = {
        main    = SOUND_ASSETS.MUSIC_MAIN,
        mining  = SOUND_ASSETS.MUSIC_MINING,
        cave    = SOUND_ASSETS.MUSIC_CAVE,
        desert  = SOUND_ASSETS.MUSIC_DESERT,
        ice     = SOUND_ASSETS.MUSIC_ICE,
        lava    = SOUND_ASSETS.MUSIC_BOSS,    -- Using boss music for intense lava areas
        shop    = SOUND_ASSETS.MUSIC_SHOP,
        boss    = SOUND_ASSETS.MUSIC_BOSS,
        victory = SOUND_ASSETS.MUSIC_VICTORY,
    },
    
    -- Pet sounds
    pets = {
        spawn    = SOUND_ASSETS.TEST_CLICK,
        happy    = SOUND_ASSETS.TEST_CLICK,
        idle     = SOUND_ASSETS.TEST_CLICK,
        working  = SOUND_ASSETS.TEST_CLICK,
        levelup  = SOUND_ASSETS.TEST_CLICK,
        equip    = SOUND_ASSETS.TEST_CLICK,
        unequip  = SOUND_ASSETS.TEST_CLICK,
    },
    
    -- Reward sounds (played when collecting items)
    rewards = {
        coin        = SOUND_ASSETS.UI_NOTIFICATION,     -- Bell ding for basic pickups
        gem         = SOUND_ASSETS.UI_NOTIFICATION,
        item        = SOUND_ASSETS.UI_NOTIFICATION,
        levelup     = SOUND_ASSETS.REWARD_EPIC,         -- Epic sound for level ups
        achievement = SOUND_ASSETS.REWARD_RARE,         -- Rare sound for achievements
        chest       = SOUND_ASSETS.UI_NOTIFICATION,
        rare        = SOUND_ASSETS.REWARD_RARE,         -- Bright gamey burst
        epic        = SOUND_ASSETS.REWARD_EPIC,         -- Sparkly tonal cluster
        legendary   = SOUND_ASSETS.REWARD_LEGENDARY,    -- Deep synth whomp
        daily       = SOUND_ASSETS.UI_NOTIFICATION,
        milestone   = SOUND_ASSETS.REWARD_EPIC,         -- Epic for milestones
    },
    
    -- Environmental sounds
    environment = {
        thunder    = SOUND_ASSETS.TEST_CLICK,
        rain       = SOUND_ASSETS.TEST_CLICK,
        explosion  = SOUND_ASSETS.TEST_CLICK,
        earthquake = SOUND_ASSETS.TEST_CLICK,
        fire       = SOUND_ASSETS.TEST_CLICK,
        rockfall   = SOUND_ASSETS.TEST_CLICK,
        steam      = SOUND_ASSETS.TEST_CLICK,
    },
}

-- Category properties for defaults (PascalCase for consistency)
SoundConfig.Properties = {
    Mining = {
        Volume = 0.6,
        Looped = false,
        RollOffMode = Enum.RollOffMode.Linear,
        RollOffMaxDistance = 50,
        RollOffMinDistance = 5,
        EmitterSize = 5,
    },
    Movement = {
        Volume = 0.4,
        Looped = false,
        RollOffMode = Enum.RollOffMode.Linear,
        RollOffMaxDistance = 30,
        RollOffMinDistance = 5,
        EmitterSize = 2,
    },
    UI = {
        Volume = 0.5,
        Looped = false,
        RollOffMode = Enum.RollOffMode.Linear,
        PlayOnRemove = false,
    },
    Ambient = {
        Volume = 0.6,  -- Increased for testing (was 0.3)
        Looped = true,
        RollOffMode = Enum.RollOffMode.Linear,
        RollOffMaxDistance = 100,
        RollOffMinDistance = 10,
        EmitterSize = 10,
    },
    Music = {
        Volume = 0.2,
        Looped = true,
        RollOffMode = Enum.RollOffMode.Linear,
        PlayOnRemove = false,
    },
    Pets = {
        Volume = 0.4,
        Looped = false,
        RollOffMode = Enum.RollOffMode.Linear,
        RollOffMaxDistance = 40,
        RollOffMinDistance = 5,
        EmitterSize = 3,
    },
    Rewards = {
        Volume = 0.7,
        Looped = false,
        RollOffMode = Enum.RollOffMode.Linear,
        PlayOnRemove = false,
    },
    Environment = {
        Volume = 0.5,
        Looped = false,
        RollOffMode = Enum.RollOffMode.Linear,
        RollOffMaxDistance = 150,
        RollOffMinDistance = 20,
        EmitterSize = 15,
    },
}

-- Sound group assignments for mixer
SoundConfig.GroupForCategory = {
    mining      = "SFX",
    movement    = "SFX",
    ui          = "UI",
    ambient     = "Ambient",
    music       = "Music",
    pets        = "SFX",
    rewards     = "SFX",
    environment = "SFX",
}

-- Music settings
SoundConfig.MusicSettings = {
    FadeTime = 2,
    CrossfadeEnabled = true,
    DynamicVolume = true,
    MinVolume = 0.1,
    MaxVolume = 0.3,
}

-- Ambient settings
SoundConfig.AmbientSettings = {
    DayNightCycle = true,
    WeatherBased = true,
    LocationBased = true,
    FadeDistance = 50,
    MaxConcurrent = 2,  -- Allow 2 zones at once for testing
}

-- Time-based sound rules (easy to configure!)
-- Each entry can have multiple time ranges and optional variants
type TimeRange = { start: number, stop: number }
type TimeRule = {
    timeRanges: {TimeRange}?,
    variants: { [string]: string }?, -- e.g. { day = "trees_rustling_gentle", night = "trees_rustling_eerie" }
}

SoundConfig.TimeRules = table.freeze({
    -- Nature sounds
    birds_morning = {
        timeRanges = { { start = 6, stop = 18 } }, -- 6:00 → 18:00
    },
    birds_evening = {
        timeRanges = { { start = 17, stop = 20 } },
    },
    crickets = {
        timeRanges = { { start = 20, stop = 24 }, { start = 0, stop = 6 } }, -- 20:00 → 06:00 next day
    },
    owls = {
        timeRanges = { { start = 22, stop = 24 }, { start = 0, stop = 4 } },
    },

    -- Trees with variants
    trees_rustling = {
        timeRanges = { { start = 0, stop = 24 } }, -- always
        variants = {
            day = "trees_rustling_gentle",
            night = "trees_rustling_eerie",
            storm = "trees_rustling_violent",
        }
    },

    -- Water with variants
    waterflow = {
        timeRanges = { { start = 0, stop = 24 } },
        variants = {
            day = "waterflow",
            night = "waterflow_quiet",
            frozen = "ice_cracking",
        }
    },

    -- Footsteps could change based on time/conditions
    footstep_grass = {
        timeRanges = { { start = 0, stop = 24 } },
        variants = {
            day = "footstep_grass",
            night = "footstep_grass_wet", -- Dew at night
            rain = "footstep_mud",
        }
    },
    
    -- Lava is always active (no time restriction)
    lavaflow = {
        timeRanges = { { start = 0, stop = 24 } },
    },
    
    -- Ice sounds might be louder at night
    icecracking = {
        timeRanges = { { start = 0, stop = 24 } },
        variants = {
            day = "icecracking",
            night = "icecracking", -- Could be different/louder
        }
    },
})

-- Helpers
local function normalizeTime(t: number): number
    t = t % 24
    if t < 0 then t = t + 24 end
    return t
end

local function inHalfOpenRange(t: number, r: TimeRange): boolean
    -- half-open intervals [start, stop) to prevent double hit at edges
    if r.start == r.stop then
        return true -- treat equal start/stop as "all day"
    end
    if r.start < r.stop then
        -- Normal range [start, stop)
        return t >= r.start and t < r.stop
    else
        -- Wraps midnight: [start, 24) ∪ [0, stop)
        return t >= r.start or t < r.stop
    end
end

-- Returns: shouldPlay, resolvedKey (variant or original)
function SoundConfig.ShouldSoundPlay(soundKey: string, currentTime: number?, currentEvent: string?): (boolean, string?)
    local rules: TimeRule? = SoundConfig.TimeRules[soundKey :: any]
    if not rules then
        return true, soundKey -- No rules = always play
    end

    local t = normalizeTime(currentTime or game.Lighting.ClockTime)

    -- Time window check
    local ok = true
    if rules.timeRanges ~= nil then
        ok = false
        for _, range in ipairs(rules.timeRanges :: {TimeRange}) do
            if inHalfOpenRange(t, range) then
                ok = true
                break
            end
        end
    end
    if not ok then
        return false, nil
    end

    -- Variant resolution (events > time-of-day)
    if rules.variants then
        -- Priority: events > time of day
        if currentEvent and rules.variants[currentEvent] then
            local variant = rules.variants[currentEvent]
            -- Check if variant sound ID exists
            if SoundConfig.ValidateSoundID(variant) then
                return true, variant
            end
        end
        
        -- Time-based variants (using half-open intervals)
        -- Also validate that the variant sound ID exists
        if (t >= 6 and t < 18) and rules.variants.day then
            local dayVariant = rules.variants.day
            if SoundConfig.ValidateSoundID(dayVariant) then
                return true, dayVariant
            end
        elseif (t >= 18 or t < 6) and rules.variants.night then
            local nightVariant = rules.variants.night
            if SoundConfig.ValidateSoundID(nightVariant) then
                return true, nightVariant
            end
        end
    end

    return true, soundKey
end

-- Build footstep mapping from MaterialDefinitions (single source of truth)
local FOOTSTEP_MAP = {}
for key, def in pairs(MaterialDefinitions.Materials) do
    FOOTSTEP_MAP[key] = def.properties.soundCategory or "rock"
end

-- Special overrides if needed (e.g., for specific footstep variations)
-- Currently, soundCategory in MaterialDefinitions handles all cases

-- Helper functions
function SoundConfig.GetMiningSoundForMaterial(materialKey: string)
    local k = string.lower(materialKey or "rock")
    return SoundConfig.SoundIDs.mining[k] or SoundConfig.SoundIDs.mining.rock
end

function SoundConfig.GetFootstepSoundForMaterial(materialKey: string)
    local k = string.lower(materialKey or "rock")
    local footstepType = FOOTSTEP_MAP[k] or "rock"
    return SoundConfig.SoundIDs.movement.footstep[footstepType]
end

function SoundConfig.GetCategoryProperties(category: string)
    -- Try exact match first, then TitleCase, then default to UI
    local props = SoundConfig.Properties[category]
    if props then return props end
    
    -- Try TitleCase conversion
    local titleCase = category:sub(1,1):upper() .. category:sub(2):lower()
    return SoundConfig.Properties[titleCase] or SoundConfig.Properties.UI
end

function SoundConfig.ValidateSoundID(soundId: string?): boolean
    return soundId ~= nil and soundId ~= "" and soundId ~= "rbxassetid://0"
end

-- ===========================================================================
-- VALIDATION AT STARTUP
-- ===========================================================================
do
    -- Ensure every material has mining sounds
    for materialKey, def in pairs(MaterialDefinitions.Materials) do
        local category = def.properties.soundCategory
        assert(
            SoundConfig.SoundIDs.mining[materialKey],
            ("[SoundConfig] Missing mining sounds for material '%s' (category '%s')")
                :format(materialKey, category)
        )
        
        -- Ensure expected events exist
        local expectedEvents = SoundCategories.GetMiningEvents(category)
        for _, event in ipairs(expectedEvents) do
            assert(
                SoundConfig.SoundIDs.mining[materialKey][event] ~= nil,
                ("[SoundConfig] Missing mining event '%s' for material '%s' (category '%s')")
                    :format(event, materialKey, category)
            )
        end
    end
    
    -- Ensure every used sound category has a footstep sound
    local usedCategories = {}
    for _, def in pairs(MaterialDefinitions.Materials) do
        usedCategories[def.properties.soundCategory] = true
    end
    
    for category, _ in pairs(usedCategories) do
        assert(
            SoundConfig.SoundIDs.movement.footstep[category],
            ("[SoundConfig] Missing footstep sound for category '%s'"):format(category)
        )
    end
end

return SoundConfig