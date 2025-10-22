--!strict
-- Settings.rf.lua
-- RemoteFunction specs for settings and preferences
-- Contract: top-level { ok, success, ... }. Exceptions: GetServerUnix (scalar), Equipped maps (raw).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local ThemePacks = require(Shared:WaitForChild("UI"):WaitForChild("ThemePacks"))

-- Return a factory function that accepts the DI container
return function(container)
    -- Resolve services from the container
    -- Note: ThemeSettingsService is empty, actual methods are in DataService
    local DataService = container:Get("DataService")

    -- Helper to normalize strings (trim only, preserve case)
    local function normalize(s: any): string?
    if type(s) ~= "string" then return nil end
    return (s:gsub("^%s*(.-)%s*$", "%1")) -- trim whitespace only
end

    -- Build whitelists from ThemePacks (case-sensitive)
    local VALID_UI_THEMES = {}
for themeName, _ in pairs(ThemePacks) do
    VALID_UI_THEMES[themeName] = true  -- Use original case
end

-- Auto-build sound pack whitelist from available modules
local SoundPacksFolder = Shared:FindFirstChild("SoundPacks")
local VALID_SOUND_PACKS = { default = true }
if SoundPacksFolder then
    for _, m in ipairs(SoundPacksFolder:GetChildren()) do
        if m:IsA("ModuleScript") then
            VALID_SOUND_PACKS[string.lower(m.Name)] = true
        end
    end
end

    type RFSpec = {
    name: string,
    handler: (ctx: any, ...any) -> any,
    validate: ((...any) -> boolean)?,
    opts: {requireProfile: boolean?, rateLimitSec: number?}?
}

-- Single source of truth for default theme settings (frozen to prevent mutations)
local DEFAULT_THEME_SETTINGS = table.freeze({
    uiTheme = "default",
    soundPack = "default",
    musicVolume = 0.5,
    sfxVolume = 0.5
})

-- Valid setting keys and their types for UpdateGeneralSettings
local VALID_SETTINGS = {
    -- Theme settings (these match what DataService accepts and are persisted)
    uiTheme = "string",
    soundPack = "string",
    musicVolume = "number",
    sfxVolume = "number",
    
    -- Note: Non-theme settings below would need profile.preferences storage
    -- Currently only theme settings above are persisted via DataService:SetThemeSettings
    
    -- Graphics settings (future expansion - not yet persisted)
    particles = "boolean",
    cameraShake = "boolean",
    reducedMotion = "boolean",
    
    -- UI settings (future expansion - not yet persisted)
    showFPS = "boolean",
    showPing = "boolean",
    compactUI = "boolean",
    
    -- Gameplay settings (future expansion - not yet persisted)
    autoSell = "boolean",
    confirmPurchases = "boolean",
    showDamageNumbers = "boolean",
}

-- Valid theme names
local VALID_THEMES = {}
for name, _ in pairs(ThemePacks) do
    VALID_THEMES[name] = true
end

-- Validate a setting value based on its expected type
local function validateSetting(key: string, value: any): boolean
    local expectedType = VALID_SETTINGS[key]
    if not expectedType then
        return false
    end
    
    if type(value) ~= expectedType then
        return false
    end
    
    -- Additional validation for specific keys
    if key == "theme" then
        return VALID_THEMES[value] == true
    elseif key == "musicVolume" or key == "sfxVolume" then
        return value >= 0 and value <= 1
    end
    
    return true
end

    local specs: {RFSpec} = {
    {
        name = "GetSettings",
        handler = function(ctx)
            local player = ctx.player
            
            -- Get theme settings from DataService
            local settings = DataService:GetThemeSettings(player)
            if settings then
                -- Return settings at top level
                local out = table.clone(settings)
                out.ok = true
                out.success = true
                return out
            end
            
            -- Return defaults at top level if no settings saved
            local out = table.clone(DEFAULT_THEME_SETTINGS)
            out.ok = true
            out.success = true
            return out
        end,
        opts = { requireProfile = true, rateLimitSec = 0.5 },
    },

    {
        name = "UpdatePreferences",
        handler = function(ctx, updates: {[string]: any})
            local player = ctx.player
            -- Whitelist and validate keys
            if type(updates) ~= "table" then
                return { ok = false, success = false, err = "INVALID_BODY" }
            end
            if updates.autoDigEnabled ~= nil and type(updates.autoDigEnabled) ~= "boolean" then
                return { ok = false, success = false, err = "INVALID_autodig", reason = "autoDigEnabled must be boolean" }
            end
            local ok = DataService:SetPreferences(player, {
                autoDigEnabled = updates.autoDigEnabled,
            })
            if ok then
                return { ok = true, success = true, updated = { autoDigEnabled = updates.autoDigEnabled } }
            else
                return { ok = false, success = false, err = "UPDATE_FAILED" }
            end
        end,
        opts = { requireProfile = true, rateLimitSec = 0.2 },
    },
    
    {
        name = "UpdateGeneralSettings",
        handler = function(ctx, updates: {[string]: any})
            local player = ctx.player
            
            -- Validate all updates
            for key, value in pairs(updates) do
                if not validateSetting(key, value) then
                    return { ok = false, success = false, err = "INVALID_SETTING", reason = string.format("Invalid setting: %s", key) }
                end
            end
            
            -- Apply updates via DataService (only passes theme-related keys)
            local themeUpdates = {}
            local skipped = {}
            
            -- Normalize and validate uiTheme
            if updates.uiTheme ~= nil then
                local theme = normalize(updates.uiTheme)
                if theme and VALID_UI_THEMES[theme] then
                    themeUpdates.uiTheme = theme
                else
                    skipped.uiTheme = "invalid"
                end
            end
            
            -- Normalize and validate soundPack
            if updates.soundPack ~= nil then
                local pack = normalize(updates.soundPack)
                if pack and VALID_SOUND_PACKS[pack] then
                    themeUpdates.soundPack = pack
                else
                    skipped.soundPack = "invalid"
                end
            end
            
            -- Validate and add volume settings
            if updates.musicVolume ~= nil then
                if type(updates.musicVolume) ~= "number" or updates.musicVolume < 0 or updates.musicVolume > 1 then
                    skipped.musicVolume = "invalid"
                else
                    themeUpdates.musicVolume = updates.musicVolume
                end
            end
            
            if updates.sfxVolume ~= nil then
                if type(updates.sfxVolume) ~= "number" or updates.sfxVolume < 0 or updates.sfxVolume > 1 then
                    skipped.sfxVolume = "invalid"
                else
                    themeUpdates.sfxVolume = updates.sfxVolume
                end
            end
            
            -- Track non-theme keys that were skipped
            for key, _ in pairs(updates) do
                if themeUpdates[key] == nil and not skipped[key] then
                    skipped[key] = "non-theme"
                end
            end
            
            -- Check if we have any theme updates to persist
            if next(themeUpdates) == nil then
                -- No theme-related updates, return unchanged with skipped info
                return { 
                    ok = true, 
                    success = true, 
                    unchanged = true,
                    skipped = next(skipped) and skipped or nil
                }
            end
            
            local success = DataService:SetThemeSettings(player, themeUpdates)
            if success then
                -- Return what we actually persisted, plus what was skipped
                return { 
                    ok = true, 
                    success = true, 
                    updated = themeUpdates,
                    skipped = next(skipped) and skipped or nil
                }
            end
            
            return { ok = false, success = false, err = "UPDATE_FAILED", reason = "Failed to update settings" }
        end,
        validate = function(updates)
            return type(updates) == "table" -- allow {} so handler can return unchanged
        end,
        opts = { requireProfile = true, rateLimitSec = 0.2 },
    },
    
    -- UpdateSettings RF removed - was unused legacy endpoint
    
    {
        name = "GetAllSettings",
        handler = function(ctx)
            local player = ctx.player
            
            -- Combine all settings from different services
            local allSettings = {}
            
            -- Player preferences from profile (if they exist) - loaded first
            local profile = DataService:GetPlayerData(player)
            if profile and type(profile.preferences) == "table" then
                for k, v in pairs(profile.preferences) do
                    allSettings[k] = v
                end
            end
            
            -- Theme settings (primary source) - OVERRIDES any duplicate keys from preferences
            -- This ensures theme settings are the single source of truth for UI/sound/volume
            local themeSettings = DataService:GetThemeSettings(player)
            if themeSettings then
                for k, v in pairs(themeSettings) do
                    allSettings[k] = v
                end
            end
            
            -- Return all settings at top level
            local out = table.clone(allSettings)
            out.ok = true
            out.success = true
            return out
        end,
        opts = { requireProfile = true, rateLimitSec = 1.0 },
    },
    
    {
        name = "ResetSettings",
        handler = function(ctx, category: string?)
            local player = ctx.player
            
            if not category or category == "all" then
                -- Reset all settings to defaults (including volumes)
                DataService:SetThemeSettings(player, table.clone(DEFAULT_THEME_SETTINGS))
                return { ok = true, success = true, reset = "all" }
            elseif category == "theme" then
                -- Reset theme settings to defaults (including volumes)
                DataService:SetThemeSettings(player, table.clone(DEFAULT_THEME_SETTINGS))
                return { ok = true, success = true, reset = "theme" }
            else
                return { ok = false, success = false, err = "INVALID_CATEGORY", reason = "Unknown category: " .. tostring(category) }
            end
        end,
        validate = function(category)
            return category == nil or type(category) == "string"
        end,
        opts = { requireProfile = true, rateLimitSec = 2.0 },
    },
}

    return specs
end -- End of factory function
