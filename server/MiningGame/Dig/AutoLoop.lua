--!strict
-- Dig/AutoLoop.lua
-- Auto-dig loop (monetization). Encapsulates state and loop logic.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(Shared:WaitForChild("Logger"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Time = require(Shared:WaitForChild("Time"))
local Types = require(Shared:WaitForChild("Types"))

local log = Logger.new("AutoLoop")

local autoDigState: { [Player]: { active: boolean, version: number } } = {}
local autoDigVersion: { [Player]: number } = {}

local function hasPermanentAutoDig(service, player: Player): boolean
	local ErrorService = require(script.Parent.Parent.ErrorService)
	local ok, gps = ErrorService.safecall("AutoLoop.GetPlayerGamepasses", function()
		local UpgradeService = service._container:Get("UpgradeService")
		if not UpgradeService or not UpgradeService.GetPlayerGamepasses then
			return nil
		end
		return UpgradeService:GetPlayerGamepasses(player)
	end)
	return ok and gps and gps["AUTO_DIGGER"] == true
end

local function runAutoDigLoop(service, player: Player)
	autoDigVersion[player] = (autoDigVersion[player] or 0) + 1
	local myVer = autoDigVersion[player]

	while autoDigState[player] and autoDigState[player].active and myVer == autoDigVersion[player] and player.Parent do
		local profile = service._container:Get("DataService"):GetPlayerData(player)
		-- Respect player preference (stored as a Player attribute)
		local prefAttr = player:GetAttribute("AutoDigEnabled")
		if type(prefAttr) == "boolean" and prefAttr == false then
			log:debug("Auto-dig disabled by preference for %s", player.Name)
			break
		end
		local boostActive = false
		if profile and profile.boosts and profile.boosts.auto_dig and Time.unix() < profile.boosts.auto_dig then
			boostActive = true
		end
		local permanent = hasPermanentAutoDig(service, player)
		if not (boostActive or permanent) then
			log:debug("Auto-dig inactive for %s (no boost and no pass)", player.Name)
			break
		end

		local character = player.Character
		if character then
			local hrpInst = character:FindFirstChild("HumanoidRootPart")
			if hrpInst and hrpInst:IsA("BasePart") then
				local hrp: BasePart = hrpInst
				local digPos
				local tgt = service._autoTargets and service._autoTargets[player]
				if
					tgt
					and (hrp.Position - tgt).Magnitude
						<= ((GameConfig.Digging and GameConfig.Digging.MAX_RANGE_STUDS) or 200)
				then
					digPos = tgt
				else
					digPos = hrp.Position - Vector3.new(0, 5, 0)
				end
				local result: Types.DigResult = service:ProcessDigRequest(player, digPos)
				local sleepSec = 1.0
				if result and result.nextAllowedAt then
					-- Server uses monotonic time for gating
					sleepSec = math.max(result.nextAllowedAt - Time.mono(), 0.5)
				else
					sleepSec = 1.0
				end
				task.wait(math.max(sleepSec, 0.5))
			else
				task.wait(1)
			end
		else
			task.wait(1)
		end
	end

	if autoDigState[player] and autoDigState[player].version == myVer then
		autoDigState[player] = nil
	end
	log:info("Auto-dig stopped for %s", player.Name)
end

local AutoLoop = {}

function AutoLoop.Start(service, player: Player)
	local profile = service._container:Get("DataService"):GetPlayerData(player)
	local hasBoost = profile and profile.boosts and profile.boosts.auto_dig and Time.unix() < profile.boosts.auto_dig
	local permanent = hasPermanentAutoDig(service, player)
	local attr = player:GetAttribute("AutoDigEnabled")
	local enabled = (type(attr) ~= "boolean") or (attr ~= false)
	if not hasBoost and not permanent then
		log:debug("Cannot start auto-dig: no active boost or pass for %s", player.Name)
		return false
	end
	if not enabled then
		log:debug("Auto-dig start suppressed by preference for %s", player.Name)
		return false
	end
	AutoLoop.Stop(service, player)
	autoDigState[player] = { active = true, version = (autoDigVersion[player] or 0) + 1 }
	if hasBoost then
		log:info(
			"Starting auto-dig for %s (expires at %s)",
			player.Name,
			tostring(profile and profile.boosts and profile.boosts.auto_dig)
		)
	else
		log:info("Starting auto-dig for %s (permanent via gamepass)", player.Name)
	end
	task.spawn(function()
		runAutoDigLoop(service, player)
	end)
	return true
end

function AutoLoop.Stop(_service, player: Player)
	if autoDigState[player] then
		log:debug("Stopping auto-dig for %s", player.Name)
		autoDigState[player].active = false
	end
	autoDigVersion[player] = (autoDigVersion[player] or 0) + 1
end

function AutoLoop.CleanupOnRemoving(_service, player: Player)
	autoDigState[player] = nil
	autoDigVersion[player] = nil
end

return AutoLoop
