--!strict
--[[
    SoundBroadcast.lua
    Server-side sound broadcasting with spatial audio support.
    
    Features:
    - Position-based sound broadcasting
    - Rate limiting to prevent spam
    - Payload validation and sanitization
    - Material-aware sound selection
    - Configurable broadcast radius
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local MaterialKeys = require(MiningGame:WaitForChild("MaterialKeys"))
local Logger = require(MiningGame:WaitForChild("Logger"))
local GameConfig = require(MiningGame:WaitForChild("GameConfig"))
local Time = require(MiningGame:WaitForChild("Time"))
local log = Logger.new("SoundBroadcast")
local EventBus = require(MiningGame:WaitForChild("EventBus"))
local EventNames = require(MiningGame:WaitForChild("EventNames"))
local Bus = EventBus.global()

local SoundBroadcast = {}

-- Default broadcast radius
local DEFAULT_RADIUS = GameConfig.Sound and GameConfig.Sound.DEFAULT_RADIUS or 150

-- Get SoundConfig for configured sound IDs
local SoundConfig = require(MiningGame:WaitForChild("SoundConfig"))

-- Valid categories
local VALID_CATEGORIES = {
    mining = true,
    movement = true,
    rewards = true,
    ui = true,
    pets = true,
    environment = true,
    ambient = true,
    music = true,
}

-- Rate limiting
local rateLimit = {} :: {[string]: number}
local function checkRateLimit(userId: number, key: string, window: number): boolean
    local now = Time.mono()
    local k = string.format("%d:%s", userId, key)
    local last = rateLimit[k]
    if not last or (now - last) > window then
        rateLimit[k] = now
        return true
    end
    return false
end

-- Validate and sanitize payload
local function sanitizePayload(payload: {[string]: any}): {[string]: any}
    local data = table.clone(payload)
    
    -- Sanitize category
    data.category = string.lower(tostring(data.category or ""))
    if not VALID_CATEGORIES[data.category] then
        log:warn("Invalid category: %s", data.category)
        data.category = "rewards" -- Safe default
    end
    
    -- Sanitize material key if present
    if data.materialKey then
        data.materialKey = string.lower(tostring(data.materialKey))
        -- Validate against known materials
        local validMaterial = false
        for _, key in ipairs(MaterialKeys.TerrainKeys) do
            if key == data.materialKey then
                validMaterial = true
                break
            end
        end
        if not validMaterial then
            log:warn("Invalid material key: %s", data.materialKey)
            data.materialKey = "rock" -- Safe default
        end
    end
    
    -- Ensure numeric values are in valid ranges
    if data.volume then
        data.volume = math.clamp(tonumber(data.volume) or 1, 0, 2)
    end
    if data.pitch then
        data.pitch = math.clamp(tonumber(data.pitch) or 1, 0.5, 2)
    end
    
    return data
end

--[[
    Broadcast a sound event to all players within radius of a position.
    Handles validation, rate limiting, and spatial distribution.
    
    @param originPlayer: Player? - The player originating the sound (for rate limiting)
    @param position: Vector3? - The world position of the sound
    @param payload: table - Sound data including category, type, material, etc.
    @param radius: number? - Broadcast radius (default: 150 studs)
]]
function SoundBroadcast.BroadcastNear(
    originPlayer: Player?,
    position: Vector3?,
    payload: {
        category: string,
        soundType: string?,
        materialKey: string?,
        subtype: string?,
        volume: number?,
        pitch: number?,
    },
    radius: number?
)
    local r = radius or DEFAULT_RADIUS
    
    -- Sanitize and prepare data
    local data = sanitizePayload(payload)
    data.position = position
    if originPlayer then
        data.originUserId = originPlayer.UserId
    end
    
    -- Broadcast to all players within range
    for _, player in ipairs(Players:GetPlayers()) do
        -- Skip if no character
        local character = player.Character
        if not character then continue end
        
        local hrp = character:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end
        
        -- Check distance if position provided
        if position then
            local distance = (hrp.Position - position).Magnitude
            if distance > r then
                continue -- Too far away
            end
        end
        
        -- Send to client
        Bus:emit(EventNames.SOUND_PLAY, {
            to = { kind = "player", player = player },
            payload = data
        })
    end
end

-- Broadcast to specific player only
function SoundBroadcast.BroadcastToPlayer(
    player: Player,
    payload: {
        category: string,
        soundType: string?,
        materialKey: string?,
        subtype: string?,
        volume: number?,
        pitch: number?,
        position: Vector3?,
    }
)
    local data = sanitizePayload(payload)
    Bus:emit(EventNames.SOUND_PLAY, {
        to = { kind = "player", player = player },
        payload = data
    })
end

-- Broadcast to all players
function SoundBroadcast.BroadcastToAll(
    payload: {
        category: string,
        soundType: string?,
        materialKey: string?,
        subtype: string?,
        volume: number?,
        pitch: number?,
        position: Vector3?,
    },
    originPlayer: Player?
)
    local data = sanitizePayload(payload)
    if originPlayer then
        data.originUserId = originPlayer.UserId
    end
    Bus:emit(EventNames.SOUND_PLAY, {
        to = { kind = "all" },
        payload = data
    })
end

-- Utility functions for common sound types

-- Removed legacy 3D mining broadcast in favor of MiningLocal (2D-on-recipients)

-- Mining sound that is culled by distance but plays as local (2D) on recipients
function SoundBroadcast.MiningLocal(
    player: Player,
    position: Vector3,
    materialKey: string,
    subtype: string
)
    -- Rate limit: ~33 hits per second max
    if not checkRateLimit(player.UserId, "mining", 0.03) then return end

    local r = 40
    local payloadBase = sanitizePayload({
        category = "mining",
        materialKey = materialKey,
        subtype = subtype,
    })
    if player then payloadBase.originUserId = player.UserId end

    -- Send to nearby players; include position so clients play spatial (3D) audio at dig location
    for _, plr in ipairs(Players:GetPlayers()) do
        local character = plr.Character
        if not character then continue end
        local hrp = character:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end
        if position and (hrp.Position - position).Magnitude > r then continue end

        local payload = table.clone(payloadBase)
        payload.position = position
        Bus:emit(EventNames.SOUND_PLAY, {
            to = { kind = "player", player = plr },
            payload = payload
        })
    end
end

function SoundBroadcast.Footstep(
    player: Player,
    position: Vector3,
    materialKey: string
)
    -- Rate limit: ~12 footsteps per second max
    if not checkRateLimit(player.UserId, "movement", 0.08) then return end
    
    SoundBroadcast.BroadcastNear(player, position, {
        category = "movement",
        materialKey = materialKey,
    }, 60)
end

function SoundBroadcast.Reward(
    player: Player,
    rewardType: string
)
    -- Rate limit: prevent reward spam
    if not checkRateLimit(player.UserId, "rewards", 0.1) then return end
    
    SoundBroadcast.BroadcastToPlayer(player, {
        category = "rewards",
        soundType = rewardType,
    })
end

function SoundBroadcast.UI(
    player: Player,
    soundType: string
)
    -- UI sounds are typically local, but if server needs to send them:
    -- Rate limit to prevent UI spam
    if not checkRateLimit(player.UserId, "ui", 0.05) then return end
    
    SoundBroadcast.BroadcastToPlayer(player, {
        category = "ui",
        soundType = soundType,
    })
end

function SoundBroadcast.Environment(
    position: Vector3,
    soundType: string,
    radius: number?
)
    SoundBroadcast.BroadcastNear(nil, position, {
        category = "environment",
        soundType = soundType,
    }, radius or 150)
end

function SoundBroadcast.Collect(
    player: Player,
    position: Vector3,
    rarity: string
)
    -- Rate limit: prevent collection spam
    if not checkRateLimit(player.UserId, "collect", 0.05) then return end
    
    -- Map rarity to sound type (case-insensitive)
    local rarityKey = string.upper(tostring(rarity or ""))
    local rarityMap = {
        RARE = "rare",
        EPIC = "epic",
        LEGENDARY = "legendary",
        MYTHIC = "legendary",  -- Use legendary sound for mythic (or add mythic to SoundConfig)
    }
    local soundType = rarityMap[rarityKey] or "item"
    
    -- Get configured sound ID
    local soundId = SoundConfig.SoundIDs.rewards[soundType] or SoundConfig.SoundIDs.rewards.item
    local pickupVolume = (GameConfig.Sound and tonumber(GameConfig.Sound.PICKUP_VOLUME)) or 0.3
    pickupVolume = math.clamp(pickupVolume, 0, 1)
    
    -- Use EventBus for sound playback
    Bus:emit(EventNames.SOUND_PLAY, {
        to = { kind = "player", player = player },
        payload = {
            soundId = soundId,
            -- Tunable pickup/collect volume
            volume = pickupVolume,
            position = position,
            category = "collect",
            rarity = rarity,
        }
    })
end

return SoundBroadcast
