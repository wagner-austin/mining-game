--!strict
-- SoundPreloader.client.lua
-- Preloads sound assets dynamically based on active theme pack

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local SoundTheme = require(MiningGame:WaitForChild("SoundThemeManager"))

local _busy = false
local _dirty = false

local function preload(ids: {string})
    if _busy then
        _dirty = true
        warn("[SoundPreloader] Preload already running; will retry after completion.")
        return
    end
    _busy = true
    
    if #ids == 0 then
        print("[SoundPreloader] No sounds to preload")
        _busy = false
        return
    end
    
    print(string.format("[SoundPreloader] Preloading %d sound assets...", #ids))
    
    -- Create temporary Sound instances for preloading
    local sounds = {}
    for _, id in ipairs(ids) do
        local s = Instance.new("Sound")
        s.SoundId = id
        s.Parent = SoundService
        table.insert(sounds, s)
    end
    
    -- Preload with error handling
    local ok, err = pcall(function()
        ContentProvider:PreloadAsync(sounds, function(assetId, status)
            if status == Enum.AssetFetchStatus.Failure then
                warn("[SoundPreloader] Failed to preload:", assetId)
            end
        end)
    end)
    
    if not ok then
        warn("[SoundPreloader] PreloadAsync error:", err)
    else
        print("[SoundPreloader] Preloading complete!")
    end
    
    -- Clean up temporary sounds
    for _, s in ipairs(sounds) do 
        s:Destroy() 
    end
    
    _busy = false
    
    -- Check if another preload was requested during this run
    if _dirty then
        _dirty = false
        preload(SoundTheme.GetAllIds())
    end
end

-- Preload initial pack
preload(SoundTheme.GetAllIds())

-- Preload new pack when theme changes
SoundTheme.Changed():Connect(function()
    print("[SoundPreloader] Sound pack changed, preloading new assets...")
    preload(SoundTheme.GetAllIds())
end)