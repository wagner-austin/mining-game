--!strict
-- SoundThemeManager.lua
-- Minimal sound theme management with runtime swapping and fallbacks

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local SoundConfig = require(MiningGame:WaitForChild("SoundConfig"))
local EventBus = require(MiningGame:WaitForChild("EventBus"))
local EventNames = require(MiningGame:WaitForChild("EventNames"))
local Bus = EventBus.global()
local Logger = require(MiningGame:WaitForChild("Logger"))
local log = Logger.new("SoundThemeManager")

local SoundThemeManager = {}
local _activeName = "default"
local _overrides: {[string]: any}? = nil
local _changed = Instance.new("BindableEvent")

-- Apply a sound pack (can be partial overrides)
function SoundThemeManager.Apply(name: string, overrides: {[string]: any}?)
    _activeName = name
    -- Defensive check for non-table overrides
    if overrides and typeof(overrides) == "table" then
        _overrides = table.clone(overrides)
    else
        _overrides = nil
    end
    _changed:Fire(_activeName)
    log:info("Applied sound pack: %s", name)
    -- Cross-module notification (client-local)
    Bus:emit(EventNames.SOUNDTHEME_CHANGED, { name = _activeName })
end

-- Get change event
function SoundThemeManager.Changed()
    return _changed.Event
end

-- Get current pack name
function SoundThemeManager.ActiveName(): string
    return _activeName
end

-- Resolve sound IDs with pack → base fallback
function SoundThemeManager.GetId(path: {string}, default: string?): string?
    -- First try the override pack
    local node = _overrides
    if node then
        for _, key in ipairs(path) do
            key = string.lower(key)
            node = node[key]
            if node == nil then break end
        end
        if typeof(node) == "string" then 
            return node 
        end
    end
    
    -- Fall back to base SoundConfig
    node = SoundConfig.SoundIDs
    for _, key in ipairs(path) do
        key = string.lower(key)
        node = node[key]
        if node == nil then return default end
    end
    
    if typeof(node) == "string" then 
        return node 
    end
    
    return default
end

-- Helper to get all IDs for a category (for preloading)
function SoundThemeManager.GetCategoryIds(category: string): {string}
    local ids = {}
    local seen = {}
    
    -- Collect from overrides
    if _overrides and _overrides[category] then
        local function collect(t)
            for k, v in pairs(t) do
                if typeof(v) == "string" and not seen[v] then
                    table.insert(ids, v)
                    seen[v] = true
                elseif typeof(v) == "table" then
                    collect(v)
                end
            end
        end
        collect(_overrides[category])
    end
    
    -- Collect from base (for non-overridden sounds)
    if SoundConfig.SoundIDs[category] then
        local function collect(t)
            for k, v in pairs(t) do
                if typeof(v) == "string" and not seen[v] then
                    table.insert(ids, v)
                    seen[v] = true
                elseif typeof(v) == "table" then
                    collect(v)
                end
            end
        end
        collect(SoundConfig.SoundIDs[category])
    end
    
    return ids
end

-- Get all IDs from current pack (for preloading everything)
function SoundThemeManager.GetAllIds(): {string}
    local categories = {"ui", "music", "mining", "movement", "ambient", "rewards", "pets", "environment"}
    local allIds = {}
    local seen = {}
    
    for _, cat in ipairs(categories) do
        for _, id in ipairs(SoundThemeManager.GetCategoryIds(cat)) do
            if not seen[id] then
                table.insert(allIds, id)
                seen[id] = true
            end
        end
    end
    
    return allIds
end

return SoundThemeManager
