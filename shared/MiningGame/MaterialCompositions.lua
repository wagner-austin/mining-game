--!strict
-- MaterialCompositions.lua
-- Defines unlockable materials that can be added to custom compositions
-- Players start with rock and unlock additional materials to mix

local MaterialCompositions = {}

export type UnlockableMaterial = {
    materialKey: string,     -- Key from MaterialDefinitions
    name: string,
    tier: number,           -- Which tier this unlocks at (1-6)
    unlockCost: number,     -- Cost to unlock this material
    defaultWeight: number,  -- Default weight when added (0.1-0.5)
    defaultScale: number,   -- Default swathe size (10-50)
    description: string,
    dropModifiers: {        -- Drop modifications when this material is present
        rarityBoost: number?,     -- Multiplier for rare drops (1.0 = normal)
        specificItems: {string}?, -- Items more likely to drop
        exclusiveItems: {string}?, -- Items only available with this material
    }?,
}

-- All unlockable materials - using actual materials from MaterialDefinitions
MaterialCompositions.UnlockableMaterials = {
    -- Starting material (free)
    rock = {
        materialKey = "rock",
        name = "Rock",
        tier = 1,
        unlockCost = 0, -- Free starter
        defaultWeight = 1.0,
        defaultScale = 30,
        description = "Basic mining rock",
    },
    
    -- Tier 1 unlocks - exciting variety
    sand = {
        materialKey = "sand",
        name = "Sand",
        tier = 1,
        unlockCost = 300,
        defaultWeight = 0.3,
        defaultScale = 25,
        description = "Desert sand with glass and gems",
        dropModifiers = {
            specificItems = {"glass_shard", "quartz"},
            rarityBoost = 1.1,
        },
    },
    
    ice = {
        materialKey = "ice",
        name = "Ice",
        tier = 1,
        unlockCost = 500,
        defaultWeight = 0.35,
        defaultScale = 22,
        description = "Frozen ice caverns",
        dropModifiers = {
            specificItems = {"ice_crystal", "frozen_gem"},
            rarityBoost = 1.2,
        },
    },
    
    mud = {
        materialKey = "mud",
        name = "Mud",
        tier = 1,
        unlockCost = 400,
        defaultWeight = 0.3,
        defaultScale = 20,
        description = "Swampy mud with organic treasures",
        dropModifiers = {
            specificItems = {"moss", "bog_iron", "worm"},
            rarityBoost = 1.15,
        },
    },
    
    basalt = {
        materialKey = "basalt",
        name = "Basalt",
        tier = 1,
        unlockCost = 600,
        defaultWeight = 0.35,
        defaultScale = 25,
        description = "Volcanic basalt with metal ores",
        dropModifiers = {
            specificItems = {"iron", "copper", "obsidian"},
            rarityBoost = 1.4,
        },
    },
    
    glacier = {
        materialKey = "glacier",
        name = "Glacier",
        tier = 1,
        unlockCost = 700,
        defaultWeight = 0.4,
        defaultScale = 30,
        description = "Ancient glacier ice",
        dropModifiers = {
            specificItems = {"frozen_amber", "ice_fossil"},
            exclusiveItems = {"eternal_ice"},
            rarityBoost = 1.5,
        },
    },
    
    salt = {
        materialKey = "salt",
        name = "Salt",
        tier = 1,
        unlockCost = 550,
        defaultWeight = 0.3,
        defaultScale = 18,
        description = "Salt crystal caves",
        dropModifiers = {
            specificItems = {"crystal", "salt_rock"},
            rarityBoost = 1.35,
        },
    },
    
    crackedlava = {
        materialKey = "crackedlava",
        name = "Cracked Lava",
        tier = 1,
        unlockCost = 1000,
        defaultWeight = 0.3,
        defaultScale = 15,
        description = "Molten lava rock with extreme heat",
        dropModifiers = {
            specificItems = {"obsidian_shard", "volcanic_glass"},
            exclusiveItems = {"lava_core", "phoenix_feather"},
            rarityBoost = 2.5,
        },
    },
    
    water = {
        materialKey = "water",
        name = "Water",
        tier = 1,
        unlockCost = 800,
        defaultWeight = 0.35,
        defaultScale = 35,
        description = "Underground water pockets",
        dropModifiers = {
            specificItems = {"pearl", "coral_fragment", "fish"},
            exclusiveItems = {"trident_shard"},
            rarityBoost = 1.8,
        },
    },
}

-- Get all materials available for a tier
function MaterialCompositions.GetAvailableForTier(maxTier: number): {UnlockableMaterial}
    local result = {}
    for _, mat in pairs(MaterialCompositions.UnlockableMaterials) do
        if mat.tier <= maxTier then
            table.insert(result, mat)
        end
    end
    table.sort(result, function(a, b)
        if a.tier ~= b.tier then
            return a.tier < b.tier
        end
        return a.unlockCost < b.unlockCost
    end)
    return result
end

-- Calculate composition from unlocked materials
function MaterialCompositions.BuildComposition(unlockedMaterials: {string}, customWeights: {[string]: number}?)
    local components = {}
    local totalWeight = 0
    
    for _, matKey in ipairs(unlockedMaterials) do
        local matData = MaterialCompositions.UnlockableMaterials[matKey]
        if matData then
            local weight = customWeights and customWeights[matKey] or matData.defaultWeight
            totalWeight = totalWeight + weight
            
            table.insert(components, {
                materialKey = matKey,
                weight = weight,
                scale = matData.defaultScale,
                dropModifier = matData.dropModifiers,
            })
        end
    end
    
    -- Normalize weights to sum to 1.0
    if totalWeight > 0 then
        for _, component in ipairs(components) do
            component.weight = component.weight / totalWeight
        end
    end
    
    return components
end

-- Get combined drop modifiers from all materials
function MaterialCompositions.GetCombinedModifiers(unlockedMaterials: {string})
    local combined = {
        rarityBoost = 1.0,
        specificItems = {},
        exclusiveItems = {},
    }
    
    local itemSet = {}
    local exclusiveSet = {}
    
    for _, matKey in ipairs(unlockedMaterials) do
        local matData = MaterialCompositions.UnlockableMaterials[matKey]
        if matData and matData.dropModifiers then
            -- Multiply rarity boosts
            if matData.dropModifiers.rarityBoost then
                combined.rarityBoost = combined.rarityBoost * matData.dropModifiers.rarityBoost
            end
            
            -- Collect specific items
            if matData.dropModifiers.specificItems then
                for _, item in ipairs(matData.dropModifiers.specificItems) do
                    itemSet[item] = true
                end
            end
            
            -- Collect exclusive items
            if matData.dropModifiers.exclusiveItems then
                for _, item in ipairs(matData.dropModifiers.exclusiveItems) do
                    exclusiveSet[item] = true
                end
            end
        end
    end
    
    -- Convert sets to arrays
    for item in pairs(itemSet) do
        table.insert(combined.specificItems, item)
    end
    for item in pairs(exclusiveSet) do
        table.insert(combined.exclusiveItems, item)
    end
    
    return combined
end

-- Validate all materials reference valid terrain materials
local function validateMaterials()
    local MaterialDefinitions = require(script.Parent:WaitForChild("MaterialDefinitions"))
    
    for id, mat in pairs(MaterialCompositions.UnlockableMaterials) do
        assert(MaterialDefinitions.GetEnum(mat.materialKey), 
            "Unknown material key '" .. mat.materialKey .. "' in " .. id)
        assert(mat.tier >= 1 and mat.tier <= 6, "Invalid tier for " .. id)
    end
end

-- Run validation
task.spawn(validateMaterials)

return table.freeze(MaterialCompositions)