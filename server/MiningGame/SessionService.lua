--!strict
-- SessionService.lua (ModuleScript)
-- Tracks player sessions and updates lifetime playtime

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Time = require(MiningGame:WaitForChild("Time"))
local Logger = require(MiningGame:WaitForChild("Logger"))
local log = Logger.new("SessionService")
local MathUtils = require(MiningGame:WaitForChild("MathUtils"))
local ServiceValidator = require(MiningGame:WaitForChild("ServiceValidator"))

-- Services (injected via Init)
local DataService

local SessionService = {}
type SessionServiceT = {
	Init: (self: SessionServiceT, container: any) -> (),
	Start: (self: SessionServiceT) -> (),
}
local sessionStartByUserId: { [number]: number } = {}
local _conns = {}

-- Initialize with DI container
function SessionService:Init(container)
	DataService = ServiceValidator.get(container, "DataService", { "GetPlayerData", "AddPlaytime" })
	log:info("Initialized with dependencies")
end

-- Public API for other services to read session info
function SessionService.getSessionStartTime(userId: number): number?
	return sessionStartByUserId[userId]
end

function SessionService.getSessionElapsed(userId: number): number
	local startTime = sessionStartByUserId[userId]
	return startTime and MathUtils.nonNegative(Time.unix() - startTime) or 0
end

-- Initialize tracking when module loads
function SessionService:Start()
	-- Track when players join
	table.insert(
		_conns,
		Players.PlayerAdded:Connect(function(player)
			sessionStartByUserId[player.UserId] = Time.unix()
			log:info("Player %s session started at %d", player.Name, sessionStartByUserId[player.UserId])
			log:event("session_started", {
				uid = player.UserId,
				timestamp = sessionStartByUserId[player.UserId],
			})

			-- Session tracking is now handled in DataService:LoadPlayerAsync
			-- We only need to track the session start time here for playtime calculation
		end)
	)

	-- Update lifetime playtime when players leave
	table.insert(
		_conns,
		Players.PlayerRemoving:Connect(function(player)
			local startTime = sessionStartByUserId[player.UserId]
			if startTime then
				local sessionDuration = MathUtils.nonNegative(Time.unix() - startTime)
				log:info("%s played for %d seconds this session", player.Name, sessionDuration)
				log:event("session_ended", {
					uid = player.UserId,
					duration = sessionDuration,
					timestamp = math.floor(Time.unix()),
				})

				-- Add to lifetime playtime
				if DataService and typeof(DataService.AddPlaytime) == "function" then
					local ErrorService = require(script.Parent.ErrorService)
					ErrorService.safecall("SessionService.AddPlaytime", function()
						DataService:AddPlaytime(player, sessionDuration)
						return true
					end)
				end

				sessionStartByUserId[player.UserId] = nil
			end
		end)
	)

	-- Handle players already in game (Studio test mode)
	for _, player in ipairs(Players:GetPlayers()) do
		if not sessionStartByUserId[player.UserId] then
			sessionStartByUserId[player.UserId] = Time.unix()
			log:info("Found existing player %s - tracking from now", player.Name)
		end
	end

	log:info("Started - tracking player sessions")
end

-- Stop lifecycle
function SessionService:Stop()
	for _, conn in ipairs(_conns) do
		if conn and conn.Disconnect then
			local ErrorService = require(script.Parent.ErrorService)
			ErrorService.safecall("SessionService.StopDisconnect", function()
				conn:Disconnect()
				return true
			end)
		end
	end
	table.clear(_conns)
	log:info("Stopped")
end

return SessionService
