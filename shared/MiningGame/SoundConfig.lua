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
-- TODO: Replace test sounds with actual game assets
local SOUND_ASSETS = {
    -- Test sound for development
    TEST_CLICK = "rbxassetid://9120386436",  -- Temporary click sound for testing
    
    -- Future sound assets go here:
    -- MINING_ROCK_HIT = "rbxassetid://YOUR_ID",
    -- MINING_ROCK_BREAK = "rbxassetid://YOUR_ID",
    -- UI_BUTTON_CLICK = "rbxassetid://YOUR_ID",
    -- FOOTSTEP_ROCK = "rbxassetid://YOUR_ID",
}

-- ===========================================================================
-- BUILD MINING SOUNDS DYNAMICALLY
-- ===========================================================================
-- Generate mining sounds from MaterialDefinitions + SoundCategories
local miningSounds = {}
for materialKey, def in pairs(MaterialDefinitions.Materials) do
    local category = def.properties.soundCategory
    local events = SoundCategories.GetMiningEvents(category)
    
    local soundSet = {}
    for _, event in ipairs(events) do
        -- All using test sound for now - replace with real assets later
        -- Future: SOUND_ASSETS.MINING[category][event] or similar
        soundSet[event] = SOUND_ASSETS.TEST_CLICK
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
        buttonclick  = SOUND_ASSETS.TEST_CLICK,
        buttonhover  = SOUND_ASSETS.TEST_CLICK,
        openmenu     = SOUND_ASSETS.TEST_CLICK,
        closemenu    = SOUND_ASSETS.TEST_CLICK,
        tabswitch    = SOUND_ASSETS.TEST_CLICK,
        notification = SOUND_ASSETS.TEST_CLICK,
        error        = SOUND_ASSETS.TEST_CLICK,
        success      = SOUND_ASSETS.TEST_CLICK,
        purchase     = SOUND_ASSETS.TEST_CLICK,
        upgrade      = SOUND_ASSETS.TEST_CLICK,
    },
    
    -- Ambient sounds (time-based, see TimeRules below)
    ambient = {
        wind           = SOUND_ASSETS.TEST_CLICK,
        birds_morning  = SOUND_ASSETS.TEST_CLICK,  -- Plays 6am-6pm
        birds_evening  = SOUND_ASSETS.TEST_CLICK,  -- Plays 5pm-8pm
        trees_rustling = SOUND_ASSETS.TEST_CLICK,
        cave           = SOUND_ASSETS.TEST_CLICK,
        waterflow      = SOUND_ASSETS.TEST_CLICK,
        crickets       = SOUND_ASSETS.TEST_CLICK,  -- Plays 8pm-6am
        desertwind     = SOUND_ASSETS.TEST_CLICK,
        oceanwaves     = SOUND_ASSETS.TEST_CLICK,
        lavaflow       = SOUND_ASSETS.TEST_CLICK,
        icecracking    = SOUND_ASSETS.TEST_CLICK,
    },
    
    -- Music tracks
    music = {
        main    = SOUND_ASSETS.TEST_CLICK,
        mining  = SOUND_ASSETS.TEST_CLICK,
        cave    = SOUND_ASSETS.TEST_CLICK,
        desert  = SOUND_ASSETS.TEST_CLICK,
        ice     = SOUND_ASSETS.TEST_CLICK,
        lava    = SOUND_ASSETS.TEST_CLICK,
        shop    = SOUND_ASSETS.TEST_CLICK,
        boss    = SOUND_ASSETS.TEST_CLICK,
        victory = SOUND_ASSETS.TEST_CLICK,
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
        coin        = SOUND_ASSETS.TEST_CLICK,
        gem         = SOUND_ASSETS.TEST_CLICK,
        item        = SOUND_ASSETS.TEST_CLICK,
        levelup     = SOUND_ASSETS.TEST_CLICK,
        achievement = SOUND_ASSETS.TEST_CLICK,
        chest       = SOUND_ASSETS.TEST_CLICK,
        rare        = SOUND_ASSETS.TEST_CLICK,
        epic        = SOUND_ASSETS.TEST_CLICK,
        legendary   = SOUND_ASSETS.TEST_CLICK,
        daily       = SOUND_ASSETS.TEST_CLICK,
        milestone   = SOUND_ASSETS.TEST_CLICK,
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