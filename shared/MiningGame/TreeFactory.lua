--!strict
-- TreeFactory.lua
-- Minimal shared helpers to spawn simple tree models

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ClientError = require(ReplicatedStorage:WaitForChild("MiningGame"):WaitForChild("ClientError"))

local TreeFactory = {}

function TreeFactory.SpawnSimple(position: Vector3, parent: Instance?, scale: number?): Model
	local s = scale or 1
	local model = Instance.new("Model")
	model.Name = "Tree"

	local trunk = Instance.new("Part")
	trunk.Name = "Trunk"
	trunk.Size = Vector3.new(2, 10, 2) * s
	trunk.Position = position + Vector3.new(0, 5 * s, 0)
	trunk.BrickColor = BrickColor.new("Brown")
	trunk.Material = Enum.Material.Wood
	trunk.Anchored = true
	trunk.Parent = model

	local leaves = Instance.new("Part")
	leaves.Name = "Leaves"
	leaves.Size = Vector3.new(8, 8, 8) * s
	leaves.Position = position + Vector3.new(0, 10 * s, 0)
	leaves.BrickColor = BrickColor.new("Bright green")
	leaves.Material = Enum.Material.Grass
	leaves.Anchored = true
	leaves.Parent = model

	model.Parent = parent or Workspace
	return model
end

-- === Procedural blocky tree (shared) ===
do
	-- Tunables (mirrors defaults used in WorldGen)
	local BLOCK_SIZE = 8
	local TRUNK_COLOR = Color3.fromRGB(101, 67, 33)
	local LEAVES_COLOR = Color3.fromRGB(106, 157, 77)
	local LEAVES_ACCENT_COLOR = Color3.fromRGB(141, 190, 97)
	local TRUNK_THICKNESS = 1.35
	local TRUNK_VARIATION = 0.15
	local BRANCH_START_HEIGHT = 0.45
	local BRANCH_CHANCE = 0.5
	local MIN_TRUNK_HEIGHT = 10
	local MAX_TRUNK_HEIGHT = 30
	local MIN_BRANCH_LENGTH = 2
	local MAX_BRANCH_LENGTH = 5

	local function createBlock(
		position: Vector3,
		size: Vector3,
		color: Color3,
		material: Enum.Material,
		parent: Instance,
		opts: { collidable: boolean?, castShadow: boolean? }?
	): BasePart
		local part = Instance.new("Part")
		part.Size = size
		part.Position = position
		part.Color = color
		part.Material = material
		part.Anchored = true
		part.CanCollide = (opts and opts.collidable) and true or false
		if opts and opts.castShadow == false then
			part.CastShadow = false
		end
		part.Parent = parent
		return part
	end

	-- Generate a broad, umbral canopy using blue-noise style spacing for even distribution.
	local function generateUmbralCanopy(
		topCenter: Vector3,
		parent: Instance,
		rng: Random,
		bs: number,
		canopyRadiusBlocks: number
	)
		local function placeLeaf(p: Vector3, transparency: number)
			local leaf = createBlock(
				p,
				Vector3.new(bs, bs, bs) * rng:NextNumber(1.10, 1.35),
				(rng:NextNumber() > 0.8) and LEAVES_ACCENT_COLOR or LEAVES_COLOR,
				Enum.Material.SmoothPlastic,
				parent,
				{ collidable = false, castShadow = false }
			)
			leaf.CanQuery = false
			leaf.CanTouch = false
			leaf.Transparency = math.clamp(transparency, 0, 1)
			return leaf
		end

		-- Spatial hash helpers for fast min-distance checks
		local function gridKey(ix: number, iz: number): string
			return tostring(ix) .. ":" .. tostring(iz)
		end
		local function canAccept(
			grid: { [string]: { Vector2 } },
			cell: number,
			xw: number,
			zw: number,
			minDist: number
		): boolean
			local ix = math.floor(xw / cell)
			local iz = math.floor(zw / cell)
			local min2 = minDist * minDist
			for dx = -1, 1 do
				for dz = -1, 1 do
					local key = gridKey(ix + dx, iz + dz)
					local bucket = grid[key]
					if bucket then
						for _, v in ipairs(bucket) do
							local dxw = xw - v.X
							local dzw = zw - v.Y
							if (dxw * dxw + dzw * dzw) < min2 then
								return false
							end
						end
					end
				end
			end
			return true
		end
		local function insertGrid(grid: { [string]: { Vector2 } }, cell: number, xw: number, zw: number)
			local ix = math.floor(xw / cell)
			local iz = math.floor(zw / cell)
			local key = gridKey(ix, iz)
			if not grid[key] then
				grid[key] = {}
			end
			table.insert(grid[key], Vector2.new(xw, zw))
		end

		-- Top dome with even spacing
		do
			local r = canopyRadiusBlocks
			local domeH = bs * 0.5 -- gentle dome height
			local slopeX = rng:NextNumber(-0.03, 0.03) * bs
			local slopeZ = rng:NextNumber(-0.03, 0.03) * bs
			local minDist = 1.5 * bs
			local cell = minDist
			local grid: { [string]: { Vector2 } } = {}
			for x = -r, r do
				for z = -r, r do
					local d = math.sqrt(x * x + z * z)
					if d <= r + rng:NextNumber(-0.2, 0.2) then
						-- Small jitter to avoid perfect lattice
						local jx = rng:NextNumber(-0.6, 0.6) * bs
						local jz = rng:NextNumber(-0.6, 0.6) * bs
						local xw = topCenter.X + x * bs + jx
						local zw = topCenter.Z + z * bs + jz
						if canAccept(grid, cell, xw, zw, minDist) then
							insertGrid(grid, cell, xw, zw)
							local dome = domeH * (1 - (d / math.max(1, r)) ^ 2)
							local tilt = (x * slopeX + z * slopeZ) / math.max(1, r)
							local noiseY = rng:NextNumber(-0.15, 0.15) * bs
							local pos = Vector3.new(xw, topCenter.Y + dome + tilt + noiseY, zw)
							local edgeFrac = math.clamp(d / math.max(1, r), 0, 1)
							local t = 0.05 + 0.55 * edgeFrac + rng:NextNumber(-0.03, 0.03)
							placeLeaf(pos, t)
						end
					end
				end
			end
		end

		-- Underside bowl with even spacing (fewer layers)
		local layers = 2
		for li = 1, layers do
			local frac = li / layers
			local r = math.max(1, canopyRadiusBlocks - math.floor(frac * (canopyRadiusBlocks * 0.6)))
			local yOff = -bs * (li * 0.6)
			local minDist = 1.7 * bs
			local cell = minDist
			local grid: { [string]: { Vector2 } } = {}
			for x = -r, r do
				for z = -r, r do
					local d = math.sqrt(x * x + z * z)
					if d <= r + rng:NextNumber(-0.25, 0.15) then
						local jx = rng:NextNumber(-0.6, 0.6) * bs
						local jz = rng:NextNumber(-0.6, 0.6) * bs
						local xw = topCenter.X + x * bs + jx
						local zw = topCenter.Z + z * bs + jz
						if canAccept(grid, cell, xw, zw, minDist) then
							insertGrid(grid, cell, xw, zw)
							local noiseY = rng:NextNumber(-0.3, 0.3) * bs
							local pos = Vector3.new(xw, topCenter.Y + yOff + noiseY, zw)
							local edgeFrac = math.clamp(d / math.max(1, r), 0, 1)
							local t = 0.07 + 0.43 * edgeFrac + rng:NextNumber(-0.03, 0.03)
							placeLeaf(pos, t)
						end
					end
				end
			end
		end
	end

	-- Helper: Gaussian (normal) sampler via Box-Muller
	local function gaussian(rng: Random, mean: number, stdDev: number): number
		local u1 = rng:NextNumber()
		if u1 <= 1e-7 then
			u1 = 1e-7
		end -- avoid log(0)
		local u2 = rng:NextNumber()
		local mag = math.sqrt(-2 * math.log(u1))
		local z0 = mag * math.cos(2 * math.pi * u2)
		return mean + z0 * stdDev
	end

	-- Spawn procedural blocky tree at position with optional rng/opts
	-- opts = { scale: number? }
	function TreeFactory.SpawnBlocky(position: Vector3, rng: Random?, opts: { scale: number }?): Model
		local r = rng or Random.new()
		local scale = (opts and opts.scale) or 1
		local bs = BLOCK_SIZE * math.max(scale, 0.1)
		local model = Instance.new("Model")
		model.Name = "BlockTree"

		-- Sample trunk height (in blocks) from a truncated Gaussian, then apply scale like before
		local meanH = (MIN_TRUNK_HEIGHT + MAX_TRUNK_HEIGHT) * 0.5
		local stdH = math.max(1, (MAX_TRUNK_HEIGHT - MIN_TRUNK_HEIGHT) / 6) -- ~99.7% within range
		local rawH = gaussian(r, meanH, stdH)
		local trunkHeight = math.max(1, math.floor(math.clamp(rawH, MIN_TRUNK_HEIGHT, MAX_TRUNK_HEIGHT) * scale + 0.5))
		local trunkThickness = bs * (TRUNK_THICKNESS + r:NextNumber(-TRUNK_VARIATION, TRUNK_VARIATION))

		-- Slight wobble
		local wobble = r:NextNumber(-bs * 0.6, bs * 0.6)
		local wobbleZ = r:NextNumber(-bs * 0.6, bs * 0.6)

		-- Main trunk
		local baseTrunkPart: BasePart? = nil
		for i = 0, trunkHeight - 1 do
			local trunkPos = position
				+ Vector3.new(wobble * (i / trunkHeight), i * bs + bs * 0.5, wobbleZ * (i / trunkHeight))
			local trunkBlock = createBlock(
				trunkPos,
				Vector3.new(trunkThickness, bs, trunkThickness),
				TRUNK_COLOR,
				Enum.Material.Wood,
				model,
				{ collidable = true, castShadow = false }
			)
			if i == 0 then
				baseTrunkPart = trunkBlock
			end
			local heightFrac = i / trunkHeight
			local radius = if heightFrac < 0.7 then 1 else 0
			for offsetX = -radius, radius do
				for offsetZ = -radius, radius do
					if offsetX == 0 and offsetZ == 0 then
						continue
					end
					if heightFrac >= 0.25 and offsetX ~= 0 and offsetZ ~= 0 then
						continue
					end
					createBlock(
						trunkPos + Vector3.new(offsetX * trunkThickness, 0, offsetZ * trunkThickness),
						trunkBlock.Size,
						TRUNK_COLOR,
						Enum.Material.Wood,
						model,
						{ collidable = true, castShadow = false }
					)
				end
			end
		end

		-- Branches
		for i = math.floor(trunkHeight * BRANCH_START_HEIGHT), trunkHeight - 2 do
			if r:NextNumber() < BRANCH_CHANCE then
				local dir = r:NextInteger(1, 4)
				local length =
					math.max(1, math.floor((r:NextInteger(MIN_BRANCH_LENGTH, MAX_BRANCH_LENGTH)) * scale + 0.5))
				local branchThickness = math.max(bs * 0.8, trunkThickness * 0.7)
				for j = 0, length - 1 do
					local bx, bz = 0, 0
					if dir == 1 then
						bx = j + 1
					elseif dir == 2 then
						bx = -(j + 1)
					elseif dir == 3 then
						bz = j + 1
					else
						bz = -(j + 1)
					end
					local branchPos = position
						+ Vector3.new(
							wobble * (i / trunkHeight) + bx * bs,
							i * bs + bs * 0.5 + math.floor(j / 2) * bs,
							wobbleZ * (i / trunkHeight) + bz * bs
						)
					createBlock(
						branchPos,
						Vector3.new(branchThickness, bs, branchThickness),
						TRUNK_COLOR,
						Enum.Material.Wood,
						model,
						{ collidable = false, castShadow = false }
					)
				end
				-- local tip = position + Vector3.new(...)
			end
		end

		local treeTop = position + Vector3.new(wobble, trunkHeight * bs, wobbleZ)

		-- Generate a single, large umbral canopy centered at the top
		local canopyRadiusBlocks = math.floor(r:NextNumber(8, 11) * math.max(scale, 1.0))
		generateUmbralCanopy(treeTop, model, r, bs, canopyRadiusBlocks)

		-- Add a visible walk surface plate for testing
		local plateSizeXZ = bs * (canopyRadiusBlocks * 2) * 0.9
		local plate = Instance.new("Part")
		plate.Name = "LeafWalkSurface"
		plate.Size = Vector3.new(math.max(4, plateSizeXZ), 1, math.max(4, plateSizeXZ))
		plate.Position = treeTop + Vector3.new(0, bs * 0.5, 0)
		plate.Anchored = true
		plate.CanCollide = true
		plate.CanQuery = true
		plate.CanTouch = false
		plate.Material = Enum.Material.SmoothPlastic
		plate.Color = Color3.fromRGB(255, 255, 0) -- kept color but fully invisible
		plate.Transparency = 1
		plate.CastShadow = false
		plate.Parent = model
		ClientError.try("TreeFactory.TagWalkSurface", function()
			CollectionService:AddTag(plate, "WalkSurface")
			return true
		end)

		-- PrimaryPart & tags
		if baseTrunkPart then
			model.PrimaryPart = baseTrunkPart
		else
			local primary = model:FindFirstChildWhichIsA("BasePart")
			if primary then
				model.PrimaryPart = primary
			end
		end
		ClientError.try("TreeFactory.TagModel", function()
			CollectionService:AddTag(model, "BlockTree")
			return true
		end)
		ClientError.try("TreeFactory.ModelStreamingMode", function()
			if model:IsA("Model") then
				model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
			end
			return true
		end)

		model.Parent = Workspace
		return model
	end
end

return TreeFactory
