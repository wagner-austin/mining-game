--!strict
--[[
    CubeVisuals.lua
    Creates and manages visual indicators for mining cubes.
    
    Features:
    - Neon floor glow outlines
    - Dynamic lighting effects
    - Material-aware positioning
    - Configurable colors and dimensions
    - CollectionService tagging for effects
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Logger = require(Shared:WaitForChild("Logger"))
local MaterialDefinitions = require(Shared:WaitForChild("MaterialDefinitions"))
local MaterialKeys = require(Shared:WaitForChild("MaterialKeys"))
local MIN_WATER = GameConfig.Terrain.MIN_WATER_OCCUPANCY
local VOX = GameConfig.Terrain.VOXEL_RESOLUTION
local VIS = GameConfig.Visuals
local log = Logger.new("CubeVisuals")
local GlowBarService = require(script.Parent:WaitForChild("GlowBarService"))

local CubeVisuals = {}

-- Clear any existing indicators to prevent duplication
local function clearExistingIndicators(model: Model)
	local old = model:FindFirstChild("Indicators")
	if old then
		old:Destroy()
	end
end

--[[
    Create a glowing neon outline at the base of the cube.
    Adds visual appeal and helps players locate their cube.
    
    @param model: Model - The cube model to add visuals to
    @param cubeOrigin: CFrame - The cube's center position
    @param size: number - The cube size in studs
    @param floorMaterial: Enum.Material? - Optional floor material for positioning
]]
function CubeVisuals.CreateFloorGlow(model: Model, cubeOrigin: CFrame, size: number, floorMaterial: Enum.Material?)
	clearExistingIndicators(model)

	log:debug(
		"Creating floor glow - Cube origin Y: %.2f, Size: %.2f, FloorMaterial: %s",
		cubeOrigin.Position.Y,
		size,
		tostring(floorMaterial)
	)

	-- Create folder for organization
	local indicators = Instance.new("Folder")
	indicators.Name = "Indicators"
	indicators.Parent = model

	-- Get config values or use defaults
	local config = GameConfig.Visuals
	local thickness = config and config.FLOOR_GLOW_THICKNESS or VIS.FLOOR_GLOW_THICKNESS
	local width = config and config.FLOOR_GLOW_WIDTH or VIS.FLOOR_GLOW_WIDTH
	local marginMin = config and config.FLOOR_GLOW_MARGIN_MIN or VIS.FLOOR_GLOW_MARGIN_MIN
	local marginMax = config and config.FLOOR_GLOW_MARGIN_MAX or VIS.FLOOR_GLOW_MARGIN_MAX

	-- Slightly larger than the cube so the outline is visible
	local margin = math.clamp(math.floor(size * VIS.MARGIN_PERCENT), marginMin, marginMax) -- Margin based on config percentage
	local glowSize = size + (margin * 2)

	-- Position the edges using the configured ground clearance
	-- Standardized glow height via shared helper
	local edgeY = GlowBarService.GetStandardGlowY(cubeOrigin, size)
	local floorY = cubeOrigin.Position.Y - (size / 2)
	local barBottomY = edgeY - (thickness / 2)

	log:debug(
		"Positions - CubeY: %.2f, FloorY: %.2f, BarBottomY: %.2f, EdgeY: %.2f",
		cubeOrigin.Position.Y,
		floorY,
		barBottomY,
		edgeY
	)
	log:debug(
		"Dimensions - Width: %.2f, Thickness: %.2f, margin: %d, glowSize: %.2f",
		width,
		thickness,
		margin,
		glowSize
	)

	-- Build standardized glow edges via service (extra length preserved)
	local edgesFolder =
		GlowBarService.CreateSquareAroundCube(indicators, cubeOrigin, size, margin, { name = "GlowEdges" })
	-- Gather edges back for terrain replacement pass
	local edgeParts = {}
	for _, ch in ipairs(edgesFolder:GetChildren()) do
		if ch:IsA("BasePart") then
			table.insert(edgeParts, ch)
		end
	end

	-- Swap terrain under each neon bar, preserving shape (deferred so bars appear immediately)
	task.defer(function()
		local Terrain = workspace.Terrain

		-- Get all terrain materials; if missing or empty, build a typed fallback
		local allTerrainMaterials: { Enum.Material } = MaterialDefinitions.AllTerrainEnums
		if (not allTerrainMaterials) or (#allTerrainMaterials == 0) then
			local fmats: { Enum.Material } = {}
			for _, key in ipairs(MaterialKeys.TerrainKeys) do
				local em = MaterialKeys.EnumFromKey[key]
				if em then
					table.insert(fmats, em)
				end
			end
			log:warn("AllTerrainEnums missing, using fallback from MaterialKeys")
			allTerrainMaterials = fmats
		end

		-- USE THE PASSED PARAM if provided; otherwise config default
		local replacementMat = floorMaterial
			or (config and config.FLOOR_GLOW_REPLACEMENT_MATERIAL)
			or Enum.Material.Concrete

		-- First, replace floor under the entire cube footprint at spawn
		local half = size / 2
		local floorDepth = VOX * VIS.FLOOR_DEPTH_MULT -- Configured depth multiplier
		local cubeFloorRegion = Region3.new(
			Vector3.new(cubeOrigin.Position.X - half, floorY - floorDepth, cubeOrigin.Position.Z - half),
			Vector3.new(cubeOrigin.Position.X + half, floorY, cubeOrigin.Position.Z + half)
		):ExpandToGrid(VOX)

		log:debug("Replacing cube footprint with %s", tostring(replacementMat))

		if replacementMat == Enum.Material.Water then
			local mats, occs = Terrain:ReadVoxels(cubeFloorRegion, VOX)
			local sx, sy, sz = mats.Size.X, mats.Size.Y, mats.Size.Z
			for x = 1, sx do
				for y = 1, sy do
					for z = 1, sz do
						if occs[x][y][z] > 0 and mats[x][y][z] ~= Enum.Material.Air then
							mats[x][y][z] = Enum.Material.Water
							if occs[x][y][z] < MIN_WATER then
								occs[x][y][z] = MIN_WATER
							end
						end
					end
				end
			end
			Terrain:WriteVoxels(cubeFloorRegion, VOX, mats, occs)
		else
			for _, src in ipairs(allTerrainMaterials) do
				Terrain:ReplaceMaterial(cubeFloorRegion, VOX, src, replacementMat)
			end
		end

		-- Then, do each glow bar region with CONSISTENT depth and base Y
		local function replaceUnderEdge(edge: BasePart)
			local pad = VIS.SELECTION_PAD
			local depth = VOX * VIS.FLOOR_DEPTH_MULT -- Configured depth to ensure no grass peeks through
			local y0 = barBottomY -- bottom of bar, consistent reference
			local region = Region3.new(
				Vector3.new(
					edge.Position.X - edge.Size.X / 2 - pad,
					y0 - depth,
					edge.Position.Z - edge.Size.Z / 2 - pad
				),
				Vector3.new(edge.Position.X + edge.Size.X / 2 + pad, y0, edge.Position.Z + edge.Size.Z / 2 + pad)
			):ExpandToGrid(VOX)

			log:debug(
				"Replacing materials under edge at Y=%.2f (region Y: %.2f to %.2f)",
				edge.Position.Y,
				y0 - depth,
				y0
			)

			-- Handle water specially, otherwise replace all terrain materials
			if replacementMat == Enum.Material.Water then
				local mats, occs = Terrain:ReadVoxels(region, VOX)
				local sx, sy, sz = mats.Size.X, mats.Size.Y, mats.Size.Z
				for x = 1, sx do
					for y = 1, sy do
						for z = 1, sz do
							if occs[x][y][z] > 0 and mats[x][y][z] ~= Enum.Material.Air then
								mats[x][y][z] = Enum.Material.Water
								if occs[x][y][z] < MIN_WATER then
									occs[x][y][z] = MIN_WATER
								end
							end
						end
					end
				end
				Terrain:WriteVoxels(region, VOX, mats, occs)
			else
				for _, src in ipairs(allTerrainMaterials) do
					Terrain:ReplaceMaterial(region, VOX, src, replacementMat)
				end
			end
		end

		-- Apply material replacement to all edges
		for _, edge in ipairs(edgeParts) do
			replaceUnderEdge(edge)
			-- Uncomment if hillside clipping is still an issue:
			-- clearAboveEdge(edge)
		end

		log:info("Floor glow material pass completed for %d edges; floor=%s", #edgeParts, tostring(replacementMat))
	end)

	return indicators
end

-- Add centralized lighting to the cube
function CubeVisuals.AddCubeLight(bounds: BasePart, size: number)
	-- Get config values or use defaults
	local config = GameConfig.Visuals
	local rangeMult = config and config.LIGHT_RANGE_MULT or 1.25
	local rangeMin = config and config.LIGHT_RANGE_MIN or 24
	local brightness = config and config.LIGHT_BRIGHTNESS or 1.5
	local lightColor = config and config.LIGHT_COLOR or Color3.fromRGB(180, 255, 255)

	-- Single centralized light (cheaper than multiple per-edge lights)
	local att = Instance.new("Attachment")
	att.Parent = bounds

	local light = Instance.new("PointLight")
	light.Range = math.max(size * rangeMult, rangeMin) -- reaches into early digs at night
	light.Brightness = brightness
	light.Color = lightColor
	light.Shadows = false -- optional; set true if you like
	light.Parent = att

	return light
end

-- Create studio-only selection box for debugging
function CubeVisuals.CreateStudioSelectionBox(bounds: BasePart): SelectionBox?
	if not RunService:IsStudio() then
		return nil
	end

	local selectionBox = Instance.new("SelectionBox")
	selectionBox.Adornee = bounds
	selectionBox.LineThickness = 0.1
	selectionBox.Transparency = 0.8
	selectionBox.Color3 = Color3.new(1, 1, 1)
	selectionBox.Parent = bounds

	return selectionBox
end

-- Create optional whole cube glow effect (for monetization/upgrades)
function CubeVisuals.CreateCubeGlow(model: Model, cubeOrigin: CFrame, size: number, enabled: boolean?): Part?
	if not enabled then
		return nil
	end

	-- Get config values or use defaults
	local config = GameConfig.Visuals
	local cubeGlowColor = config and config.CUBE_GLOW_COLOR or Color3.fromRGB(100, 255, 255)
	local cubeGlowTransparency = config and config.CUBE_GLOW_TRANSPARENCY or 0.7

	log:debug("Creating cube glow effect - Size: %.2f", size)

	-- Create a semi-transparent neon cube overlay
	local glowCube = Instance.new("Part")
	glowCube.Name = "CubeGlow"
	glowCube.Size = Vector3.new(size + 0.5, size + 0.5, size + 0.5) -- Slightly larger than the actual cube
	glowCube.CFrame = cubeOrigin
	glowCube.Material = Enum.Material.ForceField -- ForceField gives a nice glow effect
	glowCube.Color = cubeGlowColor
	glowCube.Transparency = cubeGlowTransparency
	glowCube.CanCollide = false
	glowCube.CanTouch = false
	glowCube.CanQuery = false
	glowCube.CastShadow = false
	glowCube.Anchored = true

	-- Parent to indicators folder if it exists, otherwise to model
	local indicators = model:FindFirstChild("Indicators")
	if indicators then
		glowCube.Parent = indicators
	else
		glowCube.Parent = model
	end

	return glowCube
end

-- Create a perimeter glow rectangle at the standard glow height, centered at `center`, with X/Z size `size`.
-- Parts are tagged as GlowBar so MaterialManager handles palette lighting.
-- Deprecated: use GlowBarService.CreatePerimeterAtCube from callers that have cubeOrigin
function CubeVisuals.CreatePerimeterGlowRect(parent: Instance, center: Vector3, size: Vector3)
	-- Keep a fallback that uses center.Y if no cube origin is available.
	local y = center.Y + (VIS.FLOOR_GLOW_GROUND_CLEARANCE or 0.5)
	return GlowBarService.CreateRectAtY(parent, center, size, y, { name = "BasePerimeterGlow" })
end

return CubeVisuals
