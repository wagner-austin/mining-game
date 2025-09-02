--!strict
-- ThemePacks.lua
-- UI color theme definitions

local function hex(h: string): Color3
    h = h:gsub("#","")
    return Color3.fromRGB(
        tonumber(h:sub(1,2),16) or 0, 
        tonumber(h:sub(3,4),16) or 0, 
        tonumber(h:sub(5,6),16) or 0
    )
end

return {
    default = {}, -- no overrides, uses base Theme.lua values
    
    light = {
        colors = {
            Background = hex("#F7F7F8"),
            Surface    = hex("#FFFFFF"),
            Text       = hex("#111111"),
            TextDim    = hex("#666666"),
            Primary    = hex("#3B82F6"),
            Accent     = hex("#F59E0B"),
        }
    },
    
    highContrast = {
        colors = {
            Background = hex("#000000"),  -- Pure black for maximum contrast
            Surface    = hex("#1A1A1A"),  -- Very dark gray for panels
            Text       = hex("#FFFFFF"),  -- Pure white text
            TextDim    = hex("#E0E0E0"),  -- Light gray for secondary text
            Primary    = hex("#00FF00"),  -- Bright green for primary actions
            Secondary  = hex("#FF00FF"),  -- Magenta for secondary
            Accent     = hex("#FFFF00"),  -- Yellow for accents
            Success    = hex("#00FF00"),  -- Green for success
            Error      = hex("#FF0000"),  -- Pure red for errors
        },
        effects = {
            frosted = {
                -- More opaque for better contrast
                backgroundTransparency = 0.05,
                gradientTopT = 0.80,
                gradientBottomT = 0.95,
                noiseTransparency = 0.96,
                noiseColorKey = "Background",
                noiseLighten = 0.05,
            }
        }
    },
    
    ocean = {
        colors = {
            Background = hex("#0D1B2A"),  -- Deep ocean
            Surface    = hex("#1B263B"),  -- Navy surface
            Text       = hex("#E0FBFC"),  -- Pale cyan
            TextDim    = hex("#98C1D9"),  -- Light blue
            Primary    = hex("#3D5A80"),  -- Ocean blue
            Secondary  = hex("#EE6C4D"),  -- Coral
            Accent     = hex("#FFD23F"),  -- Sun yellow
            Success    = hex("#6BCF7F"),  -- Sea green
            Error      = hex("#FF6B6B"),  -- Red coral
        }
    },
    
    forest = {
        colors = {
            Background = hex("#1A1F16"),  -- Dark forest
            Surface    = hex("#2E342A"),  -- Forest floor
            Text       = hex("#F7F3E3"),  -- Cream
            TextDim    = hex("#A8A382"),  -- Khaki
            Primary    = hex("#52734D"),  -- Forest green
            Secondary  = hex("#91C499"),  -- Mint
            Accent     = hex("#FDCA40"),  -- Sunlight
            Success    = hex("#6BCF7F"),  -- Leaf green
            Error      = hex("#DD6031"),  -- Autumn orange
        }
    },
}
