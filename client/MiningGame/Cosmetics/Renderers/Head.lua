--!strict
--[[
    Head.lua
    Handles head accessories like crowns, halos, helmets, etc.
]]

local Registry = require(script.Parent.Parent.RendererRegistry)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("MiningGame")

local Head = {}
Head.priority = 45 -- Apply after back items

function Head.apply(character: Model, def: any, ctx: any)
    local head = character:FindFirstChild("Head")
    if not head then return end
    
    local assets = Shared:FindFirstChild("Assets")
    if assets and def.asset then
        local acc = assets:FindFirstChild(def.asset)
        if acc then
            acc = acc:Clone()
            acc.Name = "CosmeticHead"
            
            -- Handle Accessory type
            if acc:IsA("Accessory") then
                local hum = character:FindFirstChildOfClass("Humanoid")
                if not hum then return end
                acc.Name = ("CosmeticHead_%s"):format(def.id or "item")
                hum:AddAccessory(acc) -- Roblox handles parenting
                return {instances = {acc}}
            else
                -- Generic model/part
                acc.Parent = character
                local base = acc.PrimaryPart or acc:FindFirstChildWhichIsA("BasePart")
                if not base then
                    acc:Destroy()
                    return
                end
                
                -- Position first (before welding)
                local offset = def.offsetCFrame or (
                    (def.id and string.find(def.id, "halo")) and CFrame.new(0, 1.5, 0)
                    or (def.id and string.find(def.id, "crown")) and CFrame.new(0, 0.8, 0)
                    or CFrame.new(0, 0.5, 0)
                )
                base.CFrame = head.CFrame * offset
                
                -- Then weld
                local weld = Instance.new("WeldConstraint")
                weld.Part0 = head
                weld.Part1 = base
                weld.Parent = acc
                
                -- Add glow if specified
                if def.glows then
                    local light = Instance.new("PointLight")
                    light.Brightness = 2
                    light.Range = 10
                    light.Parent = base
                end
                
                return {instances = {acc}}
            end
        end
    end
    
    -- Fallback placeholder accessories
    local part = Instance.new("Part")
    part.Name = ("CosmeticHead_%s"):format(def.id or "item")
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.Massless = true
    part.Parent = character
    
    -- Style based on type
    if def.id and string.find(def.id, "crown") then
        part.Size = Vector3.new(1.5, 0.5, 1.5)
        part.Shape = Enum.PartType.Cylinder
        part.Material = Enum.Material.Neon
        
        if string.find(def.id, "gold") then
            part.BrickColor = BrickColor.new("Gold")
        elseif string.find(def.id, "silver") then
            part.BrickColor = BrickColor.new("Silver flip/flop")
        else
            part.BrickColor = BrickColor.new("Copper")
        end
        
        part.CFrame = head.CFrame * CFrame.new(0, 1, 0) * CFrame.Angles(0, 0, math.rad(90))
        
    elseif def.id and string.find(def.id, "halo") then
        part.Size = Vector3.new(2, 0.2, 2)
        part.Shape = Enum.PartType.Cylinder
        part.Material = Enum.Material.Neon
        part.BrickColor = BrickColor.new("Institutional white")
        part.CFrame = head.CFrame * CFrame.new(0, 1.5, 0)
        
        -- Add glow effect
        local pointLight = Instance.new("PointLight")
        pointLight.Brightness = 2
        pointLight.Range = 10
        pointLight.Parent = part
        
    elseif def.id and string.find(def.id, "horns") then
        part.Size = Vector3.new(0.5, 1, 0.5)
        part.Material = Enum.Material.Granite
        part.BrickColor = BrickColor.new("Really black")
        part.CFrame = head.CFrame * CFrame.new(0, 1, 0)
        
    elseif def.id and string.find(def.id, "helmet") then
        part.Size = Vector3.new(1.2, 1.2, 1.2)
        part.Shape = Enum.PartType.Ball
        part.Material = Enum.Material.Metal
        part.BrickColor = BrickColor.new("Dark stone grey")
        part.CFrame = head.CFrame
        
    else
        -- Generic head accessory
        part.Size = Vector3.new(1, 0.5, 1)
        part.Material = Enum.Material.Neon
        part.CFrame = head.CFrame * CFrame.new(0, 1, 0)
    end
    
    -- Weld to head
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = head
    weld.Part1 = part
    weld.Parent = part
    
    -- Add glow if specified
    if def.glows then
        local light = Instance.new("PointLight")
        light.Brightness = 2
        light.Range = 10
        light.Parent = part
    end
    
    return {instances = {part}}
end

function Head.remove(ctx)
    if ctx and ctx.instances then
        for _, i in ipairs(ctx.instances) do
            if typeof(i) == "Instance" then
                i:Destroy()
            end
        end
    end
end

Registry.register("head", Head)
return Head