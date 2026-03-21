--!strict
-- Dig/Picker.lua
-- Volume picking helpers: prefer player's cube, else island volumes via spatial hash + scan.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(Shared:WaitForChild("Logger"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Types = require(Shared:WaitForChild("Types"))
local Snapper = require(script.Parent:WaitForChild("Snapper"))

local log = Logger.new("DigPicker")

local HASH_CELL_STUDS = 256 -- keep in sync with DigService for now

local function gridKey(x: number, z: number): string
	return tostring(math.floor(x / HASH_CELL_STUDS)) .. ":" .. tostring(math.floor(z / HASH_CELL_STUDS))
end

local Picker = {}

-- Pick any volume at worldPos. Cube preferred when player provided.
-- volumesById: {[string]: Volume}
-- playerCubeVolumeId: {[Player]: string}
-- volumeHash: {[string]: {[string]: boolean}}
type Volume = Types.Volume
type VolumeHash = { [string]: { [string]: boolean } }

function Picker.pickVolume(
	worldPos: Vector3,
	_player: Player?,
	volumesById: { [string]: Volume },
	cubeVolId: string?,
	volumeHash: VolumeHash
): Volume?
	local cell = GameConfig.Grid.CELL_SIZE_STUDS

	-- Prefer player's cube
	if cubeVolId then
		local cv = volumesById[cubeVolId]
		if cv then
			local half = cv.sizeStuds * 0.5
			local faceEps = math.max(4.0, cell * GameConfig.Digging.VOLUME_PICK_FACE_TOLERANCE)
			local ok = Snapper.snapInsideIfNearAABB(
				worldPos,
				cv.origin,
				half,
				faceEps,
				math.max(2.0, cell * GameConfig.Digging.VOLUME_EDGE_TOLERANCE),
				math.max(1.5, cell * GameConfig.Digging.VOLUME_CORNER_TOLERANCE)
			)
			if ok then
				log:debug("Pick: cube id=%s at %s", tostring(cv.id), tostring(worldPos))
				return cv
			end
		end
	end

	-- Spatial hash lookup for islands
	local key = gridKey(worldPos.X, worldPos.Z)
	local bucket = volumeHash[key]
	if bucket then
		for id, _ in pairs(bucket) do
			local vol = volumesById[id]
			if vol and vol.kind == "island" then
				local half = vol.sizeStuds * 0.5
				local faceEps = math.max(4.0, cell * GameConfig.Digging.VOLUME_PICK_FACE_TOLERANCE)
				local ok = Snapper.snapInsideIfNearAABB(
					worldPos,
					vol.origin,
					half,
					faceEps,
					math.max(2.0, cell * GameConfig.Digging.VOLUME_EDGE_TOLERANCE),
					math.max(1.5, cell * GameConfig.Digging.VOLUME_CORNER_TOLERANCE)
				)
				if ok then
					log:debug("Pick: island(hash) id=%s at %s", tostring(vol.id), tostring(worldPos))
					return vol
				end
			end
		end
	end

	-- Full scan fallback
	for _, vol in pairs(volumesById) do
		if vol.kind == "island" then
			local half = vol.sizeStuds * 0.5
			local faceEps = math.max(4.0, cell * GameConfig.Digging.VOLUME_PICK_FACE_TOLERANCE)
			local ok = Snapper.snapInsideIfNearAABB(
				worldPos,
				vol.origin,
				half,
				faceEps,
				math.max(2.0, cell * GameConfig.Digging.VOLUME_EDGE_TOLERANCE),
				math.max(1.5, cell * GameConfig.Digging.VOLUME_CORNER_TOLERANCE)
			)
			if ok then
				log:debug("Pick: island(scan) id=%s at %s", tostring(vol.id), tostring(worldPos))
				return vol
			end
		end
	end
	log:debug("Pick: no volume at %s", tostring(worldPos))
	return nil
end

-- Pick only islands at worldPos (used for cube->island retry)
function Picker.pickIsland(worldPos: Vector3, volumesById: { [string]: Volume }, volumeHash: VolumeHash): Volume?
	return Picker.pickVolume(worldPos, nil, volumesById, nil, volumeHash)
end

return Picker
