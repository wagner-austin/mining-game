--!strict
-- SoundPreloader.client.lua
-- Preloads sound assets dynamically based on active theme pack

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local SoundTheme = require(MiningGame:WaitForChild("SoundThemeManager"))
local SoundConfig = require(MiningGame:WaitForChild("SoundConfig"))
local Timeout = require(MiningGame:WaitForChild("Timeout"))
local LoadCfg = require(MiningGame:WaitForChild("LoadingConstants"))

local _busy = false
local _dirty = false

-- Always preload these core sounds regardless of theme
local ALWAYS_PRELOAD = {
    -- Core sounds can be added here if needed
}

-- Gather all sound IDs from various sources
local function gatherIds(): {string}
    local ids, seen = {}, {}
    
    local function add(id)
        if type(id) == "string" and id ~= "" and id ~= "rbxassetid://0" and not seen[id] then
            seen[id] = true
            table.insert(ids, id)
        end
    end
    
    local function walk(v)
        if type(v) == "table" then
            for _, x in pairs(v) do walk(x) end
        else
            add(v)
        end
    end
    
    -- 1) Always-preload list
    for _, id in ipairs(ALWAYS_PRELOAD) do add(id) end
    
    -- 2) All SoundConfig.SoundIDs (rewards/ui/mining/etc.) – recurse
    if SoundConfig and SoundConfig.SoundIDs then
        walk(SoundConfig.SoundIDs)
    end
    
    -- 3) Theme-provided IDs
    local themeIds = SoundTheme.GetAllIds()
    for _, id in ipairs(themeIds) do add(id) end
    
    return ids
end

local function preload(ids: {string}?): ()
    if _busy then
        _dirty = true
        warn("[SoundPreloader] Preload already running; will retry after completion.")
        return
    end
    _busy = true
    
    ids = ids or gatherIds()  -- Use the gathered set by default
    
    if #ids == 0 then
        print("[SoundPreloader] No sounds to preload")
        _busy = false
        return
    end
    
    -- Create temporary Sound instances for preloading
    local sounds = {}
    for _, id in ipairs(ids) do
        local s = Instance.new("Sound")
        s.SoundId = id
        s.Parent = SoundService
        table.insert(sounds, s)
    end
    
    -- Deduplicate and validate instances before preload
    local seen, filtered = {}, {}
    for _, s in ipairs(sounds) do
        if typeof(s) == "Instance" and s.Parent and not seen[s] then
            seen[s] = true
            table.insert(filtered, s)
        end
    end
    
    if #filtered == 0 then
        print("[SoundPreloader] No valid sounds to preload after filtering")
        _busy = false
        -- Clean up even if nothing to preload
        for _, s in ipairs(sounds) do 
            s:Destroy() 
        end
        return
    end
    
    print(string.format("[SoundPreloader] Preloading %d sound assets...", #filtered))
    
    -- Preload with timeout protection (use longer timeout for sound batches)
    local timeoutSec = LoadCfg.TIMEOUTS.AssetPreload * 2  -- Double timeout for sounds
    local ok, err = Timeout.run(function()
        ContentProvider:PreloadAsync(filtered, function(assetId, status)
            if status == Enum.AssetFetchStatus.Failure then
                warn("[SoundPreloader] Failed to preload:", assetId)
            end
        end)
    end, timeoutSec, LoadCfg.POLL_INTERVALS.Coarse)  -- Use coarse polling for non-critical
    
    if not ok then
        if err == "TIMEOUT" then
            warn(string.format("[SoundPreloader] Preload timed out after %.1fs for %d sounds", timeoutSec, #filtered))
        else
            warn("[SoundPreloader] PreloadAsync error:", err)
        end
    else
        print("[SoundPreloader] Preloading complete!")
    end
    
    -- Clean up ALL temporary sounds (not just filtered)
    for _, s in ipairs(sounds) do 
        s:Destroy() 
    end
    
    _busy = false
    
    -- Check if another preload was requested during this run
    if _dirty then
        _dirty = false
        preload()  -- Use default gatherIds()
    end
end

-- Preload initial pack
preload()  -- Use default gatherIds()

-- Preload new pack when theme changes
SoundTheme.Changed():Connect(function()
    print("[SoundPreloader] Sound pack changed, preloading new assets...")
    preload()  -- Use default gatherIds()
end)
