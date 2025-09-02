--!strict
-- AmbientLogging.client.lua
-- Detailed logging for ambient sound system debugging

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Only run in Studio
if not RunService:IsStudio() then
    script:Destroy()
    return
end

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local AmbientController = require(MiningGame:WaitForChild("AmbientController"))
local SoundManager = require(MiningGame:WaitForChild("SoundManager"))
local Logger = require(MiningGame:WaitForChild("Logger"))

local log = Logger.new("AmbientLogging")

-- Wait for initialization
task.wait(3)

log:info("Ambient logging system active - patching modules for detailed logging")

-- Track previous state for change detection
local prevTargets = {}
local prevActive = {}

-- Patch AmbientController to add logging
local originalStart = AmbientController.Start
function AmbientController.Start(...)
    log:info("AmbientController.Start() called")
    
    -- Check if it's actually starting the heartbeat
    task.spawn(function()
        task.wait(0.5)
        log:debug("Checking if AmbientController heartbeat is running...")
        
        -- Monitor for applyTargets calls
        local checkCount = 0
        while checkCount < 5 do
            checkCount = checkCount + 1
            task.wait(0.5)
            -- We'll see if providers are being polled
        end
    end)
    
    return originalStart(...)
end

local originalStop = AmbientController.Stop
function AmbientController.Stop(...)
    log:info("AmbientController.Stop() called")
    return originalStop(...)
end

-- Try to patch RegisterProvider to see what's being registered
local originalRegister = AmbientController.RegisterProvider
if originalRegister then
    function AmbientController.RegisterProvider(provider: any)
        log:info("Registering provider: %s", provider.id or "unknown")
        return originalRegister(provider)
    end
end

-- Patch SoundManager ambient functions
local originalPlayAmbient = SoundManager.PlayAmbient
function SoundManager.PlayAmbient(name: string, opts: any)
    local volume = opts and opts.volume or "default"
    log:debug("PlayAmbient('%s', volume=%.3f)", name, typeof(volume) == "number" and volume or 0)
    
    local result = originalPlayAmbient(name, opts)
    
    if result then
        log:debug("  ✅ Sound created/updated: %s", result.Name or "unknown")
        log:debug("     IsPlaying: %s | Volume: %.3f | Looped: %s", 
            tostring(result.IsPlaying), result.Volume, tostring(result.Looped))
    else
        log:debug("  ❌ Failed to create/update sound!")
    end
    
    return result
end

local originalStopAmbient = SoundManager.StopAmbient
function SoundManager.StopAmbient(name: string, fadeOut: any)
    log:debug("StopAmbient('%s', fadeOut=%s)", name, tostring(fadeOut))
    return originalStopAmbient(name, fadeOut)
end

-- Create a heartbeat logger to track state changes
local logCounter = 0
local lastLogTime = 0
local LOG_INTERVAL = 1.0 -- Log every second

RunService.Heartbeat:Connect(function()
    local now = workspace.DistributedGameTime
    if now - lastLogTime < LOG_INTERVAL then return end
    lastLogTime = now
    logCounter = logCounter + 1
    
    -- Get camera position (ear)
    local cam = workspace.CurrentCamera
    local ear = cam and cam.CFrame.Position
    if not ear then
        log:warn("No camera position available")
        return
    end
    
    -- Check zones manually
    local CollectionService = game:GetService("CollectionService")
    local zonesInRange = {}
    local zonesOutOfRange = {}
    
    for _, part in ipairs(CollectionService:GetTagged("AmbientZone")) do
        if part:IsA("BasePart") then
            local soundKey = part:GetAttribute("SoundKey")
            local radius = part:GetAttribute("Radius") or 40
            local priority = part:GetAttribute("Priority") or 0
            local baseVolume = part:GetAttribute("BaseVolume") or 0.35
            
            local distance = (ear - part.Position).Magnitude
            
            if distance <= radius then
                local falloff = 1 - (distance / radius) * 0.7
                local effectiveVolume = baseVolume * falloff
                
                table.insert(zonesInRange, {
                    key = soundKey,
                    distance = math.floor(distance),
                    radius = radius,
                    volume = effectiveVolume,
                    priority = priority,
                })
            else
                table.insert(zonesOutOfRange, {
                    key = soundKey,
                    distance = math.floor(distance),
                    radius = radius,
                })
            end
        end
    end
    
    -- Sort in-range zones by priority
    table.sort(zonesInRange, function(a, b)
        if a.priority ~= b.priority then return a.priority > b.priority end
        return a.volume > b.volume
    end)
    
    -- Build current targets (top 2)
    local currentTargets = {}
    for i = 1, math.min(2, #zonesInRange) do
        currentTargets[zonesInRange[i].key] = true
    end
    
    -- Check for changes
    local changes = {}
    
    -- Check for new zones entered
    for key, _ in pairs(currentTargets) do
        if not prevTargets[key] then
            table.insert(changes, string.format("➕ ENTERED zone '%s'", key))
        end
    end
    
    -- Check for zones left
    for key, _ in pairs(prevTargets) do
        if not currentTargets[key] then
            table.insert(changes, string.format("➖ LEFT zone '%s'", key))
        end
    end
    
    -- Get currently playing ambient sounds
    local activeAmbients = SoundManager.GetActiveAmbient()
    local currentActive = {}
    for _, key in ipairs(activeAmbients) do
        currentActive[key] = true
    end
    
    -- Check for sound changes
    for key, _ in pairs(currentActive) do
        if not prevActive[key] then
            table.insert(changes, string.format("🔊 STARTED playing '%s'", key))
        end
    end
    
    for key, _ in pairs(prevActive) do
        if not currentActive[key] then
            table.insert(changes, string.format("🔇 STOPPED playing '%s'", key))
        end
    end
    
    -- Log if there are changes or every 5 seconds for heartbeat
    if #changes > 0 or logCounter % 5 == 0 then
        log:debug("=== Update #%d (%.1fs) ===", logCounter, now)
        log:debug("  📍 Position: (%.0f, %.0f, %.0f)", ear.X, ear.Y, ear.Z)
        
        if #zonesInRange > 0 then
            log:debug("  📡 In range of %d zones:", #zonesInRange)
            for i, zone in ipairs(zonesInRange) do
                local marker = i <= 2 and "🎯" or "⏸️"
                log:debug("    %s %s: dist=%d/%d vol=%.3f pri=%d", 
                    marker, zone.key, zone.distance, zone.radius, zone.volume, zone.priority)
            end
        else
            log:debug("  📡 No zones in range")
        end
        
        if #activeAmbients > 0 then
            log:debug("  🎵 Playing %d sounds: %s", #activeAmbients, table.concat(activeAmbients, ", "))
        else
            log:debug("  🎵 No ambient sounds playing")
        end
        
        if #changes > 0 then
            log:info("  🔄 CHANGES:")
            for _, change in ipairs(changes) do
                log:info("    " .. change)
            end
        end
    end
    
    -- Update previous state
    prevTargets = currentTargets
    prevActive = currentActive
end)

-- Also log when the character moves significantly
local LocalPlayer = Players.LocalPlayer
local lastPos = Vector3.new(0, 0, 0)
local MOVE_THRESHOLD = 10

task.spawn(function()
    while true do
        task.wait(0.5)
        local char = LocalPlayer.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local pos = hrp.Position
                if (pos - lastPos).Magnitude > MOVE_THRESHOLD then
                    log:info("Player moved %.0f studs", (pos - lastPos).Magnitude)
                    lastPos = pos
                end
            end
        end
    end
end)