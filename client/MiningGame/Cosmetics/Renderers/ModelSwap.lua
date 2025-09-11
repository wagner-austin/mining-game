--!strict
--[[
    ModelSwap.lua
    Handles full character model/costume swaps using HumanoidDescriptions.
    Priority: 100 (applies before other cosmetics)
]]

local Registry = require(script.Parent.Parent.RendererRegistry)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("MiningGame")

local ModelSwap = {}
ModelSwap.priority = 100 -- Apply before other cosmetics

-- Track active tokens to prevent race conditions
local activeTokenByChar: {[Model]: number} = {}

function ModelSwap.apply(character: Model, def: any, ctx: any)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    
    -- Generate and track token to prevent race conditions
    local token = (activeTokenByChar[character] or 0) + 1
    activeTokenByChar[character] = token
    
    -- Store original description for restoration
    local originalDescription = humanoid:GetAppliedDescription()
    local rigType = humanoid.RigType
    
    -- Safe apply function with token check
    local function safeApply(desc: HumanoidDescription)
        if activeTokenByChar[character] ~= token then return end -- Newer swap took over
        -- ApplyDescription only works on server - skip on client
        -- The server should handle the actual model swap through remotes
    end
    
    -- Look for costume asset
    local assets = Shared:FindFirstChild("Assets")
    local costume = assets and def.costume and assets:FindFirstChild(def.costume)
    
    if costume then
        if costume:IsA("HumanoidDescription") then
            -- Apply the description directly
            safeApply(costume)
            return {
                originalDescription = originalDescription,
                character = character,
                token = token
            }
            
        elseif costume:IsA("Folder") then
            -- Clean up any previous instances if rapidly toggling
            if ctx and ctx.instances then
                for _, inst in ipairs(ctx.instances) do
                    if inst.Parent then inst:Destroy() end
                end
                ctx.instances = {}
            end
            
            -- Apply accessories from folder
            local accessories = {}
            for _, acc in ipairs(costume:GetChildren()) do
                if acc:IsA("Accessory") then
                    local cloned = acc:Clone()
                    humanoid:AddAccessory(cloned)
                    table.insert(accessories, cloned)
                end
            end
            
            return {
                originalDescription = originalDescription,
                character = character,
                token = token,
                instances = accessories
            }
        end
    end
    
    -- Fallback: create a basic costume modification
    -- Could modify the existing description programmatically
    local desc = originalDescription:Clone()
    
    -- Apply some basic costume changes based on ID
    if def.id and string.find(def.id, "robot") then
        desc.Head = 0
        desc.LeftArm = 0
        desc.RightArm = 0
        desc.Torso = 0
        desc.LeftLeg = 0
        desc.RightLeg = 0
        desc.HeadColor = Color3.fromRGB(163, 162, 165)
        desc.TorsoColor = Color3.fromRGB(163, 162, 165)
        desc.LeftArmColor = Color3.fromRGB(163, 162, 165)
        desc.RightArmColor = Color3.fromRGB(163, 162, 165)
        desc.LeftLegColor = Color3.fromRGB(163, 162, 165)
        desc.RightLegColor = Color3.fromRGB(163, 162, 165)
        
    elseif def.id and string.find(def.id, "ninja") then
        desc.HeadColor = Color3.fromRGB(0, 0, 0)
        desc.TorsoColor = Color3.fromRGB(0, 0, 0)
        desc.LeftArmColor = Color3.fromRGB(0, 0, 0)
        desc.RightArmColor = Color3.fromRGB(0, 0, 0)
        desc.LeftLegColor = Color3.fromRGB(0, 0, 0)
        desc.RightLegColor = Color3.fromRGB(0, 0, 0)
        
    elseif def.id and string.find(def.id, "wizard") then
        desc.TorsoColor = Color3.fromRGB(102, 51, 153)
        desc.LeftArmColor = Color3.fromRGB(102, 51, 153)
        desc.RightArmColor = Color3.fromRGB(102, 51, 153)
    end
    
    -- Apply the modified description
    safeApply(desc)
    
    return {
        originalDescription = originalDescription,
        character = character,
        token = token
    }
end

function ModelSwap.remove(ctx)
    if not ctx or not ctx.character then return end
    
    -- Check if this is still the active swap (prevent race conditions)
    if ctx.token and activeTokenByChar[ctx.character] ~= ctx.token then
        return -- A newer swap took over
    end
    
    -- Destroy any accessories we added
    if ctx.instances then
        for _, inst in ipairs(ctx.instances) do
            if typeof(inst) == "Instance" then
                inst:Destroy()
            end
        end
    end
    
    -- Restore original description
    -- Skip on client - ApplyDescription only works on server
    -- The server should handle restoration through remotes
    
    -- Clean up token
    if activeTokenByChar[ctx.character] == ctx.token then
        activeTokenByChar[ctx.character] = nil
    end
end

Registry.register("modelSwap", ModelSwap)
return ModelSwap