--!strict
-- init.server.lua
-- Bootstrap script that initializes all mining game services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Wait for shared modules
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame", 30)
local Logger = require(MiningGame:WaitForChild("Logger"))
local log = Logger.new("Bootstrap")

log:info("Starting MiningGame initialization...")
log:debug("Script name: %s", script.Name)
log:debug("Script parent: %s", tostring(script.Parent))

-- Assert correct Rojo mapping
assert(MiningGame, "Missing ReplicatedStorage.MiningGame (check Rojo mapping)")
log:info("Found ReplicatedStorage.MiningGame")

-- Create remotes first (before other services need them)
local RemotesCreator = require(script.Remotes) -- creates instances under RS.Remotes.MiningGame
log:info("Remotes created")

-- Create Unix time sync remote for day/night cycle
local GetServerUnix = Instance.new("RemoteFunction")
GetServerUnix.Name = "GetServerUnix"
GetServerUnix.Parent = ReplicatedStorage
GetServerUnix.OnServerInvoke = function()
	return os.time()
end
log:info("Time sync remote created")

-- Initialize core services (order matters)
local DataService = require(script.DataService)
log:info("DataService loaded")

-- Initialize SessionService early so PlayerAdded hooks are active
local SessionService = require(script.SessionService)
log:info("SessionService loaded")

local GridService = require(script.GridService)
log:info("GridService loaded")

local LootService = require(script.LootService)
log:info("LootService loaded")

local UpgradeService = require(script.UpgradeService)
log:info("UpgradeService loaded")

local InventoryService = require(script.InventoryService)
log:info("InventoryService loaded")

local MonetizationService = require(script.MonetizationService)
log:info("MonetizationService loaded")

local ThemeSettingsService = require(script.ThemeSettingsService)
log:info("ThemeSettingsService loaded")

local CubePositionService = require(script.CubePositionService)
log:info("CubePositionService loaded")

local CubeMaterialService = require(script.CubeMaterialService)
log:info("CubeMaterialService loaded")

local SpawnService = require(script.SpawnService)
log:info("SpawnService loaded")

local DigService = require(script.DigService)
log:info("DigService loaded")

-- Initialize UserMetricsService
local UserMetricsService = require(script.UserMetricsService)
log:info("UserMetricsService loaded")

log:info("Backend initialization complete!")

-- Export services for debugging
_G.MiningGameServices = {
    DataService = DataService,
    GridService = GridService,
    LootService = LootService,
    UpgradeService = UpgradeService,
    InventoryService = InventoryService,
    MonetizationService = MonetizationService,
    CubePositionService = CubePositionService,
    SpawnService = SpawnService,
    DigService = DigService,
    Remotes = RemotesCreator,
}

-- Set up teleportation handler
RemotesCreator.RF.TeleportToHome.OnServerInvoke = function(player: Player)
    -- Use SpawnService to teleport player to their spawn point
    SpawnService:Respawn(player)
    
    return {success = true}
end

-- Set up debug remote handlers
RemotesCreator.RF.DebugAddCurrency.OnServerInvoke = function(player: Player, currencyType: string, amount: number)
    -- Validate inputs
    if currencyType ~= "coins" and currencyType ~= "gems" then
        return {success = false, reason = "Invalid currency type"}
    end
    
    if type(amount) ~= "number" or amount <= 0 then
        return {success = false, reason = "Invalid amount"}
    end
    
    -- Add the currency
    DataService:AddCurrency(player, currencyType, amount)
    
    return {success = true, added = amount}
end

RemotesCreator.RF.DebugResetCube.OnServerInvoke = function(player: Player)
    -- Reset the player's cube to fresh state
    local cubeData = DataService:GetCubeData(player)
    if cubeData then
        -- Clear all chunks (reset to undug state)
        cubeData.chunks = {}
        cubeData.totalDug = 0
        
        -- Force save
        DataService:SaveCubeAsync(player)
        
        -- Get the player's cube from DigService and destroy it
        local DigService = require(script.DigService)
        local playerCubes = DigService.playerCubes
        if playerCubes and playerCubes[player] then
            if playerCubes[player].model then
                playerCubes[player].model:Destroy()
            end
            playerCubes[player] = nil
        end
        
        -- Re-initialize the cube (creates fresh terrain)
        DigService:InitializePlayerCube(player)
        
        return {success = true, message = "Cube reset to fresh state"}
    end
    
    return {success = false, reason = "No cube data found"}
end

-- Create logger for metrics
local metricsLog = Logger.new("Metrics")

-- Set up metrics remote handlers
RemotesCreator.RF.GetMetrics.OnServerInvoke = function(player: Player)
    metricsLog:debug("GetMetrics requested by %s", player.Name)
    local metrics = UserMetricsService:GetMetrics(player)
    metricsLog:debug("Returning metrics: %s", tostring(metrics ~= nil))
    return metrics
end

-- Gate server metrics to staff/developers
local RunService = game:GetService("RunService")
local function canSeeServerMetrics(p: Player)
    if RunService:IsStudio() then return true end
    -- Replace with your user ID or group/rank check
    -- Example: return p.UserId == 12345678 or p:GetRankInGroup(GROUP_ID) >= RANK
    return false -- Default: only in Studio
end

RemotesCreator.RF.GetServerMetrics.OnServerInvoke = function(player: Player)
    if not canSeeServerMetrics(player) then
        -- Return limited info for regular players
        return {
            totalPlayers = #Players:GetPlayers(),
            serverUptimeSec = workspace.DistributedGameTime,
        }
    end
    return UserMetricsService:GetServerMetrics()
end

RemotesCreator.RF.DebugResetStats.OnServerInvoke = function(player: Player)
    -- Reset player's stats to default
    local data = DataService:GetPlayerData(player)
    if data then
        -- Reset core stats
        data.coins = 0
        data.gems = 0
        data.upgrades.speed = 0
        data.upgrades.size = 0
        data.totalBlocksDug = 0
        data.sessionStartBlocks = 0
        data.inventory = {}
        data.equipped = {
            pickaxe = nil,
            head = nil,
            back = nil,
            aura = nil,
            trail = nil,
        }
        data.boosts = {}
        data.pets = {}
        
        -- Force save
        DataService:SavePlayerAsync(player)
        
        return {success = true, message = "Stats reset successfully"}
    end
    
    return {success = false, reason = "Failed to get player data"}
end