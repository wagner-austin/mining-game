--!strict
-- SoundPreloader.client.lua
-- Preloads audio assets for better UX (prevents first-play hitches)

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local SoundConfig = require(MiningGame:WaitForChild("SoundConfig"))

-- Collect all unique sound IDs from SoundConfig
local soundIds = {}
local seen = {}

local function addSound(id: string?)
    if id and id ~= "" and id ~= "rbxassetid://0" and not seen[id] then
        seen[id] = true
        table.insert(soundIds, id)
    end
end

local function safe_pairs(t)
    return pairs(t or {})
end

-- Mining sounds
for materialKey, events in safe_pairs(SoundConfig.SoundIDs.mining) do
    for eventName, soundId in safe_pairs(events) do
        addSound(soundId)
    end
end

-- Movement sounds
for key, soundId in safe_pairs(SoundConfig.SoundIDs.movement and SoundConfig.SoundIDs.movement.footstep) do
    addSound(soundId)
end
addSound(SoundConfig.SoundIDs.movement and SoundConfig.SoundIDs.movement.jump)
addSound(SoundConfig.SoundIDs.movement and SoundConfig.SoundIDs.movement.doublejump)
addSound(SoundConfig.SoundIDs.movement and SoundConfig.SoundIDs.movement.land)
addSound(SoundConfig.SoundIDs.movement and SoundConfig.SoundIDs.movement.landhard)

-- UI / Ambient / Music / Pets / Rewards / Environment
for key, soundId in safe_pairs(SoundConfig.SoundIDs.ui) do addSound(soundId) end
for key, soundId in safe_pairs(SoundConfig.SoundIDs.ambient) do addSound(soundId) end
for key, soundId in safe_pairs(SoundConfig.SoundIDs.music) do addSound(soundId) end
for key, soundId in safe_pairs(SoundConfig.SoundIDs.pets) do addSound(soundId) end
for key, soundId in safe_pairs(SoundConfig.SoundIDs.rewards) do addSound(soundId) end
for key, soundId in safe_pairs(SoundConfig.SoundIDs.environment) do addSound(soundId) end

print("[SoundPreloader] Preloading", #soundIds, "unique sound assets...")

-- Convert to Instance array for PreloadAsync
local soundInstances = {}
for _, id in ipairs(soundIds) do
    local sound = Instance.new("Sound")
    sound.SoundId = id
    sound.Parent = SoundService  -- ✅ Parent to SoundService (helps some Studio versions)
    table.insert(soundInstances, sound)
end

-- Preload all sounds asynchronously
if #soundInstances > 0 then
    ContentProvider:PreloadAsync(soundInstances, function(assetId, status)
        if status == Enum.AssetFetchStatus.Success then
            -- Successfully preloaded
        elseif status == Enum.AssetFetchStatus.Failed then
            warn("[SoundPreloader] Failed to preload:", assetId)
        end
    end)
    
    print("[SoundPreloader] Preloading complete!")
else
    print("[SoundPreloader] No sounds to preload")
end

-- Clean up temporary sound instances
for _, sound in ipairs(soundInstances) do
    sound:Destroy()
end