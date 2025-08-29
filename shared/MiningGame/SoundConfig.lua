--!strict
-- SoundConfig.lua
-- Sound configuration with lowercase keys and proper structure

local MaterialKeys = require(script.Parent.MaterialKeys)

local SoundConfig = {}

-- Sound IDs - all lowercase keys, nil for missing assets
SoundConfig.SoundIDs = {
    -- Mining sounds for all 22 terrain materials
    mining = {
        -- Stone-like materials
        rock        = { hit = nil, ["break"] = nil, crumble = nil },
        sandstone   = { hit = nil, ["break"] = nil, crumble = nil },
        basalt      = { hit = nil, ["break"] = nil, crumble = nil },
        slate       = { hit = nil, ["break"] = nil, crumble = nil },
        limestone   = { hit = nil, ["break"] = nil, crumble = nil },
        cobblestone = { hit = nil, ["break"] = nil, crumble = nil },
        brick       = { hit = nil, ["break"] = nil, crumble = nil },
        concrete    = { hit = nil, ["break"] = nil, crumble = nil },
        asphalt     = { hit = nil, ["break"] = nil, crumble = nil },
        pavement    = { hit = nil, ["break"] = nil, crumble = nil },
        
        -- Ice/Crystal materials
        glacier     = { hit = nil, ["break"] = nil, shatter = nil },
        ice         = { hit = nil, ["break"] = nil, shatter = nil },
        
        -- Soft/Earth materials
        grass       = { hit = nil, ["break"] = nil, dig = nil },
        leafygrass  = { hit = nil, ["break"] = nil, dig = nil },
        ground      = { hit = nil, ["break"] = nil, dig = nil },
        mud         = { hit = nil, ["break"] = nil, squish = nil },
        sand        = { hit = nil, ["break"] = nil, scatter = nil },
        snow        = { hit = nil, ["break"] = nil, crunch = nil },
        salt        = { hit = nil, ["break"] = nil, scatter = nil },
        
        -- Special materials
        water       = { hit = nil, splash = nil, flow = nil },
        crackedlava = { hit = nil, ["break"] = nil, sizzle = nil },
        woodplanks  = { hit = nil, ["break"] = nil, crack = nil },
    },
    
    -- Movement sounds
    movement = {
        footstep = {
            rock  = nil,
            sand  = nil,
            grass = nil,
            wood  = nil,
            metal = nil,
            ice   = nil,
            mud   = nil,
            snow  = nil,
            water = nil,
        },
        jump       = nil,
        doublejump = nil,
        land       = nil,
        landhard   = nil,
        dash       = nil,
        slide      = nil,
    },
    
    -- UI sounds
    ui = {
        buttonclick  = nil,
        buttonhover  = nil,
        openmenu     = nil,
        closemenu    = nil,
        tabswitch    = nil,
        notification = nil,
        error        = nil,
        success      = nil,
        purchase     = nil,
        upgrade      = nil,
    },
    
    -- Ambient sounds
    ambient = {
        wind           = nil,
        birds_morning  = nil,
        birds_evening  = nil,
        trees_rustling = nil,
        cave           = nil,
        waterflow      = nil,
        crickets       = nil,
        desertwind     = nil,
        oceanwaves     = nil,
        lavaflow       = nil,
        icecracking    = nil,
    },
    
    -- Music tracks
    music = {
        main    = nil,
        mining  = nil,
        cave    = nil,
        desert  = nil,
        ice     = nil,
        lava    = nil,
        shop    = nil,
        boss    = nil,
        victory = nil,
    },
    
    -- Pet sounds
    pets = {
        spawn    = nil,
        happy    = nil,
        idle     = nil,
        working  = nil,
        levelup  = nil,
        equip    = nil,
        unequip  = nil,
    },
    
    -- Reward sounds
    rewards = {
        coin        = nil,
        gem         = nil,
        item        = nil,
        levelup     = nil,
        achievement = nil,
        chest       = nil,
        rare        = nil,
        epic        = nil,
        legendary   = nil,
        daily       = nil,
        milestone   = nil,
    },
    
    -- Environmental sounds
    environment = {
        thunder    = nil,
        rain       = nil,
        explosion  = nil,
        earthquake = nil,
        fire       = nil,
        rockfall   = nil,
        steam      = nil,
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

-- Footstep mapping - all lowercase
local FOOTSTEP_MAP = {
    -- Stone group
    rock        = "rock",
    sandstone   = "rock",
    basalt      = "rock",
    slate       = "rock",
    limestone   = "rock",
    cobblestone = "rock",
    brick       = "rock",
    concrete    = "rock",
    asphalt     = "rock",
    pavement    = "rock",
    
    -- Ice group
    glacier = "ice",
    ice     = "ice",
    
    -- Earth group
    grass      = "grass",
    leafygrass = "grass",
    ground     = "grass",
    mud        = "mud",
    sand       = "sand",
    snow       = "snow",
    salt       = "sand",
    
    -- Special
    water       = "water",
    crackedlava = "rock",
    woodplanks  = "wood",
}

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

return SoundConfig