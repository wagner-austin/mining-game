--!strict
-- ClothClient.client.lua
-- Client applier for cloth bone transforms (minimal logs in Studio only)
-- Receives cloth updates via EventBus and applies bone transforms

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local EventBus = require(MiningGame:WaitForChild("EventBus"))
local EventNames = require(MiningGame:WaitForChild("EventNames"))
local Bus = EventBus.global()
local isStudio = RunService:IsStudio()
local function dprint(...)
    if isStudio then print(...) end
end

dprint("[ClothClient] Starting...")

local cloths = {}
local frameCount = 0

local function onClothUpdate(payload)
    local clothId = payload.id
    local offsets = payload.offsets
    if type(clothId) ~= "string" or type(offsets) ~= "table" then
        return
    end

    local entry = cloths[clothId]
    if not entry then
        local model: Instance? = nil
        -- Look anywhere in workspace, not just top-level
        for _, inst in ipairs(workspace:GetDescendants()) do
            local ok, attr = pcall(function()
                return inst:GetAttribute("ClothId")
            end)
            if ok and attr == clothId then
                model = inst:IsA("Model") and inst or inst:FindFirstAncestorOfClass("Model") or inst
                break
            end
        end
        if not model then
            dprint("[ClothClient] Cloth not found:", clothId)
            return
        end

        local mesh = model:IsA("MeshPart") and model or model:FindFirstChildWhichIsA("MeshPart")
        if not mesh then
            dprint("[ClothClient] No mesh in cloth model")
            return
        end

        local bones = {}
        for _, desc in ipairs(mesh:GetDescendants()) do
            if desc:IsA("Bone") then
                local idx = desc:GetAttribute("ClothIdx")
                if typeof(idx) == "number" then
                    bones[idx] = desc
                end
            end
        end

        entry = {
            model = model,
            mesh = mesh,
            bones = bones,
        }
        cloths[clothId] = entry

        dprint(("[ClothClient] Found cloth %s with %d indexed bones"):format(clothId:sub(1, 8), #bones))

        model.AncestryChanged:Connect(function()
            if not model.Parent then
                cloths[clothId] = nil
            end
        end)
    end

    local bones = entry.bones
    frameCount += 1

    if isStudio and (frameCount == 1 or frameCount % 60 == 0) then
        print(string.format("[ClothClient] Frame %d: Applying %d offsets to %s", frameCount, #offsets, clothId:sub(1, 8)))
    end

    for i, offset in ipairs(offsets) do
        local bone = bones[i]
        if bone then
            local x, y, z
            if typeof(offset) == "Vector3" then
                x, y, z = offset.X, offset.Y, offset.Z
            elseif type(offset) == "table" then
                x = offset[1] or offset.x or 0
                y = offset[2] or offset.y or 0
                z = offset[3] or offset.z or 0
            else
                x, y, z = 0, 0, 0
            end

            bone.Transform = CFrame.new(x, y, z)

            if isStudio and frameCount % 60 == 0 then
                if i == 1 then
                    print(string.format("  Bone 1: x=%.2f, y=%.2f, z=%.2f", x, y, z))
                elseif i == #bones then
                    print(string.format("  Bone %d: x=%.2f, y=%.2f, z=%.2f", i, x, y, z))
                end
            end
        end
    end
end

Bus:on(EventNames.CLOTH_UPDATE, onClothUpdate)

dprint("[ClothClient] Ready")
