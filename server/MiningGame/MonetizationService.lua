--!strict
-- MonetizationService.server.lua
-- Handles all Robux purchases and monetization

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Shared modules
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Types = require(Shared:WaitForChild("Types"))

-- Server siblings
local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)
local UpgradeService = require(script.Parent.UpgradeService)

-- Shared remotes accessor
local Remotes = require(ReplicatedStorage.MiningGame.Remotes)

local MonetizationService = {}

-- Product lookup tables
local productIdToData = {}
local gamepassIdToData = {}

-- Build lookup tables
for _, product in ipairs(GameConfig.Monetization.PRODUCTS) do
    if product.productId and product.productId > 0 then
        productIdToData[product.productId] = product
    end
end

for _, gamepass in ipairs(GameConfig.Monetization.GAMEPASSES) do
    if gamepass.gamepassId and gamepass.gamepassId > 0 then
        gamepassIdToData[gamepass.gamepassId] = gamepass
    end
end

-- Handle product purchase
local function handleProductPurchase(player: Player, product: Types.Product)
    local profile = DataService:GetPlayerData(player)
    if not profile then
        return false
    end
    
    -- Apply product effects
    if product.effect == "speed" then
        -- Apply speed boost
        profile.boosts.speed = os.time() + (product.duration or 3600)
        Remotes.RE.OnBoostsChanged:FireClient(player, profile.boosts)
        
    elseif product.effect == "luck" then
        -- Apply luck boost
        profile.boosts.luck = os.time() + (product.duration or 3600)
        Remotes.RE.OnBoostsChanged:FireClient(player, profile.boosts)
        
    elseif product.effect == "strength" then
        -- Apply strength boost
        profile.boosts.strength = os.time() + (product.duration or 3600)
        Remotes.RE.OnBoostsChanged:FireClient(player, profile.boosts)
        
    elseif product.effect == "instant_dig" then
        -- Perform mega dig immediately
        local cubeData = require(MiningGameServices:WaitForChild("DigService"))
        local worldPos = player.Character and player.Character:FindFirstChild("HumanoidRootPart") and player.Character.HumanoidRootPart.Position
        
        if worldPos then
            -- Temporarily boost stats for one dig
            local oldRadius = profile.upgrades.radius
            local oldDepth = profile.upgrades.strength
            
            -- Apply mega dig stats
            profile.upgrades.radius = math.min(15, (profile.upgrades.radius or 0) + (product.radius or 10))
            profile.upgrades.strength = math.min(20, (profile.upgrades.strength or 0) + (product.depth or 10))
            
            -- Process dig
            cubeData:ProcessDigRequest(player, worldPos)
            
            -- Restore stats
            profile.upgrades.radius = oldRadius
            profile.upgrades.strength = oldDepth
        end
        
    elseif product.effect == "auto_dig" then
        -- Start auto digger
        profile.boosts.auto_dig = os.time() + (product.duration or 3600)
        Remotes.RE.OnBoostsChanged:FireClient(player, profile.boosts)
        
        -- Start auto dig coroutine
        spawn(function()
            local endTime = profile.boosts.auto_dig
            while os.time() < endTime and player.Parent do
                wait(2) -- Dig every 2 seconds
                
                -- Check if still active
                local currentProfile = DataService:GetPlayerData(player)
                if not currentProfile or not currentProfile.boosts.auto_dig then
                    break
                end
                
                -- Get player position
                local worldPos = player.Character and player.Character:FindFirstChild("HumanoidRootPart") and player.Character.HumanoidRootPart.Position
                if worldPos then
                    local cubeData = require(MiningGameServices:WaitForChild("DigService"))
                    cubeData:ProcessDigRequest(player, worldPos)
                end
            end
        end)
        
    elseif product.coins then
        -- Grant coins
        DataService:AddCurrency(player, "coins", product.coins)
        
        Remotes.RE.OnReward:FireClient(player, {
            type = "coins",
            amount = product.coins,
            source = "purchase",
        })
    end
    
    -- Queue save
    DataService:QueueSave(player)
    
    -- Send notification
    Remotes.RE.OnNotification:FireClient(player, {
        type = "purchase",
        message = string.format("Purchase successful: %s!", product.id),
        color = Color3.new(0, 1, 0),
    })
    
    return true
end

-- Process receipt callback (single handler for all products)
MarketplaceService.ProcessReceipt = function(receipt)
    local player = Players:GetPlayerByUserId(receipt.PlayerId)
    if not player then
        -- Player not in server, can't grant product
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end
    
    -- Look up product data
    local productData = productIdToData[receipt.ProductId]
    if not productData then
        warn("[MonetizationService] Unknown product ID:", receipt.ProductId)
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end
    
    -- Grant product
    local success = handleProductPurchase(player, productData)
    
    if success then
        return Enum.ProductPurchaseDecision.PurchaseGranted
    else
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end
end

-- Handle gamepass purchases
local function handleGamepassPurchase(player: Player, gamepass: Types.GamePass)
    local profile = DataService:GetPlayerData(player)
    if not profile then
        return
    end
    
    -- Gamepass effects are permanent and checked in UpgradeService
    -- Just notify the player
    Remotes.RE.OnNotification:FireClient(player, {
        type = "gamepass",
        message = string.format("Gamepass activated: %s!", gamepass.id),
        color = Color3.new(1, 0.8, 0),
    })
    
    -- Special effects for specific gamepasses
    if gamepass.id == "AUTO_COLLECT" then
        -- Enable auto collection radius
        player:SetAttribute("AutoCollectRadius", gamepass.effects.auto_collect_radius or 50)
    elseif gamepass.id == "EXTRA_PETS" then
        -- Increase max pets
        player:SetAttribute("MaxPetsBonus", gamepass.effects.max_pets_bonus or 2)
    end
end

-- Check gamepass ownership on join
Players.PlayerAdded:Connect(function(player)
    wait(1) -- Wait for data to load
    
    -- Check all gamepasses
    for gamepassId, gamepassData in pairs(gamepassIdToData) do
        local success, owns = pcall(function()
            return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamepassId)
        end)
        
        if success and owns then
            handleGamepassPurchase(player, gamepassData)
        end
    end
end)

-- Listen for gamepass purchases during gameplay
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamepassId, purchased)
    if not purchased then
        return
    end
    
    local gamepassData = gamepassIdToData[gamepassId]
    if gamepassData then
        handleGamepassPurchase(player, gamepassData)
    end
end)

-- Prompt purchase function
function MonetizationService:PromptPurchase(player: Player, purchaseType: string, purchaseId: string)
    if purchaseType == "product" then
        -- Find product
        for _, product in ipairs(GameConfig.Monetization.PRODUCTS) do
            if product.id == purchaseId and product.productId and product.productId > 0 then
                MarketplaceService:PromptProductPurchase(player, product.productId)
                return true
            end
        end
    elseif purchaseType == "gamepass" then
        -- Find gamepass
        for _, gamepass in ipairs(GameConfig.Monetization.GAMEPASSES) do
            if gamepass.id == purchaseId and gamepass.gamepassId and gamepass.gamepassId > 0 then
                MarketplaceService:PromptGamePassPurchase(player, gamepass.gamepassId)
                return true
            end
        end
    end
    
    return false
end

-- Setup remote handlers
local function setupRemotes()
    -- Handle purchase requests
    Remotes.RF.PurchaseProduct.OnServerInvoke = function(player: Player, purchaseType: string, purchaseId: string)
        local success = MonetizationService:PromptPurchase(player, purchaseType, purchaseId)
        return {success = success}
    end
    
    -- Handle material purchases (with coins)
    Remotes.RF.PurchaseMaterial.OnServerInvoke = function(player: Player, materialId: string)
        local profile = DataService:GetPlayerData(player)
        if not profile then
            return {success = false, reason = "No profile"}
        end
        
        -- Find material
        local material = GameConfig.CubeMaterialsById[materialId]
        if not material then
            return {success = false, reason = "Unknown material"}
        end
        
        -- Check if already owned
        if profile.materialId == materialId then
            return {success = false, reason = "Already owned"}
        end
        
        -- Check cost
        if not DataService:CanAfford(player, "coins", material.unlockCost) then
            return {success = false, reason = "Insufficient coins"}
        end
        
        -- Purchase
        DataService:AddCurrency(player, "coins", -material.unlockCost)
        profile.materialId = materialId
        
        -- Queue save
        DataService:QueueSave(player)
        
        -- Notify
        Remotes.RE.OnNotification:FireClient(player, {
            type = "material",
            message = string.format("Unlocked %s material!", material.name),
            color = Color3.new(0, 1, 0),
        })
        
        return {success = true}
    end
    
    -- Handle upgrade purchases
    Remotes.RF.PurchaseUpgrade.OnServerInvoke = function(player: Player, upgradeType: string)
        local profile = DataService:GetPlayerData(player)
        if not profile then
            return {success = false, reason = "No profile"}
        end
        
        local result = UpgradeService:PurchaseUpgrade(player, profile, upgradeType)
        
        if result.success then
            -- Queue save
            DataService:QueueSave(player)
            
            -- Notify client
            Remotes.RE.OnUpgradesChanged:FireClient(player, {
                upgrades = profile.upgrades,
                coins = profile.coins,
            })
        end
        
        return result
    end
end

-- Initialize
setupRemotes()

print("[MonetizationService] Initialized")

return MonetizationService