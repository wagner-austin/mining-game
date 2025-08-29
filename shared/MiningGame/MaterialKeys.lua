--!strict
-- MaterialKeys.lua (derived from MaterialDefinitions)
-- Maintains backwards compatibility while deriving all data from MaterialDefinitions

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Defs = require(MiningGame:WaitForChild("MaterialDefinitions"))

local MaterialKeys = {}

-- Reuse canonical ordering from definitions
local orderedKeys = table.clone(Defs.KeysOrdered)

-- Build tables from MaterialDefinitions
local enumFromKey = {}
local displayNames = {}
for _, key in ipairs(orderedKeys) do
    local def = Defs.Materials[key]
    enumFromKey[key] = def.enum
    displayNames[key] = def.displayName
end

-- Shallow-freeze nested tables to prevent mutation
MaterialKeys.TerrainKeys   = table.freeze(orderedKeys)
MaterialKeys.EnumFromKey   = table.freeze(enumFromKey)
MaterialKeys.DisplayNames  = table.freeze(displayNames)
MaterialKeys.KeyFromEnum   = table.freeze(table.clone(Defs.KeyFromEnum))

-- Maintain backwards compatibility
MaterialKeys.CubeMaterials  = MaterialKeys.TerrainKeys
MaterialKeys.FloorMaterials = MaterialKeys.TerrainKeys

-- Dev-guard: ensure consistency
do
    local seen = {}
    for _, k in ipairs(MaterialKeys.TerrainKeys) do
        assert(MaterialKeys.EnumFromKey[k] ~= nil, ("[MaterialKeys] Missing EnumFromKey for '%s'"):format(k))
        assert(not seen[k], ("[MaterialKeys] Duplicate key '%s' in TerrainKeys"):format(k))
        seen[k] = true
    end
end

return table.freeze(MaterialKeys)