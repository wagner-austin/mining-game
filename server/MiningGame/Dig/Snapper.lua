--!strict
-- Dig/Snapper.lua
-- Snap a world position inside or near an axis-aligned volume AABB with tolerances.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(Shared:WaitForChild("Logger"))
local log = Logger.new("DigSnap")

local Snapper = {}

-- Returns (ok: boolean, adjustedPos: Vector3)
function Snapper.snapInsideIfNearAABB(
	worldPos: Vector3,
	origin: CFrame,
	half: Vector3,
	faceEps: number,
	edgeEps: number,
	cornerEps: number
): (boolean, Vector3)
	local center = origin.Position
	local localPos = worldPos - center
	local function over(v: number, h: number)
		return math.max(0, math.abs(v) - h)
	end
	local ox = over(localPos.X, half.X)
	local oy = over(localPos.Y, half.Y)
	local oz = over(localPos.Z, half.Z)
	local outsideAxes = (ox > 0 and 1 or 0) + (oy > 0 and 1 or 0) + (oz > 0 and 1 or 0)
	local maxOver = math.max(ox, oy, oz)

	if outsideAxes == 0 then
		return true, worldPos
	end

	local allow = (outsideAxes == 1 and maxOver <= faceEps)
		or (outsideAxes == 2 and maxOver <= edgeEps)
		or (outsideAxes == 3 and maxOver <= cornerEps)

	if not allow then
		return false, worldPos
	end

	local tiny = 1e-3
	localPos = Vector3.new(
		math.clamp(localPos.X, -half.X + tiny, half.X - tiny),
		math.clamp(localPos.Y, -half.Y + tiny, half.Y - tiny),
		math.clamp(localPos.Z, -half.Z + tiny, half.Z - tiny)
	)
	local adjusted = center + localPos
	log:debug("Snap adjusted from %s to %s", tostring(worldPos), tostring(adjusted))
	return true, adjusted
end

return Snapper
