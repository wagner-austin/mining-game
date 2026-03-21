--!strict
-- SpawnGuard.client.lua
-- Coordinates client-side streaming and readiness handshake to prevent spawn falls.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Ready = require(MiningGame:WaitForChild("Ready"))
local Time = require(MiningGame:WaitForChild("Time"))
local ClientError = require(script.Parent.Parent:WaitForChild("ClientErrorHandler"))
local ClientRF = require(MiningGame:WaitForChild("ClientRF"))
local EventBus = require(MiningGame:WaitForChild("EventBus"))
local EventNames = require(MiningGame:WaitForChild("EventNames"))
local GameConfig = require(MiningGame:WaitForChild("GameConfig"))

local Bus = EventBus.global()

-- Feature gate
local function orchestrated()
	local s = GameConfig.Spawn
	return s == nil or s.ORCHESTRATED ~= false
end

if not orchestrated() then
	return -- No-op if feature disabled
end

local didSignalReady = false
local latestOriginCF: CFrame? = nil

-- Listen for cube origin changes; keep only the most recent
Bus:on(EventNames.CUBE_ORIGIN_CHANGED, function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	local originAny = payload.origin or payload.cframe or payload.CFrame or payload
	if typeof(originAny) == "CFrame" then
		latestOriginCF = originAny
	elseif typeof(originAny) == "Vector3" then
		latestOriginCF = CFrame.new(originAny)
	elseif typeof(originAny) == "table" and originAny.x then
		latestOriginCF = CFrame.new(originAny.x, originAny.y, originAny.z)
	end
end)

local function waitDataLoaded(timeoutSec: number): boolean
	local t0 = Time.mono()
	if LocalPlayer:GetAttribute("DataLoaded") then
		return true
	end
	local conn
	local done = false
	conn = LocalPlayer:GetAttributeChangedSignal("DataLoaded"):Connect(function()
		if LocalPlayer:GetAttribute("DataLoaded") then
			done = true
		end
	end)
	while not done do
		if Time.mono() - t0 >= timeoutSec then
			break
		end
		task.wait(0.05)
		if LocalPlayer:GetAttribute("DataLoaded") then
			done = true
		end
	end
	if conn then
		ClientError.try("SpawnGuard.Disconnect", function()
			conn:Disconnect()
		end)
	end
	return LocalPlayer:GetAttribute("DataLoaded") == true
end

local function chooseStreamRadius(): number
	-- Keep it deterministic/config-driven; avoid introspecting Workspace
	return (GameConfig.Spawn and GameConfig.Spawn.CLIENT_STREAM_RADIUS) or 128
end

local function ensureStreamAroundOrigin()
	local origin = latestOriginCF
	if not origin then
		return
	end
	local radius = chooseStreamRadius()
	ClientError.try("SpawnGuard.RequestStream", function()
		Workspace:RequestStreamAroundAsync(origin.Position, radius)
		return true
	end)
end

local function signalReadyOnce()
	if didSignalReady then
		return
	end
	didSignalReady = true
	-- Fire RF handshake; ignore errors since server will timeout safely
	task.spawn(function()
		ClientRF.call("SpawnClientReady")
	end)
end

-- Character lifecycle hook
local function onCharacterAdded(char: Model)
	didSignalReady = false
	latestOriginCF = nil
	-- Anchor locally as an extra safety before server anchoring replicates
	local hrpInst = char:WaitForChild("HumanoidRootPart", 10)
	if hrpInst and hrpInst:IsA("BasePart") then
		hrpInst.Anchored = true
	end

	-- Wait for server ready + data loaded
	Ready.wait(10)
	waitDataLoaded(10)

	-- If we already have an origin, stream immediately; otherwise we will stream when event arrives.
	if latestOriginCF then
		ensureStreamAroundOrigin()
		signalReadyOnce()
	end

	-- Also, if the origin arrives later, stream then signal.
	local unsub
	unsub = Bus:on(EventNames.CUBE_ORIGIN_CHANGED, function(_)
		if latestOriginCF and not didSignalReady then
			ensureStreamAroundOrigin()
			signalReadyOnce()
			if unsub then
				ClientError.try("SpawnGuard.unsubscribe", function()
					unsub()
				end)
			end
		end
	end)
end

-- Connect
LocalPlayer.CharacterAdded:Connect(onCharacterAdded)
if LocalPlayer.Character then
	onCharacterAdded(LocalPlayer.Character)
end
