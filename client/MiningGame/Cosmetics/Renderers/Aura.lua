--!strict
--[[
    Aura.lua
    Handles particle-based aura cosmetics around the player.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Time = require(Shared:WaitForChild("Time"))
local RendererRegistry = require(script.Parent.Parent.RendererRegistry)

local Aura = {}
Aura.priority = 40 -- Apply after model/back/head

function Aura.apply(character: Model, def: any, ctx: any)
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return nil end
    
    local attachment = Instance.new("Attachment")
    attachment.Name = "AuraAttachment"
    attachment.Parent = rootPart
    
    local emitter = Instance.new("ParticleEmitter")
    emitter.Name = "AuraEmitter"
    emitter.Parent = attachment
    
    -- Base configuration
    emitter.Texture = def.particleTexture or "rbxasset://textures/particles/sparkles_main.dds"
    emitter.Rate = def.emissionRate or 50
    emitter.Lifetime = NumberRange.new(1, 2)
    emitter.Speed = NumberRange.new(2, 4)
    emitter.SpreadAngle = Vector2.new(360, 360)
    emitter.LightEmission = def.lightEmission or 0.5
    emitter.LightInfluence = 0.2
    
    -- Light host: welded, invisible part
    local lightPart = character:FindFirstChild("AuraLightPart") :: Part?
    if not lightPart then
        lightPart = Instance.new("Part")
        lightPart.Name = "AuraLightPart"
        lightPart.Size = Vector3.new(0.2, 0.2, 0.2)
        lightPart.Transparency = 1
        lightPart.CanCollide = false
        lightPart.CanQuery = false
        lightPart.CanTouch = false
        lightPart.Massless = true
        lightPart.Parent = character
        
        -- Set CFrame BEFORE creating weld to avoid position doubling with streaming
        lightPart.CFrame = rootPart.CFrame
        
        local weld = Instance.new("WeldConstraint")
        weld.Part0 = rootPart
        weld.Part1 = lightPart
        weld.Parent = lightPart
    end
    
    -- Reuse or create the light
    local light = lightPart:FindFirstChildOfClass("PointLight") or Instance.new("PointLight")
    light.Name = "AuraLight"
    light.Shadows = false
    light.Brightness = 2
    light.Range = 20
    light.Enabled = true
    light.Parent = lightPart
    
    -- Helper to set light properties
    local function setLight(c: Color3, b: number?, r: number?)
        light.Color = c
        if b then light.Brightness = b end
        if r then light.Range = r end
    end
    
    local connections = {}
    
    -- Handle colors and effects
    if def.effect == "rainbow" then
        -- Animated rainbow effect (10 updates/sec instead of 60)
        local last = 0
        local connection = RunService.Heartbeat:Connect(function(dt)
            last = last + dt
            if last < 0.1 then return end
            last = 0
            local hue = (Time.mono() * 0.3) % 1
            local rainbowColor = Color3.fromHSV(hue, 1, 1)
            emitter.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, rainbowColor),
                ColorSequenceKeypoint.new(0.5, Color3.fromHSV((hue + 0.5) % 1, 1, 1)),
                ColorSequenceKeypoint.new(1, rainbowColor),
            })
            -- Sync light color with rainbow if still attached
            if light:IsDescendantOf(character) then
                setLight(rainbowColor)
            end
        end)
        table.insert(connections, connection)
    elseif typeof(def.color) == "Color3" then
        emitter.Color = ColorSequence.new(def.color)
        setLight(def.color)
    end
    
    -- Special effect variations
    if def.effect == "void" then
        emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
        emitter.Color = ColorSequence.new(Color3.fromRGB(50, 0, 100))
        emitter.LightEmission = 0
        emitter.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.1, 0.5),
            NumberSequenceKeypoint.new(0.9, 0.5),
            NumberSequenceKeypoint.new(1, 1),
        })
        emitter.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.5, 2),
            NumberSequenceKeypoint.new(1, 0),
        })
        -- Void: Very dim purple light
        setLight(Color3.fromRGB(50, 0, 100), 0.5, 10)
    elseif def.effect == "fire" then
        emitter.Texture = "rbxasset://textures/particles/fire_main.dds"
        emitter.LightEmission = 1
        emitter.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.5),
            NumberSequenceKeypoint.new(0.5, 1),
            NumberSequenceKeypoint.new(1, 0),
        })
        emitter.Acceleration = Vector3.new(0, 5, 0)
        -- Fire: Warm orange glow
        setLight(def.color or Color3.fromRGB(255, 150, 50), 3, 25)
    elseif def.effect == "ice" then
        emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
        emitter.Speed = NumberRange.new(1, 2)
        emitter.Acceleration = Vector3.new(0, -2, 0)
        emitter.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.3),
            NumberSequenceKeypoint.new(1, 0.8),
        })
        -- Ice: Cool blue light
        setLight(def.color or Color3.fromRGB(100, 200, 255), 2, 20)
    elseif def.effect == "cosmic" then
        emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
        emitter.LightEmission = 1
        emitter.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(0.1, 0.5),
            NumberSequenceKeypoint.new(0.9, 0.5),
            NumberSequenceKeypoint.new(1, 0),
        })
        emitter.RotSpeed = NumberRange.new(-180, 180)
        emitter.VelocityInheritance = 0.5
        -- Cosmic: Bright white/purple starlight
        setLight(Color3.fromRGB(200, 150, 255), 4, 30)
    elseif def.effect == "energy" then
        -- Energy auras: Electric blue/yellow
        local energyColor = def.color or Color3.fromRGB(100, 200, 255)
        emitter.Color = ColorSequence.new(energyColor)
        setLight(energyColor, 2.5, 22)
    end
    
    return {instances = {attachment, emitter, lightPart, light}, connections = connections}
end

function Aura.remove(ctx: any)
    if not ctx then return end
    
    -- Disconnect connections first
    if ctx.connections then
        for _, conn in ipairs(ctx.connections) do
            if typeof(conn) == "RBXScriptConnection" then
                conn:Disconnect()
            end
        end
    end
    
    -- Clean up instances
    if ctx.instances then
        for _, inst in ipairs(ctx.instances) do
            if typeof(inst) == "Instance" and inst.Parent then
                -- Special handling for AuraLightPart to avoid conflicts if multiple auras share it
                if inst:IsA("Part") and inst.Name == "AuraLightPart" then
                    -- Just disable the light instead of destroying the part
                    -- This prevents issues if switching auras quickly
                    local lightInst = inst:FindFirstChildOfClass("PointLight")
                    if lightInst then 
                        lightInst.Enabled = false 
                    end
                else
                    -- Destroy other instances normally (attachment, emitter, etc)
                    inst:Destroy()
                end
            end
        end
    end
end

-- Register with the registry
RendererRegistry.register("aura", Aura)

return Aura