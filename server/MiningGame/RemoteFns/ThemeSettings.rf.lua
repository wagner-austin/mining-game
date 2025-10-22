--!strict
-- ThemeSettings.rf.lua
-- RemoteFunction specs for UI/sound theme management
-- Contract: top-level { ok, success, ... }. Exceptions: GetServerUnix (scalar), Equipped maps (raw).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local ThemePacks = require(Shared:WaitForChild("UI"):WaitForChild("ThemePacks"))

-- Return a factory function that accepts the DI container
return function(container)
    -- Resolve services from the container
    local DataService = container:Get("DataService")

    type RFSpec = {
    name: string,
    handler: (ctx: any, ...any) -> any,
    validate: ((...any) -> boolean)?,
    opts: {requireProfile: boolean?, rateLimitSec: number?, debugOnly: boolean?}?
}

    -- Build whitelists from ThemePacks (use actual case)
    local VALID_UI_THEMES = {}
for themeName, _ in pairs(ThemePacks) do
    VALID_UI_THEMES[themeName] = true  -- Store with actual case
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

    -- Helper to normalize strings (lowercase + trim)
    local function norm(s: any): string?
    if type(s) ~= "string" then return nil end
    return (s:lower():gsub("^%s*(.-)%s*$", "%1")) -- lowercase & trim
end

-- Cache discovery lists (they rarely change)
    local THEMES_CACHE: {string}? = nil
    local PACKS_CACHE: {string}? = nil

    local specs: {RFSpec} = {
    {
        name = "GetThemeSettings",
        handler = function(ctx)
            local settings = DataService:GetThemeSettings(ctx.player)
            if settings then
                -- Return full settings at top level (clients expect settings.uiTheme, settings.soundPack)
                local out = table.clone(settings)
                out.ok = true
                if out.success == nil then out.success = true end
                return out
            end
            return { ok = false, success = false, err = "NO_SETTINGS", reason = "Settings not available" }
        end,
        opts = { requireProfile = true, rateLimitSec = 1.0 },
    },
    
    {
        name = "UpdateThemeSettings",
        handler = function(ctx, patch: {uiTheme: string?, soundPack: string?, musicVolume: number?, sfxVolume: number?})
            -- Check for no-op
            local current = DataService:GetThemeSettings(ctx.player) or {}
            if (patch.uiTheme == nil or patch.uiTheme == current.uiTheme)
               and (patch.soundPack == nil or patch.soundPack == current.soundPack)
               and (patch.musicVolume == nil or patch.musicVolume == current.musicVolume)
               and (patch.sfxVolume == nil or patch.sfxVolume == current.sfxVolume) then
                -- Return at top level for consistency
                return { ok = true, success = true, unchanged = true }
            end
            
            local ok = DataService:SetThemeSettings(ctx.player, patch)
            if ok then
                return { ok = true, success = true }
            end
            return { ok = false, success = false, err = "UPDATE_FAILED", reason = "Failed to update theme settings" }
        end,
        validate = function(patch)
            if type(patch) ~= "table" then return false end
            -- Check only allowed keys exist
            for key, _ in pairs(patch) do
                if key ~= "uiTheme" and key ~= "soundPack" and key ~= "musicVolume" and key ~= "sfxVolume" then
                    return false
                end
            end
            -- Validate uiTheme if present
            if patch.uiTheme ~= nil then
                if type(patch.uiTheme) ~= "string" or #patch.uiTheme > 64 or not VALID_UI_THEMES[patch.uiTheme] then
                    return false
                end
                -- Keep original case
            end
            -- Validate and normalize soundPack if present  
            if patch.soundPack ~= nil then
                local pack = norm(patch.soundPack)
                if not pack or #pack > 64 or not VALID_SOUND_PACKS[pack] then
                    return false
                end
                patch.soundPack = pack -- normalize for handler
            end
            -- Validate musicVolume if present
            if patch.musicVolume ~= nil then
                if type(patch.musicVolume) ~= "number" or patch.musicVolume < 0 or patch.musicVolume > 1 then
                    return false
                end
            end
            -- Validate sfxVolume if present
            if patch.sfxVolume ~= nil then
                if type(patch.sfxVolume) ~= "number" or patch.sfxVolume < 0 or patch.sfxVolume > 1 then
                    return false
                end
            end
            -- Must have at least one valid key
            return patch.uiTheme ~= nil or patch.soundPack ~= nil or patch.musicVolume ~= nil or patch.sfxVolume ~= nil
        end,
        opts = { requireProfile = true, rateLimitSec = 0.4 },
    },
    
    {
        name = "GetAvailableThemes",
        handler = function(ctx)
            if not THEMES_CACHE then
                local keys = {}
                for k in pairs(ThemePacks) do 
                    table.insert(keys, k) 
                end
                table.sort(keys)
                THEMES_CACHE = keys
            end
            -- Return themes list at top level
            return { ok = true, success = true, themes = THEMES_CACHE }
        end,
        opts = { requireProfile = false, rateLimitSec = 2.0 },
    },
    
    {
        name = "GetAvailableSoundPacks",
        handler = function(ctx)
            if not PACKS_CACHE then
                local packs = {}
                for k in pairs(VALID_SOUND_PACKS) do 
                    table.insert(packs, k) 
                end
                table.sort(packs)
                PACKS_CACHE = packs
            end
            -- Return sound packs list at top level
            return { ok = true, success = true, soundPacks = PACKS_CACHE }
        end,
        opts = { requireProfile = false, rateLimitSec = 2.0 },
    },
}

    return specs
end -- End of factory function