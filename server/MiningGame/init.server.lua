--!strict
-- init.server.lua
-- Bootstrap script that initializes all mining game services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

print("[Bootstrap] Starting MiningGame initialization...")
print("[Bootstrap] Script name:", script.Name)
print("[Bootstrap] Script parent:", script.Parent)

-- Assert correct Rojo mapping
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame", 30)
assert(MiningGame, "Missing ReplicatedStorage.MiningGame (check Rojo mapping)")
print("[Bootstrap] Found ReplicatedStorage.MiningGame")

-- Create remotes first (before other services need them)
local RemotesCreator = require(script.Remotes) -- creates instances under RS.Remotes.MiningGame
print("[Bootstrap] Remotes created")

-- Create Unix time sync remote for day/night cycle
local GetServerUnix = Instance.new("RemoteFunction")
GetServerUnix.Name = "GetServerUnix"
GetServerUnix.Parent = ReplicatedStorage
GetServerUnix.OnServerInvoke = function()
	return os.time()
end
print("[Bootstrap] Time sync remote created")

-- Initialize core services (order matters)
local DataService = require(script.DataService)
print("[Bootstrap] DataService loaded")

local GridService = require(script.GridService)
print("[Bootstrap] GridService loaded")

local LootService = require(script.LootService)
print("[Bootstrap] LootService loaded")

local UpgradeService = require(script.UpgradeService)
print("[Bootstrap] UpgradeService loaded")

local InventoryService = require(script.InventoryService)
print("[Bootstrap] InventoryService loaded")

local MonetizationService = require(script.MonetizationService)
print("[Bootstrap] MonetizationService loaded")

local CubePositionService = require(script.CubePositionService)
print("[Bootstrap] CubePositionService loaded")

local CubeMaterialService = require(script.CubeMaterialService)
print("[Bootstrap] CubeMaterialService loaded")

local SpawnService = require(script.SpawnService)
print("[Bootstrap] SpawnService loaded")

local DigService = require(script.DigService)
print("[Bootstrap] DigService loaded")

print("[MiningGame] Backend initialization complete!")

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