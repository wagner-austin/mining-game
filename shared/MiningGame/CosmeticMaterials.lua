--!strict
-- CosmeticMaterials.lua
-- Centralized material presets for cosmetics (neon + terrain-friendly)

local CosmeticMaterials = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local MaterialDefinitions = require(MiningGame:WaitForChild("MaterialDefinitions"))

-- Build presets from the game's terrain material definitions, plus a few part-only staples
local presets: {[string]: Enum.Material} = {
    neon = Enum.Material.Neon, -- extra preset for glowing cosmetics
}

-- Pull exact floor/terrain materials from MaterialDefinitions
for key, def in pairs(MaterialDefinitions.Materials) do
    presets[string.lower(key)] = def.enum
end

-- Optionally add a couple of non-terrain part materials (kept minimal)
presets["metal"] = Enum.Material.Metal
presets["glass"] = Enum.Material.Glass
presets["plastic"] = Enum.Material.Plastic
presets["smoothplastic"] = Enum.Material.SmoothPlastic
presets["fabric"] = Enum.Material.Fabric

CosmeticMaterials.PRESETS = presets

-- Resolve a material from string/enum/table
function CosmeticMaterials.resolve(spec: any, default: Enum.Material?): Enum.Material
    if typeof(spec) == "EnumItem" and tostring(spec.EnumType) == "Enum.Material" then
        return spec :: Enum.Material
    end
    if type(spec) == "string" then
        local key = string.lower(spec)
        return presets[key] or default or Enum.Material.Neon
    end
    if type(spec) == "table" then
        local name = spec.name or spec.preset or spec.id
        if type(name) == "string" then
            local key = string.lower(name)
            return presets[key] or default or Enum.Material.Neon
        end
    end
    return default or Enum.Material.Neon
end

-- Pick material for a cosmetic def, honoring material/materialPreset fields.
function CosmeticMaterials.pick(def: any, default: Enum.Material?): Enum.Material
    if not def then return default or Enum.Material.Neon end
    local m = def.material or def.materialPreset or def.cosmeticMaterial
    return CosmeticMaterials.resolve(m, default)
end

return CosmeticMaterials
