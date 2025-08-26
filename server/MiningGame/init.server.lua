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