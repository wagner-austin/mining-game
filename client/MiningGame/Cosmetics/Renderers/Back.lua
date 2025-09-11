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

local Back = {}
Back.priority = 50 -- Apply after model swap

function Back.apply(character: Model, def: any, ctx: any)
    local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
    if not torso then return end
    
    -- Try asset model first
    local assets = Shared:FindFirstChild("Assets")
    if assets and def.asset then
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
            if def.animates then
                -- Use Motor6D for animatable connection
                local motor = Instance.new("Motor6D")
                motor.Name = "BackMotor"
                motor.Part0 = torso
                motor.Part1 = part
                motor.Parent = torso
                motor.C0 = CFrame.new(0, 0, 1) -- Offset from torso
                
                -- Animate via Transform
                conn = RunService.Heartbeat:Connect(function()
                    local flap = math.sin(Time.mono() * 2) * math.rad(10)
                    motor.Transform = CFrame.Angles(0, flap, 0)
                end)
                
                return {instances = {model, motor}, connections = {conn}}
            else
                -- Static weld
                local weld = Instance.new("WeldConstraint")
                weld.Part0 = torso
                weld.Part1 = part
                weld.Parent = model
                return {instances = {model}, connections = {}}
            end
        end
    end
    
    -- Fallback simple wings
    local model = Instance.new("Model")
    model.Name = "CosmeticBack"
    model.Parent = character
    
    local left = Instance.new("Part")
    left.Name = "LeftWing"
    left.Size = Vector3.new(3, 4, 0.5)
    left.CanCollide = false
    left.Material = Enum.Material.Neon
    left.BrickColor = BrickColor.new("White")
    left.Parent = model
    
    local right = left:Clone()
    right.Name = "RightWing"
    right.Parent = model
    
    -- Apply style based on ID
    if def.id and string.find(def.id, "fire") then
        left.BrickColor = BrickColor.new("Bright orange")
        right.BrickColor = BrickColor.new("Bright orange")
        left.Material = Enum.Material.Neon
        right.Material = Enum.Material.Neon
    elseif def.id and string.find(def.id, "ice") then
        left.BrickColor = BrickColor.new("Cyan")
        right.BrickColor = BrickColor.new("Cyan")
        left.Material = Enum.Material.Ice
        right.Material = Enum.Material.Ice
    elseif def.id and string.find(def.id, "void") then
        left.BrickColor = BrickColor.new("Dark indigo")
        right.BrickColor = BrickColor.new("Dark indigo")
        left.Material = Enum.Material.ForceField
        right.Material = Enum.Material.ForceField
    end
    
    -- Use Motor6Ds for animatable wings
    local leftMotor = Instance.new("Motor6D")
    leftMotor.Name = "LeftWingMotor"
    leftMotor.Part0 = torso
    leftMotor.Part1 = left
    leftMotor.Parent = torso
    leftMotor.C0 = CFrame.new(-2, 0, 1)
    
    local rightMotor = Instance.new("Motor6D")
    rightMotor.Name = "RightWingMotor"
    rightMotor.Part0 = torso
    rightMotor.Part1 = right
    rightMotor.Parent = torso
    rightMotor.C0 = CFrame.new(2, 0, 1)
    
    local conn = nil
    if def.animates ~= false then -- Default to animated
        conn = RunService.Heartbeat:Connect(function()
            local flap = math.sin(Time.mono() * 2) * math.rad(15)
            leftMotor.Transform = CFrame.Angles(0, -flap, 0)
            rightMotor.Transform = CFrame.Angles(0, flap, 0)
        end)
    end
    
    model.PrimaryPart = left
    return {instances = {model, leftMotor, rightMotor}, connections = {conn}}
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