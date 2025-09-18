--!strict
-- SoundConfig.lua
-- Sound configuration with lowercase keys and proper structure

local MaterialKeys = require(script.Parent.MaterialKeys)
local MaterialDefinitions = require(script.Parent.MaterialDefinitions)
local SoundCategories = require(script.Parent.SoundCategories)
local SoundDefs = require(script.Parent.SoundDefs)

local SoundConfig = {}

-- ===========================================================================
-- SOUND ASSET DICTIONARY (single source of truth)
-- ===========================================================================
local SOUND_ASSETS = SoundDefs.ASSETS

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
            hit    = SOUND_ASSETS.MINING_METAL_HIT,
            crack  = SOUND_ASSETS.MINING_METAL_CRACK,
            ["break"] = SOUND_ASSETS.MINING_METAL_BREAK,
        },
        rock = {
            hit      = SOUND_ASSETS.MINING_ROCK_HIT,
            ["break"] = SOUND_ASSETS.MINING_ROCK_BREAK,
            crumble  = SOUND_ASSETS.MINING_ROCK_CRUMBLE,
        },
        ice = {
            hit      = SOUND_ASSETS.MINING_ICE_HIT,
            ["break"] = SOUND_ASSETS.MINING_ICE_BREAK,
            shatter  = SOUND_ASSETS.MINING_ICE_SHATTER,
        },
        sand = {
            hit      = SOUND_ASSETS.MINING_SAND_HIT,
            ["break"] = SOUND_ASSETS.MINING_SAND_BREAK,
            scatter  = SOUND_ASSETS.MINING_SAND_SCATTER,
        },
        mud = {
            hit      = SOUND_ASSETS.MINING_MUD_HIT,
            ["break"] = SOUND_ASSETS.MINING_MUD_BREAK,
            squish   = SOUND_ASSETS.MINING_MUD_SQUISH,
        },
        snow = {
            hit      = SOUND_ASSETS.MINING_SNOW_HIT,
            ["break"] = SOUND_ASSETS.MINING_SNOW_BREAK,
            crunch   = SOUND_ASSETS.MINING_SNOW_CRUNCH,
        },
        water = {
            hit      = SOUND_ASSETS.MINING_WATER_HIT,
            splash   = SOUND_ASSETS.MINING_WATER_SPLASH,
            flow     = SOUND_ASSETS.MINING_WATER_FLOW,
        },
        grass = {
            hit      = SOUND_ASSETS.MINING_GRASS_HIT,
            ["break"] = SOUND_ASSETS.MINING_GRASS_BREAK,
            dig      = SOUND_ASSETS.MINING_GRASS_DIG,
        },
        dirt = {
            hit      = SOUND_ASSETS.MINING_DIRT_HIT,
            ["break"] = SOUND_ASSETS.MINING_DIRT_BREAK,
            dig      = SOUND_ASSETS.MINING_DIRT_DIG,
        },
        wood = {
            hit      = SOUND_ASSETS.MINING_WOOD_HIT,
            ["break"] = SOUND_ASSETS.MINING_WOOD_BREAK,
            crack    = SOUND_ASSETS.MINING_WOOD_CRACK,
        },
        -- Add more variants later: mud = {...}, snow = {...}, water = {...}, grass = {...}, dirt = {...}, wood = {...}
    }
    
    local defaultSet = {
        hit   = SOUND_ASSETS.MINING_ROCK_HIT,
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
    movement = {
        footstep = {
            rock  = SOUND_ASSETS.MOVEMENT_FOOTSTEP_ROCK,
            sand  = SOUND_ASSETS.MOVEMENT_FOOTSTEP_SAND,
            grass = SOUND_ASSETS.MOVEMENT_FOOTSTEP_GRASS,
            dirt  = SOUND_ASSETS.MOVEMENT_FOOTSTEP_DIRT,   -- used by "ground" material
            wood  = SOUND_ASSETS.MOVEMENT_FOOTSTEP_WOOD,
            ice   = SOUND_ASSETS.MOVEMENT_FOOTSTEP_ICE,
            mud   = SOUND_ASSETS.MOVEMENT_FOOTSTEP_MUD,
            snow  = SOUND_ASSETS.MOVEMENT_FOOTSTEP_SNOW,
            water = SOUND_ASSETS.MOVEMENT_FOOTSTEP_WATER,
        },
        -- Movement actions
        jump       = SOUND_ASSETS.MOVEMENT_JUMP,
        doublejump = SOUND_ASSETS.MOVEMENT_JUMP,   -- reuse jump
        land       = SOUND_ASSETS.MOVEMENT_LAND,
        dash       = nil,  -- Not implemented
        slide      = nil,  -- Not implemented
    },
    
    -- UI sounds (actively used by UI components)
    ui = {
        buttonclick  = SOUND_ASSETS.UI_BUTTON_CLICK,
        buttonhover  = SOUND_ASSETS.UI_BUTTON_CLICK,  -- reuse
        openmenu     = SOUND_ASSETS.UI_MENU_OPEN,
        closemenu    = SOUND_ASSETS.UI_BUTTON_CLICK,  -- reuse
        tabswitch    = SOUND_ASSETS.UI_BUTTON_CLICK,
        notification = SOUND_ASSETS.UI_NOTIFICATION,
        error        = SOUND_ASSETS.UI_ERROR,
        success      = SOUND_ASSETS.UI_NOTIFICATION,
        purchase     = SOUND_ASSETS.UI_NOTIFICATION,
        upgrade      = SOUND_ASSETS.UI_NOTIFICATION,
    },
    
    -- Ambient sounds (time-based, see TimeRules below)
    ambient = {
        wind           = SOUND_ASSETS.AMBIENT_WIND,
        birds_morning  = SOUND_ASSETS.AMBIENT_BIRDS_MORNING,  -- Plays 6am-6pm
        birds_evening  = SOUND_ASSETS.AMBIENT_BIRDS_MORNING,  -- reuse morning birds
        trees_rustling = SOUND_ASSETS.AMBIENT_TREES_RUSTLING,
        cave           = SOUND_ASSETS.AMBIENT_CAVE_WIND,
        cave_water     = SOUND_ASSETS.AMBIENT_CAVE_WATER,
        cave_drips     = SOUND_ASSETS.AMBIENT_CAVE_DRIPS,
        waterflow      = SOUND_ASSETS.AMBIENT_WATERFLOW,
        crickets       = SOUND_ASSETS.AMBIENT_CRICKETS,
        desertwind     = SOUND_ASSETS.AMBIENT_WIND,           -- reuse wind
        oceanwaves     = SOUND_ASSETS.AMBIENT_OCEANWAVES,
        lavaflow       = SOUND_ASSETS.AMBIENT_LAVAFLOW,
        icecracking    = SOUND_ASSETS.AMBIENT_ICECRACKING,
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
        -- Optional playlist of background tracks for rotation/shuffle
        playlist = {
            SOUND_ASSETS.MUSIC_MAIN,
            SOUND_ASSETS.MUSIC_BG_01,
            SOUND_ASSETS.MUSIC_BG_02,
            SOUND_ASSETS.MUSIC_BG_03,
            SOUND_ASSETS.MUSIC_BG_04,
            SOUND_ASSETS.MUSIC_BG_05,
        },
    },
    
    -- Pet sounds
    pets = {
        spawn    = SOUND_ASSETS.PET_SPAWN,
        happy    = SOUND_ASSETS.PET_HAPPY,
        idle     = SOUND_ASSETS.PET_IDLE,
        working  = SOUND_ASSETS.PET_WORKING,
        levelup  = SOUND_ASSETS.PET_LEVELUP,
        equip    = SOUND_ASSETS.PET_EQUIP,
        unequip  = SOUND_ASSETS.PET_UNEQUIP,
    },
    
    -- Reward sounds (played when collecting items)
    rewards = {
        coin        = SOUND_ASSETS.REWARD_COIN,
        gem         = SOUND_ASSETS.REWARD_GEM,
        item        = SOUND_ASSETS.REWARD_ITEM,
        levelup     = SOUND_ASSETS.REWARD_LEVELUP,
        achievement = SOUND_ASSETS.REWARD_ACHIEVEMENT,
        chest       = SOUND_ASSETS.REWARD_CHEST,
        rare        = SOUND_ASSETS.REWARD_RARE,
        epic        = SOUND_ASSETS.REWARD_EPIC,
        legendary   = SOUND_ASSETS.REWARD_LEGENDARY,
        milestone   = SOUND_ASSETS.REWARD_MILESTONE,
    },
    
    -- Environmental sounds
    environment = {
        thunder    = SOUND_ASSETS.ENV_THUNDER,
        rain       = SOUND_ASSETS.ENV_RAIN,
        explosion  = SOUND_ASSETS.ENV_EXPLOSION,
        earthquake = SOUND_ASSETS.ENV_EARTHQUAKE,
        fire       = SOUND_ASSETS.ENV_FIRE,
        rockfall   = SOUND_ASSETS.ENV_ROCKFALL,
        steam      = SOUND_ASSETS.ENV_STEAM,
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

-- Loop preferences for Environment keys (override category default)
-- Environment loop preferences are defined in SoundDefs metadata (looped field)

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
