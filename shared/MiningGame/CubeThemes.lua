--!strict
-- CubeThemes.lua
-- Defines preset cube themes with specific material combinations

local CubeThemes = {}

export type CubeTheme = {
    name: string,
    materials: {[string]: number}, -- material weights
    scales: {[string]: number}, -- swathe scales
    minTier: number, -- minimum tier required
    description: string,
    dropBoost: number?, -- optional drop rate multiplier
}

CubeThemes.Themes = {
    
    volcanic_rift = {
        name = "Volcanic Rift",
        -- Increase lava stone (crackedlava) proportion for stronger lava presence
        materials = { basalt = 0.35, crackedlava = 0.55, rock = 0.10 },
        scales = { basalt = 22, crackedlava = 16, rock = 26 },
        minTier = 1,
        description = "Molten rock formations rich in metals",
        dropBoost = 1.5,
    },
    
    desert_oasis = {
        name = "Desert Oasis",
        -- Add water to the oasis theme with a decent ratio
        materials = { sand = 0.40, salt = 0.25, water = 0.20, rock = 0.15 },
        scales = { sand = 25, salt = 18, water = 35, rock = 28 },
        minTier = 1,
        description = "Sandy deposits with crystalline formations",
        dropBoost = 1.15,
    },
    
    swamp_bog = {
        name = "Swamp Bog",
        materials = { mud = 0.60, water = 0.25, rock = 0.15 },
        scales = { mud = 20, water = 35, rock = 25 },
        minTier = 1,
        description = "Murky swamplands with organic treasures",
        dropBoost = 1.25,
    },
    
    underwater_cave = {
        name = "Underwater Cave",
        materials = { water = 0.50, rock = 0.30, ice = 0.20 },
        scales = { water = 35, rock = 28, ice = 22 },
        minTier = 1,
        description = "Submerged caverns with aquatic treasures",
        dropBoost = 1.8,
    },
    
    mixed_geology = {
        name = "Mixed Geology",
        -- Adjusted to sandstone (brick-like), sand, and water with high water ratio
        materials = {
            brick = 0.30,
            sand  = 0.30,
            water = 0.40,  -- reduced from 0.50
        },
        scales = {
            brick = 24,
            sand = 25,
            water = 35,
        },
        minTier = 1,
        description = "Sandy formations with plentiful water and sandstone",
        dropBoost = 1.4,
    },
    
    infernal_depths = {
        name = "Infernal Depths",
        materials = { crackedlava = 0.70, basalt = 0.30 },
        scales = { crackedlava = 15, basalt = 25 },
        minTier = 2, -- Requires tier 2
        description = "Extreme heat with rare volcanic materials",
        dropBoost = 2.5,
    },
}

-- Get all themes available for a tier
function CubeThemes.GetAvailableForTier(tier: number): {[string]: CubeTheme}
    local available = {}
    for id, theme in pairs(CubeThemes.Themes) do
        if theme.minTier <= tier then
            available[id] = theme
        end
    end
    return available
end

-- Get theme by ID
function CubeThemes.GetTheme(themeId: string): CubeTheme?
    return CubeThemes.Themes[themeId]
end

-- Convert theme to material weights and scales
function CubeThemes.GetThemeComponents(themeId: string)
    local theme = CubeThemes.Themes[themeId]
    if not theme then return nil end
    
    local components = {}
    for materialKey, weight in pairs(theme.materials) do
        table.insert(components, {
            materialKey = materialKey,
            weight = weight,
            scale = theme.scales[materialKey] or 25,
        })
    end
    
    return components
end

return table.freeze(CubeThemes)
