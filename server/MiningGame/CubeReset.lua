--!strict
-- CubeReset.lua
-- Centralized helpers to reset a player's cube with optional gating/reseed/save

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Time = require(Shared:WaitForChild("Time"))

local CubeReset = {}

-- Compute dug fraction for a cube state
function CubeReset.computeDugFraction(container, state): (number, number, number)
	if not state then
		return 0, 1, 0
	end
	local GridService = container:Get("GridService")
	local stats = GridService:GetChunkStats(state)
	local ext = state.extentsCells
	local cellSize = GameConfig.Grid.CELL_SIZE_STUDS
	local sideX, sideY, sideZ
	if ext and typeof(ext) == "Vector3" then
		sideX, sideY, sideZ = ext.X * 2, ext.Y * 2, ext.Z * 2
	else
		local perSide = math.floor(GameConfig.Grid.CUBE_SIZE_STUDS / cellSize)
		sideX, sideY, sideZ = perSide, perSide, perSide
	end
	local totalCells = math.max(1, sideX * sideY * sideZ)
	local dug = math.max(0, stats.dugCells or 0)
	return (dug / totalCells), totalCells, dug
end

-- Reset a player's cube model+state with optional gating and reseed
-- opts = { gateAtMostMinedFrac: number?, reseed: boolean?, saveAfterReset: boolean? }
type ResetOpts = {
	gateAtLeastMinedFrac: number?,
	gateAtMostMinedFrac: number?,
	reseed: boolean?,
	saveAfterReset: boolean?,
}

type ResetResponse = {
	ok: boolean,
	success: boolean,
	err: string?,
	reason: string?,
	minedFrac: number?,
	threshold: number?,
}

function CubeReset.resetPlayerCube(container, player: Player, opts: ResetOpts?): ResetResponse
	local o: ResetOpts = (opts :: any) or {}
	local DataService = container:Get("DataService")
	local DigService = container:Get("DigService")

	local state = DataService:GetCubeData(player)
	local cubeInfo = DigService.playerCubes[player]
	if not state or not cubeInfo then
		return { ok = false, success = false, err = "NO_CUBE", reason = "No cube data found" }
	end

	-- Evaluate gates if provided
	do
		local frac: number = CubeReset.computeDugFraction(container, state)
		if o.gateAtLeastMinedFrac ~= nil then
			if frac < o.gateAtLeastMinedFrac then
				return {
					ok = false,
					success = false,
					err = "NOT_ENOUGH_MINED",
					reason = "Mine more to enable manual reset",
					minedFrac = frac,
					threshold = o.gateAtLeastMinedFrac,
				}
			end
		end
		if o.gateAtMostMinedFrac ~= nil then
			if frac > o.gateAtMostMinedFrac then
				return {
					ok = false,
					success = false,
					err = "TOO_DUG",
					reason = "Gate exceeded",
					minedFrac = frac,
					threshold = o.gateAtMostMinedFrac,
				}
			end
		end
	end

	-- Clear state in-place
	state.chunks = {}
	state.totalDug = 0
	state.createdAt = Time.unix()

	if o.reseed then
		local rng = Random.new()
		local newSeed = rng:NextInteger(1, 1000000)
		DataService:UpdateMaterialPrefs(player, { compositionSeed = newSeed, variationMode = "PER_REGEN" })
	end

	if o.saveAfterReset then
		local ErrorService = require(script.Parent.ErrorService)
		ErrorService.safecall("CubeReset.SaveCubeAsync", function()
			DataService:SaveCubeAsync(player)
		end)
	end

	-- Destroy model and re-init
	local model = cubeInfo.model :: Instance?
	if model then
		model:Destroy()
		cubeInfo.model = nil
	end
	DigService:InitializePlayerCube(player, { skipEnsureBase = true })

	return { ok = true, success = true }
end

return CubeReset
