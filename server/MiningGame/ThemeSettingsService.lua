--!strict
-- ThemeSettingsService.lua
-- Server-side theme settings validation and persistence

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local MG = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(MG:WaitForChild("Logger"))
local log = Logger.new("ThemeSettingsService")
local Remotes = require(script.Parent.Remotes)
local DataService = require(script.Parent.DataService)

-- Whitelist UI themes from shared packs
local ThemePacks = require(MG:WaitForChild("UI"):WaitForChild("ThemePacks"))
local AllowedUI = {}
for name in pairs(ThemePacks) do 
    AllowedUI[name] = true 
end

-- Whitelist sound packs by ModuleScript name under shared/MiningGame/SoundPacks
local SoundPacksFolder = MG:FindFirstChild("SoundPacks")
local function soundPackExists(name: string): boolean
    if name == "default" then return true end
    if not SoundPacksFolder then return false end
    local m = SoundPacksFolder:FindFirstChild(name)
    return m ~= nil and m:IsA("ModuleScript")
end

-- GET theme settings
Remotes.RF.GetThemeSettings.OnServerInvoke = function(player: Player)
    DataService:EnsureLoaded(player)
    return DataService:GetThemeSettings(player)
end

-- UPDATE theme settings { uiTheme?: string, soundPack?: string }
Remotes.RF.UpdateThemeSettings.OnServerInvoke = function(player: Player, patch)
    if typeof(patch) ~= "table" then 
        log:warn("Invalid patch type from %s", player.Name)
        return false 
    end

    local clean: {[string]: string} = {}

    -- Validate UI theme
    if patch.uiTheme ~= nil then
        if typeof(patch.uiTheme) == "string" and AllowedUI[patch.uiTheme] then
            clean.uiTheme = patch.uiTheme
            log:info("%s changing UI theme to: %s", player.Name, patch.uiTheme)
        else
            log:warn("Invalid UI theme from %s: %s", player.Name, tostring(patch.uiTheme))
        end
    end

    -- Validate sound pack
    if patch.soundPack ~= nil then
        if typeof(patch.soundPack) == "string" and soundPackExists(patch.soundPack) then
            clean.soundPack = patch.soundPack
            log:info("%s changing sound pack to: %s", player.Name, patch.soundPack)
        else
            log:warn("Invalid sound pack from %s: %s", player.Name, tostring(patch.soundPack))
        end
    end

    if next(clean) == nil then 
        log:warn("No valid changes in patch from %s", player.Name)
        return false 
    end

    DataService:EnsureLoaded(player)
    local success = DataService:SetThemeSettings(player, clean)
    if success then
        log:info("Saved theme settings for uid=%d", player.UserId)
    end
    return success
end

log:info("Initialized")

return {}