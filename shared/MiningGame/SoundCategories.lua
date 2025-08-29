--!strict
-- SoundCategories.lua
-- Canonical list of sound categories and their event schemas
-- Single source of truth for all sound category definitions

local SoundCategories = {}

-- Enum-like constants (use these in MaterialDefinitions.soundCategory)
SoundCategories.Categories = table.freeze({
    ROCK  = "rock",
    ICE   = "ice",
    SAND  = "sand",
    MUD   = "mud",
    SNOW  = "snow",
    WATER = "water",
    GRASS = "grass",
    DIRT  = "dirt",
    WOOD  = "wood",
    -- METAL = "metal", -- Reserved for non-terrain BasePart surfaces if needed
})

-- Ordered list for consistent UI/iteration
SoundCategories.Ordered = table.freeze({
    "rock",
    "sand",
    "grass",
    "dirt",
    "wood",
    "ice",
    "mud",
    "snow",
    "water",
})

-- Mining event schemas per category
-- Defines what sound events each category should have
SoundCategories.MiningEvents = table.freeze({
    rock  = {"hit", "break", "crumble"},
    ice   = {"hit", "break", "shatter"},
    sand  = {"hit", "break", "scatter"},
    mud   = {"hit", "break", "squish"},
    snow  = {"hit", "break", "crunch"},
    water = {"hit", "splash", "flow"},
    grass = {"hit", "break", "dig"},
    dirt  = {"hit", "break", "dig"},
    wood  = {"hit", "break", "crack"},
})

-- Default events for unknown categories
SoundCategories.DefaultMiningEvents = table.freeze({"hit", "break"})

-- Build validity set for fast lookup
local validCategories: {[string]: boolean} = {}
for _, category in ipairs(SoundCategories.Ordered) do
    validCategories[category] = true
end
SoundCategories.ValidCategories = table.freeze(validCategories)

-- Helper: Check if a category is valid
function SoundCategories.IsValid(category: string): boolean
    return SoundCategories.ValidCategories[category] == true
end

-- Helper: Get mining events for a category
function SoundCategories.GetMiningEvents(category: string): {string}
    return SoundCategories.MiningEvents[category] or SoundCategories.DefaultMiningEvents
end

-- Helper: Get all categories as array
function SoundCategories.GetAll(): {string}
    return SoundCategories.Ordered
end

-- Validation at startup
do
    -- Ensure all mining events are defined for ordered categories
    for _, category in ipairs(SoundCategories.Ordered) do
        assert(
            SoundCategories.MiningEvents[category],
            ("[SoundCategories] Missing mining events for category '%s'"):format(category)
        )
    end
    
    -- Ensure Categories constants match ordered list
    for key, value in pairs(SoundCategories.Categories) do
        assert(
            validCategories[value],
            ("[SoundCategories] Category constant %s = '%s' not in Ordered list"):format(key, value)
        )
    end
end

return table.freeze(SoundCategories)