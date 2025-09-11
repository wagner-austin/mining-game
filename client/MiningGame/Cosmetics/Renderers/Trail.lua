--!strict
--[[
    Trail.lua
    Handles trail effects that follow player movement.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Time = require(Shared:WaitForChild("Time"))
local Registry = require(script.Parent.Parent.RendererRegistry)

local Trail = {}
Trail.priority = 35 -- Apply after auras

function Trail.apply(character: Model, def: any, ctx: any)
    local root = character:FindFirstChild("HumanoidRootPart")
    if not root then return end
    
    -- Debug logging
    print("[Trail] Applying trail cosmetic:", def.itemId or "unknown")
    print("[Trail] Color:", def.color)
    print("[Trail] Effect:", def.effect)
    
    -- Use HumanoidRootPart size as base, NOT GetExtentsSize which includes all accessories
    local rootSize = root.Size
    local halfWidth = math.clamp(rootSize.X * 0.5, 0.8, 2.0)  -- Typically 1 stud for normal avatars
    
    local a0 = Instance.new("Attachment")
    a0.Name = "TrailA0"
    a0.Position = Vector3.new(-halfWidth, 0, 0)
    a0.Parent = root
    
    local a1 = Instance.new("Attachment")
    a1.Name = "TrailA1"
    a1.Position = Vector3.new(halfWidth, 0, 0)
    a1.Parent = root
    
    local tr = Instance.new("Trail")
    tr.Name = "CosmeticTrail"
    tr.Attachment0 = a0
    tr.Attachment1 = a1
    tr.Parent = root
    
    tr.Lifetime = def.lifetime or 1
    tr.MinLength = 0
    tr.FaceCamera = true
    tr.LightEmission = def.lightEmission or 0.5
    
    -- Don't set Width0/Width1 - let it use attachment spacing
    
    -- Set width scale for tapering
    tr.WidthScale = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(1, 0)
    })
    
    if def.texture then
        tr.Texture = def.texture
    end
    
    local conn = nil
    if def.effect == "rainbow" then
        local last = 0
        conn = RunService.Heartbeat:Connect(function(dt)
            last = last + dt
            if last < 0.1 then return end
            last = 0
            local hue = (Time.mono() * 0.5) % 1
            tr.Color = ColorSequence.new(Color3.fromHSV(hue, 1, 1))
        end)
    elseif typeof(def.color) == "Color3" then
        tr.Color = ColorSequence.new(def.color)
    end
    
    return {instances = {tr, a0, a1}, connections = {conn}}
end

function Trail.remove(ctx)
    if ctx and ctx.connections then
        for _, c in ipairs(ctx.connections) do
            if typeof(c) == "RBXScriptConnection" then
                c:Disconnect()
            end
        end
    end
    if ctx and ctx.instances then
        for _, i in ipairs(ctx.instances) do
            if typeof(i) == "Instance" then
                i:Destroy()
            end
        end
    end
end

Registry.register("trail", Trail)
return Trail