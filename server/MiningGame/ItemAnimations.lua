--!strict
-- ItemAnimations.lua
-- Modular animations for item collection effects

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local ErrorService = require(script.Parent:WaitForChild("ErrorService"))

local ItemAnimations = {}

-- Fly-to-player animation (server-side, replicates to all clients)
function ItemAnimations.flyDropToPlayer(dropModel: Model, player: Player, onComplete: (() -> ())?): ()
    if not dropModel or not dropModel.PrimaryPart then
        if onComplete then onComplete() end
        return
    end

    local part = dropModel.PrimaryPart

    -- Hide billboard during flight
    local bb = part:FindFirstChildOfClass("BillboardGui")
    if bb then bb.Enabled = false end
    
    -- Turn off outlines/glow during flight for clean look
    local sel = part:FindFirstChildOfClass("SelectionBox")
    if sel then 
        sel.Adornee = nil
        sel.Visible = false 
    end
    local light = part:FindFirstChildOfClass("PointLight")
    if light then light.Enabled = false end
    
    -- Disable ambient hover particles during the zip
    local ambient = part:FindFirstChild("AmbientParticles")
    if ambient and ambient:IsA("ParticleEmitter") then
        ambient.Enabled = false
    end

    -- Function to compute target position (re-evaluated for moving players)
    local function computeTarget()
        local character = player.Character
        if character and character.PrimaryPart then
            return character.PrimaryPart.Position + Vector3.new(0, 2, 0)
        end
        return part.Position
    end

    -- Small trail (needs two attachments for proper rendering)
    local a0 = Instance.new("Attachment")
    a0.Position = Vector3.new(0, 0.5, 0)
    a0.Parent = part
    
    local a1 = Instance.new("Attachment")
    a1.Position = Vector3.new(0, -0.5, 0)
    a1.Parent = part

    local trail = Instance.new("Trail")
    trail.Attachment0 = a0
    trail.Attachment1 = a1
    trail.FaceCamera = true
    trail.MinLength = 0
    trail.Lifetime = 0.25
    trail.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(1, 1),
    })
    trail.Color = ColorSequence.new(part.Color)
    trail.LightEmission = 0.5
    trail.Parent = part
    
    -- Clean up trail and attachments after animation
    Debris:AddItem(trail, 1)
    Debris:AddItem(a0, 1)
    Debris:AddItem(a1, 1)

    -- Emphasis pop, then zip to player and fade out
    local scaleUp = TweenService:Create(
        part,
        TweenInfo.new(0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        { Size = part.Size * 1.25 }
    )

    local flyTween -- Define first so we can assign in callback
    
    -- Track if animation was cancelled
    local cancelled = false
    
    -- Connect before Play to avoid race conditions
    scaleUp.Completed:Connect(function(playbackState)
        if cancelled or playbackState ~= Enum.PlaybackState.Completed then
            if onComplete then onComplete() end
            return
        end
        
        -- Refresh the target right as we start flying (for moving players)
        local targetPos = computeTarget()
        
        -- Optional: Scale duration based on distance for constant speed
        local distance = (part.Position - targetPos).Magnitude
        local duration = math.clamp(distance / 60, 0.2, 0.6) -- ~60 studs/sec
        
        flyTween = TweenService:Create(
            part,
            TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { 
                Position = targetPos, 
                Size = Vector3.new(0.1, 0.1, 0.1), 
                Transparency = 1 
            }
        )
        flyTween.Completed:Connect(function()
            if onComplete then onComplete() end
        end)
        flyTween:Play()
    end)
    
    scaleUp:Play()
    
    -- Ensure cleanup happens even if animation is interrupted
    task.delay(2, function()
        if not cancelled then
            cancelled = true
            if onComplete then 
                ErrorService.safecall("Animation:onComplete", onComplete)
            end
        end
    end)
end

-- Create hover animation for floating items
function ItemAnimations.createHoverAnimation(part: BasePart): Tween
    local startPos = part.Position
    local hoverTweenInfo = TweenInfo.new(
        2,
        Enum.EasingStyle.Sine,
        Enum.EasingDirection.InOut,
        -1,  -- Repeat indefinitely
        true -- Reverse
    )
    
    local hoverTween = TweenService:Create(
        part,
        hoverTweenInfo,
        {Position = startPos + Vector3.new(0, 1, 0)}
    )
    hoverTween:Play()
    
    return hoverTween
end

-- Stop any active animations on a model
function ItemAnimations.stopAnimations(dropModel: Model, hoverTween: Tween?): ()
    if hoverTween then 
        ErrorService.safecall("Tween:Cancel", function() hoverTween:Cancel() end)
    end
    -- (No need to scan children; tweens aren't parented under parts)
end

-- Pulse animation for partial pickups
function ItemAnimations.pulsePartialPickup(part: BasePart): ()
    local originalSize = part.Size
    local pulseInfo = TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
    local pulse = TweenService:Create(
        part,
        pulseInfo,
        {Size = originalSize * 1.2}
    )
    pulse:Play()
    pulse.Completed:Connect(function()
        if part and part.Parent then
            part.Size = originalSize
        end
    end)
end

-- Keep rotation tick co-located with animations for clarity
function ItemAnimations.updateRotations(activeDrops: {[Model]: any}, dt: number, rotationSpeed: number)
    for dropModel, dropData in pairs(activeDrops) do
        if dropModel.Parent and dropModel.PrimaryPart and not dropData.claimed then
            dropModel.PrimaryPart.CFrame = dropModel.PrimaryPart.CFrame * CFrame.Angles(0, rotationSpeed * dt, 0)
        end
    end
end

return ItemAnimations
