--!strict
-- SoundReplication.client.lua
-- Handles replicated sounds from server for multiplayer

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local SoundManager = require(MiningGame:WaitForChild("SoundManager"))
local Remotes = require(MiningGame:WaitForChild("Remotes"))

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
    local now = tick()
    local lastTime = lastPlayTime[category]
    if not lastTime or (now - lastTime) > window then
        lastPlayTime[category] = now
        return true
    end
    return false
end

-- Handle sound effects from server
Remotes.RE.OnSoundEffect.OnClientEvent:Connect(function(data: {
    category: string,
    soundType: string?,
    position: Vector3?,
    volume: number?,
    pitch: number?,
    materialKey: string?,
    subtype: string?,
    originUserId: number?,
})
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
    else
        warn(("[SoundReplication] Unhandled category: %s, soundType=%s"):format(
            tostring(data.category), 
            tostring(data.soundType)
        ))
    end
end)

-- Handle collection sounds (backward compatible with ItemService)
Remotes.RE.PlaySound.OnClientEvent:Connect(function(data: {
    soundId: string,
    volume: number?,
    position: Vector3?,
    category: string?,
    rarity: string?
})
    -- Play collection sound directly
    if data.soundId then
        SoundManager.PlayId(data.soundId, {
            Volume = data.volume or 0.6,
            Position = data.position,
        })
    end
end)

-- Handle item collected feedback
Remotes.RE.OnItemCollected.OnClientEvent:Connect(function(data: {
    itemId: string,
    count: number,
    rarity: string
})
    -- Visual/UI feedback for item collection could go here
    print(string.format("Collected %s x%d [%s]", data.itemId, data.count, data.rarity))
end)

print("[SoundReplication] Client sound replication initialized")