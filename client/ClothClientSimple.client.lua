--!strict
-- ClothClientSimple.client.lua
-- Receives bone rotations and applies them using indexed bones

local RS = game:GetService("ReplicatedStorage")

local MiningGame = RS:WaitForChild("MiningGame")
local Remotes = require(MiningGame:WaitForChild("Remotes"))
local ClothUpdate = Remotes.RE.ClothUpdate

print("[ClothClientSimple] Starting...")

-- Active cloth instances
local cloths = {}
local frameCount = 0

-- When we get an update from server
ClothUpdate.OnClientEvent:Connect(function(clothId: string, offsets: {any})
    -- Find the cloth model
    local model
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:GetAttribute("ClothId") == clothId then
            model = obj
            break
        end
    end
    
    if not model then
        print("[ClothClientSimple] Cloth not found:", clothId)
        return
    end
    
    -- Find mesh
    local mesh = model:IsA("MeshPart") and model or model:FindFirstChildWhichIsA("MeshPart")
    if not mesh then
        print("[ClothClientSimple] No mesh in cloth model")
        return
    end
    
    -- Get bones if we haven't already (using server's indexing)
    if not cloths[clothId] then
        local bones = {}
        for _, desc in ipairs(mesh:GetDescendants()) do
            if desc:IsA("Bone") then
                local idx = desc:GetAttribute("ClothIdx")
                if typeof(idx) == "number" then
                    bones[idx] = desc
                end
            end
        end
        
        cloths[clothId] = {
            model = model,
            mesh = mesh,
            bones = bones,
        }
        
        print(("[ClothClientSimple] Found cloth %s with %d indexed bones"):format(
            clothId:sub(1,8), #bones))
        
        -- Clean up when destroyed
        model.AncestryChanged:Connect(function()
            if not model.Parent then
                cloths[clothId] = nil
            end
        end)
    end
    
    -- Apply the offsets
    local cloth = cloths[clothId]
    frameCount = frameCount + 1
    
    -- Debug first update and periodically
    if frameCount == 1 or frameCount % 60 == 0 then
        print(string.format("[ClothClientSimple] Frame %d: Applying %d offsets to %s", 
            frameCount, #offsets, clothId:sub(1,8)))
    end
    
    for i, offset in ipairs(offsets) do
        local bone = cloth.bones[i]
        if bone then
            -- Apply the full transform from server
            local x = offset[1] or 0
            local y = offset[2] or 0
            local z = offset[3] or 0
            
            -- Apply full transform to match server
            bone.Transform = CFrame.new(x, y, z)
            
            -- Debug first bone
            if i == 1 and frameCount % 60 == 0 then
                print(string.format("  Bone 1: x=%.2f, y=%.2f, z=%.2f", x, y, z))
            end
        end
    end
end)

print("[ClothClientSimple] Ready")