--!strict
-- HeadBuilders.lua
-- Procedural builders for head cosmetics (e.g., horns, halos, crowns)

local HeadBuilders = {}
local RegistryTypes = require(script.Parent.Parent.RendererRegistry)
type CosmeticDef = RegistryTypes.CosmeticDef
type RendererCtx = RegistryTypes.RendererCtx
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Materials = require(Shared:WaitForChild("CosmeticMaterials"))
local RunService = game:GetService("RunService")
local Time = require(Shared:WaitForChild("Time"))

export type HeadBuildDef = CosmeticDef & {
	-- common
	color: Color3?,
	scale: number?,
	glows: boolean?,
	segments: number?,
	-- horns
	hornLength: number?,
	hornRadius: number?,
	hornSeparation: number?,
	hornTiltDeg: number?,
	hornHeightOffset: number?,
	-- halo
	haloThickness: number?,
	thickness: number?,
	haloRadius: number?,
	radius: number?,
	haloHeightOffset: number?,
	heightOffset: number?,
	haloRingOffset: number?,
	-- crown
	crownRadius: number?,
	bandHeight: number?,
	height: number?,
	bandThickness: number?,
	crownHeightOffset: number?,
	spikeCount: number?,
	spikeHeight: number?,
	spikeRadius: number?,
	spikeTiltDeg: number?,
	spikeSegments: number?,
	-- charm
	charmCoreRadius: number?,
	coreRadius: number?,
	charmRingRadius: number?,
	ringRadius: number?,
	charmRingThickness: number?,
	ringThickness: number?,
	charmHeightOffset: number?,
	charmForwardOffset: number?,
	forwardOffset: number?,
	charmPlacement: string?,
	placement: string?,
	charmOrbRing: boolean?,
	orbRing: boolean?,
	charmOrbCount: number?,
	orbCount: number?,
	charmOrbSmallRadius: number?,
	orbSmallRadius: number?,
	charmOrbMediumRadius: number?,
	orbMediumRadius: number?,
	charmOrbRadius: number?,
	orbRadius: number?,
	charmSpinHz: number?,
	spinHz: number?,
	-- sunglasses
	glassesForwardOffset: number?,
	glassesHeightOffset: number?,
	lensWidth: number?,
	lensHeight: number?,
	lensThickness: number?,
	bridgeWidth: number?,
	frameThickness: number?,
	templeLength: number?,
	templeThickness: number?,
	lensTint: Color3?,
	lensColor: Color3?,
	lensTransparency: number?,
	frameColor: Color3?,
}

-- Build neon tapered horns from stacked cylinders
function HeadBuilders.horns(character: Model, head: BasePart, def: CosmeticDef): RendererCtx
	local hornsColor: Color3
	do
		local c = def.color
		if typeof(c) == "Color3" then
			hornsColor = c
		else
			hornsColor = Color3.fromRGB(255, 255, 255)
		end
	end
	local scale: number = def.scale or 1.0
	local length: number = def.hornLength or (1.2 * scale)
	local baseRadius: number = def.hornRadius or (0.22 * scale)
	local separation: number = def.hornSeparation or (0.55 * scale)
	local tiltDeg: number = def.hornTiltDeg or 18
	local heightOffset: number = def.hornHeightOffset or 0.08 -- keep consistent head-top baseline
	local segments: number = math.max(2, math.floor(def.segments or 4))

	local function buildHorn(sign: number): Instance
		local folder = Instance.new("Folder")
		folder.Name = (sign < 0) and "CosmeticHornLeft" or "CosmeticHornRight"
		folder.Parent = character

		local topCF = head.CFrame * CFrame.new(0, head.Size.Y / 2 + heightOffset, 0)
		local baseCF = topCF * CFrame.new(sign * separation, 0, 0) * CFrame.Angles(0, 0, math.rad(-sign * tiltDeg))

		local segHeight = length / segments
		local firstPart: BasePart? = nil
		local prevPart: BasePart? = nil

		for i = 1, segments do
			local t = (i - 1) / (segments - 1)
			local radius = math.max(0.06 * scale, baseRadius * (1 - 0.85 * t))

			local p = Instance.new("Part")
			p.Name = string.format("HornSeg_%d", i)
			p.Material = Materials.pick(def, Enum.Material.Neon)
			p.Color = hornsColor
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Massless = true
			p.Anchored = false
			p.Shape = Enum.PartType.Cylinder
			p.Size = Vector3.new(2 * radius, segHeight, 2 * radius)
			p.Parent = folder

			local y = (i - 0.5) * segHeight
			p.CFrame = baseCF * CFrame.new(0, y, 0)

			if not firstPart then
				firstPart = p
			end
			if prevPart then
				local wc = Instance.new("WeldConstraint")
				wc.Part0 = prevPart
				wc.Part1 = p
				wc.Parent = folder
			end
			prevPart = p
		end

		if firstPart then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = head
			weld.Part1 = firstPart
			weld.Parent = folder
		end

		if def.glows ~= false then
			local light = Instance.new("PointLight")
			light.Brightness = 2
			light.Range = 10
			light.Color = hornsColor
			light.Parent = firstPart or prevPart
		end

		return folder
	end

	local left = buildHorn(-1)
	local right = buildHorn(1)
	local instancesLR: { Instance } = { left, right }
	return { instances = instancesLR }
end

-- Build a circular neon halo using segmented cylinders along the tangent
function HeadBuilders.halo(character: Model, head: BasePart, def: CosmeticDef): RendererCtx
	local folder = Instance.new("Folder")
	folder.Name = "CosmeticHalo"
	folder.Parent = character

	local color: Color3
	do
		local c = def.color
		if typeof(c) == "Color3" then
			color = c
		else
			color = Color3.fromRGB(255, 255, 255)
		end
	end
	local segments: number = math.max(12, math.floor(def.segments or 24))
	local scale: number = def.scale or 1.0
	local thickness: number = ((def.haloThickness or def.thickness) or 0.08) * scale
	local radiusOpt: number? = (def.haloRadius or def.radius)
	local heightOffset: number = (def.haloHeightOffset or def.heightOffset) or 0.9 -- lowered slightly
	local ringOffset: number = (def.haloRingOffset or 0.35) * scale

	local headRadius = (head.Size.X + head.Size.Z) * 0.25
	local radius: number = radiusOpt or (headRadius + ringOffset)

	local origin = head.CFrame * CFrame.new(0, head.Size.Y / 2 + heightOffset, 0)

	local firstPart: BasePart? = nil
	local prevPart: BasePart? = nil

	for i = 1, segments do
		local a = (i - 1) * (2 * math.pi / segments)
		local r = Vector3.new(math.cos(a), 0, math.sin(a))
		local t = Vector3.new(-math.sin(a), 0, math.cos(a))
		local rW = origin:VectorToWorldSpace(r)
		local tW = origin:VectorToWorldSpace(t)
		local _upW = origin.UpVector
		local pos = origin.Position + rW * radius

		local segLen = (2 * math.pi * radius / segments) * 0.95 -- tiny gap to smooth edges

		local p = Instance.new("Part")
		p.Name = string.format("HaloSeg_%d", i)
		p.Material = Materials.pick(def, Enum.Material.Neon)
		p.Color = color
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.Anchored = false
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(2 * thickness, segLen, 2 * thickness)
		p.Parent = folder

		local x = rW.Unit
		local y = tW.Unit -- align cylinder axis along tangent
		local z = x:Cross(y).Unit
		p.CFrame = CFrame.fromMatrix(pos, x, y, z)

		if not firstPart then
			firstPart = p
		end
		if prevPart then
			local wc = Instance.new("WeldConstraint")
			wc.Part0 = prevPart
			wc.Part1 = p
			wc.Parent = folder
		end
		prevPart = p
	end

	if firstPart then
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = firstPart
		weld.Parent = folder
	end

	if def.glows ~= false then
		local center = Instance.new("Part")
		center.Name = "HaloCenter"
		center.Size = Vector3.new(0.2, 0.2, 0.2)
		center.Transparency = 1
		center.Anchored = false
		center.CanCollide = false
		center.CanQuery = false
		center.CanTouch = false
		center.Massless = true
		center.Parent = folder
		center.CFrame = origin

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = center
		weld.Parent = center

		local light = Instance.new("PointLight")
		light.Brightness = 2
		light.Range = 12
		light.Color = color
		light.Parent = center
	end

	local instancesHalo: { Instance } = { folder }
	return { instances = instancesHalo }
end

-- Build a stylized crown: band + prongs (small cones), metal material
function HeadBuilders.crown(character: Model, head: BasePart, def: CosmeticDef): RendererCtx
	local folder = Instance.new("Folder")
	folder.Name = "CosmeticCrown"
	folder.Parent = character

	local color: Color3
	do
		local c = def.color
		if typeof(c) == "Color3" then
			color = c
		else
			color = Color3.fromRGB(212, 175, 55) -- gold-ish
		end
	end
	local mat = Materials.pick(def, Enum.Material.Metal)
	local segments: number = math.max(10, math.floor(def.segments or 18))
	local scale: number = def.scale or 1.0
	local radiusOpt: number? = (def.crownRadius or def.radius)
	local bandHeight: number = ((def.bandHeight or def.height) or 0.35) * scale
	local bandThickness: number = ((def.bandThickness or def.thickness) or 0.12) * scale
	local heightOffset: number = (def.crownHeightOffset or def.heightOffset) or 0.08

	local spikeCount: number = math.max(3, math.floor(def.spikeCount or 6))
	local spikeHeight: number = (def.spikeHeight or 0.7) * scale
	local spikeRadius: number = (def.spikeRadius or (bandThickness * 0.8)) * 1.0 -- already scaled by bandThickness
	local spikeTiltDeg: number = def.spikeTiltDeg or 5

	local headRadius = (head.Size.X + head.Size.Z) * 0.25
	local radius: number = radiusOpt or (headRadius + 0.15 * scale)

	local origin = head.CFrame * CFrame.new(0, head.Size.Y / 2 + heightOffset, 0)

	-- Band via box segments
	local firstBand: BasePart? = nil
	local prevBand: BasePart? = nil
	for i = 1, segments do
		local a = (i - 1) * (2 * math.pi / segments)
		local r = Vector3.new(math.cos(a), 0, math.sin(a))
		local t = Vector3.new(-math.sin(a), 0, math.cos(a))
		local rW = origin:VectorToWorldSpace(r)
		local tW = origin:VectorToWorldSpace(t)
		local pos = origin.Position + rW * radius

		local segLen = (2 * math.pi * radius / segments) * 0.98

		local p = Instance.new("Part")
		p.Name = string.format("CrownBand_%d", i)
		p.Material = mat
		p.Color = color
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.Anchored = false
		p.Size = Vector3.new(segLen, bandHeight, bandThickness)
		p.Parent = folder

		local x = tW.Unit -- along tangent
		local y = origin.UpVector.Unit
		local z = x:Cross(y).Unit
		p.CFrame = CFrame.fromMatrix(pos, x, y, z)

		if not firstBand then
			firstBand = p
		end
		if prevBand then
			local wc = Instance.new("WeldConstraint")
			wc.Part0 = prevBand
			wc.Part1 = p
			wc.Parent = folder
		end
		prevBand = p
	end

	if firstBand then
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = firstBand
		weld.Parent = folder
	end

	-- Prongs using mini-cones (stacked cylinders) at even intervals
	local function buildConeAtAngle(a: number)
		local r = Vector3.new(math.cos(a), 0, math.sin(a))
		local rW = origin:VectorToWorldSpace(r)
		local tW = origin:VectorToWorldSpace(Vector3.new(-math.sin(a), 0, math.cos(a)))
		local pos = origin.Position + rW * (radius + bandThickness * 0.5)

		local baseUp = origin.UpVector
		local tiltRad = math.rad(spikeTiltDeg)
		local y = (baseUp * math.cos(tiltRad) + rW.Unit * math.sin(tiltRad)).Unit
		local x = tW.Unit
		local z = x:Cross(y).Unit
		local baseCF = CFrame.fromMatrix(pos, x, y, z)

		local segs = math.max(2, math.floor(def.spikeSegments or 3))
		local segHeight = spikeHeight / segs
		local firstPart: BasePart? = nil
		local prev: BasePart? = nil
		for i = 1, segs do
			local t = (i - 1) / (segs - 1)
			local rad = math.max(0.05 * scale, spikeRadius * (1 - 0.8 * t))
			local p = Instance.new("Part")
			p.Name = string.format("CrownSpike_%d", i)
			p.Material = mat
			p.Color = color
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Massless = true
			p.Anchored = false
			p.Shape = Enum.PartType.Cylinder
			p.Size = Vector3.new(2 * rad, segHeight, 2 * rad)
			p.Parent = folder

			local yoff = (i - 0.5) * segHeight + bandHeight * 0.5
			p.CFrame = baseCF * CFrame.new(0, yoff, 0)

			if not firstPart then
				firstPart = p
			end
			if prev then
				local wc = Instance.new("WeldConstraint")
				wc.Part0 = prev
				wc.Part1 = p
				wc.Parent = folder
			end
			prev = p
		end
		if firstPart then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = head
			weld.Part1 = firstPart
			weld.Parent = folder
		end
	end

	for j = 1, spikeCount do
		local a = (j - 1) * (2 * math.pi / spikeCount)
		buildConeAtAngle(a)
	end

	if def.glows then
		local light = Instance.new("PointLight")
		light.Brightness = 2.5
		light.Range = 12
		light.Color = color
		light.Parent = firstBand or folder:FindFirstChildWhichIsA("BasePart") or folder
	end

	local instancesCrown: { Instance } = { folder }
	return { instances = instancesCrown }
end

-- Build a small levitating charm: neon core sphere with a thin ring in front of forehead
function HeadBuilders.charm(character: Model, head: BasePart, def: CosmeticDef): RendererCtx
	local folder = Instance.new("Folder")
	folder.Name = "CosmeticCharm"
	folder.Parent = character

	local color: Color3
	do
		local c = def.color
		if typeof(c) == "Color3" then
			color = c
		else
			color = Color3.fromRGB(0, 255, 200)
		end
	end
	local scale: number = def.scale or 1.0
	local coreRadius: number = ((def.charmCoreRadius or def.coreRadius) or 0.2) * scale
	local ringRadius: number = ((def.charmRingRadius or def.ringRadius) or 0.28) * scale -- planet ring
	local ringThickness: number = ((def.charmRingThickness or def.ringThickness) or 0.06) * scale
	local segments: number = math.max(12, math.floor(def.segments or 18))
	local heightOffset: number = (def.charmHeightOffset or def.heightOffset) or 0.2
	local forwardOffset: number = (def.charmForwardOffset or def.forwardOffset) or (head.Size.Z / 2 + 0.15)
	local placement: string = (def.charmPlacement or def.placement) or "top" -- "top" | "front"

	-- Ring pivot at halo level above head; this is the center of the orb ring
	local ringOrigin: CFrame = head.CFrame * CFrame.new(0, head.Size.Y / 2 + heightOffset, 0)
	-- If specifically front placement and a FaceFrontAttachment exists, bias ring forward slightly
	do
		if placement == "front" then
			local face = head:FindFirstChild("FaceFrontAttachment")
			if face and face:IsA("Attachment") then
				ringOrigin = face.WorldCFrame * CFrame.new(0, 0, forwardOffset)
			end
		end
	end

	-- Build an optional orb ring (halo-like, sparse, alternating sizes)
	local makeOrbRing = (def.charmOrbRing or def.orbRing) and true or false
	local orbCount = math.max(4, math.floor((def.charmOrbCount or def.orbCount) or 10))
	local orbSmall = ((def.charmOrbSmallRadius or def.orbSmallRadius) or 0.12) * scale
	local orbMedium = ((def.charmOrbMediumRadius or def.orbMediumRadius) or 0.18) * scale
	local orbRingRadius = (
		((def.charmOrbRadius or def.orbRadius) or ((head.Size.X + head.Size.Z) * 0.25 + 0.35)) * scale
	)

	-- Pivot for animation (Motor6D rotates this pivot)
	local pivot = Instance.new("Part")
	pivot.Name = "CharmPivot"
	pivot.Size = Vector3.new(0.2, 0.2, 0.2)
	pivot.Transparency = 1
	pivot.CanCollide = false
	pivot.CanQuery = false
	pivot.CanTouch = false
	pivot.Massless = true
	pivot.Anchored = false
	pivot.Parent = folder
	pivot.CFrame = ringOrigin

	if makeOrbRing then
		for i = 1, orbCount do
			local a = (i - 1) * (2 * math.pi / orbCount)
			local r = (i % 2 == 1) and orbMedium or orbSmall
			local posCF = ringOrigin * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -orbRingRadius)
			local orb = Instance.new("Part")
			orb.Name = string.format("CharmOrb_%d", i)
			orb.Shape = Enum.PartType.Ball
			orb.Material = Materials.pick(def, Enum.Material.Neon)
			orb.Color = color
			orb.Size = Vector3.new(2 * r, 2 * r, 2 * r)
			orb.CanCollide = false
			orb.CanQuery = false
			orb.CanTouch = false
			orb.Massless = true
			orb.Anchored = false
			orb.Parent = folder
			orb.CFrame = posCF

			local wc = Instance.new("WeldConstraint")
			wc.Part0 = pivot
			wc.Part1 = orb
			wc.Parent = folder
		end
	end

	-- Core sphere (planet) placed at the face side of the orb ring
	local core = Instance.new("Part")
	core.Name = "CharmCore"
	core.Shape = Enum.PartType.Ball
	core.Color = color
	core.Material = Materials.pick(def, Enum.Material.Neon)
	core.Size = Vector3.new(coreRadius * 2, coreRadius * 2, coreRadius * 2)
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.Massless = true
	core.Anchored = false
	core.Parent = folder
	local planetCF = ringOrigin * CFrame.new(0, 0, -orbRingRadius)
	core.CFrame = planetCF

	local _firstPart: BasePart? = core
	-- Thin ring around core (like a small halo)
	for i = 1, segments do
		local a = (i - 1) * (2 * math.pi / segments)
		local r = Vector3.new(math.cos(a), 0, math.sin(a))
		local t = Vector3.new(-math.sin(a), 0, math.cos(a))
		local rW = planetCF:VectorToWorldSpace(r)
		local tW = planetCF:VectorToWorldSpace(t)
		local pos = planetCF.Position + rW * ringRadius

		local segLen = (2 * math.pi * ringRadius / segments) * 0.96

		local p = Instance.new("Part")
		p.Name = string.format("CharmRing_%d", i)
		p.Material = Materials.pick(def, Enum.Material.Neon)
		p.Color = color
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.Anchored = false
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(2 * ringThickness, segLen, 2 * ringThickness)
		p.Parent = folder

		local x = tW.Unit
		local y = planetCF.UpVector.Unit
		local z = x:Cross(y).Unit
		p.CFrame = CFrame.fromMatrix(pos, x, y, z)

		local wc = Instance.new("WeldConstraint")
		wc.Part0 = core
		wc.Part1 = p
		wc.Parent = folder
	end

	-- Attach pivot via Motor6D for spin animation
	local motor = Instance.new("Motor6D")
	motor.Name = "CharmMotor"
	motor.Part0 = head
	motor.Part1 = pivot
	motor.Parent = head
	motor.C0 = head.CFrame:ToObjectSpace(ringOrigin)
	motor.C1 = CFrame.new()

	-- Weld planet core to pivot so it revolves with the orb ring
	do
		local wc = Instance.new("WeldConstraint")
		wc.Part0 = pivot
		wc.Part1 = core
		wc.Parent = folder
	end

	if def.glows ~= false then
		local light = Instance.new("PointLight")
		light.Brightness = 2
		light.Range = 8
		light.Color = color
		light.Parent = core
	end

	-- Spin animation
	local spinHz = (def.charmSpinHz or def.spinHz) or 1.2
	local conn = RunService.Heartbeat:Connect(function()
		local t = Time.mono()
		local ang = (t * spinHz * 2 * math.pi) % (2 * math.pi)
		motor.Transform = CFrame.Angles(0, ang, 0)
	end)

	local instances: { Instance } = { folder, pivot, core, motor }
	return { instances = instances, connections = { conn } }
end

-- Build an icon chip: small disc with a billboarded glyph (e.g., 🚀)
-- chip builder removed; jump icon is handled via BoostDefs (UI emoji)

-- Build sunglasses: two glass lenses + bridge + simple temples
function HeadBuilders.sunglasses(character: Model, head: BasePart, def: CosmeticDef): RendererCtx
	local folder = Instance.new("Folder")
	folder.Name = "CosmeticSunglasses"
	folder.Parent = character

	-- Params
	local forwardOffset: number = (def.glassesForwardOffset or def.forwardOffset) or 0.08
	local heightOffset: number = (def.glassesHeightOffset or def.heightOffset) or 0.0
	local scale: number = def.scale or 1.0

	local lensWidth: number = (def.lensWidth or 0.8) * scale
	local lensHeight: number = (def.lensHeight or 0.35) * scale
	local lensThickness: number = (def.lensThickness or 0.06) * scale
	local bridgeWidth: number = (def.bridgeWidth or 0.12) * scale
	local frameThickness: number = (def.frameThickness or 0.06) * scale
	local templeLength: number = (def.templeLength or 0.8) * scale
	local templeThickness: number = (def.templeThickness or 0.06) * scale

	local lensColor: Color3 = (def.lensTint or def.lensColor) or Color3.fromRGB(10, 10, 10)
	local lensTransparency: number = def.lensTransparency or 0.5
	local frameColor: Color3 = def.frameColor or Color3.fromRGB(20, 20, 20)

	-- Use the same material selection as horns for consistency
	local mat = Materials.pick(def, Enum.Material.Neon)
	local lensMat = mat
	local frameMat = mat

	-- Determine face reference
	local face = head:FindFirstChild("FaceFrontAttachment")
	local faceCF: CFrame = head.CFrame
	if face and face:IsA("Attachment") then
		faceCF = face.WorldCFrame
	end
	local origin = faceCF * CFrame.new(0, heightOffset, -forwardOffset)

	-- Pivot
	local pivot = Instance.new("Part")
	pivot.Name = "GlassesPivot"
	pivot.Transparency = 1
	pivot.Anchored = false
	pivot.CanCollide = false
	pivot.CanQuery = false
	pivot.CanTouch = false
	pivot.Massless = true
	pivot.Size = Vector3.new(0.2, 0.2, 0.2)
	pivot.CFrame = origin
	pivot.Parent = folder

	local function makePart(
		name: string,
		size: Vector3,
		cframe: CFrame,
		material: Enum.Material,
		color: Color3,
		transparency: number?
	): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = material
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.Anchored = false
		p.CFrame = cframe
		if transparency then
			p.Transparency = transparency
		end
		p.Parent = folder
		local w = Instance.new("WeldConstraint")
		w.Part0 = pivot
		w.Part1 = p
		w.Parent = folder
		return p
	end

	-- Lenses positions (left/right)
	local halfSpan = lensWidth / 2 + bridgeWidth / 2
	local leftCF = origin * CFrame.new(-halfSpan, 0, 0)
	local rightCF = origin * CFrame.new(halfSpan, 0, 0)
	local lensSize = Vector3.new(lensWidth, lensHeight, lensThickness)

	local leftLens = makePart("LeftLens", lensSize, leftCF, lensMat, lensColor, lensTransparency)
	local rightLens = makePart("RightLens", lensSize, rightCF, lensMat, lensColor, lensTransparency)

	-- Top frame bar across lenses
	local topWidth = lensWidth * 2 + bridgeWidth
	local topSize = Vector3.new(topWidth, frameThickness, lensThickness)
	local topCF = origin * CFrame.new(0, (lensHeight / 2 + frameThickness / 2), 0)
	local topBar = makePart("TopBar", topSize, topCF, frameMat, frameColor, 0)

	-- Removed billboard highlights per request

	-- Temples (simple straight bars going back) - attach to the horizontal top bar above lenses
	local templeSize = Vector3.new(templeThickness, templeThickness, templeLength)
	local barHalfSpan = ((lensWidth * 2 + bridgeWidth) / 2)
	local leftTempleCF = topCF * CFrame.new(-(barHalfSpan + templeThickness / 2), 0, templeLength / 2)
	local rightTempleCF = topCF * CFrame.new((barHalfSpan + templeThickness / 2), 0, templeLength / 2)
	local leftTemple = makePart("LeftTemple", templeSize, leftTempleCF, frameMat, frameColor, 0)
	local rightTemple = makePart("RightTemple", templeSize, rightTempleCF, frameMat, frameColor, 0)

	-- Subtle glow on lenses for emissive look
	if def.glows ~= false then
		local l1 = Instance.new("PointLight")
		l1.Brightness = 1.8
		l1.Range = 8
		l1.Color = lensColor
		l1.Parent = leftLens
		local l2 = Instance.new("PointLight")
		l2.Brightness = 1.8
		l2.Range = 8
		l2.Color = lensColor
		l2.Parent = rightLens
	end

	-- Attach pivot to head
	local motor = Instance.new("Motor6D")
	motor.Name = "GlassesMotor"
	motor.Part0 = head
	motor.Part1 = pivot
	motor.Parent = head
	motor.C0 = head.CFrame:ToObjectSpace(origin)
	motor.C1 = CFrame.new()

	local instances: { Instance } = { folder, pivot, leftLens, rightLens, topBar, leftTemple, rightTemple, motor }
	return { instances = instances }
end

return HeadBuilders
