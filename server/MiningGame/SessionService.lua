--!strict
-- SessionService.lua (ModuleScript)
-- Tracks player sessions and updates lifetime playtime

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(MiningGame:WaitForChild("Logger"))
local log = Logger.new("SessionService")

local DataService
local ok, ds = pcall(function()
    return require(script.Parent:WaitForChild("DataService"))
end)
if ok then DataService = ds end

local SessionService = {}
local sessionStartByUserId: {[number]: number} = {}

-- Public API for other services to read session info
function SessionService.getSessionStartTime(userId: number): number?
    return sessionStartByUserId[userId]
end

function SessionService.getSessionElapsed(userId: number): number
    local startTime = sessionStartByUserId[userId]
    return startTime and math.max(0, os.time() - startTime) or 0
end

-- Initialize tracking when module loads
local function init()
    -- Track when players join
    Players.PlayerAdded:Connect(function(player)
        sessionStartByUserId[player.UserId] = os.time()
        print("[SessionService] Player", player.Name, "session started at", sessionStartByUserId[player.UserId])
        
        -- Session tracking is now handled in DataService:LoadPlayerAsync
        -- We only need to track the session start time here for playtime calculation
    end)

    -- Update lifetime playtime when players leave
    Players.PlayerRemoving:Connect(function(player)
        local startTime = sessionStartByUserId[player.UserId]
        if startTime then
            local sessionDuration = math.max(0, os.time() - startTime)
            log:info("%s played for %d seconds this session", player.Name, sessionDuration)
            
            -- Add to lifetime playtime
            if DataService and typeof(DataService.AddPlaytime) == "function" then
                pcall(function()
                    DataService:AddPlaytime(player, sessionDuration)
                end)
            end
            
            sessionStartByUserId[player.UserId] = nil
        end
    end)
    
    -- Handle players already in game (Studio test mode)
    for _, player in ipairs(Players:GetPlayers()) do
        if not sessionStartByUserId[player.UserId] then
            sessionStartByUserId[player.UserId] = os.time()
            print("[SessionService] Found existing player", player.Name, "- tracking from now")
        end
    end
    
    log:info("Initialized - tracking player sessions")
end

-- Auto-initialize
init()

return SessionService
