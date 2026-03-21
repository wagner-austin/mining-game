--!strict
-- HandItemBuilders.lua
-- Procedural builders for right-hand cosmetic items: pickaxe, sword, warhammer

local HandItemBuilders = {}

local RegistryTypes = require(script.Parent.Parent.RendererRegistry)
type CosmeticDef = RegistryTypes.CosmeticDef

export type BuildResult = {
	model: Model,
	motor: Motor6D,
	parts: { BasePart },
}

export type HandBuildDef = CosmeticDef & {
	kind: "pickaxe" | "sword" | "warhammer"?,
	procedural: { kind: "pickaxe" | "sword" | "warhammer" }?,
	-- shared dims
	handleLength: number?,
	handleRadius: number?,
	gripOffset: number?,
	gripHandOffsetY: number?,
	gripTiltDeg: number?,
	gripYawDeg: number?,
	gripRollDeg: number?,
	-- pickaxe / hammer head dims
	headLength: number?,
	headWidth: number?,
	headHeight: number?,
	headAttachOffsetZ: number?,
	-- sword blades / guard
	bladeLength: number?,
	bladeWidth: number?,
	bladeThickness: number?,
	guardRingRadius: number?,
	guardRingThickness: number?,
	guardRingSegments: number?,
	-- materials/colors
	material: Enum.Material?,
	materialPreset: string?,
	handleMaterial: Enum.Material?,
	headMaterial: Enum.Material?,
	tint: Color3?,
	color: Color3?,
	handleTint: Color3?,
	headTint: Color3?,
}

-- MiningGame not required here; keep module-local requires via script.Parent
local HandGrip = require(script.Parent.HandGrip)

local function findRightHand(character: Model): BasePart?
	local candidates = { "RightHand", "Right Arm", "RightLowerArm", "UpperTorso", "Torso" }
	for _, name in ipairs(candidates) do
		local inst = character:FindFirstChild(name)
		if inst and inst:IsA("BasePart") then
			return inst
		end
	end
	return nil
end

local function resolveMaterial(def: CosmeticDef): Enum.Material
	local preset = def.materialPreset
	if type(preset) == "string" then
		local key = string.lower(preset)
		if key == "neon" then
			return Enum.Material.Neon
		end
		if key == "glass" then
			return Enum.Material.Glass
		end
		if key == "metal" then
			return Enum.Material.Metal
		end
		if key == "plastic" then
			return Enum.Material.Plastic
		end
		if key == "smoothplastic" then
			return Enum.Material.SmoothPlastic
		end
		if key == "forcefield" then
			return Enum.Material.ForceField
		end
		if key == "ice" then
			return Enum.Material.Ice
		end
		if key == "wood" then
			return Enum.Material.Wood
		end
	end
	return Enum.Material.Metal
end

local function ensureMaterial(opt: Enum.Material?, fallback: Enum.Material): Enum.Material
	if opt ~= nil then
		local out: Enum.Material = opt
		return out
	end
	return fallback
end

local function resolveColor(def: CosmeticDef, fallback: Color3): Color3
	if typeof(def.tint) == "Color3" then
		return def.tint
	end
	if typeof(def.color) == "Color3" then
		return def.color
	end
	return fallback
end

-- PICKAXE (handle along +X; head arms along Z)
local function buildPickaxe(character: Model, def: CosmeticDef): BuildResult?
	local hand = findRightHand(character)
	if not hand then
		return nil
	end

	local model = Instance.new("Model")
	model.Name = "CosmeticHandItem"
	model.Parent = character

	local handleLen = def.handleLength or 3.6
	local handleRad = def.handleRadius or 0.18
	-- New block head dims (bigger head)
	local headLen = def.headLength or 2.4
	local headWidth = def.headWidth or 2.6
	local headHeight = def.headHeight or 1.8

	local mat = resolveMaterial(def)
	local handleMat: Enum.Material = ensureMaterial(def.handleMaterial, mat)
	local headMat: Enum.Material = ensureMaterial(def.headMaterial, mat)
	local handleColor: Color3 = (typeof(def.handleTint) == "Color3") and (def.handleTint :: Color3)
		or Color3.fromRGB(130, 90, 50)
	local headColor: Color3 = (typeof(def.headTint) == "Color3") and (def.headTint :: Color3)
		or Color3.fromRGB(150, 150, 155)

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

	-- halfLen not needed; keeping handle mount purely via utilities

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
		local zOffset = def.headAttachOffsetZ or -(headLen * 0.30)
		head.CFrame = head.CFrame * CFrame.new(0, 0, zOffset)
		MountUtils.weld(handle, head)
	end

	model.PrimaryPart = handle

	local motor = HandGrip.attachXToUp(hand, handle, handleLen, {
		gripOffset = def.gripOffset or 0.25,
		gripHandOffsetY = def.gripHandOffsetY or -0.15,
		gripTiltDeg = def.gripTiltDeg or -70,
		gripYawDeg = def.gripYawDeg or 0,
		gripRollDeg = def.gripRollDeg or 0,
	})

	return { model = model, motor = motor, parts = { handle, head } }
end

-- SWORD (handle along +X; blade extends +X; guard near tip)
local function buildSword(character: Model, def: CosmeticDef): BuildResult?
	local hand = findRightHand(character)
	if not hand then
		return nil
	end

	local model = Instance.new("Model")
	model.Name = "CosmeticHandItem"
	model.Parent = character

	local handleLen = def.handleLength or 2.2
	local handleRad = def.handleRadius or 0.18
	-- Much bigger blade
	local bladeLen = def.bladeLength or 5.5
	local bladeWidth = def.bladeWidth or 1.8
	local bladeThick = def.bladeThickness or 0.32
	-- Smaller ring radius, thicker rings
	local guardRingRadius = def.guardRingRadius or 0.45
	local guardRingThickness = def.guardRingThickness or 0.14
	local guardRingSegments = def.guardRingSegments or 12

	local mat = Enum.Material.Neon
	local baseColor: Color3 = resolveColor(def, Color3.fromRGB(255, 255, 255))
	local bladeColor: Color3 = resolveColor(def, Color3.fromRGB(200, 200, 210))

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
	local guardCenter = handle.CFrame * CFrame.new(halfLen - 0.25, 0, 0)
	-- Use baseColor here; runtime renderer applies darker neon pulse
	local ring1 = GuardBuilder.makeGuard(
		model,
		guardCenter * CFrame.new(0, 0.06, 0),
		guardRingRadius * 1.2,
		guardRingThickness,
		baseColor,
		{ segments = guardRingSegments, name = "GuardRingSeg1", axis = "X" }
	)
	local ring2 = GuardBuilder.makeGuard(
		model,
		guardCenter * CFrame.new(0, -0.06, 0),
		guardRingRadius * 0.8,
		guardRingThickness,
		baseColor,
		{ segments = guardRingSegments, name = "GuardRingSeg2", axis = "X" }
	)
	-- Weld guard segments to the handle so they follow the hand
	for _, seg in ipairs(ring1) do
		require(script.Parent.MountUtils).weld(handle, seg)
	end
	for _, seg in ipairs(ring2) do
		require(script.Parent.MountUtils).weld(handle, seg)
	end

	-- No single guard part; rings are welded above

	model.PrimaryPart = handle

	local motor = HandGrip.attachXToUp(hand, handle, handleLen, {
		gripOffset = def.gripOffset or 0.25,
		gripHandOffsetY = def.gripHandOffsetY or -0.15,
		gripTiltDeg = def.gripTiltDeg or -85,
		gripYawDeg = def.gripYawDeg or 0,
		gripRollDeg = def.gripRollDeg or 0,
	})

	-- Now that the motor has oriented the handle, attach blade by its TOP EDGE to the TOP of the handle end face
	do
		MountUtils.mountEndTopEdge(handle, blade, { axis = "Z", rollQuarter = 1, inset = 0.02 })
		MountUtils.weld(handle, blade)
	end

	local parts: { BasePart } = { handle, blade }
	for _, p in ipairs(ring1) do
		table.insert(parts, p)
	end
	for _, p in ipairs(ring2) do
		table.insert(parts, p)
	end
	return { model = model, motor = motor, parts = parts }
end

-- WARHAMMER (handle along +X; head at +X tip)
local function buildWarhammer(character: Model, def: CosmeticDef): BuildResult?
	local hand = findRightHand(character)
	if not hand then
		return nil
	end

	local model = Instance.new("Model")
	model.Name = "CosmeticHandItem"
	model.Parent = character

	local handleLen = def.handleLength or 3.2
	local handleRad = def.handleRadius or 0.22
	local headLen = def.headLength or 1.2
	local headWidth = def.headWidth or 1.0
	local headHeight = def.headHeight or 0.9
	local gripHandOffsetY = def.gripHandOffsetY or -0.15

	local mat = resolveMaterial(def)
	local handleMat: Enum.Material = ensureMaterial(def.handleMaterial, mat)
	local headMat: Enum.Material = ensureMaterial(def.headMaterial, mat)
	local handleColor: Color3 = (typeof(def.handleTint) == "Color3") and (def.handleTint :: Color3)
		or resolveColor(def, Color3.fromRGB(100, 80, 60))
	local headColor: Color3 = (typeof(def.headTint) == "Color3") and (def.headTint :: Color3)
		or resolveColor(def, Color3.fromRGB(160, 160, 160))

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

	local _halfLen = handleLen * 0.5
	local MountUtils = require(script.Parent.MountUtils)
	-- Match original look: handle tip barely protrudes beyond head's far face
	MountUtils.mountEndByTip(handle, head, 0.02)
	MountUtils.weld(handle, head)

	model.PrimaryPart = handle

	local motor = HandGrip.attachXToUp(hand, handle, handleLen, {
		gripOffset = def.gripOffset or 0.25,
		gripHandOffsetY = gripHandOffsetY,
		gripTiltDeg = def.gripTiltDeg or -85,
		gripYawDeg = def.gripYawDeg or 0,
		gripRollDeg = def.gripRollDeg or 0,
	})

	return { model = model, motor = motor, parts = { handle, head } }
end

function HandItemBuilders.build(character: Model, def: CosmeticDef): BuildResult?
	local pKind: string? = nil
	if def and def.procedural then
		local p = def.procedural
		if type(p) == "table" and type(p.kind) == "string" then
			pKind = p.kind :: string
		end
	end
	local dKind = (type(def.kind) == "string" and (def.kind :: string) or nil)
	local kind = pKind or dKind or "pickaxe"
	if kind == "pickaxe" then
		return buildPickaxe(character, def)
	end
	if kind == "sword" then
		return buildSword(character, def)
	end
	if kind == "warhammer" then
		return buildWarhammer(character, def)
	end
	return buildPickaxe(character, def)
end

function HandItemBuilders.destroy(ctx: BuildResult?)
	if not ctx then
		return
	end
	if ctx.motor and ctx.motor.Parent then
		ctx.motor:Destroy()
	end
	if ctx.model and ctx.model.Parent then
		ctx.model:Destroy()
	end
end

return HandItemBuilders
