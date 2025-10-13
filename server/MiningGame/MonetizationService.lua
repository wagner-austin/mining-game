--!strict
-- MonetizationService.server.lua
-- Handles all Robux purchases and monetization

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Shared modules
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Time = require(Shared:WaitForChild("Time"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Types = require(Shared:WaitForChild("Types"))
local Logger = require(Shared:WaitForChild("Logger"))
local MathUtils = require(Shared:WaitForChild("MathUtils"))
local ServiceValidator = require(Shared:WaitForChild("ServiceValidator"))
local ErrorService = require(script.Parent.ErrorService)  -- OK: ErrorService is a foundation service

-- Services (injected via Init)
local DataService
local InventoryService
local UpgradeService
local CurrencyService
local UserMetricsService  -- Optional dependency
local CharacterStateManager -- Optional dependency for runtime effect sync

-- Use EventBus for events
local EventBus = require(Shared:WaitForChild("EventBus"))
local EventNames = require(Shared:WaitForChild("EventNames"))
local Contracts = require(Shared:WaitForChild("EventContracts"))
local Bus = EventBus.global()

local MonetizationService = {}
MonetizationService.__index = MonetizationService
local log = Logger.new("MonetizationService")

-- Initialize with DI container
function MonetizationService:Init(container)
    DataService = ServiceValidator.get(container, "DataService", {
        "GetPlayerData", "QueueSave", "EnqueueReceiptGrant", "ConsumePendingGrants"
    })
    InventoryService = ServiceValidator.get(container, "InventoryService", {"AddItem", "AddItemsBulk"})
    UpgradeService = ServiceValidator.get(container, "UpgradeService", {"GetPlayerGamepasses"})
    CurrencyService = ServiceValidator.get(container, "CurrencyService", {"add"})
    UserMetricsService = ServiceValidator.tryGet(container, "UserMetricsService", {"Invalidate"})  -- Optional
    CharacterStateManager = ServiceValidator.tryGet(container, "CharacterStateManager", {"SyncProfileBoosts"}) -- Optional
    log:info("Initialized with dependencies")
end

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

    local ok, info = ErrorService.safecall("MarketplaceService:GetProductInfo", function()
        return MarketplaceService:GetProductInfo(id, infoType)
    end, { id = id, infoType = tostring(infoType) })
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

    -- Donations: track spend specifically for the DONATE developer product
    if kind == "DevProduct" then
        local prod = productIdToData[id]
        if prod and prod.id == "DONATE" then
            profile.robuxSpentDonations = (profile.robuxSpentDonations or 0) + (price or 0)
        end
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
    if UserMetricsService then 
        ErrorService.safecall("UserMetricsService:Invalidate", function() 
            UserMetricsService:Invalidate(player) 
        end, { uid = player.UserId })
    end

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
        log:warn("No profile found for player %s during product purchase", player.Name)
        return false
    end
    
    log:info("Processing product purchase: %s for player %s", tostring(product.id), player.Name)
    log:event("product_purchased", {
        uid = player.UserId,
        productId = product.id,
        effect = product.effect,
        price = product.robux or 0
    })
    
    -- Apply product effects
    if product.effect == "speed" then
        -- Apply movement speed potion-style boost (tier 1) for duration
        local duration = product.duration or GameConfig.Timing.ONE_HOUR
        local now = Time.unix()
        profile.boosts["potion_speed_tier_1"] = now + duration
        Bus:emit(EventNames.BOOSTS_CHANGED, {
            to = { kind = "player", player = player },
            payload = Contracts.BOOSTS_CHANGED(profile.boosts)
        })
        
    elseif product.effect == "luck" then
        -- Apply luck boost
        profile.boosts.luck = Time.unix() + (product.duration or GameConfig.Timing.ONE_HOUR)
        Bus:emit(EventNames.BOOSTS_CHANGED, {
            to = { kind = "player", player = player },
            payload = Contracts.BOOSTS_CHANGED(profile.boosts)
        })
        
    elseif product.effect == "size" then
        -- Apply size boost
        profile.boosts.size = Time.unix() + (product.duration or GameConfig.Timing.ONE_HOUR)
        Bus:emit(EventNames.BOOSTS_CHANGED, {
            to = { kind = "player", player = player },
            payload = Contracts.BOOSTS_CHANGED(profile.boosts)
        })
        
    elseif product.effect == "instant_dig" then
        -- Perform mega dig immediately via event
        local worldPos = player.Character and player.Character:FindFirstChild("HumanoidRootPart") and player.Character.HumanoidRootPart.Position
        
        if worldPos then
            -- Request mega dig via event bus with validated contract
            Bus:emit(EventNames.MEGA_DIG_REQUEST, {
                to = { kind = "server" },
                payload = Contracts.MEGA_DIG_REQUEST({
                    player = player,
                    position = worldPos,
                    sizeBoost = product.size or 10
                })
            })
        end
        
    elseif product.effect == "auto_dig" then
        -- Start auto digger
        profile.boosts.auto_dig = Time.unix() + (product.duration or GameConfig.Timing.ONE_HOUR)
        Bus:emit(EventNames.BOOSTS_CHANGED, {
            to = { kind = "player", player = player },
            payload = Contracts.BOOSTS_CHANGED(profile.boosts)
        })
        
        -- Request auto-dig start via event bus with validated contract
        Bus:emit(EventNames.AUTO_DIG_START, {
            to = { kind = "server" },
            payload = Contracts.AUTO_DIG_START({ player = player })
        })
        
    elseif product.coins then
        -- Grant coins
        CurrencyService.add(player, "coins", product.coins)
        
        Bus:emit(EventNames.REWARD_GRANTED, {
            to = { kind = "player", player = player },
            payload = Contracts.REWARD_GRANTED({
                coins = product.coins,
                meta = { source = "purchase" },
            })
        })
    end
    
    -- If boosts were modified above (speed/size/luck), sync runtime effects snapshot now
    if CharacterStateManager and (product.effect == "speed" or product.effect == "size" or product.effect == "luck") then
        CharacterStateManager:SyncProfileBoosts(player)
    end
    
    -- Queue save
    DataService:QueueSave(player)
    
    -- Send notification
    Bus:emit(EventNames.NOTIFICATION_PUSH, {
        to = { kind = "player", player = player },
        payload = Contracts.NOTIFICATION_PUSH({
            type = "purchase",
            message = string.format("Purchase successful: %s!", product.id),
            color = Color3.new(0, 1, 0),
        })
    })
    
    return true
end

-- Process receipt callback (single handler for all products)
local function processReceipt(receipt)
    local userId = receipt.PlayerId
    local productId = receipt.ProductId
    local receiptId = receipt.PurchaseId
    
    -- Check if product is known (BLOCKER FIX #4)
    local productData = productIdToData[productId]
    if not productData then
        log:warn("Unknown product ID: %s - returning NotProcessedYet", tostring(productId))
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
        log:warn("Enqueue attempt %d failed for receipt %s", attempt, receiptId)
        if attempt < 3 then
            task.wait(0.2 * attempt)
        end
    end
    
    if not enqueued then
        -- Failed to persist after retries - must retry later
        log:error("Failed to enqueue receipt after retries: %s", receiptId)
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end
    
    -- Durably persisted; if player is online, record metrics & apply effects exactly once
    local player = Players:GetPlayerByUserId(userId)
    if player then
        local firstTime = processPurchase(userId, "DevProduct", productId, grant.price, "Prompt", receiptId)
        if firstTime then
            log:info("Receipt %s processed successfully for product %s", tostring(receiptId), tostring(productId))
            log:event("receipt_processed", {
                uid = userId,
                productId = productId,
                receiptId = receiptId,
                price = grant.price
            })
            handleProductPurchase(player, productData)
        else
            log:debug("Receipt %s already processed, skipping", tostring(receiptId))
        end
    end
    
    -- BLOCKER FIX #2: Only return PurchaseGranted after durable enqueue
    return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Handle gamepass purchases
local function handleGamepassPurchase(player: Player, gamepass: Types.GamePass)
    local profile = DataService:GetPlayerData(player)
    if not profile then
        log:warn("No profile found for player %s during gamepass purchase", player.Name)
        return
    end
    
    log:info("Processing gamepass purchase: %s for player %s", tostring(gamepass.id), player.Name)
    log:event("gamepass_purchased", {
        uid = player.UserId,
        gamepassId = gamepass.id,
        price = gamepass.robux or 0
    })
    
    -- Gamepass effects are permanent and checked in UpgradeService
    -- Just notify the player
    Bus:emit(EventNames.NOTIFICATION_PUSH, {
        to = { kind = "player", player = player },
        payload = Contracts.NOTIFICATION_PUSH({
            type = "gamepass",
            message = string.format("Gamepass activated: %s!", gamepass.id),
            color = Color3.new(1, 0.8, 0),
        })
    })
    
    -- Special effects for specific gamepasses
    if gamepass.id == "AUTO_DIGGER" then
        -- Start auto dig when the gamepass is activated/backfilled
        Bus:emit(EventNames.AUTO_DIG_START, {
            to = { kind = "server" },
            payload = Contracts.AUTO_DIG_START({ player = player })
        })
    end
end

-- Check gamepass ownership on join
local function onPlayerAdded(player)
    log:debug("Player %s joined, checking gamepass ownership", player.Name)
    
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
        log:info("Processing %d pending grants for player %s", #grants, player.Name)
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
            local success, owns = ErrorService.safecall("MarketplaceService:UserOwnsGamePassAsync", function()
                return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamepassId)
            end, { uid = player.UserId, gamepassId = gamepassId })
            
            if not success then
                log:error("Backfill verify error for gamepass %s player %s", tostring(gamepassId), player.Name)
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
                    log:info("Backfilled game pass %s for %s", tostring(gamepassId), player.Name)
                    log:event("gamepass_backfilled", {
                        uid = player.UserId,
                        gamepassId = gamepassId,
                        price = price
                    })
                end
            end
        end
    end

    -- Ensure permanent effects (like AUTO_DIGGER) are applied at join if owned
    local okGP, gps = pcall(function()
        return UpgradeService and UpgradeService.GetPlayerGamepasses and UpgradeService:GetPlayerGamepasses(player) or {}
    end)
    if okGP and gps and gps["AUTO_DIGGER"] == true then
        Bus:emit(EventNames.AUTO_DIG_START, {
            to = { kind = "server" },
            payload = Contracts.AUTO_DIG_START({ player = player })
        })
        log:debug("Emitted AUTO_DIG_START on join for %s (owns AUTO_DIGGER)", player.Name)
    end
end

-- Clean up receipt queues when player leaves
local function onPlayerRemoving(player)
    receiptQueues[player.UserId] = nil
end

-- Listen for game pass purchases (idempotent + tracked once)
local function onGamePassPurchaseFinished(player, gamePassId, purchased)
    log:info("PromptGamePassPurchaseFinished player=%s gamePassId=%s purchased=%s ", player and player.Name or "<nil>", tostring(gamePassId), tostring(purchased))
    if not purchased then return end

    local profile = DataService:GetPlayerData(player)
    if not profile then return end

    -- Verify ownership server-side
    local ok, owns = ErrorService.safecall("MarketplaceService:UserOwnsGamePassAsync", function()
        return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamePassId)
    end, { uid = player.UserId, gamePassId = gamePassId })
    if not ok or not owns then
        log:error("Game pass verify failed %s for %s", tostring(gamePassId), player.Name)
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
end

-- Get monetization metrics for a player
function MonetizationService:GetMetrics(player: Player)
    local profile = DataService:GetPlayerData(player)
    if not profile then
        return nil
    end
    
    local now = getTimestamp()
    local daysSinceLastPurchase = nil
    if profile.lastPurchaseTime then
        daysSinceLastPurchase = math.floor((now - profile.lastPurchaseTime) / GameConfig.Timing.SECONDS_PER_DAY)
    end
    
    local dev = profile.robuxSpentDevProducts or 0
    local gp = profile.robuxSpentGamePasses or 0
    
    return {
        robuxSpentLifetime = profile.robuxSpentLifetime or 0,
        robuxSpentThisSession = MathUtils.saturatingSub(
            profile.robuxSpentLifetime or 0, 
            profile.sessionStartRobuxSpent or 0
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
    log:debug("Prompting %s purchase: %s for player %s", purchaseType, purchaseId, player.Name)
    if purchaseType == "product" then
        -- Find product
        for _, product in ipairs(GameConfig.Monetization.PRODUCTS) do
            if product.id == purchaseId and product.productId and product.productId > 0 then
                log:info("Calling PromptProductPurchase uid=%d id=%s (#%s)", player.UserId, tostring(product.id), tostring(product.productId))
                MarketplaceService:PromptProductPurchase(player, product.productId)
                log:event("purchase_prompted", {
                    uid = player.UserId,
                    type = "product",
                    id = purchaseId
                })
                return true
            end
        end
        log:warn("Product not configured or not found id=%s for %s", tostring(purchaseId), player.Name)
    elseif purchaseType == "gamepass" then
        -- Find gamepass
        for _, gamepass in ipairs(GameConfig.Monetization.GAMEPASSES) do
            if gamepass.id == purchaseId and gamepass.gamepassId and gamepass.gamepassId > 0 then
                log:info("Calling PromptGamePassPurchase uid=%d id=%s (#%s)", player.UserId, tostring(gamepass.id), tostring(gamepass.gamepassId))
                MarketplaceService:PromptGamePassPurchase(player, gamepass.gamepassId)
                log:event("purchase_prompted", {
                    uid = player.UserId,
                    type = "gamepass",
                    id = purchaseId
                })
                return true
            end
        end
        log:warn("Gamepass not configured or not found id=%s for %s", tostring(purchaseId), player.Name)
    end
    
    log:warn("Failed to prompt purchase: %s %s not found", tostring(purchaseType), tostring(purchaseId))
    return false
end

-- Lifecycle connections
local playerAddedConn
local playerRemovingConn
local gamePassPurchaseConn

-- Start lifecycle - wire up all event handlers
function MonetizationService:Start()
    -- Set up MarketplaceService handlers
    MarketplaceService.ProcessReceipt = processReceipt
    
    -- Connect player events
    playerAddedConn = Players.PlayerAdded:Connect(onPlayerAdded)
    playerRemovingConn = Players.PlayerRemoving:Connect(onPlayerRemoving)
    gamePassPurchaseConn = MarketplaceService.PromptGamePassPurchaseFinished:Connect(onGamePassPurchaseFinished)
    
    log:info("Started with event handlers")
end

-- Stop lifecycle - disconnect all handlers
function MonetizationService:Stop()
    if playerAddedConn then
        playerAddedConn:Disconnect()
        playerAddedConn = nil
    end
    if playerRemovingConn then
        playerRemovingConn:Disconnect()
        playerRemovingConn = nil
    end
    if gamePassPurchaseConn then
        gamePassPurchaseConn:Disconnect()
        gamePassPurchaseConn = nil
    end
    
    -- Clear receipt handler
    MarketplaceService.ProcessReceipt = nil
    
    log:info("Stopped and disconnected handlers")
end

return MonetizationService
