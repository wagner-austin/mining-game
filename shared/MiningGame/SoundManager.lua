--!strict
-- SoundManager.lua
-- Sound management with pooling, 3D emitters, and proper cleanup

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local SoundConfig = require(MiningGame:WaitForChild("SoundConfig"))
local SoundTheme = require(MiningGame:WaitForChild("SoundThemeManager"))
local MaterialDefinitions = require(MiningGame:WaitForChild("MaterialDefinitions"))
local Logger = require(MiningGame:WaitForChild("Logger"))
local MathUtils = require(MiningGame:WaitForChild("MathUtils"))

local log = Logger.new(Logger.CAT.Sound)

type PlayOpts = {
    position: Vector3?,
    parent: Instance?,
    category: string?,
    subtype: string?,
    volume: number?,
    pitch: number?,
}

local SoundManager = {}

-- Category to group mapping (using PascalCase to match SoundConfig.Properties)
local GROUP_FOR_CATEGORY = {
    UI = "UI",
    Mining = "SFX",
    Movement = "SFX",
    Ambient = "Ambient",
    Music = "Music",
    Pets = "SFX",
    Rewards = "SFX",
    Environment = "SFX",
}

-- Helper to convert to TitleCase
local function TitleCase(s: string): string
    return (s:sub(1,1):upper() .. s:sub(2):lower())
end

-- === SoundGroups / mixer ===
local groups: {[string]: SoundGroup} = {}
local masterVolume = 1.0
local baseGroupVolume: {[string]: number} = {
    SFX = 1.0,
    UI = 1.0,
    Ambient = 1.0,
    Music = 1.0,
}

local function ensureGroup(name: string): SoundGroup
    local g = groups[name]
    if g then return g end
    
    g = Instance.new("SoundGroup")
    g.Name = name
    g.Parent = SoundService
    groups[name] = g
    return g
end

local function applyGroupVolumes()
    for name, g in pairs(groups) do
        g.Volume = math.clamp((baseGroupVolume[name] or 1) * masterVolume, 0, 1)
    end
end

-- Initialize groups
ensureGroup("SFX")
ensureGroup("UI")
ensureGroup("Ambient")
ensureGroup("Music")

-- === Sound emitters folder ===
local EMITTERS = workspace:FindFirstChild("_SoundEmitters")
if not EMITTERS then
    EMITTERS = Instance.new("Folder")
    EMITTERS.Name = "_SoundEmitters"
    EMITTERS.Parent = workspace
end

-- === Pooling ===
local pool: {[string]: {free: {Sound}, busy: {Sound}}} = {}

local function keyFor(soundId: string, groupName: string): string
    return (soundId or "nil") .. "@" .. groupName
end

local function getSound(soundId: string, groupName: string): Sound
    local k = keyFor(soundId, groupName)
    pool[k] = pool[k] or {free = {}, busy = {}}
    local bucket = pool[k]

    local s: Sound
    if #bucket.free > 0 then
        s = table.remove(bucket.free)
    else
        s = Instance.new("Sound")
        s.SoundId = soundId
        s.SoundGroup = ensureGroup(groupName)
        s.RollOffMode = Enum.RollOffMode.Linear
        s.Archivable = false
    end
    table.insert(bucket.busy, s)
    return s
end

local function releaseSound(s: Sound)
    if not s or not s.Parent then return end
    local groupName = s.SoundGroup and s.SoundGroup.Name or "SFX"
    local k = keyFor(s.SoundId, groupName)
    local bucket = pool[k]
    if not bucket then return end
    
    -- Remove from busy
    for i, b in ipairs(bucket.busy) do
        if b == s then
            table.remove(bucket.busy, i)
            break
        end
    end
    
    -- Reset common props
    s.PlaybackSpeed = 1
    s.Volume = 0.5
    s.TimePosition = 0
    s.Looped = false
    
    -- Park sound instance for reuse
    s.Parent = SoundService
    table.insert(bucket.free, s)
end

-- === Utilities ===
local function applyCategoryDefaults(s: Sound, category: string)
    local props = SoundConfig.GetCategoryProperties(category)
    if props then
        if props.Volume ~= nil then s.Volume = props.Volume end
        if props.Looped ~= nil then s.Looped = props.Looped end
        if props.RollOffMode ~= nil then s.RollOffMode = props.RollOffMode end
        if props.RollOffMaxDistance ~= nil then s.RollOffMaxDistance = props.RollOffMaxDistance end
        if props.RollOffMinDistance ~= nil then s.RollOffMinDistance = props.RollOffMinDistance end
        if props.EmitterSize ~= nil then s.EmitterSize = props.EmitterSize end
    end
end

local function attach3D(opts: PlayOpts): Instance
    if opts.parent then return opts.parent end
    if not opts.position then return SoundService end
    
    -- Create a tiny invisible part as the 3D emitter
    local p = Instance.new("Part")
    p.Name = "SoundEmitter"
    p.Anchored = true
    p.CanCollide = false
    p.CanQuery = false
    p.CanTouch = false
    p.Transparency = 1
    p.Size = Vector3.new(0.2, 0.2, 0.2)
    p.CFrame = CFrame.new(opts.position)
    p.Parent = EMITTERS
    
    local a = Instance.new("Attachment")
    a.Parent = p
    return a
end

local function safeId(id: string?): string?
    local isValid = id and SoundConfig.ValidateSoundID(id)
    if not isValid then
        log:warn("Sound ID validation failed for: %s", tostring(id))
    end
    return isValid and id or nil
end

-- === Public API ===
function SoundManager.PlayUI(name: string, opts: PlayOpts?)
    local id = SoundTheme.GetId({"ui", name})
    if not safeId(id) then return end
    
    opts = opts or {}
    opts.category = "UI"
    return SoundManager.PlayId(id, opts)
end

function SoundManager.PlayMining(materialKey: string, subtype: string?, position: Vector3?, opts: PlayOpts?)
    local k = string.lower(materialKey or "rock")
    log:debug("PlayMining called - material: %s, subtype: %s", tostring(k), subtype or "hit")
    
    local id = SoundTheme.GetId({"mining", k, subtype or "hit"}) or SoundTheme.GetId({"mining", k, "hit"})
    log:debug("Sound ID for %s: %s", tostring(k), tostring(id))
    
    if not safeId(id) then 
        warn("[SoundManager] Invalid or missing sound ID:", id)
        return 
    end
    
    opts = opts or {}
    opts.category = "Mining"
    opts.subtype = subtype
    opts.position = position
    log:debug("Playing mining sound at position: (%.0f,%.0f,%.0f)", position.X, position.Y, position.Z)
    return SoundManager.PlayId(id, opts)
end

function SoundManager.PlayFootstep(materialKey: string, position: Vector3?, opts: PlayOpts?)
    local mk = string.lower(materialKey or "rock")
    local def = MaterialDefinitions.Materials[mk]
    local footstepType = (def and def.properties and def.properties.soundCategory) or "rock"
    local id = SoundTheme.GetId({"movement","footstep", footstepType}) or SoundTheme.GetId({"movement","footstep","rock"})
    if not safeId(id) then return end
    
    opts = opts or {}
    opts.category = "Movement"
    opts.position = position
    return SoundManager.PlayId(id, opts)
end

function SoundManager.PlayReward(rewardType: string, opts: PlayOpts?)
    local id = SoundTheme.GetId({"rewards", rewardType})
    if not safeId(id) then return end
    
    opts = opts or {}
    opts.category = "Rewards"
    return SoundManager.PlayId(id, opts)
end

function SoundManager.PlayPet(action: string, position: Vector3?, opts: PlayOpts?)
    local id = SoundTheme.GetId({"pets", action})
    if not safeId(id) then return end
    
    opts = opts or {}
    opts.category = "Pets"
    opts.position = position
    return SoundManager.PlayId(id, opts)
end

function SoundManager.PlayEnvironment(soundType: string, position: Vector3?, opts: PlayOpts?)
    local id = SoundTheme.GetId({"environment", soundType})
    if not safeId(id) then return end
    
    opts = opts or {}
    opts.category = "Environment"
    opts.position = position
    return SoundManager.PlayId(id, opts)
end

function SoundManager.PlayId(id: string, opts: PlayOpts?)
    log:debug("PlayId called with ID: %s", tostring(id))
    opts = opts or {}
    local catTitle = TitleCase(opts.category or "SFX")
    local groupName = GROUP_FOR_CATEGORY[catTitle] or "SFX"

    local parent = attach3D(opts)
    log:debug("Parent for sound: %s", parent:GetFullName())
    
    local s = getSound(id, groupName)
    s.Parent = parent
    applyCategoryDefaults(s, catTitle)
    
    if opts.volume then s.Volume = opts.volume end
    if opts.pitch then s.PlaybackSpeed = opts.pitch end

    -- Log detailed sound properties (only in debug mode)
    log:debug("Playing sound - ID: %s, Vol: %.2f, Parent: %s", 
        s.SoundId, s.Volume, s.Parent:GetFullName())
    log:debug("  RollOff: %s, MinDist: %d, MaxDist: %d",
        tostring(s.RollOffMode), s.RollOffMinDistance, s.RollOffMaxDistance)
    
    -- If 3D positioned, calculate distance to player
    if opts.position then
        local Players = game:GetService("Players")
        local LocalPlayer = Players.LocalPlayer
        if LocalPlayer and LocalPlayer.Character then
            local hrp = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local distance = (hrp.Position - opts.position).Magnitude
                log:debug("  3D sound - Distance: %d studs, Pos: (%.0f,%.0f,%.0f)",
                    math.floor(distance), opts.position.X, opts.position.Y, opts.position.Z)
                
                -- Calculate approximate volume at player position
                if s.RollOffMode == Enum.RollOffMode.Linear then
                    local minDist = s.RollOffMinDistance
                    local maxDist = s.RollOffMaxDistance
                    local effectiveVolume = s.Volume
                    if distance > minDist then
                        local falloff = MathUtils.nonNegative(1 - (distance - minDist) / (maxDist - minDist))
                        effectiveVolume = s.Volume * falloff
                    end
                    local audible = effectiveVolume > 0.01
                    log:debug("  Effective vol: %.3f (%s)", effectiveVolume, audible and "audible" or "too far")
                end
            end
        end
    else
        log:debug("  2D sound (plays everywhere)")
    end
    
    -- For looped sounds (e.g., ambient beds), apply a micro fade-in to avoid pops
    local targetVolume = s.Volume
    local doMicroFadeIn = s.Looped == true

    if doMicroFadeIn then
        s.Volume = 0
    end

    s:Play()
    log:debug("Sound IsPlaying: %s", tostring(s.IsPlaying))

    if doMicroFadeIn then
        -- Very short ramp (≈80ms) to target volume to avoid DC pops on start
        task.spawn(function()
            local fadeTime = 0.08
            local steps = math.max(3, math.floor(fadeTime * 30)) -- 30 FPS
            for i = 1, steps do
                local t = i / steps
                s.Volume = targetVolume * t
                RunService.Heartbeat:Wait()
            end
            s.Volume = targetVolume
        end)
    end

    -- Cleanup (looped sounds should be managed by caller)
    if not s.Looped then
        local ttl = math.max(0.1, (s.TimeLength > 0 and s.TimeLength or 1.0) + 0.25)
        
        -- Clean up emitter part if we created one
        if parent:IsA("Attachment") and parent.Parent and parent.Parent:IsA("BasePart") then
            Debris:AddItem(parent.Parent, ttl + 0.1)
        end
        
        -- Return sound to pool after it finishes
        task.delay(ttl, function()
            if s.IsPlaying then 
                s.Ended:Wait() 
            end
            releaseSound(s)
        end)
    end
    
    return s
end

-- === Volume controls ===
function SoundManager.SetGroupVolume(groupName: string, volume: number)
    ensureGroup(groupName)
    baseGroupVolume[groupName] = math.clamp(volume, 0, 1)
    applyGroupVolumes()
end

function SoundManager.SetMasterVolume(volume: number)
    masterVolume = math.clamp(volume, 0, 1)
    applyGroupVolumes()
end

function SoundManager.GetMasterVolume(): number
    return masterVolume
end

function SoundManager.GetGroupVolume(groupName: string): number
    return baseGroupVolume[groupName] or 1.0
end

-- === Music system with crossfade ===
local currentMusic: Sound? = nil
local musicFading = false
local lastMusicName: string? = nil
local pendingThemeMusicRestart = false

function SoundManager.PlayMusic(name: string, opts: PlayOpts?)
    local id = SoundTheme.GetId({"music", name})
    if not safeId(id) then return end
    
    -- Track the logical name for theme changes
    lastMusicName = name
    
    -- If the requested track is already playing, gently ensure it's at target volume
    if currentMusic and currentMusic.SoundId == id then
        local maxVol = SoundConfig.MusicSettings.MaxVolume or 0.3
        if not currentMusic.IsPlaying then currentMusic:Play() end
        task.spawn(function()
            local steps = 12
            for i = 1, steps do
                local t = i / steps
                currentMusic.Volume = currentMusic.Volume + (maxVol - currentMusic.Volume) * t
                RunService.Heartbeat:Wait()
            end
            currentMusic.Volume = maxVol
        end)
        return currentMusic
    end

    -- Don't interrupt an ongoing fade
    if musicFading then return end
    
    local next = getSound(id, "Music")
    next.Looped = true
    next.Parent = SoundService
    applyCategoryDefaults(next, "Music")
    
    local fadeTime = SoundConfig.MusicSettings.FadeTime or 1.5
    local minVol = SoundConfig.MusicSettings.MinVolume or 0.1
    local maxVol = SoundConfig.MusicSettings.MaxVolume or 0.3
    
    -- Start fully silent to avoid any start click, then ramp
    next.Volume = 0
    next:Play()

    if currentMusic and currentMusic ~= next and SoundConfig.MusicSettings.CrossfadeEnabled then
        musicFading = true
        
        -- Crossfade
        local steps = math.floor(fadeTime * 30) -- 30 FPS
        local oldMusic = currentMusic
        
        task.spawn(function()
            for i = 1, steps do
                local t = i / steps
                if oldMusic then 
                    oldMusic.Volume = MathUtils.nonNegative((1 - t) * maxVol) 
                end
                next.Volume = t * maxVol
                RunService.Heartbeat:Wait()
            end
            
            if oldMusic then 
                oldMusic:Stop()
                releaseSound(oldMusic)
            end
            
            musicFading = false
            
            -- Check if theme changed during crossfade
            if pendingThemeMusicRestart then
                pendingThemeMusicRestart = false
                if lastMusicName then
                    SoundManager.PlayMusic(lastMusicName)
                end
            end
        end)
    else
        -- Instant switch (no previous music): apply a short fade-in to maxVol
        if currentMusic then
            currentMusic:Stop()
            releaseSound(currentMusic)
        end

        task.spawn(function()
            local fadeIn = math.max(0.08, math.min(0.3, fadeTime * 0.25)) -- quick, perceptually smooth
            local steps = math.max(3, math.floor(fadeIn * 30))
            for i = 1, steps do
                local t = i / steps
                next.Volume = minVol + (maxVol - minVol) * t
                RunService.Heartbeat:Wait()
            end
            next.Volume = maxVol
        end)
    end
    
    currentMusic = next
    return next
end

function SoundManager.StopMusic(fadeOut: boolean?)
    if not currentMusic then return end
    
    if fadeOut and not musicFading then
        musicFading = true
        local fadeTime = SoundConfig.MusicSettings.FadeTime or 1.5
        local steps = math.floor(fadeTime * 30)
        local music = currentMusic
        
        task.spawn(function()
            for i = 1, steps do
                local t = i / steps
                music.Volume = MathUtils.nonNegative((1 - t) * (SoundConfig.MusicSettings.MaxVolume or 0.3))
                RunService.Heartbeat:Wait()
            end
            
            music:Stop()
            releaseSound(music)
            musicFading = false
        end)
    else
        currentMusic:Stop()
        releaseSound(currentMusic)
    end
    
    currentMusic = nil
    lastMusicName = nil
end

function SoundManager.GetCurrentMusic(): string?
    if currentMusic then
        -- Extract music name from sound ID if possible
        return currentMusic.SoundId
    end
    return nil
end

-- === Ambient system ===
local ambientSounds: {[string]: Sound} = {}

function SoundManager.PlayAmbient(name: string, opts: PlayOpts?)
    local key = string.lower(name or "")
    local id = SoundTheme.GetId({"ambient", key})
    if not safeId(id) then return end
    
    -- If already playing, update volume if provided
    if ambientSounds[key] then
        local existing = ambientSounds[key]
        if opts and opts.volume and existing then
            existing.Volume = opts.volume
        end
        return existing
    end
    
    -- Check max concurrent
    local maxConcurrent = SoundConfig.AmbientSettings.MaxConcurrent or 3
    local count = 0
    for _ in pairs(ambientSounds) do
        count = count + 1
    end
    
    if count >= maxConcurrent then
        -- Stop oldest ambient
        local oldest = next(ambientSounds)
        if oldest then
            SoundManager.StopAmbient(oldest)
        end
    end
    
    opts = opts or {}
    opts.category = "Ambient"
    local s = SoundManager.PlayId(id, opts)
    
    if s then
        s.Looped = true -- Ensure ambient sounds loop
        ambientSounds[key] = s
    end
    
    return s
end

function SoundManager.StopAmbient(name: string, fadeOut: boolean?)
    local key = string.lower(name or "")
    local s = ambientSounds[key]
    if not s then return end
    
    -- IMMEDIATELY remove from tracking so new ones can start
    ambientSounds[key] = nil
    
    if fadeOut then
        local fadeTime = 0.25 -- Quick fade
        local steps = 15
        local originalVolume = s.Volume
        
        task.spawn(function()
            for i = 1, steps do
                local t = i / steps
                s.Volume = MathUtils.nonNegative((1 - t) * originalVolume)
                RunService.Heartbeat:Wait()
            end
            
            s:Stop()
            releaseSound(s)
        end)
    else
        s:Stop()
        releaseSound(s)
    end
end

function SoundManager.StopAllAmbient()
    local keys = {}
    for k in pairs(ambientSounds) do
        table.insert(keys, k)
    end
    for _, k in ipairs(keys) do
        SoundManager.StopAmbient(k)
    end
end

function SoundManager.GetActiveAmbient(): {string}
    local active = {}
    for k in pairs(ambientSounds) do
        table.insert(active, k)
    end
    return active
end

-- === Initialize default volumes ===
applyGroupVolumes()

-- === React to sound theme changes ===
-- Restart looped sounds (music/ambient) with new theme assets
SoundTheme.Changed():Connect(function()
    -- Restart music with the same logical track name if one was playing
    if lastMusicName and currentMusic then
        if musicFading then
            -- Defer restart until crossfade completes
            pendingThemeMusicRestart = true
            log:debug("Will restart music after crossfade completes")
        else
            log:info("Restarting music with new theme: %s", tostring(lastMusicName))
            SoundManager.PlayMusic(lastMusicName)
        end
    end
    
    -- Restart ambient layers with same keys
    local active = SoundManager.GetActiveAmbient()
    if #active > 0 then
        log:info("Restarting %d ambient sounds with new theme", #active)
        SoundManager.StopAllAmbient()
        for _, k in ipairs(active) do
            SoundManager.PlayAmbient(k)
        end
    end
end)

return SoundManager
