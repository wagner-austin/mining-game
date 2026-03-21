--!strict
-- Dig/VolumeRegistry.lua
-- Centralized store for volumes and spatial hash. No lazy DI; explicit container per call.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(Shared:WaitForChild("Logger"))
local ServiceValidator = require(Shared:WaitForChild("ServiceValidator"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Types = require(Shared:WaitForChild("Types"))

local log = Logger.new("DigVolumes")

type Volume = Types.Volume

local volumesById: { [string]: Volume } = {}
local playerCubeVolumeId: { [Player]: string? } = {}

-- Spatial hash (XZ)
local HASH_CELL_STUDS = 256
local volumeHash: { [string]: { [string]: boolean } } = {}
local volumeHashKeys: { [string]: { string } } = {}

local function addVolumeToHash(vol: Volume)
	if not (vol and vol.origin and vol.sizeStuds) then
		return
	end
	if vol.kind ~= "island" then
		return
	end
	local half = vol.sizeStuds * 0.5
	local minX = vol.origin.Position.X - half.X
	local maxX = vol.origin.Position.X + half.X
	local minZ = vol.origin.Position.Z - half.Z
	local maxZ = vol.origin.Position.Z + half.Z
	local kx0 = math.floor(minX / HASH_CELL_STUDS)
	local kx1 = math.floor(maxX / HASH_CELL_STUDS)
	local kz0 = math.floor(minZ / HASH_CELL_STUDS)
	local kz1 = math.floor(maxZ / HASH_CELL_STUDS)
	local keys = {}
	for gx = kx0, kx1 do
		for gz = kz0, kz1 do
			local key = tostring(gx) .. ":" .. tostring(gz)
			volumeHash[key] = volumeHash[key] or {}
			volumeHash[key][vol.id] = true
			table.insert(keys, key)
		end
	end
	volumeHashKeys[vol.id] = keys
end

local function removeVolumeFromHash(id: string)
	local keys = volumeHashKeys[id]
	if not keys then
		return
	end
	for _, key in ipairs(keys) do
		local bucket = volumeHash[key]
		if bucket then
			bucket[id] = nil
			local hasAny = false
			for _ in pairs(bucket) do
				hasAny = true
				break
			end
			if not hasAny then
				volumeHash[key] = nil
			end
		end
	end
	volumeHashKeys[id] = nil
end

local VolumeRegistry = {}

local function halfExtentsCells(sizeStuds: Vector3): Vector3
	local cell = GameConfig.Grid.CELL_SIZE_STUDS
	return Vector3.new(
		math.floor((sizeStuds.X / cell) / 2),
		math.floor((sizeStuds.Y / cell) / 2),
		math.floor((sizeStuds.Z / cell) / 2)
	)
end

function VolumeRegistry.Register(
	container,
	init: {
		id: string?,
		kind: string,
		origin: CFrame,
		sizeStuds: Vector3,
		permissions: { public: boolean, ownerUserId: number? }?,
		meta: any?,
		state: Types.CubeState?,
	}
): Volume
	local GridService = ServiceValidator.get(container, "GridService")
	local Time = require(Shared:WaitForChild("Time"))
	-- Explicitly type id as string (not string?) since fallback guarantees non-nil
	local id: string = init.id
		or (init.kind .. ":" .. tostring(Time.mono()):gsub("%.", "") .. ":" .. tostring(math.random(1, 1e9)))
	local perms = init.permissions or { public = false, ownerUserId = nil }
	local state = init.state or GridService:CreateCubeState(perms.ownerUserId or 0, "tier1")
	-- Only set extentsCells if not already set (CubeVolume sets it for islands after terrain snapping)
	if not state.extentsCells then
		state.extentsCells = halfExtentsCells(init.sizeStuds)
	end

	local vol: Volume = {
		id = id,
		kind = ((init.kind == "cube" or init.kind == "island") and init.kind or "cube") :: Types.VolumeKind,
		origin = init.origin,
		sizeStuds = init.sizeStuds,
		permissions = perms,
		meta = init.meta,
		state = state,
	}
	volumesById[id] = vol
	addVolumeToHash(vol)
	log:debug(
		"Registered volume %s kind=%s at %s size=%s",
		id,
		tostring(vol.kind),
		tostring(vol.origin.Position),
		tostring(vol.sizeStuds)
	)
	return vol
end

function VolumeRegistry.Unregister(id: string): boolean
	if volumesById[id] then
		removeVolumeFromHash(id)
		volumesById[id] = nil
		log:debug("Unregistered volume %s", id)
		return true
	end
	return false
end

function VolumeRegistry.UpdateOrigin(id: string, origin: CFrame)
	local v = volumesById[id]
	if v then
		v.origin = origin
	end
end

function VolumeRegistry.GetVolumes()
	return volumesById
end

function VolumeRegistry.GetHash()
	return volumeHash
end

function VolumeRegistry.SetPlayerCubeVolumeId(player: Player, id: string?)
	playerCubeVolumeId[player] = id
end

function VolumeRegistry.GetPlayerCubeVolumeId(player: Player): string?
	return playerCubeVolumeId[player]
end

return VolumeRegistry
