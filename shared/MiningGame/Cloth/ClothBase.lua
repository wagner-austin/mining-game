--!strict
-- shared/MiningGame/Cloth/ClothBase.lua
-- Reusable base for cloth-like skinned meshes (server/client-safe)

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local ClientError = require(MiningGame:WaitForChild("ClientError"))
-- local Logger = require(MiningGame:WaitForChild("Logger"))
-- local log = Logger.new("ClothBase")

export type BoneMeta = { col: number, row: number, rowsInCol: number }
export type ClothInstance = {
	id: string,
	model: Model,
	mesh: MeshPart,
	bones: { Bone },
	columns: { { Bone } },
	meta: { [Bone]: BoneMeta },
	numCols: number,
	maxRows: number,
	debugParts: { Instance }?,
}

local ClothBase = {}
ClothBase.__index = ClothBase

-- Natural name sort to keep columns stable (e.g. "Col2" before "Col10")
local function nameLess(a: Instance, b: Instance): boolean
	local an = string.match(a.Name, "%d+")
	local bn = string.match(b.Name, "%d+")
	if an and bn and tonumber(an) ~= tonumber(bn) then
		return tonumber(an) < tonumber(bn)
	end
	return a.Name < b.Name
end

local function boolDefault(v: boolean?, default: boolean): boolean
	if v == nil then
		return default
	end
	return v
end

-- Build a column-row grid by walking root bones down their child chains
function ClothBase.buildGrid(mesh: MeshPart, bones: { Bone }): ({ { Bone } }, { [Bone]: BoneMeta }, number, number)
	local isBone = {}
	for _, b in ipairs(bones) do
		isBone[b] = true
	end

	local roots = {}
	for _, b in ipairs(bones) do
		local p = b.Parent
		if not (p and p:IsA("Bone")) then
			table.insert(roots, b)
		end
	end

	-- Sort columns by X position (more reliable than names)
	table.sort(roots, function(a, b)
		local ax = mesh.CFrame:PointToObjectSpace(a.WorldPosition).X
		local bx = mesh.CFrame:PointToObjectSpace(b.WorldPosition).X
		if math.abs(ax - bx) > 0.01 then
			return ax < bx
		end
		return nameLess(a, b) -- tie-breaker
	end)

	local columns = {} :: { { Bone } }
	local meta = {} :: { [Bone]: BoneMeta }
	local maxRows = 0

	for ci, root in ipairs(roots) do
		-- Follow the bone chain down, preferring first child by name
		local col = {}
		local node: Bone? = root
		local r = 1
		while node and isBone[node] do
			table.insert(col, node)
			meta[node] = { col = ci, row = r, rowsInCol = 0 }
			maxRows = math.max(maxRows, r)
			-- Pick next child bone (smallest name) if any
			local nextNode: Bone? = nil
			for _, child in ipairs(node:GetChildren()) do
				if child:IsA("Bone") then
					if not nextNode or nameLess(child, nextNode) then
						nextNode = child
					end
				end
			end
			node = nextNode
			r += 1
		end
		columns[ci] = col
	end

	-- Store total row count for each bone's column
	for _, col in ipairs(columns) do
		local n = #col
		for _, b in ipairs(col) do
			meta[b].rowsInCol = n
		end
	end

	return columns, meta, #roots, maxRows
end

export type SpawnVisual = {
	material: Enum.Material?,
	color: Color3?,
	transparency: number?,
	reflectance: number?,
	castShadow: boolean?,
	clearSurfaceAppearance: boolean?,
	clearHighlights: boolean?,
	materialVariant: string?, -- set to "" to clear
}

export type GlowBarOpts = {
	enabled: boolean?,
	thickness: number?,
	width: number?,
	extraLen: number?,
	shortenFactor: number?,
	colorOverride: Color3?,
}

export type SpawnOpts = {
	parent: Instance?,
	name: string?,
	cframe: CFrame?,
	anchored: boolean?,
	canCollide: boolean?,
	canQuery: boolean?,
	canTouch: boolean?,
	scale: number?, -- uniform scale factor
	widen: number?, -- multiply X size
	id: string?,
	idAttribute: string?,
	indexBones: boolean?, -- default true
	makeDebugSpheres: boolean?, -- default false
	glowBar: GlowBarOpts?,
	visual: SpawnVisual?,
}

function ClothBase.spawnFromTemplate(template: Instance, opts: SpawnOpts?): ClothInstance
	local o: SpawnOpts = if opts then opts else {} :: SpawnOpts
	local parent = o.parent or workspace
	local name = o.name or "Cloth"

	local clone = template:Clone()
	clone.Name = name
	clone.Parent = parent

	local meshCandidate: Instance? = clone:IsA("MeshPart") and clone or clone:FindFirstChildWhichIsA("MeshPart")
	if not meshCandidate or not meshCandidate:IsA("MeshPart") then
		clone:Destroy()
		error("ClothBase.spawnFromTemplate: no MeshPart found in template")
	end
	local mesh: MeshPart = meshCandidate

	-- Ensure we operate with a Model container so scaling works reliably
	local model: Model
	if clone:IsA("Model") then
		model = clone
	else
		model = Instance.new("Model")
		model.Name = name
		model.Parent = parent
		clone.Parent = model
	end

	-- Default orientation: hang vertically (-90deg around X) then face backward (180deg Y)
	if o.cframe then
		mesh.CFrame = o.cframe
	end

	-- Ensure Skin is enabled so bone deformation is active
	local skin = mesh:FindFirstChildOfClass("Skin")
	if skin and skin:IsA("Skin") then
		skin.Enabled = true
	end

	-- Physics defaults
	mesh.Anchored = boolDefault(o.anchored, true)
	mesh.CanCollide = boolDefault(o.canCollide, true)
	mesh.CanQuery = boolDefault(o.canQuery, true)
	mesh.CanTouch = boolDefault(o.canTouch, true)

	-- Visuals
	if o.visual then
		local v = o.visual
		if v.clearSurfaceAppearance then
			local sa = mesh:FindFirstChildOfClass("SurfaceAppearance")
			if sa then
				sa:Destroy()
			end
		end
		if v.clearHighlights then
			for _, child in ipairs(model:GetChildren()) do
				if child:IsA("Highlight") then
					child:Destroy()
				end
			end
		end
		if v.material ~= nil then
			mesh.Material = v.material
		end
		if v.color ~= nil then
			mesh.Color = v.color
		end
		if v.transparency ~= nil then
			mesh.Transparency = v.transparency
		end
		if v.reflectance ~= nil then
			mesh.Reflectance = v.reflectance
		end
		if v.castShadow ~= nil then
			mesh.CastShadow = v.castShadow
		end
		if v.materialVariant ~= nil then
			if typeof(v.materialVariant) == "string" then
				mesh.MaterialVariant = v.materialVariant
			else
				mesh.MaterialVariant = ""
			end
		end
	end

	-- Scaling: model.ScaleTo if available, otherwise adjust MeshPart size directly
	if o.scale and o.scale ~= 1 then
		local ok = ClientError.try("ClothBase.ModelScaleTo", function()
			local m: Model = model :: Model
			m:ScaleTo(o.scale :: number)
			return true
		end)
		if not ok then
			local s = mesh.Size
			mesh.Size = Vector3.new(s.X * o.scale, s.Y * o.scale, s.Z * o.scale)
		end
	end

	-- Widen in X, preserve Y/Z
	if o.widen and o.widen ~= 1 then
		local s = mesh.Size
		mesh.Size = Vector3.new(s.X * o.widen, s.Y, s.Z)
	end

	-- Collect bones
	local bones = {}
	for _, desc in ipairs(mesh:GetDescendants()) do
		if desc:IsA("Bone") then
			table.insert(bones, desc)
		end
	end

	-- Build grid metadata
	local columns, meta, numCols, maxRows = ClothBase.buildGrid(mesh, bones)

	-- Index bones for client mapping (default true)
	if o.indexBones ~= false then
		for i, bone in ipairs(bones) do
			bone:SetAttribute("ClothIdx", i)
		end
	end

	-- Optional debug spheres (hidden by default)
	local debugParts: { Instance }? = nil
	if o.makeDebugSpheres then
		debugParts = {}
		for i, bone in ipairs(bones) do
			local sphere = Instance.new("Part")
			sphere.Name = "BoneDebug_" .. i
			sphere.Shape = Enum.PartType.Ball
			sphere.Material = Enum.Material.Neon
			sphere.Size = Vector3.new(0.3, 0.3, 0.3)
			sphere.Anchored = true
			sphere.CanCollide = false
			sphere.CanQuery = false
			sphere.CanTouch = false
			sphere.Color = Color3.fromRGB(255, 255, 255)
			local m = meta[bone]
			if m and m.row == 1 then
				sphere.Size = Vector3.new(0.5, 0.5, 0.5)
			end
			local light = Instance.new("PointLight")
			light.Brightness = 5.0
			light.Range = 0.0
			light.Color = sphere.Color
			light.Shadows = false
			light.Parent = sphere
			sphere.CFrame = bone.WorldCFrame
			sphere.Transparency = 1.0
			sphere.Parent = model
			if debugParts then
				debugParts[i] = sphere
			end
		end
	end

	-- Assign ID attribute
	local id = o.id or HttpService:GenerateGUID(false)
	local idAttr = o.idAttribute or "ClothId"
	model:SetAttribute(idAttr, id)

	-- Optional glow bar along the top edge
	local glow = o.glowBar
	if glow and glow.enabled ~= false then
		local thickness = glow.thickness or 0.2
		local width = glow.width or 1.0
		local extraLen = glow.extraLen or 2.0
		local shortenFactor = glow.shortenFactor or 0.9

		-- Determine top row via metadata
		local topBones = {}
		for _, bone in ipairs(bones) do
			local m = meta[bone]
			if m and m.row == 1 then
				table.insert(topBones, bone)
			end
		end

		local right = mesh.CFrame.RightVector
		local baseWidth = mesh.Size.X
		local barLength = (baseWidth + extraLen) * shortenFactor
		local barCenter: Vector3
		if #topBones > 0 then
			local sum = Vector3.new(0, 0, 0)
			local minProj, maxProj = math.huge, -math.huge
			for _, b in ipairs(topBones) do
				local p = b.WorldPosition
				sum += p
				local t = p:Dot(right)
				if t < minProj then
					minProj = t
				end
				if t > maxProj then
					maxProj = t
				end
			end
			local avg = sum / #topBones
			barCenter = Vector3.new(avg.X, avg.Y + (thickness * 0.5), avg.Z)
			local span = (maxProj - minProj) + extraLen
			barLength = math.max(2, span * shortenFactor)
		else
			-- Fallback to mesh center and width if no bones found
			local topApprox = mesh.Position + Vector3.new(0, mesh.Size.Y * 0.5, 0)
			barCenter = Vector3.new(topApprox.X, topApprox.Y + (thickness * 0.5), topApprox.Z)
			barLength = math.max(2, (baseWidth + extraLen) * shortenFactor)
		end

		local bar = Instance.new("Part")
		bar.Name = "ClothGlowBar"
		bar.Anchored = true
		bar.CanCollide = false
		bar.CanTouch = false
		bar.CanQuery = false
		bar.CastShadow = false
		bar.Size = Vector3.new(barLength, thickness, width)

		-- Keep bar horizontal; X across cloth width; Bottom face points downward
		local x = right.Unit
		local y = Vector3.new(0, 1, 0)
		local z = x:Cross(y).Unit
		y = z:Cross(x).Unit
		bar.CFrame = CFrame.fromMatrix(barCenter, x, y, z)
		bar.Parent = model
		-- Tag so MaterialManager themes it as a GlowBar (Neon + lights)
		ClientError.try("ClothBase.TagGlowBar", function()
			CollectionService:AddTag(bar, "GlowBar")
			return true
		end)
		if glow and glow.colorOverride then
			bar:SetAttribute("GlowColorOverride", glow.colorOverride)
		end
	end

	local inst: ClothInstance = {
		id = id,
		model = model,
		mesh = mesh :: MeshPart,
		bones = bones :: { Bone },
		columns = columns,
		meta = meta,
		numCols = numCols,
		maxRows = maxRows,
		debugParts = debugParts,
	}

	return inst
end

export type WaveParams = {
	waveSpeed: number?,
	waveLength: number?,
	zAmplitude: number?,
	stretchAmount: number?,
}

-- Compute per-bone offsets for simple curtain-like motion
function ClothBase.computeOffsets(inst: ClothInstance, t: number, params: WaveParams?): { [number]: Vector3 }
	local p: WaveParams = if params then params else {} :: WaveParams
	local waveSpeed = p.waveSpeed or 2.0
	local waveLength = p.waveLength or 3.0
	local zAmplitude = p.zAmplitude or 2.0
	local stretchAmount = p.stretchAmount or 0.15

	local offsets = table.create(#inst.bones)
	for i, bone in ipairs(inst.bones) do
		local m = inst.meta[bone]
		if m then
			local u = (m.col - 1) / math.max(inst.numCols - 1, 1)
			local v = (m.row - 1) / math.max(m.rowsInCol - 1, 1)
			if m.row == 1 then
				offsets[i] = Vector3.new(0, 0, 0)
			else
				local gravityDroop = (m.row - 1) * stretchAmount
				local waveStrength = v * v
				local forwardWave = math.sin(waveSpeed * t + u * waveLength * math.pi) * zAmplitude * waveStrength
				local xSway = math.sin(waveSpeed * t * 0.7 + u * math.pi * 2) * 0.2 * waveStrength
				offsets[i] = Vector3.new(xSway, gravityDroop, forwardWave * 0.5)
			end
		else
			offsets[i] = Vector3.new(0, 0, 0)
		end
	end
	return offsets
end

-- Optional visualizer update for debug spheres ("icicle rain" effect)
function ClothBase.updateDebug(inst: ClothInstance, t: number)
	local debugParts = inst.debugParts
	if not debugParts then
		return
	end

	local total = #inst.bones
	for i, bone in ipairs(inst.bones) do
		local sphere = debugParts[i]
		if sphere and sphere:IsA("BasePart") then
			local m = inst.meta[bone]
			sphere.CFrame = bone.WorldCFrame
			sphere.Color = Color3.fromRGB(255, 255, 255)

			-- Multiple evenly-spaced active orbs (6 heads) with a short trailing tail behind each head
			local cycle = 12.0 -- seconds for a full sweep (base)
			local N = 6 -- number of simultaneous bright orbs
			local trail = 2.2 -- trail length in orb indices behind the head
			local baseRate = 1 / cycle
			local peak = 0
			local peakBF = 1.0 -- brightness factor of the contributing head

			local function h01(x: number): number
				local s = math.sin(x * 12.9898) * 43758.5453
				return s - math.floor(s)
			end

			for j = 0, N - 1 do
				local speedFactor = 0.2 + 0.9 * h01(j + 1)
				local brightnessFactor = 0.8 + 0.4 * h01(101 + j)
				local rate = baseRate * speedFactor
				local phase = (t * rate + j / N) % 1
				local pos = phase * total -- head position in [0,total)
				local i0 = i - 1
				local d = pos - i0
				d = (d % total + total) % total -- wrap into [0,total)
				if d >= 0 and d <= trail then
					local x = 1 - (d / trail)
					local contrib = x * x
					if contrib > peak then
						peak = contrib
						peakBF = brightnessFactor
					end
				end
			end

			if peak > 0 then
				sphere.Transparency = math.clamp(1.0 - 0.98 * peak, 0.0, 1.0)
				local pl = sphere:FindFirstChildOfClass("PointLight")
				if pl then
					pl.Color = Color3.fromRGB(255, 255, 255)
					pl.Range = 0.0
					pl.Brightness = (2.0 + 28.0 * peak) * peakBF
				end
			else
				sphere.Transparency = 1.0
				local pl = sphere:FindFirstChildOfClass("PointLight")
				if pl then
					pl.Range = 0.0
					pl.Brightness = 0.0
				end
			end

			-- Stable size
			local s = (m and m.row == 1) and 0.5 or 0.3
			sphere.Size = Vector3.new(s, s, s)
		end
	end
end

return ClothBase
