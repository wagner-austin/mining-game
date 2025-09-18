--!strict
-- HandItemBuilders.lua
-- Procedural builders for right-hand cosmetic items: pickaxe, sword, warhammer

local HandItemBuilders = {}

export type BuildResult = {
    model: Model,
    motor: Motor6D,
    parts: { BasePart },
}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local HandGrip = require(script.Parent.HandGrip)

local function findRightHand(character: Model): BasePart?
    return (character:FindFirstChild("RightHand") :: BasePart?)
        or (character:FindFirstChild("Right Arm") :: BasePart?)
        or (character:FindFirstChild("RightLowerArm") :: BasePart?)
        or (character:FindFirstChild("UpperTorso") :: BasePart?)
        or (character:FindFirstChild("Torso") :: BasePart?)
end

local function resolveMaterial(def: any): Enum.Material
    local m = def and (def.material or def.materialPreset)
    if typeof(m) == "EnumItem" and tostring(m.EnumType) == "Enum.Material" then
        return m
    end
    if type(m) == "string" then
        local key = string.lower(m)
        if key == "neon" then return Enum.Material.Neon end
        if key == "glass" then return Enum.Material.Glass end
        if key == "metal" then return Enum.Material.Metal end
        if key == "plastic" then return Enum.Material.Plastic end
        if key == "smoothplastic" then return Enum.Material.SmoothPlastic end
        if key == "forcefield" then return Enum.Material.ForceField end
        if key == "ice" then return Enum.Material.Ice end
        if key == "wood" then return Enum.Material.Wood end
    end
    return Enum.Material.Metal
end

local function resolveColor(def: any, fallback: Color3): Color3
    if def and typeof(def.tint) == "Color3" then return def.tint end
    if def and typeof(def.color) == "Color3" then return def.color end
    return fallback
end

-- PICKAXE (handle along +X; head arms along Z)
local function buildPickaxe(character: Model, def: any): BuildResult?
    local hand = findRightHand(character)
    if not hand then return nil end

    local model = Instance.new("Model")
    model.Name = "CosmeticHandItem"
    model.Parent = character

    local handleLen = tonumber(def and def.handleLength) or 3.6
    local handleRad = tonumber(def and def.handleRadius) or 0.18
    -- New block head dims (bigger head)
    local headLen = tonumber(def and def.headLength) or 2.4
    local headWidth = tonumber(def and def.headWidth) or 2.6
    local headHeight = tonumber(def and def.headHeight) or 1.8

    local mat = resolveMaterial(def)
    local handleMat = (def and def.handleMaterial) or mat or Enum.Material.Wood
    local headMat = (def and def.headMaterial) or mat or Enum.Material.Metal
    local handleColor = (def and def.handleTint) or Color3.fromRGB(130, 90, 50)
    local headColor = (def and def.headTint) or Color3.fromRGB(150, 150, 155)

    local handle = Instance.new("Part")
    handle.Name = "Handle"
    handle.Size = Vector3.new(handleLen, handleRad * 2, handleRad * 2)
    handle.CanCollide = false
    handle.CanQuery = false
    handle.CanTouch = false
    handle.Massless = true
    handle.Anchored = false
    handle.Material = handleMat
    handle.Color = handleColor
    -- Prism (block) handle rather than cylinder
    handle.Shape = Enum.PartType.Block
    handle.Parent = model

    local halfLen = handleLen * 0.5

    -- Single rectangular head centered; handle slightly protrudes through far face
    local head = Instance.new("Part")
    head.Name = "Head"
    head.Size = Vector3.new(headWidth, headHeight, headLen)
    head.CanCollide = false
    head.CanQuery = false
    head.CanTouch = false
    head.Massless = true
    head.Anchored = false
    head.Material = headMat
    head.Color = headColor
    head.Parent = model
    do
        local MountUtils = require(script.Parent.MountUtils)
        MountUtils.mountEndByTip(handle, head, 0.02)
        -- Offset the mount along the head's long axis (Z) so the handle does not
        -- intersect the head at its center — more like a scythe/pick profile.
        local zOffset = tonumber(def and def.headAttachOffsetZ) or -(headLen * 0.30)
        head.CFrame = head.CFrame * CFrame.new(0, 0, zOffset)
        MountUtils.weld(handle, head)
    end

    model.PrimaryPart = handle

    local motor = HandGrip.attachXToUp(hand, handle, handleLen, {
        gripOffset = def and def.gripOffset or 0.25,
        gripHandOffsetY = def and def.gripHandOffsetY or -0.15,
        gripTiltDeg = def and def.gripTiltDeg or -70,
        gripYawDeg = def and def.gripYawDeg or 0,
        gripRollDeg = def and def.gripRollDeg or 0,
    })

    return { model = model, motor = motor, parts = { handle, head } }
end

-- SWORD (handle along +X; blade extends +X; guard near tip)
local function buildSword(character: Model, def: any): BuildResult?
    local hand = findRightHand(character)
    if not hand then return nil end

    local model = Instance.new("Model")
    model.Name = "CosmeticHandItem"
    model.Parent = character

    local handleLen = tonumber(def and def.handleLength) or 2.2
    local handleRad = tonumber(def and def.handleRadius) or 0.18
    -- Much bigger blade
    local bladeLen = tonumber(def and def.bladeLength) or 5.5
    local bladeWidth = tonumber(def and def.bladeWidth) or 1.8
    local bladeThick = tonumber(def and def.bladeThickness) or 0.32
    -- Smaller ring radius, thicker rings
    local guardRingRadius = tonumber(def and def.guardRingRadius) or 0.45
    local guardRingThickness = tonumber(def and def.guardRingThickness) or 0.14
    local guardRingSegments = tonumber(def and def.guardRingSegments) or 12

    local mat = Enum.Material.Neon
    local baseColor = resolveColor(def, Color3.fromRGB(255, 255, 255))
    local bladeColor = resolveColor(def, Color3.fromRGB(200, 200, 210))

    local handle = Instance.new("Part")
    handle.Name = "Handle"
    handle.Size = Vector3.new(handleLen, handleRad * 2, handleRad * 2)
    handle.CanCollide = false
    handle.CanQuery = false
    handle.CanTouch = false
    handle.Massless = true
    handle.Anchored = false
    handle.Material = mat
    handle.Color = baseColor
    -- Rectangular handle (block)
    handle.Shape = Enum.PartType.Block
    handle.Parent = model

    local blade = Instance.new("Part")
    blade.Name = "Blade"
    -- Orient so Y = bladeWidth (vertical span), Z = bladeThick (edge thickness)
    blade.Size = Vector3.new(bladeLen, bladeWidth, bladeThick)
    blade.CanCollide = false
    blade.CanQuery = false
    blade.CanTouch = false
    blade.Massless = true
    blade.Anchored = false
    blade.Material = mat
    blade.Color = bladeColor
    blade.Parent = model

    local MountUtils = require(script.Parent.MountUtils)
    local GuardBuilder = require(script.Parent.GuardBuilder)

    local halfLen = handleLen * 0.5
    local eps = 0.002
    local guardCenter = handle.CFrame * CFrame.new(halfLen - 0.25, 0, 0)
    -- Use baseColor here; runtime renderer applies darker neon pulse
    local ring1 = GuardBuilder.makeGuard(model, guardCenter * CFrame.new(0, 0.06, 0), guardRingRadius * 1.2, guardRingThickness, baseColor, {segments = guardRingSegments, name = "GuardRingSeg1", axis = "X"})
    local ring2 = GuardBuilder.makeGuard(model, guardCenter * CFrame.new(0, -0.06, 0), guardRingRadius * 0.8, guardRingThickness, baseColor, {segments = guardRingSegments, name = "GuardRingSeg2", axis = "X"})
    -- Weld guard segments to the handle so they follow the hand
    for _, seg in ipairs(ring1) do require(script.Parent.MountUtils).weld(handle, seg) end
    for _, seg in ipairs(ring2) do require(script.Parent.MountUtils).weld(handle, seg) end

    -- No single guard part; rings are welded above

    model.PrimaryPart = handle

    local motor = HandGrip.attachXToUp(hand, handle, handleLen, {
        gripOffset = def and def.gripOffset or 0.25,
        gripHandOffsetY = def and def.gripHandOffsetY or -0.15,
        gripTiltDeg = def and def.gripTiltDeg or -85,
        gripYawDeg = def and def.gripYawDeg or 0,
        gripRollDeg = def and def.gripRollDeg or 0,
    })

    -- Now that the motor has oriented the handle, attach blade by its TOP EDGE to the TOP of the handle end face
    do
        MountUtils.mountEndTopEdge(handle, blade, { axis = "Z", rollQuarter = 1, inset = 0.02 })
        MountUtils.weld(handle, blade)
    end

    local parts: {BasePart} = { handle, blade }
    for _, p in ipairs(ring1) do table.insert(parts, p) end
    for _, p in ipairs(ring2) do table.insert(parts, p) end
    return { model = model, motor = motor, parts = parts }
end

-- WARHAMMER (handle along +X; head at +X tip)
local function buildWarhammer(character: Model, def: any): BuildResult?
    local hand = findRightHand(character)
    if not hand then return nil end

    local model = Instance.new("Model")
    model.Name = "CosmeticHandItem"
    model.Parent = character

    local handleLen = tonumber(def and def.handleLength) or 3.2
    local handleRad = tonumber(def and def.handleRadius) or 0.22
    local headLen = tonumber(def and def.headLength) or 1.2
    local headWidth = tonumber(def and def.headWidth) or 1.0
    local headHeight = tonumber(def and def.headHeight) or 0.9
    local gripHandOffsetY = tonumber(def and def.gripHandOffsetY) or -0.15

    local mat = resolveMaterial(def)
    local handleMat = (def and def.handleMaterial) or mat
    local headMat = (def and def.headMaterial) or mat
    local handleColor = (def and def.handleTint) or resolveColor(def, Color3.fromRGB(100, 80, 60))
    local headColor = (def and def.headTint) or resolveColor(def, Color3.fromRGB(160, 160, 160))

    local handle = Instance.new("Part")
    handle.Name = "Handle"
    handle.Size = Vector3.new(handleLen, handleRad * 2, handleRad * 2)
    handle.CanCollide = false
    handle.CanQuery = false
    handle.CanTouch = false
    handle.Massless = true
    handle.Anchored = false
    handle.Material = handleMat
    handle.Color = handleColor
    handle.Shape = Enum.PartType.Cylinder
    handle.Parent = model

    local head = Instance.new("Part")
    head.Name = "Head"
    head.Size = Vector3.new(headWidth, headHeight, headLen)
    head.CanCollide = false
    head.CanQuery = false
    head.CanTouch = false
    head.Massless = true
    head.Anchored = false
    head.Material = headMat
    head.Color = headColor
    head.Parent = model

    local halfLen = handleLen * 0.5
    local MountUtils = require(script.Parent.MountUtils)
    -- Match original look: handle tip barely protrudes beyond head's far face
    MountUtils.mountEndByTip(handle, head, 0.02)
    local weld = MountUtils.weld(handle, head)

    model.PrimaryPart = handle

    local motor = HandGrip.attachXToUp(hand, handle, handleLen, {
        gripOffset = def and def.gripOffset or 0.25,
        gripHandOffsetY = gripHandOffsetY,
        gripTiltDeg = def and def.gripTiltDeg or -85,
        gripYawDeg = def and def.gripYawDeg or 0,
        gripRollDeg = def and def.gripRollDeg or 0,
    })

    return { model = model, motor = motor, parts = { handle, head } }
end

function HandItemBuilders.build(character: Model, def: any): BuildResult?
    local kind = def and def.procedural and def.procedural.kind or def and def.kind or "pickaxe"
    if kind == "pickaxe" then return buildPickaxe(character, def) end
    if kind == "sword" then return buildSword(character, def) end
    if kind == "warhammer" then return buildWarhammer(character, def) end
    return buildPickaxe(character, def)
end

function HandItemBuilders.destroy(ctx: BuildResult?)
    if not ctx then return end
    if ctx.motor and ctx.motor.Parent then ctx.motor:Destroy() end
    if ctx.model and ctx.model.Parent then ctx.model:Destroy() end
end

return HandItemBuilders
