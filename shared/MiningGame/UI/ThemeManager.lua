--!strict
-- ThemeManager.lua
-- Hot-swappable UI themes with in-place mutation so existing references keep working

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Theme = require(MiningGame:WaitForChild("UI"):WaitForChild("Theme"))
local Packs = require(MiningGame:WaitForChild("UI"):WaitForChild("ThemePacks"))
local EventBus = require(MiningGame:WaitForChild("EventBus"))
local EventNames = require(MiningGame:WaitForChild("EventNames"))
local Bus = EventBus.global()
local Logger = require(MiningGame:WaitForChild("Logger"))
local log = Logger.new("ThemeManager")

local ThemeManager = {}
local _name = "default"
local _changed = Instance.new("BindableEvent")

-- Keep pristine copies so applying "default" truly resets, while preserving table identity
local _baseColors = table.clone(Theme.colors)
local _baseRarity = table.clone(Theme.rarityColors)
local _baseFonts = Theme.fonts and table.clone(Theme.fonts) or {}
local _baseButtonSize = Theme.buttonSize or 18

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
local _basePostProcessing = deepClone(Theme.postProcessing or {})

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

local function assertType(name: string, v: any, kind: string)
    if kind == "Color3" then 
        assert(typeof(v) == "Color3", name .. " must be Color3, got " .. typeof(v))
    elseif kind == "Font" then 
        assert(typeof(v) == "EnumItem" and tostring(v.EnumType) == "Font", name .. " must be Enum.Font")
    else 
        assert(type(v) == kind, name .. " must be " .. kind .. ", got " .. type(v))
    end
end

local function validateTheme()
    -- Validate required fields exist with correct types
    assertType("Theme.buttonSize", Theme.buttonSize, "number")
    assert(Theme.fonts, "Theme.fonts missing")
    assertType("Theme.fonts.Primary", Theme.fonts.Primary, "Font")
    assert(Theme.colors, "Theme.colors missing")
    assertType("Theme.colors.Primary", Theme.colors.Primary, "Color3")
    assertType("Theme.colors.TextSecondary", Theme.colors.TextSecondary, "Color3")
    -- Add more validations as needed
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
    -- Themes are now stored with proper case, no normalization needed
    if not Packs[name] then 
        name = "Default" 
    end
    _name = name

    -- Reset to base (preserve table identity!)
    replaceTable(Theme.colors, _baseColors)
    replaceTable(Theme.rarityColors, _baseRarity)
    -- Fonts are frozen, so we need to replace the whole table
    Theme.fonts = table.clone(_baseFonts)
    Theme.buttonSize = _baseButtonSize
    -- Use deep clones so we never share nested tables with the baseline
    if Theme.effects then replaceTable(Theme.effects, deepClone(_baseEffects)) end
    if Theme.tabs then replaceTable(Theme.tabs, deepClone(_baseTabs)) end
    if Theme.glassEdge then replaceTable(Theme.glassEdge, _baseGlassEdge) end
    replaceTable(Theme.postProcessing, deepClone(_basePostProcessing))

    -- Apply overrides (partial packs OK)
    local pack = Packs[name]
    if pack.colors then mutate(Theme.colors, pack.colors) end
    if pack.rarityColors then mutate(Theme.rarityColors, pack.rarityColors) end
    if pack.fonts then
        -- Fonts are frozen, so we need to merge and recreate
        local newFonts = table.clone(Theme.fonts)
        for k, v in pairs(pack.fonts) do
            newFonts[k] = v
        end
        Theme.fonts = table.freeze(newFonts)
    end
    if type(pack.buttonSize) == "number" then Theme.buttonSize = pack.buttonSize end
    if pack.effects then mutate(Theme.effects, pack.effects) end
    if pack.tabs then mutate(Theme.tabs, pack.tabs) end
    if pack.glassEdge then mutate(Theme.glassEdge, pack.glassEdge) end
    
    -- Handle post-processing overrides (shallow merge for each class)
    if pack.postProcessing then
        for className, props in pairs(pack.postProcessing) do
            Theme.postProcessing[className] = Theme.postProcessing[className] or {}
            for k, v in pairs(props) do
                Theme.postProcessing[className][k] = v
            end
        end
    end

    rederiveDerivedValues()
    
    -- Validate theme has all required fields
    validateTheme()
    
    _changed:Fire(_name)
    log:info("Applied theme: %s", _name)
    -- Cross-module notification (client-local)
    Bus:emit(EventNames.THEME_CHANGED, { name = _name })
end

function ThemeManager.Changed() 
    return _changed.Event 
end

function ThemeManager.ActiveName(): string 
    return _name 
end

return ThemeManager
