--!strict
-- SoundReplication.client.lua
-- Handles replicated sounds from server for multiplayer

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local SoundManager = require(MiningGame:WaitForChild("SoundManager"))
local EventBus = require(MiningGame:WaitForChild("EventBus"))
local EventNames = require(MiningGame:WaitForChild("EventNames"))
local Time = require(MiningGame:WaitForChild("Time"))
local Bus = EventBus.global()
local Logger = require(MiningGame:WaitForChild("Logger"))
local log = Logger.new("SoundReplication")

-- Mark SOUND_PLAY as fast-path for high-frequency audio events
Bus:markFastPath(EventNames.SOUND_PLAY)

-- Store connections for cleanup
local connections: {{ Disconnect: () -> () }} = {}

-- Use Time.mono() for interval timing
local function now(): number return Time.mono() end

local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")
local Camera = workspace.CurrentCamera

-- Update references when character respawns
LocalPlayer.CharacterAdded:Connect(function(newCharacter)
    Character = newCharacter
    HumanoidRootPart = newCharacter:WaitForChild("HumanoidRootPart")
end)

-- Get listener position (camera preferred, fallback to HRP)
local function getListenerPosition(): Vector3?
    if Camera then return Camera.CFrame.Position end
    if HumanoidRootPart then return HumanoidRootPart.Position end
    return nil
end

-- Maximum distance to play sounds (studs) - per category
local MAX_SOUND_DISTANCE = 150
local CATEGORY_MAX_DISTANCE = {
    mining = 120,
    movement = 60,
    rewards = 80,
    pets = 80,
    environment = 150,
    ambient = 200,
    ui = math.huge,
    music = math.huge,
}

-- Spam prevention
local lastPlayTime = {} :: {[string]: number}
local function shouldPlay(category: string, window: number): boolean
    local t = now()
    local lastTime = lastPlayTime[category]
    if not lastTime or (t - lastTime) > window then
        lastPlayTime[category] = t
        return true
    end
    return false
end

-- Handle sound play events via EventBus (replaces both OnSoundEffect and PlaySound)
local offSound = Bus:on(EventNames.SOUND_PLAY, function(data)
    -- Handle simplified sound.play payload
    if data.soundId then
        -- Direct sound ID play (replaces PlaySound)
        SoundManager.PlayId(data.soundId, {
            volume = data.volume or 0.6,
            position = data.position,
        })
        return
    end
    
    -- Handle category-based sounds (replaces OnSoundEffect)
    -- Skip if this was our own action to prevent double playback
    if data.originUserId and data.originUserId == LocalPlayer.UserId then
        return
    end
    
    local category = string.lower(data.category or "")
    
    -- Check distance if position provided
    if data.position then
        local ear = getListenerPosition()
        if ear then
            local maxDist = CATEGORY_MAX_DISTANCE[category] or MAX_SOUND_DISTANCE
            if (data.position - ear).Magnitude > maxDist then
                return -- Too far away
            end
        end
    end
    
    -- Route to appropriate sound manager function with spam prevention
    if category == "mining" and data.materialKey then
        if shouldPlay("mining", 0.05) then -- Max 20 per second
            SoundManager.PlayMining(
                data.materialKey,
                data.subtype,
                data.position,
                {volume = data.volume, pitch = data.pitch}
            )
        end
    elseif category == "movement" and data.materialKey then
        if shouldPlay("movement", 0.1) then -- Max 10 per second
            SoundManager.PlayFootstep(
                data.materialKey,
                data.position,
                {volume = data.volume, pitch = data.pitch}
            )
        end
    elseif category == "ui" and data.soundType then
        SoundManager.PlayUI(data.soundType, {volume = data.volume})
    elseif category == "rewards" and data.soundType then
        SoundManager.PlayReward(data.soundType, {volume = data.volume})
    elseif category == "pets" and data.soundType then
        if shouldPlay("pets", 0.2) then -- Max 5 per second
            SoundManager.PlayPet(data.soundType, data.position, {volume = data.volume, pitch = data.pitch})
        end
    elseif category == "environment" and data.soundType then
        -- One-shots like thunder don't need spam prevention
        SoundManager.PlayEnvironment(data.soundType, data.position, {volume = data.volume, pitch = data.pitch})
    elseif category == "ambient" and data.soundType then
        -- Ambient should be client-driven, but handle if server sends
        SoundManager.PlayAmbient(data.soundType, {position = data.position, volume = data.volume})
    elseif category == "music" and data.soundType then
        -- Music changes are rare, no spam prevention needed
        SoundManager.PlayMusic(data.soundType)
    end
end)
table.insert(connections, { Disconnect = offSound })

-- Batch collection events to prevent duplicate toasts
local collectionBatch = {} :: {[string]: {count: number, rarity: string, timestamp: number}}
local BATCH_WINDOW = 0.08  -- 80ms - faster batching
local recentShown = {} :: {[string]: number}
local DEDUPE_WINDOW = 0.8  -- suppress repeats for ~0.8s
local RARE_PLUS = { EPIC = true, LEGENDARY = true, MYTHIC = true }

local function flushCollectionBatch()
    local UIManager = _G.UIManager
    if not UIManager or not UIManager.showNotificationWithRarity then return end

    local t = now()
    local nextDelay: number? = nil

    for itemId, data in pairs(collectionBatch) do
        local age = t - data.timestamp
        if age >= BATCH_WINDOW then
            local key = string.format("%s|%s", itemId, data.rarity or "?")
            if not recentShown[key] or (t - recentShown[key] >= DEDUPE_WINDOW) then
                -- Format item name (capitalize, replace underscores)
                local itemName = itemId:gsub("_", " "):gsub("(%a)([%w_']*)", function(f, r) 
                    return f:upper()..r:lower() 
                end)
                UIManager:showNotificationWithRarity(
                    string.format("Found %s x%d", itemName, data.count),
                    data.rarity
                )
                recentShown[key] = t
            end
            collectionBatch[itemId] = nil
        else
            local remaining = BATCH_WINDOW - age
            nextDelay = nextDelay and math.min(nextDelay, remaining) or remaining
        end
    end

    if nextDelay then
        task.delay(nextDelay + 0.01, flushCollectionBatch)
    end
end

-- Handle item collected feedback via EventBus
local offItemCollected = Bus:on(EventNames.ITEM_COLLECTED, function(data)
    -- Visual/UI feedback for item collection
    log:debug("Collected %s x%d [%s]", tostring(data.itemId), tonumber(data.count) or 0, tostring(data.rarity or ""))
    
    -- Skip EPIC+ items - they'll get announcement banners instead
    local rarityUpper = (data.rarity or ""):upper()
    if RARE_PLUS[rarityUpper] then
        -- Announcement/banners will cover EPIC+, so don't generate a second toast here.
        return
    end
    
    local t = now()
    local id = data.itemId

    local batch = collectionBatch[id]
    if batch and (t - batch.timestamp) < BATCH_WINDOW then
        batch.count = batch.count + data.count
        batch.timestamp = t
    else
        collectionBatch[id] = { count = data.count, rarity = data.rarity, timestamp = t }
    end

    -- Always (re)schedule a flush; the flusher will delay if needed
    task.delay(BATCH_WINDOW, flushCollectionBatch)
end)
table.insert(connections, { Disconnect = offItemCollected })

-- Cleanup on script destroy
script.Destroying:Connect(function()
    for _, c in ipairs(connections) do
        if c and c.Disconnect then c.Disconnect() end
    end
end)

log:info("Client sound replication initialized")
