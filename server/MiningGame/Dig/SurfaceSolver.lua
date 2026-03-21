--!strict
-- Dig/SurfaceSolver.lua
-- Robust server-side surface detection around a candidate position.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(Shared:WaitForChild("Logger"))
local TerrainSurfaceDetector = require(Shared:WaitForChild("TerrainSurfaceDetector"))

local log = Logger.new("SurfaceSolver")

local SurfaceSolver = {}

local OFFSETS = {
	Vector3.new(0, 0, 0),
	Vector3.new(1, 0, 0),
	Vector3.new(-1, 0, 0),
	Vector3.new(0, 1, 0),
	Vector3.new(0, -1, 0),
	Vector3.new(0, 0, 1),
	Vector3.new(0, 0, -1),
}

-- Try original, then adjusted, then a small local neighborhood to find a stable surface.
function SurfaceSolver.find(worldPos: Vector3, adjusted: Vector3, cellSize: number): (boolean, Vector3?, Vector3?)
	local hasSurface, surfacePos, surfaceNormal
	hasSurface, surfacePos, surfaceNormal = TerrainSurfaceDetector.CheckCellSurface(worldPos, cellSize)
	if hasSurface then
		return true, surfacePos, surfaceNormal
	end

	hasSurface, surfacePos, surfaceNormal = TerrainSurfaceDetector.CheckCellSurface(adjusted, cellSize)
	if hasSurface then
		return true, surfacePos, surfaceNormal
	end

	-- Local neighborhood search to reduce false negatives from voxel sampling
	for i = 2, #OFFSETS do
		local p = worldPos + OFFSETS[i] * (cellSize * 0.5)
		hasSurface, surfacePos, surfaceNormal = TerrainSurfaceDetector.CheckCellSurface(p, cellSize)
		if hasSurface then
			log:debug("Surface found via neighborhood search at %s", tostring(p))
			return true, surfacePos, surfaceNormal
		end
	end
	return false, nil, nil
end

return SurfaceSolver
