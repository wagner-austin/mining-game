--!strict
-- Dig/HoldLoop.lua
-- Continuous dig loop (hold-to-dig). Encapsulates state and loop logic.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(Shared:WaitForChild("Logger"))
local GridMath = require(Shared:WaitForChild("Utils"):WaitForChild("GridMath"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Time = require(Shared:WaitForChild("Time"))
local Types = require(Shared:WaitForChild("Types"))
local VolumeRegistry = require(script.Parent:WaitForChild("VolumeRegistry"))

local log = Logger.new("HoldLoop")

local holdState: { [Player]: { active: boolean, target: Vector3, version: number } } = {}
local loopVersion: { [Player]: number } = {}

local function runHoldLoop(service, player: Player)
	loopVersion[player] = (loopVersion[player] or 0) + 1
	local myVer = loopVersion[player]
	local iterationCount = 0

	while holdState[player] and holdState[player].active and myVer == loopVersion[player] and player.Parent do
		iterationCount += 1
		local target = holdState[player].target
		local result: Types.DigResult = service:ProcessDigRequest(player, target)

		local sleepSec = GameConfig.Timing.AUTO_DIG_INITIAL_DELAY
		if result and result.ok then
			local cube = service.playerCubes[player]
			if cube then
				local baseX, baseY, baseZ
				if result.centerCell then
					baseX = result.centerCell.x
					baseY = result.centerCell.y
					baseZ = result.centerCell.z
				else
					local originForStep = result.volumeOrigin or cube.origin
					baseX, baseY, baseZ = GridMath.worldToCell(target, originForStep, GameConfig.Grid.CELL_SIZE_STUDS)
				end

				local nextY = baseY - 1
				local halfCells = (GameConfig.Grid.CUBE_SIZE_STUDS / GameConfig.Grid.CELL_SIZE_STUDS) / 2
				if result.volumeId then
					local vol = VolumeRegistry.GetVolumes()[result.volumeId]
					if vol and vol.state and vol.state.extentsCells then
						halfCells = math.floor(vol.state.extentsCells.Y)
					end
				end
				if nextY >= -halfCells then
					local originForStep = result.volumeOrigin or cube.origin
					holdState[player].target =
						GridMath.cellToWorld(baseX, nextY, baseZ, originForStep, GameConfig.Grid.CELL_SIZE_STUDS)
					-- Server uses monotonic time for gating
					sleepSec = (result.nextAllowedAt and math.max(result.nextAllowedAt - Time.mono(), 0))
						or GameConfig.Timing.AUTO_DIG_DEFAULT_INTERVAL
				else
					break
				end
			else
				sleepSec = GameConfig.Timing.AUTO_DIG_DEFAULT_INTERVAL
			end
		elseif result and result.reason == "On cooldown" then
			-- Compare against server monotonic timebase
			local nowM = Time.mono()
			local nextAt = result.nextAllowedAt or nowM
			sleepSec = math.max(nextAt - nowM, 0.05)
		elseif result and result.reason == "No cells dug" then
			local cube = service.playerCubes[player]
			if cube then
				local baseX, baseY, baseZ
				if result.centerCell then
					baseX = result.centerCell.x
					baseY = result.centerCell.y
					baseZ = result.centerCell.z
				else
					local originForStep = result.volumeOrigin or cube.origin
					baseX, baseY, baseZ = GridMath.worldToCell(target, originForStep, GameConfig.Grid.CELL_SIZE_STUDS)
				end
				local nextY = baseY - 1
				local halfCells = (GameConfig.Grid.CUBE_SIZE_STUDS / GameConfig.Grid.CELL_SIZE_STUDS) / 2
				if result.volumeId then
					local vol = VolumeRegistry.GetVolumes()[result.volumeId]
					if vol and vol.state and vol.state.extentsCells then
						halfCells = math.floor(vol.state.extentsCells.Y)
					end
				end
				if nextY >= -halfCells then
					local originForStep = result.volumeOrigin or cube.origin
					holdState[player].target =
						GridMath.cellToWorld(baseX, nextY, baseZ, originForStep, GameConfig.Grid.CELL_SIZE_STUDS)
					sleepSec = 0.05
				else
					break
				end
			else
				sleepSec = 0.2
			end
		elseif result and result.reason then
			log:debug("Hold dig stopped for %s: %s", player.Name, tostring(result.reason))
			break
		end

		task.wait(math.max(sleepSec, 0.05))
	end

	log:info("Hold loop ended for %s after %d iterations", player.Name, iterationCount)
	if holdState[player] and holdState[player].version == myVer then
		holdState[player] = nil
	end
end

local HoldLoop = {}

function HoldLoop.Start(service, player: Player, initialWorldPos: Vector3)
	HoldLoop.Stop(service, player)
	holdState[player] = { active = true, target = initialWorldPos, version = (loopVersion[player] or 0) + 1 }
	log:debug("Starting hold dig for %s at %s", player.Name, tostring(initialWorldPos))
	task.spawn(function()
		runHoldLoop(service, player)
	end)
end

function HoldLoop.UpdateTarget(_service, player: Player, worldPos: Vector3)
	if holdState[player] then
		holdState[player].target = worldPos
	end
end

function HoldLoop.Stop(_service, player: Player)
	if holdState[player] then
		log:debug("Stopping hold dig for %s", player.Name)
		holdState[player].active = false
	end
	loopVersion[player] = (loopVersion[player] or 0) + 1
end

function HoldLoop.CleanupOnRemoving(_service, player: Player)
	holdState[player] = nil
	loopVersion[player] = nil
end

return HoldLoop
