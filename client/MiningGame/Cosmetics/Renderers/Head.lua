--!strict
--[[
    Head.lua
    Handles head accessories like crowns, halos, helmets, etc.
]]

local Registry = require(script.Parent.Parent.RendererRegistry)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(Shared:WaitForChild("Logger"))
local log = Logger.new("CosmeticHead")
local HeadBuilders = require(script.Parent.Parent.Procedural.HeadBuilders)

local Head = {}
Head.priority = 45 -- Apply after back items

function Head.apply(character: Model, def: any, ctx: any)
    log:info("Apply head cosmetic: id=%s asset=%s for %s", tostring(def and def.id), tostring(def and def.asset), character.Name)
    local head = character:FindFirstChild("Head")
    if not head then
        log:warn("No Head found on character %s", character.Name)
        return
    end

    -- Explicit procedural path (bypass asset lookup when specified)
    if def and def.procedural and def.procedural.kind == "horns" or (def and def.shape == "horns") then
        local ctx2 = HeadBuilders.horns(character, head :: BasePart, def)
        if ctx2 then return ctx2 end
    elseif def and def.procedural and def.procedural.kind == "halo" or (def and def.shape == "halo") then
        local ctx2 = HeadBuilders.halo(character, head :: BasePart, def)
        if ctx2 then return ctx2 end
    elseif def and def.procedural and def.procedural.kind == "crown" or (def and def.shape == "crown") then
        local ctx2 = HeadBuilders.crown(character, head :: BasePart, def)
        if ctx2 then return ctx2 end
    elseif def and def.procedural and def.procedural.kind == "charm" or (def and def.shape == "charm") then
        local ctx2 = HeadBuilders.charm(character, head :: BasePart, def)
        if ctx2 then return ctx2 end
    elseif def and def.procedural and def.procedural.kind == "sunglasses" or (def and def.shape == "sunglasses") then
        local ctx2 = HeadBuilders.sunglasses(character, head :: BasePart, def)
        if ctx2 then return ctx2 end
    end
    
    local assets = nil -- Assets disabled; procedural-only cosmetics
    if false then
        local acc = assets:FindFirstChild(def.asset)
        if not acc then
            log:warn("Asset '%s' not found under %s. Available: %s", tostring(def.asset), assets:GetFullName(), table.concat((function()
                local names = {}
                for _, c in ipairs(assets:GetChildren()) do table.insert(names, c.Name .. "(" .. c.ClassName .. ")") end
                table.sort(names)
                return names
            end)(), ", "))
        end
        if acc then
            acc = acc:Clone()
            acc.Name = "CosmeticHead"

            -- Helpers
            local function normalizeAssetId(s: string?): string?
                if not s or s == "" then return s end
                local id = s:match("rbxassetid://(%d+)") or s:match("id=(%d+)") or s:match("/(%d+)$")
                if id then return "rbxassetid://" .. id end
                return s
            end

            local function ensureAttachedToHead(accessory: Instance, headPart: BasePart, offset: CFrame?, rot: CFrame?)
                local handle = accessory:FindFirstChildWhichIsA("BasePart")
                if not handle then return end
                -- If engine did not create an AccessoryWeld and no HatAttachment pairing, weld manually
                local hasWeld = handle:FindFirstChild("AccessoryWeld") or handle:FindFirstChildWhichIsA("Weld")
                local headAttach = headPart:FindFirstChild("HatAttachment")
                local hatAttach = handle:FindFirstChild("HatAttachment")
                if not hasWeld then
                    if headAttach and hatAttach and headAttach:IsA("Attachment") and hatAttach:IsA("Attachment") then
                        handle.CFrame = headPart.CFrame * (headAttach :: Attachment).CFrame * ((hatAttach :: Attachment).CFrame:Inverse())
                    else
                        handle.CFrame = headPart.CFrame * (offset or CFrame.new(0, 0.5, 0))
                    end
                    if rot then
                        handle.CFrame = handle.CFrame * rot
                    end
                    local weld = Instance.new("WeldConstraint")
                    weld.Part0 = headPart
                    weld.Part1 = handle
                    weld.Parent = accessory
                    log:debug("Manually welded accessory '%s' to head", accessory.Name)
                end
                handle.CanCollide = false
                handle.CanQuery = false
                handle.CanTouch = false
                handle.Massless = true
            end
            
            -- Handle Accessory type
            if acc:IsA("Accessory") or acc.ClassName == "Hat" then
                local hum = character:FindFirstChildOfClass("Humanoid")
                if not hum then
                    log:warn("Humanoid not found on %s; cannot AddAccessory", character.Name)
                    return
                end
                acc.Name = ("CosmeticHead_%s"):format(def.id or "item")
                -- Optional scaling for accessory/hat via SpecialMesh or MeshPart + normalize MeshId
                local desiredScale = tonumber(def and def.scale) or 1
                if desiredScale and desiredScale ~= 1 then
                    local handle = acc:FindFirstChildWhichIsA("BasePart")
                    if handle then
                        local sm = handle:FindFirstChildOfClass("SpecialMesh")
                        if sm then
                            local norm = normalizeAssetId(sm.MeshId)
                            if norm and norm ~= sm.MeshId then sm.MeshId = norm end
                            sm.Scale = sm.Scale * desiredScale
                            log:debug("Scaled SpecialMesh for %s by %.2f", acc.Name, desiredScale)
                        elseif handle:IsA("MeshPart") then
                            local mp = handle :: MeshPart
                            local norm = normalizeAssetId(mp.MeshId)
                            if norm and norm ~= mp.MeshId then mp.MeshId = norm end
                            handle.Size = handle.Size * desiredScale
                            log:debug("Scaled MeshPart for %s by %.2f", acc.Name, desiredScale)
                        end
                    end
                end
                local ok, err = pcall(function()
                    hum:AddAccessory(acc)
                end)
                if not ok then
                    log:warn("AddAccessory failed for %s: %s", tostring(def.id), tostring(err))
                else
                    log:info("Accessory applied: %s", acc.Name)
                    -- Optional fine offset for accessory/hat after attach (adjust AccessoryWeld)
                    local handle = acc:FindFirstChildWhichIsA("BasePart")
                    if handle and def then
                        local weld = handle:FindFirstChild("AccessoryWeld") or handle:FindFirstChildWhichIsA("Weld")
                        if weld and weld:IsA("Weld") then
                            if def.offsetCFrame then
                                (weld :: Weld).C1 = (weld :: Weld).C1 * (def.offsetCFrame :: any)
                                log:debug("Applied accessory offset for %s", acc.Name)
                            end
                            if def.rotOffset then
                                (weld :: Weld).C1 = (weld :: Weld).C1 * (def.rotOffset :: any)
                                log:debug("Applied accessory rotation for %s", acc.Name)
                            end
                        end
                    end
                    -- Ensure attached (older/newer formats may not auto-weld)
                    ensureAttachedToHead(acc, head :: BasePart, def and def.offsetCFrame, def and def.rotOffset)
                    -- Studio-only debug highlight to verify location/extent
                    local RunService = game:GetService("RunService")
                    if RunService:IsStudio() then
                        local sb = Instance.new("SelectionBox")
                        sb.LineThickness = 0.02
                        sb.Adornee = handle
                        sb.Parent = handle
                        task.delay(0.7, function()
                            if sb then sb:Destroy() end
                        end)
                        -- Quick diagnostics + invisible detection
                        if handle then
                            local size = handle.Size
                            log:debug("Handle size: (%.2f, %.2f, %.2f) trans=%.2f", size.X, size.Y, size.Z, handle.Transparency)
                            local ha = handle:FindFirstChild("HatAttachment")
                            local fa = handle:FindFirstChild("FaceFrontAttachment")
                            local hairA = handle:FindFirstChild("HairAttachment")
                            local acw = handle:FindFirstChild("AccessoryWeld")
                            log:debug("Attachments: Hat=%s FaceFront=%s Hair=%s Weld=%s", tostring(ha ~= nil), tostring(fa ~= nil), tostring(hairA ~= nil), tostring(acw ~= nil))

                            local sm = handle:FindFirstChildOfClass("SpecialMesh")
                            if sm then
                                local s = sm.Scale
                                log:debug("SpecialMesh: MeshId=%s TextureId=%s Scale=(%.2f,%.2f,%.2f)", tostring(sm.MeshId), tostring(sm.TextureId), s.X, s.Y, s.Z)
                            elseif handle:IsA("MeshPart") then
                                local mp = handle :: MeshPart
                                log:debug("MeshPart: MeshId=%s TextureID=%s Size=(%.2f,%.2f,%.2f) Trans=%.2f", tostring(mp.MeshId), tostring(mp.TextureID), mp.Size.X, mp.Size.Y, mp.Size.Z, mp.Transparency)
                            end

                            local function isLikelyInvisible(h: BasePart): boolean
                                local transparent = (h.Transparency or 0) >= 0.99
                                local sm2 = h:FindFirstChildOfClass("SpecialMesh")
                                local meshPart = h:IsA("MeshPart") and h or nil
                                local hasMeshId = false
                                if sm2 and sm2.MeshId and sm2.MeshId ~= "" and sm2.MeshId ~= "rbxassetid://0" then
                                    hasMeshId = true
                                end
                                if meshPart then
                                    if (meshPart.Transparency or 0) < 0.99 then return false end
                                end
                                if transparent and not hasMeshId and not meshPart then
                                    return true
                                end
                                return false
                            end

                            if isLikelyInvisible(handle) then
                                log:warn("Accessory appears invisible — adding debug shell (mesh missing/transparent)")
                                local dbg = Instance.new("Part")
                                dbg.Name = "CosmeticHeadDebugShell"
                                dbg.Size = head.Size * 1.3
                                dbg.Color = Color3.fromRGB(255, 200, 0)
                                dbg.Material = Enum.Material.Neon
                                dbg.Anchored = false
                                dbg.CanCollide = false
                                dbg.CanTouch = false
                                dbg.CanQuery = false
                                dbg.Transparency = 0.5
                                dbg.Parent = character
                                dbg.CFrame = head.CFrame * CFrame.new(0, 0.15, 0)
                                local weld2 = Instance.new("WeldConstraint")
                                weld2.Part0 = head
                                weld2.Part1 = dbg
                                weld2.Parent = dbg
                                task.delay(1.2, function()
                                    if dbg then dbg:Destroy() end
                                end)
                            end
                        end
                    end
                end
                return {instances = {acc}}
            else
                -- Generic model/part
                acc.Parent = character
                local base
                if acc:IsA("Model") then
                    base = acc.PrimaryPart or acc:FindFirstChildWhichIsA("BasePart")
                else
                    -- Handle legacy Hat/classic container: find a BasePart (usually Handle)
                    base = acc:FindFirstChildWhichIsA("BasePart")
                end
                if not base then
                    log:warn("No BasePart/PrimaryPart in asset '%s'", acc.Name)
                    acc:Destroy()
                    return
                end
                -- Apply scaling for model-style assets
                local desiredScale = tonumber(def and def.scale) or 1
                if desiredScale and desiredScale ~= 1 then
                    for _, desc in ipairs(acc:GetDescendants()) do
                        if desc:IsA("SpecialMesh") then
                            desc.Scale = desc.Scale * desiredScale
                        elseif desc:IsA("MeshPart") then
                            desc.Size = desc.Size * desiredScale
                        end
                    end
                    log:debug("Scaled model '%s' by %.2f", acc.Name, desiredScale)
                end
                -- Prefer attachment alignment when possible (reduces clipping)
                local handle = (acc:IsA("Model") and acc:FindFirstChild("Handle")) and (acc :: any).Handle
                    or base
                local headAttach = head:FindFirstChild("HatAttachment")
                local hatAttach = handle and handle:FindFirstChild("HatAttachment")
                if handle and headAttach and hatAttach and headAttach:IsA("Attachment") and hatAttach:IsA("Attachment") then
                    -- Align handle so its HatAttachment matches the head's HatAttachment
                    handle.CFrame = head.CFrame * (headAttach :: Attachment).CFrame * ((hatAttach :: Attachment).CFrame:Inverse())
                    log:debug("Aligned '%s' via HatAttachment -> %s", acc.Name, (handle :: BasePart).Name)
                else
                    -- Position first (before welding)
                    local offset = def.offsetCFrame or (
                        (def.id and string.find(def.id, "halo")) and CFrame.new(0, 1.5, 0)
                        or (def.id and string.find(def.id, "crown")) and CFrame.new(0, 0.8, 0)
                        or CFrame.new(0, 0.5, 0)
                    )
                    base.CFrame = head.CFrame * offset
                    log:debug("Aligned '%s' via generic offset", acc.Name)
                end
                
                -- Then weld
                local weld = Instance.new("WeldConstraint")
                weld.Part0 = head
                weld.Part1 = base
                weld.Parent = acc
                log:debug("Welded model '%s' to head (base=%s)", acc.Name, base.Name)
                
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
    elseif not assets then
        log:warn("Assets folder missing under ReplicatedStorage.MiningGame")
    end
    
    -- Fallback placeholder accessories
    log:debug("Using placeholder for head cosmetic id=%s", tostring(def and def.id))
    local part = Instance.new("Part")
    part.Name = ("CosmeticHead_%s"):format(def.id or "item")
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.Massless = true
    part.Parent = character
    
    -- Style based on type
    if def.id and string.find(def.id, "crown") then
        local ctx2 = HeadBuilders.crown(character, head :: BasePart, def)
        part:Destroy()
        return ctx2
    elseif def.id and string.find(def.id, "halo") then
        local ctx2 = HeadBuilders.halo(character, head :: BasePart, def)
        part:Destroy()
        return ctx2
        
    elseif def.id and string.find(def.id, "horns") then
        -- Use procedural horns builder for id-matched horns
        local ctx2 = HeadBuilders.horns(character, head :: BasePart, def)
        part:Destroy()
        return ctx2
        
    elseif def.id and string.find(def.id, "glasses") then
        local ctx2 = HeadBuilders.sunglasses(character, head :: BasePart, def)
        part:Destroy()
        return ctx2
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
    log:debug("Placeholder welded for head cosmetic id=%s", tostring(def and def.id))
    
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
    log:debug("Removing head cosmetic context")
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

Registry.register("head", Head)
return Head
