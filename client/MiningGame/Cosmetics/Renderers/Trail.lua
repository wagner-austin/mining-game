--!strict
--[[
    Trail.lua
    Handles trail effects that follow player movement.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(Shared:WaitForChild("Logger"))
local log = Logger.new("Trail")
local Time = require(Shared:WaitForChild("Time"))
local Registry = require(script.Parent.Parent.RendererRegistry)

local Trail = {}
Trail.priority = 35 -- Apply after auras

function Trail.apply(character: Model, def: any, ctx: any)
    local root = character:FindFirstChild("HumanoidRootPart")
    if not root then return end
    
    -- Debug logging (tamed via Logger levels)
    log:info("Applying trail cosmetic: %s", def.itemId or "unknown")
    log:debug("Color: %s", tostring(def.color))
    log:debug("Effect: %s", tostring(def.effect))
    
    -- Use HumanoidRootPart size as base, NOT GetExtentsSize which includes all accessories
    local rootSize = root.Size
    local halfWidth = math.clamp(rootSize.X * 0.5, 0.8, 2.0)  -- Typically 1 stud for normal avatars
    
    -- Support multiple parallel bands via bandCount (e.g., double trail)
    local bandCount = math.max(1, tonumber(def.bandCount) or 1)
    local sep = tonumber(def.bandSeparation) or 0.3 -- separation in studs along chosen axis
    local bandOffsetScalar = tonumber(def.bandOffset) or 0.0
    local axisName = tostring(def.bandAxis or "up"):lower()
    local axisVec
    if axisName == "up" or axisName == "y" then
        axisVec = Vector3.new(0, 1, 0)
    elseif axisName == "down" then
        axisVec = Vector3.new(0, -1, 0)
    elseif axisName == "forward" or axisName == "front" or axisName == "z-" then
        axisVec = Vector3.new(0, 0, -1)
    elseif axisName == "back" or axisName == "backward" or axisName == "z+" then
        axisVec = Vector3.new(0, 0, 1)
    elseif axisName == "right" or axisName == "x+" then
        axisVec = Vector3.new(1, 0, 0)
    elseif axisName == "left" or axisName == "x-" then
        axisVec = Vector3.new(-1, 0, 0)
    else
        axisVec = Vector3.new(0, 1, 0)
    end

    local attachments = {}
    local trails = {}
    for i = 1, bandCount do
        local idx = (i - ((bandCount + 1) / 2))
        local centerOffset = axisVec * (idx * sep + bandOffsetScalar)

        local a0 = Instance.new("Attachment")
        a0.Name = string.format("TrailA0_%d", i)
        a0.Position = Vector3.new(-halfWidth, 0, 0) + centerOffset
        a0.Parent = root

        local a1 = Instance.new("Attachment")
        a1.Name = string.format("TrailA1_%d", i)
        a1.Position = Vector3.new(halfWidth, 0, 0) + centerOffset
        a1.Parent = root

        local tr = Instance.new("Trail")
        tr.Name = (bandCount == 1) and "CosmeticTrail" or string.format("CosmeticTrail_%d", i)
        tr.Attachment0 = a0
        tr.Attachment1 = a1
        tr.Parent = root

        table.insert(attachments, a0)
        table.insert(attachments, a1)
        table.insert(trails, tr)
    end

    -- Helpers
    local function toNumberSequence(val): NumberSequence?
        if typeof(val) == "NumberSequence" then return val end
        if typeof(val) == "NumberRange" then
            local nr: NumberRange = val
            return NumberSequence.new({
                NumberSequenceKeypoint.new(0, nr.Min),
                NumberSequenceKeypoint.new(1, nr.Max),
            })
        end
        if type(val) == "table" then
            local keys = {}
            if #val > 0 then
                if type(val[1]) == "number" then
                    local n = #val
                    for i, v in ipairs(val) do
                        local t = (n > 1) and ((i-1)/(n-1)) or 0
                        table.insert(keys, NumberSequenceKeypoint.new(math.clamp(t, 0, 1), tonumber(v) or 0))
                    end
                elseif type(val[1]) == "table" then
                    for _, kp in ipairs(val) do
                        local t = tonumber(kp.t or kp.time or kp.key or kp[1])
                        local v = tonumber(kp.value or kp.v or kp[2])
                        if t ~= nil and v ~= nil then
                            table.insert(keys, NumberSequenceKeypoint.new(math.clamp(t, 0, 1), v))
                        end
                    end
                end
            else
                for k, v in pairs(val) do
                    local t = tonumber(k)
                    if t ~= nil then
                        table.insert(keys, NumberSequenceKeypoint.new(math.clamp(t, 0, 1), tonumber(v) or 0))
                    end
                end
            end
            table.sort(keys, function(a, b) return a.Time < b.Time end)
            if #keys >= 1 then return NumberSequence.new(keys) end
        end
        if type(val) == "number" then
            return NumberSequence.new(val)
        end
        return nil
    end
    local function toColorSequence(val): ColorSequence?
        if typeof(val) == "ColorSequence" then return val end
        if type(val) == "table" then
            local keys = {}
            if #val > 0 then
                if typeof(val[1]) == "Color3" then
                    local n = #val
                    for i, c in ipairs(val) do
                        local t = (n > 1) and ((i-1)/(n-1)) or 0
                        table.insert(keys, ColorSequenceKeypoint.new(math.clamp(t, 0, 1), c))
                    end
                elseif type(val[1]) == "table" then
                    for _, kp in ipairs(val) do
                        local t = tonumber(kp.t or kp.time or kp.key or kp[1])
                        local c = kp.color or kp.c or kp[2]
                        if t ~= nil and typeof(c) == "Color3" then
                            table.insert(keys, ColorSequenceKeypoint.new(math.clamp(t, 0, 1), c))
                        end
                    end
                end
            else
                for k, c in pairs(val) do
                    local t = tonumber(k)
                    if t ~= nil and typeof(c) == "Color3" then
                        table.insert(keys, ColorSequenceKeypoint.new(math.clamp(t, 0, 1), c))
                    end
                end
            end
            table.sort(keys, function(a, b) return a.Time < b.Time end)
            if #keys >= 1 then return ColorSequence.new(keys) end
        end
        return nil
    end

    -- Base tunables (apply to all bands)
    for _, tr in ipairs(trails) do
        tr.Lifetime = def.lifetime or 1
        tr.MinLength = def.minLength or 0
        tr.FaceCamera = (def.faceCamera ~= false)
        tr.LightEmission = def.lightEmission or 0.5
    end

    -- Don't set Width0/Width1 - let it use attachment spacing

    -- Width scale (tapering) - overridable
    local widthSeq = toNumberSequence(def.widthScaleSequence) or NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(1, 0)
    })
    for _, tr in ipairs(trails) do
        tr.WidthScale = widthSeq
    end

    for _, tr in ipairs(trails) do
        if def.texture then tr.Texture = def.texture end
        if def.textureLength then tr.TextureLength = def.textureLength end
        if def.textureMode then tr.TextureMode = def.textureMode end
    end

    local conn = nil
    if def.effect == "rainbow" then
        local last = 0
        conn = RunService.Heartbeat:Connect(function(dt)
            last = last + dt
            if last < 0.1 then return end
            last = 0
            local hue = (Time.mono() * 0.5) % 1
            local cs = ColorSequence.new(Color3.fromHSV(hue, 1, 1))
            for _, tr in ipairs(trails) do
                tr.Color = cs
            end
        end)
    else
        local cs
        if def.colorSequence then
            cs = toColorSequence(def.colorSequence)
        elseif typeof(def.color) == "Color3" then
            cs = ColorSequence.new(def.color)
        end
        local ts
        if def.transparencySequence then
            ts = toNumberSequence(def.transparencySequence)
        end
        for _, tr in ipairs(trails) do
            if cs then tr.Color = cs end
            if ts then tr.Transparency = ts end
        end
    end

    local inst = {}
    for _, a in ipairs(attachments) do table.insert(inst, a) end
    for _, t in ipairs(trails) do table.insert(inst, t) end
    return {instances = inst, connections = {conn}}
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