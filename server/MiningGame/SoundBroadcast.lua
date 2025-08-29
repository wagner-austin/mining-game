--!strict
-- SoundBroadcast.lua
-- Server-side sound broadcasting utilities with rate limiting and validation

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local MaterialKeys = require(MiningGame:WaitForChild("MaterialKeys"))
local ServerMiningGame = ServerScriptService:WaitForChild("MiningGame")
local Remotes = require(ServerMiningGame:WaitForChild("Remotes"))

local SoundBroadcast = {}

-- Default broadcast radius
local DEFAULT_RADIUS = 150

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
    local now = tick()
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
        warn("[SoundBroadcast] Invalid category:", data.category)
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
            warn("[SoundBroadcast] Invalid material key:", data.materialKey)
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

-- Broadcast to all players within radius of a position
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
        Remotes.RE.OnSoundEffect:FireClient(player, data)
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
    Remotes.RE.OnSoundEffect:FireClient(player, data)
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
    Remotes.RE.OnSoundEffect:FireAllClients(data)
end

-- Utility functions for common sound types

function SoundBroadcast.Mining(
    player: Player,
    position: Vector3,
    materialKey: string,
    subtype: string
)
    -- Rate limit: ~33 hits per second max
    if not checkRateLimit(player.UserId, "mining", 0.03) then return end
    
    SoundBroadcast.BroadcastNear(player, position, {
        category = "mining",
        materialKey = materialKey,
        subtype = subtype,
    }, 120)
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

return SoundBroadcast