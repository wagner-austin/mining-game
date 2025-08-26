--!strict
-- Remotes.lua (Accessor)
-- Provides access to RemoteEvents and RemoteFunctions for client/server

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local mg = ReplicatedStorage:WaitForChild("Remotes", 30):WaitForChild("MiningGame", 30)

return {
    RF = {
        -- Core gameplay
        GetProfile = mg:WaitForChild("GetProfile"),
        RequestDig = mg:WaitForChild("RequestDig"),
        
        -- Purchases and upgrades
        PurchaseUpgrade = mg:WaitForChild("PurchaseUpgrade"),
        PurchaseProduct = mg:WaitForChild("PurchaseProduct"),
        PurchaseMaterial = mg:WaitForChild("PurchaseMaterial"),
        
        -- Inventory management
        SellItems = mg:WaitForChild("SellItems"),
        EquipItem = mg:WaitForChild("EquipItem"),
        UnequipItem = mg:WaitForChild("UnequipItem"),
        UseConsumable = mg:WaitForChild("UseConsumable"),
        
        -- Pet management
        EquipPet = mg:WaitForChild("EquipPet"),
        UnequipPet = mg:WaitForChild("UnequipPet"),
        UpgradePet = mg:WaitForChild("UpgradePet"),
        
        -- Multiplayer
        VisitNeighbor = mg:WaitForChild("VisitNeighbor"),
        ReturnHome = mg:WaitForChild("ReturnHome"),
        GetNeighborhood = mg:WaitForChild("GetNeighborhood"),
        
        -- Settings
        UpdateSettings = mg:WaitForChild("UpdateSettings"),
    },
    RE = {
        -- State updates
        OnProfileUpdate = mg:WaitForChild("OnProfileUpdate"),
        OnInventoryChanged = mg:WaitForChild("OnInventoryChanged"),
        OnUpgradesChanged = mg:WaitForChild("OnUpgradesChanged"),
        OnBoostsChanged = mg:WaitForChild("OnBoostsChanged"),
        OnPetsChanged = mg:WaitForChild("OnPetsChanged"),
        
        -- Dig feedback
        OnDigFeedback = mg:WaitForChild("OnDigFeedback"),
        OnTerrainUpdate = mg:WaitForChild("OnTerrainUpdate"),
        OnLootDropped = mg:WaitForChild("OnLootDropped"),
        
        -- UI notifications
        OnNotification = mg:WaitForChild("OnNotification"),
        OnReward = mg:WaitForChild("OnReward"),
        OnAchievement = mg:WaitForChild("OnAchievement"),
        
        -- Multiplayer events
        OnNeighborJoined = mg:WaitForChild("OnNeighborJoined"),
        OnNeighborLeft = mg:WaitForChild("OnNeighborLeft"),
        OnCubeUpdate = mg:WaitForChild("OnCubeUpdate"),
        
        -- Effects
        OnParticleEffect = mg:WaitForChild("OnParticleEffect"),
        OnSoundEffect = mg:WaitForChild("OnSoundEffect"),
        OnCameraShake = mg:WaitForChild("OnCameraShake"),
    },
    Folder = mg,
}