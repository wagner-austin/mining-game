--!strict
-- Remotes.server.lua
-- Creates and manages all RemoteEvents and RemoteFunctions for client-server communication

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Wait for initialization in Studio
if RunService:IsStudio() then
    wait(0.1)
end

-- Create folder structure (or reuse existing)
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
remotesFolder.Name = "Remotes"
remotesFolder.Parent = ReplicatedStorage

local miningGameFolder = remotesFolder:FindFirstChild("MiningGame") or Instance.new("Folder")
miningGameFolder.Name = "MiningGame"
miningGameFolder.Parent = remotesFolder

-- Helper function to create or get RemoteFunction
local function createRemoteFunction(name: string): RemoteFunction
    local existing = miningGameFolder:FindFirstChild(name)
    if existing and existing:IsA("RemoteFunction") then
        return existing
    end
    local rf = Instance.new("RemoteFunction")
    rf.Name = name
    rf.Parent = miningGameFolder
    return rf
end

-- Helper function to create or get RemoteEvent
local function createRemoteEvent(name: string): RemoteEvent
    local existing = miningGameFolder:FindFirstChild(name)
    if existing and existing:IsA("RemoteEvent") then
        return existing
    end
    local re = Instance.new("RemoteEvent")
    re.Name = name
    re.Parent = miningGameFolder
    return re
end

-- Create RemoteFunctions (client -> server with return value)
local remoteFunctions = {
    -- Core gameplay
    GetProfile = createRemoteFunction("GetProfile"),
    RequestDig = createRemoteFunction("RequestDig"),
    
    -- Purchases and upgrades
    PurchaseUpgrade = createRemoteFunction("PurchaseUpgrade"),
    PurchaseProduct = createRemoteFunction("PurchaseProduct"),
    PurchaseMaterial = createRemoteFunction("PurchaseMaterial"),
    
    -- Inventory management
    SellItems = createRemoteFunction("SellItems"),
    EquipItem = createRemoteFunction("EquipItem"),
    UnequipItem = createRemoteFunction("UnequipItem"),
    UseConsumable = createRemoteFunction("UseConsumable"),
    
    -- Pet management
    EquipPet = createRemoteFunction("EquipPet"),
    UnequipPet = createRemoteFunction("UnequipPet"),
    UpgradePet = createRemoteFunction("UpgradePet"),
    
    -- Multiplayer
    VisitNeighbor = createRemoteFunction("VisitNeighbor"),
    ReturnHome = createRemoteFunction("ReturnHome"),
    GetNeighborhood = createRemoteFunction("GetNeighborhood"),
    
    -- Settings
    UpdateSettings = createRemoteFunction("UpdateSettings"),
    
    -- Debug
    DebugAddCurrency = createRemoteFunction("DebugAddCurrency"),
    DebugResetStats = createRemoteFunction("DebugResetStats"),
    DebugResetCube = createRemoteFunction("DebugResetCube"),
}

-- Create RemoteEvents (server -> client, no return value)
local remoteEvents = {
    -- State updates
    OnProfileUpdate = createRemoteEvent("OnProfileUpdate"),
    OnInventoryChanged = createRemoteEvent("OnInventoryChanged"),
    OnUpgradesChanged = createRemoteEvent("OnUpgradesChanged"),
    OnBoostsChanged = createRemoteEvent("OnBoostsChanged"),
    OnPetsChanged = createRemoteEvent("OnPetsChanged"),
    
    -- Dig feedback
    OnDigFeedback = createRemoteEvent("OnDigFeedback"),
    OnTerrainUpdate = createRemoteEvent("OnTerrainUpdate"),
    OnLootDropped = createRemoteEvent("OnLootDropped"),
    
    -- UI notifications
    OnNotification = createRemoteEvent("OnNotification"),
    OnReward = createRemoteEvent("OnReward"),
    OnAchievement = createRemoteEvent("OnAchievement"),
    
    -- Multiplayer events
    OnNeighborJoined = createRemoteEvent("OnNeighborJoined"),
    OnNeighborLeft = createRemoteEvent("OnNeighborLeft"),
    OnCubeUpdate = createRemoteEvent("OnCubeUpdate"),
    
    -- Effects
    OnParticleEffect = createRemoteEvent("OnParticleEffect"),
    OnSoundEffect = createRemoteEvent("OnSoundEffect"),
    OnCameraShake = createRemoteEvent("OnCameraShake"),
    
    -- Debug/Visual
    OnTerrainPoke = createRemoteEvent("OnTerrainPoke"),
}

print("[Remotes] Initialized all RemoteEvents and RemoteFunctions")

-- Return the remotes table
return {
    RF = remoteFunctions,
    RE = remoteEvents,
    Folder = miningGameFolder,
}