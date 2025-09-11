--!strict
--[[
    PickaxeSkin.lua
    Handles pickaxe/tool visual customization with full reversibility.
]]

local RunService = game:GetService("RunService")
local Registry = require(script.Parent.Parent.RendererRegistry)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Time = require(Shared:WaitForChild("Time"))

local PickaxeSkin = {}
PickaxeSkin.priority = 30 -- Apply last (after all wearables)

-- Store original properties and apply cosmetic
local function paintTool(tool: Tool, def: any, state: any)
    local handle = tool:FindFirstChild("Handle")
    if not handle then return {} end
    
    -- Store original properties if not already stored
    state = state or {}
    state.orig = state.orig or {}
    if not state.orig[handle] then
        state.orig[handle] = {
            Color = handle.Color,
            Material = handle.Material
        }
    end
    
    -- Apply material
    if def.material then
        handle.Material = def.material
    end
    
    -- Apply base tint
    if def.tint and typeof(def.tint) == "Color3" then
        handle.Color = def.tint
    end
    
    -- Apply special effects
    local effects = {}
    
    if def.effect == "fire" then
        local fire = Instance.new("Fire")
        fire.Name = "PickaxeEffect"
        fire.Size = 5
        fire.Heat = 10
        fire.Parent = handle
        table.insert(effects, fire)
        
    elseif def.effect == "ice" then
        handle.Material = Enum.Material.Ice
        if def.tint then
            handle.Color = def.tint
        else
            handle.Color = Color3.fromRGB(100, 200, 255)
        end
        
        local sparkle = Instance.new("Sparkles")
        sparkle.Name = "PickaxeEffect"
        sparkle.SparkleColor = Color3.fromRGB(100, 200, 255)
        sparkle.Parent = handle
        table.insert(effects, sparkle)
        
    elseif def.effect == "void" then
        handle.Material = Enum.Material.ForceField
        if def.tint then
            handle.Color = def.tint
        else
            handle.Color = Color3.fromRGB(50, 0, 100)
        end
        
    elseif def.effect == "cosmic" then
        handle.Material = Enum.Material.Neon
        if def.tint then
            handle.Color = def.tint
        else
            handle.Color = Color3.fromRGB(150, 50, 200)
        end
        
        local sparkle = Instance.new("Sparkles")
        sparkle.Name = "PickaxeEffect"
        sparkle.SparkleColor = def.tint or Color3.fromRGB(255, 100, 255)
        sparkle.Parent = handle
        table.insert(effects, sparkle)
        
    elseif def.effect == "neon" then
        handle.Material = Enum.Material.Neon
        if def.tint then
            handle.Color = def.tint
        end
    end
    
    return effects
end

function PickaxeSkin.apply(character: Model, def: any, ctx: any)
    local instances = {}
    local connections = {}
    local state = { orig = {} }  -- Store original handle properties
    
    -- Helper to paint and track effects
    local function paintAndTrack(tool: Tool)
        -- Remove any lingering effects from previous skins
        local handle = tool:FindFirstChild("Handle")
        if handle then
            for _, child in ipairs(handle:GetChildren()) do
                if (child:IsA("Sparkles") or child:IsA("Fire")) and child.Name == "PickaxeEffect" then
                    child:Destroy()
                end
            end
        end
        
        -- Paint and store effects
        local effects = paintTool(tool, def, state)
        for _, effect in ipairs(effects or {}) do
            table.insert(instances, effect)
        end
    end
    
    -- Paint current equipped tool
    local tool = character:FindFirstChildWhichIsA("Tool")
    if tool then
        paintAndTrack(tool)
    end
    
    -- Handle rainbow animation
    if def.effect == "rainbow" then
        local last = 0
        local rainbowConn = RunService.Heartbeat:Connect(function(dt)
            last = last + dt
            if last < 0.1 then return end
            last = 0
            
            local hue = (Time.mono() * 0.5) % 1
            local color = Color3.fromHSV(hue, 1, 1)
            
            -- Update all equipped tools
            local currentTool = character:FindFirstChildWhichIsA("Tool")
            if currentTool then
                local handle = currentTool:FindFirstChild("Handle")
                if handle then
                    -- Store original if not stored
                    if not state.orig[handle] then
                        state.orig[handle] = {
                            Color = handle.Color,
                            Material = handle.Material
                        }
                    end
                    handle.Color = color
                    handle.Material = Enum.Material.Neon
                end
            end
            
            -- Also update backpack tools
            local player = Players:GetPlayerFromCharacter(character)
            if player and player.Backpack then
                for _, backpackTool in ipairs(player.Backpack:GetChildren()) do
                    if backpackTool:IsA("Tool") then
                        local handle = backpackTool:FindFirstChild("Handle")
                        if handle then
                            if not state.orig[handle] then
                                state.orig[handle] = {
                                    Color = handle.Color,
                                    Material = handle.Material
                                }
                            end
                            handle.Color = color
                            handle.Material = Enum.Material.Neon
                        end
                    end
                end
            end
        end)
        table.insert(connections, rainbowConn)
    end
    
    -- Reapply on future tool equips
    local equipConn = character.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then
            paintAndTrack(child)
        end
    end)
    table.insert(connections, equipConn)
    
    -- Also handle backpack tools
    local player = Players:GetPlayerFromCharacter(character)
    if player then
        local backpack = player:FindFirstChild("Backpack")
        if backpack then
            -- Paint existing backpack tools
            for _, backpackTool in ipairs(backpack:GetChildren()) do
                if backpackTool:IsA("Tool") then
                    paintAndTrack(backpackTool)
                end
            end
            
            -- Listen for new tools in backpack
            local backpackConn = backpack.ChildAdded:Connect(function(child)
                if child:IsA("Tool") then
                    paintAndTrack(child)
                end
            end)
            table.insert(connections, backpackConn)
        end
    end
    
    return {instances = instances, connections = connections, state = state}
end

function PickaxeSkin.remove(ctx)
    -- Disconnect all connections
    if ctx and ctx.connections then
        for _, c in ipairs(ctx.connections) do
            if typeof(c) == "RBXScriptConnection" then
                c:Disconnect()
            end
        end
    end
    
    -- Destroy all effect instances
    if ctx and ctx.instances then
        for _, i in ipairs(ctx.instances) do
            if typeof(i) == "Instance" then
                i:Destroy()
            end
        end
    end
    
    -- Restore original handle properties
    if ctx and ctx.state and ctx.state.orig then
        for handle, props in pairs(ctx.state.orig) do
            if handle and handle.Parent then
                handle.Color = props.Color
                handle.Material = props.Material
                
                -- Also clean up any leftover effects
                for _, child in ipairs(handle:GetChildren()) do
                    if (child:IsA("Sparkles") or child:IsA("Fire")) and child.Name == "PickaxeEffect" then
                        child:Destroy()
                    end
                end
            end
        end
    end
end

Registry.register("pickaxeSkin", PickaxeSkin)
return PickaxeSkin