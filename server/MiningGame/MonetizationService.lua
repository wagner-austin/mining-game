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
local Logger = require(Shared:WaitForChild("Logger"))

-- Server siblings
local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)
local UpgradeService = require(script.Parent.UpgradeService)

-- Shared remotes accessor
local Remotes = require(ReplicatedStorage.MiningGame.Remotes)

local MonetizationService = {}
local log = Logger.new("MonetizationService")

-- Constants
local PRICE_CACHE_EXPIRY = 300 -- 5 minutes
local RECEIPT_CACHE_SIZE = 500 -- Max receipt IDs to track per profile

-- Product lookup tables
local productIdToData = {}
local gamepassIdToData = {}

-- Price cache to avoid rate limits
local priceCache: { [string]: { [number]: { price: number, timestamp: number } } } = {}

-- Receipt queues for bounded idempotency tracking (userId -> list of receiptIds)
local receiptQueues: { [number]: { string } } = {}

-- Helper: current unix timestamp
local function getTimestamp(): number
    return DateTime.now().UnixTimestamp
end

-- Helper: record a processed receipt id with bounded memory (keyed by userId)
local function addReceiptId(profile: any, userId: number, receiptId: string)
    profile.processedReceiptIds = profile.processedReceiptIds or {}
    receiptQueues[userId] = receiptQueues[userId] or {}

    if not profile.processedReceiptIds[receiptId] then
        profile.processedReceiptIds[receiptId] = true
        table.insert(receiptQueues[userId], receiptId)

        -- Evict oldest if over limit
        while #receiptQueues[userId] > RECEIPT_CACHE_SIZE do
            local evict = table.remove(receiptQueues[userId], 1)
            if evict then profile.processedReceiptIds[evict] = nil end
        end
    end
end

-- Helper: bounded purchase log (keep only most recent 20 entries)
local function addToPurchaseLog(profile: any, entry: Types.PurchaseEntry)
    profile.purchaseLog = profile.purchaseLog or {}
    
    table.insert(profile.purchaseLog, entry)
    
    -- Keep only most recent 20 entries
    while #profile.purchaseLog > 20 do
        table.remove(profile.purchaseLog, 1)
    end
end

-- Helper: cached price lookup with fallback to config
local function getProductPrice(infoType: Enum.InfoType, id: number): number?
    local key = (infoType == Enum.InfoType.Product) and "Product" or "GamePass"
    priceCache[key] = priceCache[key] or {}

    local now = getTimestamp()
    local cached = priceCache[key][id]
    if cached and (now - cached.timestamp) < PRICE_CACHE_EXPIRY then
        return cached.price
    end

    local ok, info = pcall(function()
        return MarketplaceService:GetProductInfo(id, infoType)
    end)
    if ok and info and info.PriceInRobux then
        priceCache[key][id] = { price = info.PriceInRobux, timestamp = now }
        return info.PriceInRobux
    end

    -- Fallback to config
    if key == "Product" then
        local prod = productIdToData[id]
        return prod and prod.robux or nil
    else
        local pass = gamepassIdToData[id]
        return pass and pass.robux or nil
    end
end

-- Record spend and mark receipt as processed; returns true if this is the first time
local function processPurchase(
    userId: number,
    kind: "DevProduct" | "GamePass",
    id: number,
    price: number,
    source: "Prompt" | "Backfill",
    receiptId: string?
): boolean
    local player = Players:GetPlayerByUserId(userId)
    if not player then return false end

    local profile = DataService:GetPlayerData(player)
    if not profile then return false end

    -- Idempotence for dev products
    if receiptId then
        if profile.processedReceiptIds and profile.processedReceiptIds[receiptId] then
            return false
        end
        addReceiptId(profile, userId, receiptId)
    end

    -- Totals
    profile.robuxSpentLifetime = (profile.robuxSpentLifetime or 0) + (price or 0)
    profile.purchasesCount = (profile.purchasesCount or 0) + 1
    if kind == "DevProduct" then
        profile.robuxSpentDevProducts = (profile.robuxSpentDevProducts or 0) + (price or 0)
    else
        profile.robuxSpentGamePasses = (profile.robuxSpentGamePasses or 0) + (price or 0)
    end

    -- Timestamps
    local now = getTimestamp()
    profile.firstPurchaseTime = profile.firstPurchaseTime or now
    profile.lastPurchaseTime = now

    -- Ledger (bounded)
    addToPurchaseLog(profile, {
        kind = kind,
        id = id,
        priceRobux = price or 0,
        at = now,
        source = source,
    })

    -- Persist + metrics
    DataService:QueueSave(player)
    local ok, UMS = pcall(function() return require(script.Parent.UserMetricsService) end)
    if ok and UMS then pcall(function() UMS:Invalidate(player) end) end

    return true
end

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
        log:warn("No profile found for player {} during product purchase", player.Name)
        return false
    end
    
    log:info("Processing product purchase: {} for player {}", product.id, player.Name)
    log:event("product_purchased", {
        uid = player.UserId,
        productId = product.id,
        effect = product.effect,
        price = product.robux or 0
    })
    
    -- Apply product effects
    if product.effect == "speed" then
        -- Apply speed boost
        profile.boosts.speed = os.time() + (product.duration or 3600)
        Remotes.RE.OnBoostsChanged:FireClient(player, profile.boosts)
        
    elseif product.effect == "luck" then
        -- Apply luck boost
        profile.boosts.luck = os.time() + (product.duration or 3600)
        Remotes.RE.OnBoostsChanged:FireClient(player, profile.boosts)
        
    elseif product.effect == "size" then
        -- Apply size boost
        profile.boosts.size = os.time() + (product.duration or 3600)
        Remotes.RE.OnBoostsChanged:FireClient(player, profile.boosts)
        
    elseif product.effect == "instant_dig" then
        -- Perform mega dig immediately
        local DigService = require(script.Parent.DigService)
        local worldPos = player.Character and player.Character:FindFirstChild("HumanoidRootPart") and player.Character.HumanoidRootPart.Position
        
        if worldPos then
            -- Temporarily boost stats for one dig
            local oldSize = profile.upgrades.size or 0
            
            -- Apply mega dig stats
            profile.upgrades.size = math.min(15, oldSize + (product.size or 10))
            
            -- Process dig
            DigService:ProcessDigRequest(player, worldPos)
            
            -- Restore stats
            profile.upgrades.size = oldSize
        end
        
    elseif product.effect == "auto_dig" then
        -- Start auto digger
        profile.boosts.auto_dig = os.time() + (product.duration or 3600)
        Remotes.RE.OnBoostsChanged:FireClient(player, profile.boosts)
        
        -- Use DigService's auto-dig system instead of spawning our own loop
        local DigService = require(script.Parent.DigService)
        DigService:StartAutoDig(player)
        
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
    local userId = receipt.PlayerId
    local productId = receipt.ProductId
    local receiptId = receipt.PurchaseId
    
    -- Check if product is known (BLOCKER FIX #4)
    local productData = productIdToData[productId]
    if not productData then
        log:warn("Unknown product ID: {} - returning NotProcessedYet", productId)
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end
    
    -- Build grant payload for durable queue (with actual price at time of purchase)
    local grant = {
        kind = "DevProduct",
        id = productId,
        price = getProductPrice(Enum.InfoType.Product, productId) or 0,
        source = "Prompt",
        receiptId = receiptId,
        timestamp = getTimestamp()
    }
    
    -- BLOCKER FIX #1: Durably enqueue BEFORE returning PurchaseGranted (with retry)
    local enqueued = false
    for attempt = 1, 3 do
        enqueued = DataService:EnqueueReceiptGrant(userId, grant)
        if enqueued then
            break
        end
        -- Backoff on failure
        log:warn("Enqueue attempt {} failed for receipt {}", attempt, receiptId)
        if attempt < 3 then
            task.wait(0.2 * attempt)
        end
    end
    
    if not enqueued then
        -- Failed to persist after retries - must retry later
        log:error("Failed to enqueue receipt after retries: {}", receiptId)
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end
    
    -- Durably persisted; if player is online, record metrics & apply effects exactly once
    local player = Players:GetPlayerByUserId(userId)
    if player then
        local firstTime = processPurchase(userId, "DevProduct", productId, grant.price, "Prompt", receiptId)
        if firstTime then
            log:info("Receipt {} processed successfully for product {}", receiptId, productId)
            log:event("receipt_processed", {
                uid = userId,
                productId = productId,
                receiptId = receiptId,
                price = grant.price
            })
            handleProductPurchase(player, productData)
        else
            log:debug("Receipt {} already processed, skipping", receiptId)
        end
    end
    
    -- BLOCKER FIX #2: Only return PurchaseGranted after durable enqueue
    return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Handle gamepass purchases
local function handleGamepassPurchase(player: Player, gamepass: Types.GamePass)
    local profile = DataService:GetPlayerData(player)
    if not profile then
        log:warn("No profile found for player {} during gamepass purchase", player.Name)
        return
    end
    
    log:info("Processing gamepass purchase: {} for player {}", gamepass.id, player.Name)
    log:event("gamepass_purchased", {
        uid = player.UserId,
        gamepassId = gamepass.id,
        price = gamepass.robux or 0
    })
    
    -- Gamepass effects are permanent and checked in UpgradeService
    -- Just notify the player
    Remotes.RE.OnNotification:FireClient(player, {
        type = "gamepass",
        message = string.format("Gamepass activated: %s!", gamepass.id),
        color = Color3.new(1, 0.8, 0),
    })
    
    -- Special effects for specific gamepasses
    if gamepass.id == "AUTO_COLLECT" then
        -- Enable auto collection range
        player:SetAttribute("AutoCollectRange", gamepass.effects.auto_collect_range or 50)
    elseif gamepass.id == "EXTRA_PETS" then
        -- Increase max pets
        player:SetAttribute("MaxPetsBonus", gamepass.effects.max_pets_bonus or 2)
    end
end

-- Check gamepass ownership on join
Players.PlayerAdded:Connect(function(player)
    log:debug("Player {} joined, checking gamepass ownership", player.Name)
    
    -- Wait until DataService has loaded profile (critical to avoid race)
    if player:GetAttribute("DataLoaded") ~= true then
        player:GetAttributeChangedSignal("DataLoaded"):Wait()
    end
    
    -- Check if player is still in game
    if not player.Parent then 
        return 
    end
    
    -- Process any durably queued grants (from offline purchases)
    local grants = DataService:ConsumePendingGrants(player.UserId)
    if #grants > 0 then
        log:info("Processing {} pending grants for player {}", #grants, player.Name)
    end
    for _, grant in ipairs(grants) do
        local firstTime = processPurchase(
            grant.userId or player.UserId,
            grant.kind,
            grant.id,
            grant.price or 0,
            grant.source or "Prompt",
            grant.receiptId
        )
        -- Apply product effects if this is first time processing
        if firstTime and grant.kind == "DevProduct" then
            local productData = productIdToData[grant.id]
            if productData then
                handleProductPurchase(player, productData)
            end
        end
    end
    
    -- Set session baseline for Robux tracking
    local profile = DataService:GetPlayerData(player)
    if profile then
        profile.sessionStartRobuxSpent = profile.robuxSpentLifetime or 0
    end
    
    -- Backfill game passes (check all known passes for untracked ownership)
    profile.ownedGamePasses = profile.ownedGamePasses or {}
    
    for gamepassId, gamepassData in pairs(gamepassIdToData) do
        -- Skip if already tracked
        if not profile.ownedGamePasses[gamepassId] then
            local success, owns = pcall(function()
                return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamepassId)
            end)
            
            if not success then
                log:error("Backfill verify error for gamepass {} player {}", gamepassId, player.Name)
            elseif owns then
                -- Player owns this but we haven't tracked it yet
                local price = getProductPrice(Enum.InfoType.GamePass, gamepassId) or 0
                
                -- Use synthetic receipt for idempotency
                local syntheticReceipt = "GP:" .. tostring(gamepassId)
                
                -- Track as backfill with idempotent processing
                local firstTime = processPurchase(
                    player.UserId, "GamePass", gamepassId, price, "Backfill", syntheticReceipt
                )
                
                if firstTime then
                    profile.ownedGamePasses[gamepassId] = true
                    handleGamepassPurchase(player, gamepassData)
                    log:info("Backfilled game pass {} for {}", gamepassId, player.Name)
                    log:event("gamepass_backfilled", {
                        uid = player.UserId,
                        gamepassId = gamepassId,
                        price = price
                    })
                end
            end
        end
    end
end)

-- Clean up receipt queues when player leaves
Players.PlayerRemoving:Connect(function(player)
    receiptQueues[player.UserId] = nil
end)

-- Listen for game pass purchases (idempotent + tracked once)
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, purchased)
    if not purchased then return end

    local profile = DataService:GetPlayerData(player)
    if not profile then return end

    -- Verify ownership server-side
    local ok, owns = pcall(function()
        return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamePassId)
    end)
    if not ok or not owns then
        log:error("Game pass verify failed {} for {}", gamePassId, player.Name)
        return
    end

    profile.ownedGamePasses = profile.ownedGamePasses or {}
    if profile.ownedGamePasses[gamePassId] then
        -- Already recorded; nothing to do
        return
    end

    -- Price at time of purchase (cached, with config fallback)
    local price = getProductPrice(Enum.InfoType.GamePass, gamePassId) or 0

    -- Use a synthetic receipt key so retries can't double-count
    local syntheticReceipt = "GP:" .. tostring(gamePassId)

    local firstTime = processPurchase(
        player.UserId, "GamePass", gamePassId, price, "Prompt", syntheticReceipt
    )
    if firstTime then
        profile.ownedGamePasses[gamePassId] = true
        local gamepassData = gamepassIdToData[gamePassId]
        if gamepassData then
            handleGamepassPurchase(player, gamepassData)
        end
    end
end)

-- Get monetization metrics for a player
function MonetizationService:GetMetrics(player: Player)
    local profile = DataService:GetPlayerData(player)
    if not profile then
        return nil
    end
    
    local now = getTimestamp()
    local daysSinceLastPurchase = nil
    if profile.lastPurchaseTime then
        daysSinceLastPurchase = math.floor((now - profile.lastPurchaseTime) / 86400)
    end
    
    local dev = profile.robuxSpentDevProducts or 0
    local gp = profile.robuxSpentGamePasses or 0
    
    return {
        robuxSpentLifetime = profile.robuxSpentLifetime or 0,
        robuxSpentThisSession = math.max(0, 
            (profile.robuxSpentLifetime or 0) - (profile.sessionStartRobuxSpent or 0)
        ),
        purchasesCount = profile.purchasesCount or 0,
        firstPurchaseTime = profile.firstPurchaseTime,
        lastPurchaseTime = profile.lastPurchaseTime,
        daysSinceLastPurchase = daysSinceLastPurchase,
        byKind = {
            devProducts = dev,
            gamePasses = gp,
        },
        -- Flat aliases for UI
        devProducts = dev,
        gamePasses = gp,
        isPayingUser = profile.firstPurchaseTime ~= nil,
    }
end

-- Prompt purchase function
function MonetizationService:PromptPurchase(player: Player, purchaseType: string, purchaseId: string)
    log:debug("Prompting {} purchase: {} for player {}", purchaseType, purchaseId, player.Name)
    if purchaseType == "product" then
        -- Find product
        for _, product in ipairs(GameConfig.Monetization.PRODUCTS) do
            if product.id == purchaseId and product.productId and product.productId > 0 then
                MarketplaceService:PromptProductPurchase(player, product.productId)
                log:event("purchase_prompted", {
                    uid = player.UserId,
                    type = "product",
                    id = purchaseId
                })
                return true
            end
        end
    elseif purchaseType == "gamepass" then
        -- Find gamepass
        for _, gamepass in ipairs(GameConfig.Monetization.GAMEPASSES) do
            if gamepass.id == purchaseId and gamepass.gamepassId and gamepass.gamepassId > 0 then
                MarketplaceService:PromptGamePassPurchase(player, gamepass.gamepassId)
                log:event("purchase_prompted", {
                    uid = player.UserId,
                    type = "gamepass",
                    id = purchaseId
                })
                return true
            end
        end
    end
    
    log:warn("Failed to prompt purchase: {} {} not found", purchaseType, purchaseId)
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

log:info("Initialized")

return MonetizationService