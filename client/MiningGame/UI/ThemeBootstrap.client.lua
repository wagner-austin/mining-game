--!strict
-- ThemeBootstrap.client.lua
-- Loads and applies saved themes on player join (before UI appears)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MG = ReplicatedStorage:WaitForChild("MiningGame")

local ThemeManager = require(MG:WaitForChild("UI"):WaitForChild("ThemeManager"))
local SoundTheme = require(MG:WaitForChild("SoundThemeManager"))
local ClientRF = require(MG:WaitForChild("ClientRF"))
local Ready = require(MG:WaitForChild("Ready"))

-- Helper to load sound pack by name
local function packByName(name: string): any?
    if name == "default" then return nil end
    
    local SoundPacks = MG:FindFirstChild("SoundPacks")
    if not SoundPacks then return nil end
    
    local m = SoundPacks:FindFirstChild(name)
    if m and m:IsA("ModuleScript") then
        local ok, mod = pcall(require, m)
        if ok and typeof(mod) == "table" then 
            return mod 
        end
    end
    return nil
end

-- Load saved themes from server
local function loadSavedThemes(): ()
    -- Use retry for initial bootstrap to handle network issues
    local t, err = ClientRF.callWithRetry("GetThemeSettings", 2)
    
    local ui = "default"
    local snd = "default"
    
    if not err and typeof(t) == "table" then
        ui = t.uiTheme or "default"
        snd = t.soundPack or "default"
        print("[ThemeBootstrap] Loaded saved themes - UI:", ui, "Sound:", snd)
    else
        print("[ThemeBootstrap] Using default themes (no saved data or error)")
    end
    
    -- Apply UI theme
    ThemeManager.Apply(ui)
    
    -- Apply sound pack with fallback
    local pack = packByName(snd)
    if not pack and snd ~= "default" then
        print("[ThemeBootstrap] Sound pack", snd, "not found, falling back to default")
        snd = "default"
    end
    SoundTheme.Apply(snd, pack)
end

-- Apply themes immediately on startup
if Ready.wait(10) then
    loadSavedThemes()
else
    warn("[ThemeBootstrap] Server not ready after timeout; using defaults")
    -- Defaults already applied by ThemeManager and SoundTheme on init
end

print("[ThemeBootstrap] Theme settings applied")
