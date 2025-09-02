--!strict
-- ThemeManager.lua
-- Hot-swappable UI themes with in-place mutation so existing references keep working

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Theme = require(MiningGame:WaitForChild("UI"):WaitForChild("Theme"))
local Packs = require(MiningGame:WaitForChild("UI"):WaitForChild("ThemePacks"))

local ThemeManager = {}
local _name = "default"
local _changed = Instance.new("BindableEvent")

-- Keep pristine copies so applying "default" truly resets, while preserving table identity
local _baseColors = table.clone(Theme.colors)
local _baseRarity = table.clone(Theme.rarityColors)

local function deepClone(tbl)
    if typeof(tbl) ~= "table" then return tbl end
    local copy = {}
    for k, v in pairs(tbl) do
        if typeof(v) == "table" then
            copy[k] = deepClone(v)
        else
            copy[k] = v
        end
    end
    return copy
end

local _baseEffects = deepClone(Theme.effects)
local _baseTabs = deepClone(Theme.tabs)
local _baseGlassEdge = table.clone(Theme.glassEdge)

local function replaceTable(target: {[string]: any}, src: {[string]: any})
    for k in pairs(target) do target[k] = nil end
    for k, v in pairs(src) do target[k] = v end
end

local function mutate(dst: {[string]: any}, src: {[string]: any})
    for k, v in pairs(src) do
        if typeof(v) == "table" and typeof(dst[k]) == "table" then
            mutate(dst[k], v)
        else
            dst[k] = v
        end
    end
end

local function rederiveDerivedValues()
    -- Keep any derived fields in sync with the new colors
    if Theme.toast and Theme.toast.tint then
        Theme.toast.tint.info    = Theme.colors.Primary
        Theme.toast.tint.success = Theme.colors.Success
        Theme.toast.tint.error   = Theme.colors.Error
    end
end

function ThemeManager.Apply(name: string)
    if not Packs[name] then name = "default" end
    _name = name

    -- Reset to base (preserve table identity!)
    replaceTable(Theme.colors, _baseColors)
    replaceTable(Theme.rarityColors, _baseRarity)
    -- Use deep clones so we never share nested tables with the baseline
    replaceTable(Theme.effects, deepClone(_baseEffects))
    replaceTable(Theme.tabs, deepClone(_baseTabs))
    replaceTable(Theme.glassEdge, _baseGlassEdge)

    -- Apply overrides (partial packs OK)
    local pack = Packs[name]
    if pack.colors then mutate(Theme.colors, pack.colors) end
    if pack.rarityColors then mutate(Theme.rarityColors, pack.rarityColors) end
    if pack.effects then mutate(Theme.effects, pack.effects) end
    if pack.tabs then mutate(Theme.tabs, pack.tabs) end
    if pack.glassEdge then mutate(Theme.glassEdge, pack.glassEdge) end

    rederiveDerivedValues()
    _changed:Fire(_name)
    print("[ThemeManager] Applied theme:", _name)
end

function ThemeManager.Changed() 
    return _changed.Event 
end

function ThemeManager.ActiveName(): string 
    return _name 
end

return ThemeManager
