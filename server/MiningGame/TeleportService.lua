--!strict
-- TeleportService.lua
-- Handles simple in-world teleports (e.g., random sky teleport)

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(Shared:WaitForChild("Logger"))
local EventBus = require(Shared:WaitForChild("EventBus"))
local RequestNames = require(Shared:WaitForChild("RequestNames"))
-- No GameConfig or WorldGenUtils usage here

local log = Logger.new("TeleportService")
local Bus = EventBus.global()

local TeleportService = {}
TeleportService.__index = TeleportService

local function getWorldBounds(): (Vector3, Vector3)
	local spawnBounds = Workspace:FindFirstChild("SpawnBounds")
	if spawnBounds and spawnBounds:IsA("BasePart") then
		local c = spawnBounds.CFrame.Position
		local s = spawnBounds.Size
		local min = Vector3.new(c.X - s.X * 0.5, c.Y, c.Z - s.Z * 0.5)
		local max = Vector3.new(c.X + s.X * 0.5, c.Y, c.Z + s.Z * 0.5)
		return min, max
	end
	-- Fallback area if SpawnBounds is missing
	return Vector3.new(-1000, 0, -1000), Vector3.new(1000, 0, 1000)
end

local function randomSkyPosition(): CFrame
	local min, max = getWorldBounds()
	local rx = math.random() * (max.X - min.X) + min.X
	local rz = math.random() * (max.Z - min.Z) + min.Z
	-- Choose a height well above map and islands
	-- Absolute height target: lowered by 200 -> 600 to 1000 world Y
	local ry = math.random(600, 1000)
	-- Face toward map center for consistency
	local lookAt = Vector3.new(0, ry, 0)
	local pos = Vector3.new(rx, ry, rz)
	return CFrame.new(pos, lookAt)
end

function TeleportService:Init(container)
	self._container = container
	log:info("Initialized")
end

function TeleportService:Start()
	-- Handle client requests to teleport to a random sky position
	Bus:on(RequestNames.TELEPORT_RANDOM_SKY, function(evt)
		local player = evt and evt.from
		if not player or not player.Parent then
			return
		end
		local character = player.Character
		if not character then
			return
		end
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp or not hrp:IsA("BasePart") then
			return
		end

		local target = randomSkyPosition()
		-- Soft safety: unseat and clear velocities
		local ErrorService = require(script.Parent.ErrorService)
		ErrorService.safecall("TeleportService.ClearVelocities", function()
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Sit = false
			end
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.AssemblyAngularVelocity = Vector3.zero
			return true
		end)
		hrp.CFrame = target
		log:info("Teleported %s to sky @ %s", player.Name, tostring(target.Position))
	end)
	log:info("Started")
end

return TeleportService
