--!strict
-- BasePlacement.lua
-- Reusable helper to compute normalized base-plane placement for decor (banners, pedestals, etc.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(Shared:WaitForChild("Logger"))

local log = Logger.new("BasePlacement")

export type Params = {
	alongZT: number, -- 0..1 front->back across base (required)
	inwardXT: number, -- 0..1 left->right across base (required)
	insideZ: number, -- additive world-studs inward from edge (required)
}

local BasePlacement = {}

-- Resolve anchors from a base model produced by PlayerBaseService
local function getAnchors(baseModel: Model): (BasePart?, BasePart?, BasePart?)
	local hsInst = baseModel:FindFirstChild("HighScoreAnchor_Anchor")
	local petsInst = baseModel:FindFirstChild("PetsAnchor_Anchor")
	local shopInst = baseModel:FindFirstChild("ShopAnchor_Anchor")
	local hs = (hsInst and hsInst:IsA("BasePart")) and hsInst or nil
	local pets = (petsInst and petsInst:IsA("BasePart")) and petsInst or nil
	local shop = (shopInst and shopInst:IsA("BasePart")) and shopInst or nil
	if not (hs and pets and shop) then
		log:warn(
			"Missing base anchors (hs=%s pets=%s shop=%s) on %s",
			tostring(hs ~= nil),
			tostring(pets ~= nil),
			tostring(shop ~= nil),
			baseModel:GetFullName()
		)
		return nil, nil, nil
	end
	return hs, pets, shop
end

-- Compute a flat placement point on the player's base from normalized parameters.
-- Returns:
--  centerFlat: Vector3 (Y equals base floor Y), baseFloorY: number
function BasePlacement.compute(baseModel: Model, params: Params): (Vector3?, number?)
	local hs, pets, shop = getAnchors(baseModel)
	if not (hs and pets and shop) then
		return nil, nil
	end

	-- Strict: require all params with no internal fallbacks
	if type(params) ~= "table" then
		return nil, nil
	end
	if type(params.alongZT) ~= "number" then
		return nil, nil
	end
	if type(params.inwardXT) ~= "number" then
		return nil, nil
	end
	if type(params.insideZ) ~= "number" then
		return nil, nil
	end

	local alongZT = math.clamp(params.alongZT, 0, 1)
	local inwardXT = math.clamp(params.inwardXT, 0, 1)
	local insideZ = params.insideZ

	-- Compute edges using anchor positions
	local leftEdgeX = math.min(hs.Position.X, pets.Position.X)
	local rightEdgeX = shop.Position.X
	local baseFloorY = math.min(hs.Position.Y, pets.Position.Y)
	local frontZ = hs.Position.Z
	local backZ = pets.Position.Z

	-- Interpolate to a point on the base rectangle
	local edgeZ = frontZ + (backZ - frontZ) * alongZT
	local centerZ = edgeZ + insideZ
	local centerX = leftEdgeX + (rightEdgeX - leftEdgeX) * inwardXT

	local centerFlat = Vector3.new(centerX, baseFloorY, centerZ)
	return centerFlat, baseFloorY
end

return BasePlacement
