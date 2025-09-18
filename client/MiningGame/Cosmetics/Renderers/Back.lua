--!strict
--[[
    Back.lua
    Handles back cosmetics like wings, capes, and jetpacks.
]]

local RunService = game:GetService("RunService")
local Registry = require(script.Parent.Parent.RendererRegistry)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Time = require(Shared:WaitForChild("Time"))
local CosmeticMaterials = require(Shared:WaitForChild("CosmeticMaterials"))
local CosmeticDefinitions = require(Shared:WaitForChild("CosmeticDefinitions"))

local Back = {}
Back.priority = 50 -- Apply after model swap

function Back.apply(character: Model, def: any, ctx: any)
    local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
    if not torso then return end
    
    -- Try asset model first
    local assets = nil -- Assets disabled; procedural-only cosmetics
    if false then
        local model = assets:FindFirstChild(def.asset)
        if model then
            model = model:Clone()
            model.Name = "CosmeticBack"
            
            -- Handle Accessory assets
            if model:IsA("Accessory") then
                local hum = character:FindFirstChildOfClass("Humanoid")
                if hum then
                    model.Parent = character
                    hum:AddAccessory(model)
                    return {instances = {model}}
                end
            end
            
            model.Parent = character

            local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
            if not part then
                model:Destroy()
                return
            end
            
            -- Set PrimaryPart for animation
            model.PrimaryPart = part
            
            local conn = nil
            -- Apply color/material overrides to all BaseParts and collect for color animation
            local desiredMaterial = CosmeticMaterials.pick(def)
            local desiredColor = (typeof(def.color) == "Color3") and def.color or nil
            local colorParts = {}
            for _, d in ipairs(model:GetDescendants()) do
                if d:IsA("BasePart") then
                    d.Material = desiredMaterial
                    if desiredColor then d.Color = desiredColor end
                    if type(def.transparency) == "number" then
                        d.Transparency = math.clamp(def.transparency, 0, 1)
                    end
                    table.insert(colorParts, d)
                end
            end

            -- Optional lighting on primary part
            if tonumber(def.lightBrightness) and (def.lightBrightness or 0) > 0 then
                local light = Instance.new("PointLight")
                light.Name = "BackLight"
                light.Brightness = def.lightBrightness
                light.Range = tonumber(def.lightRange) or 8
                if typeof(def.lightColor) == "Color3" then
                    light.Color = def.lightColor
                elseif desiredColor then
                    light.Color = desiredColor
                end
                light.Parent = part
            end

            -- Optional highlight for semi-transparent/glass wings
            if def.highlight or def.highlightColor then
                local hl = Instance.new("Highlight")
                hl.Name = "BackHighlight"
                hl.Adornee = model
                hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                hl.FillTransparency = math.clamp(tonumber(def.highlightFillT) or 0.8, 0, 1)
                hl.OutlineTransparency = math.clamp(tonumber(def.highlightOutlineT) or 0.2, 0, 1)
                local hc = (typeof(def.highlightColor) == "Color3") and def.highlightColor or desiredColor
                if hc then hl.OutlineColor = hc end
                hl.Parent = model
            end

            -- Optional tiny base particle emitters at wing bases
            do
                local pdef = def.baseParticles
                if false then
                    local texture = pdef.texture
                    if not texture and type(pdef.textureFromAura) == "string" then
                        local auraDef = CosmeticDefinitions.Get(pdef.textureFromAura)
                        texture = auraDef and auraDef.particleTexture or texture
                    end
                    texture = texture or "rbxasset://textures/particles/sparkles_main.dds"
                    local aL = Instance.new("Attachment")
                    aL.Name = "WingBaseL"
                    aL.Position = Vector3.new(-1, 0, 0.3)
                    aL.Parent = part
                    local aR = Instance.new("Attachment")
                    aR.Name = "WingBaseR"
                    aR.Position = Vector3.new(1, 0, 0.3)
                    aR.Parent = part
                    -- Optional reposition: top of wings
                    do
                        local _mode = tostring(pdef.attach or pdef.attachMode or ""):lower()
                        if _mode == "wingtop" then
                            aL.Position = aL.Position + Vector3.new(0, 1.5, 0)
                            aR.Position = aR.Position + Vector3.new(0, 1.5, 0)
                        end
                    end
                    local function makeEmitter(att: Attachment)
                        local pe = Instance.new("ParticleEmitter")
                        pe.Name = "WingBaseFX"
                        pe.Texture = texture
                        pe.Rate = tonumber(pdef.rate) or 10
                        pe.Lifetime = typeof(pdef.lifetime) == "NumberRange" and pdef.lifetime or NumberRange.new(2.0, 3.0)
                        pe.Speed = typeof(pdef.speed) == "NumberRange" and pdef.speed or NumberRange.new(0.3, 0.8)
                        pe.Drag = tonumber(pdef.drag) or 1.2
                        pe.Acceleration = Vector3.new(0, tonumber(pdef.accelY) or -0.8, 0)
                        pe.LightEmission = tonumber(pdef.lightEmission) or 0.8
                        if typeof(pdef.sizeSequence) == "NumberSequence" then pe.Size = pdef.sizeSequence end
                        if typeof(pdef.transparencySequence) == "NumberSequence" then pe.Transparency = pdef.transparencySequence end
                        pe.Parent = att
                        return pe
                    end
                    local eL = makeEmitter(aL)
                    local eR = makeEmitter(aR)
                end
            end

            -- Optional rainbow color cycling
            local conns = {}
            if tostring(def.effect or def.colorMode or ""):lower() == "rainbow" then
                local hueHz = tonumber(def.hueSpeedHz or def.colorSpeedHz) or 0.25
                local lightObj = part:FindFirstChild("BackLight")
                table.insert(conns, RunService.Heartbeat:Connect(function()
                    local h = (Time.mono() * hueHz) % 1
                    local c = Color3.fromHSV(h, 1, 1)
                    for _, bp in ipairs(colorParts) do
                        bp.Color = c
                    end
                    if lightObj and lightObj:IsA("PointLight") then
                        lightObj.Color = c
                    end
                end))
            end

            if def.animates then
                -- Use Motor6D for animatable connection
                local motor = Instance.new("Motor6D")
                motor.Name = "BackMotor"
                motor.Part0 = torso
                motor.Part1 = part
                motor.Parent = torso
                -- Offset from torso (allow item to override)
                local c0 = (def.animSpec and def.animSpec.c0) or CFrame.new(0, 0, 1)
                motor.C0 = c0

                -- Animate via Transform
                local freq = (def.animSpec and (def.animSpec.speedHz or def.animSpec.freqHz)) or 2
                local ampDeg = (def.animSpec and def.animSpec.amplitudeDeg) or 10
                local axis = (def.animSpec and def.animSpec.axis) or "yaw" -- yaw|pitch|roll
                conn = RunService.Heartbeat:Connect(function()
                    local flap = math.sin(Time.mono() * freq) * math.rad(ampDeg)
                    if axis == "pitch" then
                        motor.Transform = CFrame.Angles(flap, 0, 0)
                    elseif axis == "roll" then
                        motor.Transform = CFrame.Angles(0, 0, flap)
                    else
                        motor.Transform = CFrame.Angles(0, flap, 0)
                    end
                end)
                table.insert(conns, conn)
                return {instances = {model, motor}, connections = conns}
            else
                -- Static weld
                local weld = Instance.new("WeldConstraint")
                weld.Part0 = torso
                weld.Part1 = part
                weld.Parent = model
                return {instances = {model}, connections = conns}
            end
        end
    end
    
    -- Fallback simple wings (procedural)
    local model = Instance.new("Model")
    model.Name = "CosmeticBack"
    model.Parent = character

    local left = Instance.new("Part")
    left.Name = "LeftWing"
    local span = tonumber(def.spanStuds) or 3
    local height = tonumber(def.wingHeight) or 4
    local thick = tonumber(def.wingThickness) or 0.5
    left.Size = Vector3.new(span, height, thick)
    left.CanCollide = false
    left.CanQuery = false
    left.CanTouch = false
    left.Massless = true
    left.Anchored = false
    left.Material = CosmeticMaterials.pick(def)
    if typeof(def.color) == "Color3" then
        left.Color = def.color
    else
        left.BrickColor = BrickColor.new("White")
    end
    if type(def.transparency) == "number" then
        left.Transparency = math.clamp(def.transparency, 0, 1)
    end
    left.Parent = model

    local right = left:Clone()
    right.Name = "RightWing"
    right.Anchored = false
    if type(def.transparency) == "number" then
        right.Transparency = math.clamp(def.transparency, 0, 1)
    end
    right.Parent = model
    
    -- Apply style based on ID (only when no explicit presets provided)
    local hasExplicit = (def.material ~= nil) or (def.materialPreset ~= nil) or (typeof(def.color) == "Color3")
    if (not hasExplicit) and def.id and string.find(def.id, "fire") then
        left.BrickColor = BrickColor.new("Bright orange")
        right.BrickColor = BrickColor.new("Bright orange")
        left.Material = Enum.Material.Neon
        right.Material = Enum.Material.Neon
    elseif (not hasExplicit) and def.id and string.find(def.id, "ice") then
        left.BrickColor = BrickColor.new("Cyan")
        right.BrickColor = BrickColor.new("Cyan")
        left.Material = Enum.Material.Ice
        right.Material = Enum.Material.Ice
    elseif (not hasExplicit) and def.id and string.find(def.id, "void") then
        left.BrickColor = BrickColor.new("Dark indigo")
        right.BrickColor = BrickColor.new("Dark indigo")
        left.Material = Enum.Material.ForceField
        right.Material = Enum.Material.ForceField
    end

    -- Optional lighting for fallback parts
    if tonumber(def.lightBrightness) and (def.lightBrightness or 0) > 0 then
        local function addLight(p: BasePart)
            local light = Instance.new("PointLight")
            light.Name = "BackLight"
            light.Brightness = def.lightBrightness
            light.Range = tonumber(def.lightRange) or 8
            if typeof(def.lightColor) == "Color3" then
                light.Color = def.lightColor
            elseif typeof(def.color) == "Color3" then
                light.Color = def.color
            end
            light.Parent = p
        end
        addLight(left)
        addLight(right)
    end
    
    -- Use Motor6Ds for animatable wings
    local leftMotor = Instance.new("Motor6D")
    leftMotor.Name = "LeftWingMotor"
    leftMotor.Part0 = torso
    leftMotor.Part1 = left
    leftMotor.Parent = torso
    local mountX = tonumber(def.mountX) or 2
    local mountY = tonumber(def.mountY) or 0
    local mountZ = tonumber(def.mountZ) or 1
    leftMotor.C0 = CFrame.new(-mountX, mountY, mountZ)
    
    local rightMotor = Instance.new("Motor6D")
    rightMotor.Name = "RightWingMotor"
    rightMotor.Part0 = torso
    rightMotor.Part1 = right
    rightMotor.Parent = torso
    rightMotor.C0 = CFrame.new(mountX, mountY, mountZ)
    
    local conns = {}
    -- Optional highlight outline for semi-transparent/glass wings
    if def.highlight or def.highlightColor then
        local hl = Instance.new("Highlight")
        hl.Name = "BackHighlight"
        hl.Adornee = model
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.FillTransparency = math.clamp(tonumber(def.highlightFillT) or 0.85, 0, 1)
        hl.OutlineTransparency = math.clamp(tonumber(def.highlightOutlineT) or 0.25, 0, 1)
        local hc = (typeof(def.highlightColor) == "Color3") and def.highlightColor or left.Color
        if hc then hl.OutlineColor = hc end
        hl.Parent = model
        table.insert(conns, hl)
    end

    -- Optional tiny base particle emitters on fallback parts
    do
        local pdef = def.baseParticles
        if false then
            local texture = pdef.texture
            if not texture and type(pdef.textureFromAura) == "string" then
                local auraDef = CosmeticDefinitions.Get(pdef.textureFromAura)
                texture = auraDef and auraDef.particleTexture or texture
            end
            texture = texture or "rbxasset://textures/particles/sparkles_main.dds"
            local function makeEmitter(p: BasePart)
                local att = Instance.new("Attachment")
                att.Name = "WingTopFX"
                local zofs = tonumber(pdef.offsetZ or pdef.forwardOffsetZ) or 0.1
                att.Position = Vector3.new(0, (p.Size.Y * 0.5) - 0.02, zofs)
                att.Parent = p
                local pe = Instance.new("ParticleEmitter")
                pe.Name = "WingBaseFX"
                pe.Texture = texture
                pe.Lifetime = typeof(pdef.lifetime) == "NumberRange" and pdef.lifetime or NumberRange.new(2.0, 3.0)
                pe.Speed = typeof(pdef.speed) == "NumberRange" and pdef.speed or NumberRange.new(0.3, 0.8)
                if typeof(pdef.sizeSequence) == "NumberSequence" then pe.Size = pdef.sizeSequence end
                if typeof(pdef.transparencySequence) == "NumberSequence" then pe.Transparency = pdef.transparencySequence end
                if typeof(pdef.colorSequence) == "ColorSequence" then pe.Color = pdef.colorSequence elseif typeof(pdef.color) == "Color3" then pe.Color = ColorSequence.new(pdef.color) end
                pe.Rate = tonumber(pdef.rate) or 14
                pe.Drag = tonumber(pdef.drag) or 1.2
                pe.Acceleration = Vector3.new(0, tonumber(pdef.accelY) or -0.8, 0)
                pe.LightEmission = tonumber(pdef.lightEmission) or 0.8
                do
                    local dirStr = tostring(pdef.emissionDirection or "top"):lower()
                    local dir = Enum.NormalId.Top
                    if dirStr == "bottom" or dirStr == "down" then dir = Enum.NormalId.Bottom
                    elseif dirStr == "front" or dirStr == "forward" then dir = Enum.NormalId.Front
                    elseif dirStr == "back" or dirStr == "backward" then dir = Enum.NormalId.Back
                    elseif dirStr == "left" then dir = Enum.NormalId.Left
                    elseif dirStr == "right" then dir = Enum.NormalId.Right
                    end
                    pe.EmissionDirection = dir
                end
                -- Optional spread angles
                if typeof(pdef.spreadAngle) == "Vector2" then
                    pe.SpreadAngle = pdef.spreadAngle
                else
                    local sx = tonumber(pdef.spreadXDeg or pdef.spreadX) or nil
                    local sy = tonumber(pdef.spreadYDeg or pdef.spreadY) or nil
                    if sx or sy then
                        pe.SpreadAngle = Vector2.new(sx or 0, sy or 0)
                    end
                end
                -- Optional rotation dynamics
                if typeof(pdef.rotSpeed) == "NumberRange" then pe.RotSpeed = pdef.rotSpeed end
                if typeof(pdef.rotation) == "NumberRange" then pe.Rotation = pdef.rotation end
                pe.Parent = att
                return att, pe
            end
            local a1, e1 = makeEmitter(left)
            local a2, e2 = makeEmitter(right)
            table.insert(conns, a1)
            table.insert(conns, e1)
            table.insert(conns, a2)
            table.insert(conns, e2)
        end
    end
    if tostring(def.effect or def.colorMode or ""):lower() == "rainbow" then
        local hueHz = tonumber(def.hueSpeedHz or def.colorSpeedHz) or 0.25
        local lights = {}
        for _, d in ipairs({left, right}) do
            local l = d:FindFirstChild("BackLight")
            if l and l:IsA("PointLight") then table.insert(lights, l) end
        end
        table.insert(conns, RunService.Heartbeat:Connect(function()
            local h = (Time.mono() * hueHz) % 1
            local c = Color3.fromHSV(h, 1, 1)
            left.Color = c
            right.Color = c
            for _, l in ipairs(lights) do l.Color = c end
        end))
    end

    local conn = nil
    if def.animates ~= false then -- Default to animated
        local freq = (def.animSpec and (def.animSpec.speedHz or def.animSpec.freqHz)) or 2.5
        local ampDeg = (def.animSpec and def.animSpec.amplitudeDeg) or 22
        if ampDeg < 5 then ampDeg = 22 end -- ensure visible motion
        local axis = (def.animSpec and def.animSpec.axis) or "yaw"
        conn = RunService.Heartbeat:Connect(function()
            local flap = math.sin(Time.mono() * freq) * math.rad(ampDeg)
            if axis == "pitch" then
                leftMotor.Transform = CFrame.Angles(flap, 0, 0)
                rightMotor.Transform = CFrame.Angles(flap, 0, 0)
            elseif axis == "roll" then
                leftMotor.Transform = CFrame.Angles(0, 0, flap)
                rightMotor.Transform = CFrame.Angles(0, 0, flap)
            else
                leftMotor.Transform = CFrame.Angles(0, -flap, 0)
                rightMotor.Transform = CFrame.Angles(0, flap, 0)
            end
        end)
        table.insert(conns, conn)
    end
    
    model.PrimaryPart = left
    return {instances = {model, leftMotor, rightMotor}, connections = conns}
end

function Back.remove(ctx)
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

Registry.register("back", Back)
return Back
