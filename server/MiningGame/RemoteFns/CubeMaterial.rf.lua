--!strict
-- CubeMaterial.rf.lua
-- RemoteFunction specs for cube material and palette management
-- Contract: top-level { ok, success, ... } for all user-facing RFs

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local MaterialDefinitions = require(Shared:WaitForChild("MaterialDefinitions"))
local MaterialPalettes = require(Shared:WaitForChild("MaterialPalettes"))

-- Return a factory function that accepts the DI container
return function(container)
    -- Resolve services from the container
    local CubeMaterialService = container:Get("CubeMaterialService")

    type RFSpec = {
    name: string,
    handler: (ctx: any, ...any) -> any,
    validate: ((...any) -> boolean)?,
    opts: {requireProfile: boolean?, rateLimitSec: number?, debugOnly: boolean?}?
}

    -- Helper function to normalize input strings (trim whitespace, lowercase)
    local function normalize(s: any): string?
    if type(s) ~= "string" then return nil end
    return (s:lower():gsub("^%s*(.-)%s*$", "%1"))
end

    -- Build validation whitelists
    local VALID_MATERIALS = {}
for key, _ in pairs(MaterialDefinitions.Materials) do
    VALID_MATERIALS[key] = true
end

local VALID_PALETTES = {}
if MaterialPalettes.Palettes then
    for key, _ in pairs(MaterialPalettes.Palettes) do
        VALID_PALETTES[key] = true
    end
end

    local specs: {RFSpec} = {
    {
        name = "ApplyCubeSurfaceMaterial",
        handler = function(ctx, materialKey: string)
            local key = normalize(materialKey)
            if not key or not VALID_MATERIALS[key] then
                return { ok = false, success = false, err = "INVALID_MATERIAL", reason = "Unknown material" }
            end
            local ok = CubeMaterialService.ApplyCubeSurfaceMaterial(ctx.player, key)
            if ok then
                return { ok = true, success = true, material = key }
            end
            return { ok = false, success = false, err = "APPLY_MATERIAL_FAILED", reason = "Failed to apply material" }
        end,
        validate = function(materialKey)
            local key = normalize(materialKey)
            return key ~= nil and VALID_MATERIALS[key] == true
        end,
        opts = { requireProfile = true, rateLimitSec = 0.4 },
    },
    
    {
        name = "ApplyFloorMaterial",
        handler = function(ctx, floorKey: string)
            local key = normalize(floorKey)
            if not key or not VALID_MATERIALS[key] then
                return { ok = false, success = false, err = "INVALID_FLOOR", reason = "Unknown floor material" }
            end
            local ok = CubeMaterialService.ApplyFloorMaterial(ctx.player, key)
            if ok then
                return { ok = true, success = true, floor = key }
            end
            return { ok = false, success = false, err = "APPLY_FLOOR_FAILED", reason = "Failed to apply floor material" }
        end,
        validate = function(floorKey)
            local key = normalize(floorKey)
            return key ~= nil and VALID_MATERIALS[key] == true
        end,
        opts = { requireProfile = true, rateLimitSec = 0.4 },
    },
    
    {
        name = "GetMaterialPreferences",
        handler = function(ctx)
            local prefs = CubeMaterialService.GetMaterialPreferences(ctx.player) or {}
            -- Return the full prefs table; shallow clone to avoid mutating service tables
            local out = table.clone(prefs)
            out.ok = true
            if out.success == nil then out.success = true end
            return out
        end,
        opts = { requireProfile = true, rateLimitSec = 1.0 },
    },
    
    {
        name = "SetPalettePreference",
        handler = function(ctx, paletteKey: string)
            local key = normalize(paletteKey)
            if not key or not VALID_PALETTES[key] then
                return { ok = false, success = false, err = "INVALID_PALETTE", reason = "Unknown palette" }
            end
            local ok = CubeMaterialService.SetPalettePreference(ctx.player, key)
            if ok then
                return { ok = true, success = true, palette = key }
            end
            return { ok = false, success = false, err = "SET_PALETTE_FAILED", reason = "Failed to set palette" }
        end,
        validate = function(paletteKey)
            local key = normalize(paletteKey)
            return key ~= nil and VALID_PALETTES[key] == true
        end,
        opts = { requireProfile = true, rateLimitSec = 0.3 },
    },
}

    return specs
end -- End of factory function