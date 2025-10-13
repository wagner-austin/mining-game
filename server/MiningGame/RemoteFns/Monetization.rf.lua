--!strict
-- Monetization.rf.lua
-- RemoteFunction specs for monetization and purchase operations
-- Contract: top-level { ok, success, ... }. Exceptions: GetServerUnix (scalar), Equipped maps (raw).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Time = require(Shared:WaitForChild("Time"))
local Logger = require(Shared:WaitForChild("Logger"))
local log = Logger.new("MonetizationRF")

-- Return a factory function that accepts the DI container
return function(container)
    -- Resolve services from the container
    local MonetizationService = container:Get("MonetizationService")
    local DataService = container:Get("DataService")

    type RFSpec = {
    name: string,
    handler: (ctx: any, ...any) -> any,
    validate: ((...any) -> boolean)?,
    opts: {requireProfile: boolean?, rateLimitSec: number?, debugOnly: boolean?}?
}

-- Valid product IDs from GameConfig (build map from Monetization.PRODUCTS)
local PRODUCTS_BY_ID = {}
do
    local list = (GameConfig.Monetization and GameConfig.Monetization.PRODUCTS) or {}
    for _, prod in ipairs(list) do
        if type(prod) == "table" and type(prod.id) == "string" then
            PRODUCTS_BY_ID[prod.id] = prod
        end
    end
end

local VALID_PRODUCTS = {}
for id, _ in pairs(PRODUCTS_BY_ID) do
    VALID_PRODUCTS[id] = true
end

-- Gamepass map by semantic id (e.g., "VIP")
local PASSES_BY_ID = {}
do
    local passes = (GameConfig.Monetization and GameConfig.Monetization.GAMEPASSES) or {}
    for _, pass in ipairs(passes) do
        if type(pass) == "table" and type(pass.id) == "string" then
            PASSES_BY_ID[pass.id] = pass
        end
    end
end

-- (Material purchase flow removed; single-material mode is deprecated.)

-- Gamepass ownership cache to reduce API calls
local gamepassCache: {[number]: { time: number, owned: {[number]: boolean}, ownedById: {[string]: boolean}, list: {any} }} = {}
local GAMEPASS_CACHE_TTL = 120 -- 2 minutes

-- Debug overrides (per-player) for owned state in testing environments
-- Schema: debugOverrides[uid] = { unownedAll = boolean?, ownedIds = { [string]=true }? }
local debugOverrides: {[number]: { unownedAll: boolean?, ownedIds: {[string]: boolean}? }} = {}

    local specs: {RFSpec} = {
    {
        name = "PurchaseProduct",
        handler = function(ctx, productId: string)
            local player = ctx.player
            
            -- Validate product exists (by string id in GameConfig.Monetization.PRODUCTS)
            local product = PRODUCTS_BY_ID[productId]
            if not product then
                log:warn("PurchaseProduct invalid id=%s from %s", tostring(productId), player.Name)
                return {
                    ok = false,
                    success = false,
                    err = "INVALID_PRODUCT",
                    reason = "Unknown product: " .. productId
                }
            end
            if type(product.productId) ~= "number" or product.productId <= 0 then
                log:warn("PurchaseProduct not configured id=%s, productId=%s from %s", tostring(productId), tostring(product.productId), player.Name)
                return {
                    ok = false,
                    success = false,
                    err = "NOT_CONFIGURED",
                    reason = "Product not configured for sale",
                    id = product.id,
                }
            end
            
            -- Prompt the purchase via MonetizationService (uses GameConfig.Monetization.PRODUCTS)
            local prompted = MonetizationService:PromptPurchase(player, "product", productId)
            if prompted then
                log:info("Prompted dev product %s (#%s) for %s", tostring(product.id), tostring(product.productId), player.Name)
                return { ok = true, success = true, prompted = true }
            end
            log:warn("PromptProduct failed id=%s (#%s) for %s", tostring(product.id), tostring(product.productId), player.Name)
            return { ok = false, success = false, err = "PROMPT_FAILED", reason = "Failed to prompt product purchase" }
        end,
        validate = function(productId)
            return type(productId) == "string" and VALID_PRODUCTS[productId] == true
        end,
        opts = { requireProfile = true, rateLimitSec = 2.0 }, -- Higher limit to prevent double-taps
    },

    {
        name = "PurchaseGamepass",
        handler = function(ctx, id: string)
            local player = ctx.player
            -- Validate gamepass exists by semantic id (e.g., "VIP")
            local pass = PASSES_BY_ID[id]
            if not pass or type(pass.gamepassId) ~= "number" or pass.gamepassId <= 0 then
                log:warn("PurchaseGamepass invalid or unavailable id=%s for %s (gamepassId=%s)", tostring(id), player.Name, pass and tostring(pass.gamepassId) or "nil")
                return {
                    ok = false,
                    success = false,
                    err = "INVALID_GAMEPASS",
                    reason = string.format("Unknown or unavailable gamepass: %s", tostring(id))
                }
            end
            -- Prompt the Roblox purchase flow via service
            local prompted = MonetizationService:PromptPurchase(player, "gamepass", id)
            if prompted then
                log:info("Prompted gamepass %s (#%s) for %s", tostring(pass.id), tostring(pass.gamepassId), player.Name)
                return { ok = true, success = true, prompted = true }
            end
            log:warn("PromptGamepass failed id=%s (#%s) for %s", tostring(pass.id), tostring(pass.gamepassId), player.Name)
            return { ok = false, success = false, err = "PROMPT_FAILED", reason = "Failed to prompt gamepass purchase" }
        end,
        validate = function(id)
            return type(id) == "string" and PASSES_BY_ID[id] ~= nil
        end,
        opts = { requireProfile = true, rateLimitSec = 2.0 },
    },
    
    {
        name = "GetPrices",
        handler = function(ctx)
            -- Return current prices/products
            local prices = {}
            
            local list = (GameConfig.Monetization and GameConfig.Monetization.PRODUCTS) or {}
            for _, product in ipairs(list) do
                local id = product.id
                if id then
                    local priceRobux = product.robux or product.price
                    prices[id] = {
                        id = id,
                        name = product.name,
                        price = priceRobux,
                        currency = product.currency or (priceRobux and "robux" or "coins"),
                        rewards = product.rewards or { coins = product.coins },
                        description = product.description,
                    }
                end
            end
            
            return {
                ok = true,
                success = true,
                prices = prices
            }
        end,
        opts = { requireProfile = false, rateLimitSec = 2.0 }, -- Can view without profile
    },
    
    {
        name = "GetGamepasses",
        handler = function(ctx)
            local player = ctx.player
            local now = Time.mono()
            
            -- Check cache first
            local cached = gamepassCache[player.UserId]
            if cached and (now - cached.time) < GAMEPASS_CACHE_TTL then
                return {
                    ok = true,
                    success = true,
                    owned = cached.ownedByGamepassId, -- backward-compat alias
                    ownedById = cached.ownedById,
                    ownedByGamepassId = cached.ownedByGamepassId,
                    list = cached.list,
                    cached = true
                }
            end
            
            -- Check owned gamepasses
            local ownedById = {}
            local ownedByGamepassId = {}
            local list = {}
            local passes = (GameConfig.Monetization and GameConfig.Monetization.GAMEPASSES) or {}
            for _, pass in ipairs(passes) do
                local passId = pass.gamepassId
                local id = pass.id
                if type(passId) == "number" and passId > 0 then
                    local hasPass = false
                    -- Check if player owns it
                    local success, ownsPass = pcall(function()
                        return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
                    end)
                    if success then
                        hasPass = ownsPass
                    end
                    -- Try to fetch official Game Pass icon once per request
                    local iconStr: string? = nil
                    local okInfo, info = pcall(function()
                        return MarketplaceService:GetProductInfo(passId, Enum.InfoType.GamePass)
                    end)
                    if okInfo and info and type(info.IconImageAssetId) == "number" and info.IconImageAssetId > 0 then
                        iconStr = "rbxassetid://" .. tostring(info.IconImageAssetId)
                    end
                    ownedById[id] = hasPass
                    ownedByGamepassId[passId] = hasPass
                    table.insert(list, {
                        id = id,
                        name = pass.name,
                        gamepassId = passId,
                        owned = hasPass,
                        robux = pass.robux,
                        icon = iconStr,
                    })
                end
            end

            -- Apply debug overrides (testing only)
            local ov = debugOverrides[player.UserId]
            if ov then
                if ov.unownedAll == true then
                    for _, entry in ipairs(list) do entry.owned = false end
                    for k, _ in pairs(ownedById) do ownedById[k] = false end
                    for k, _ in pairs(ownedByGamepassId) do ownedByGamepassId[k] = false end
                end
                if ov.ownedIds then
                    for _, entry in ipairs(list) do
                        if ov.ownedIds[entry.id] then entry.owned = true end
                    end
                    for id, _ in pairs(ov.ownedIds) do
                        ownedById[id] = true
                    end
                end
            end
            
            -- Update cache
            gamepassCache[player.UserId] = {
                time = now,
                ownedById = ownedById,
                ownedByGamepassId = ownedByGamepassId,
                list = list,
            }
            
            return {
                ok = true,
                success = true,
                owned = ownedByGamepassId, -- backward-compat alias
                ownedById = ownedById,
                ownedByGamepassId = ownedByGamepassId,
                list = list,
                cached = false
            }
        end,
        opts = { requireProfile = false, rateLimitSec = 5.0 }, -- Cache-friendly rate limit
    },

    -- Debug diagnostics: show Roblox-side info for configured passes
    {
        name = "DebugGetPassDiagnostics",
        handler = function(ctx)
            local player = ctx.player
            local out = {}
            local passes = (GameConfig.Monetization and GameConfig.Monetization.GAMEPASSES) or {}
            for _, pass in ipairs(passes) do
                if type(pass.gamepassId) == "number" and pass.gamepassId > 0 then
                    local owns = false
                    local okOwns, ownsVal = pcall(function()
                        return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.gamepassId)
                    end)
                    if okOwns then owns = ownsVal end
                    local info = nil
                    local okInfo, resInfo = pcall(function()
                        return MarketplaceService:GetProductInfo(pass.gamepassId, Enum.InfoType.GamePass)
                    end)
                    if okInfo then info = resInfo end
                    table.insert(out, {
                        id = pass.id,
                        gamepassId = pass.gamepassId,
                        owns = owns,
                        info = info,
                    })
                end
            end
            return { ok = true, success = true, entries = out }
        end,
        opts = { requireProfile = false, rateLimitSec = 1.0, debugOnly = true },
    },

    -- Debug diagnostics: show Roblox-side info for Donate developer product
    {
        name = "DebugGetDonateDiagnostics",
        handler = function(ctx)
            local prods = (GameConfig.Monetization and GameConfig.Monetization.PRODUCTS) or {}
            local donate = nil
            for _, p in ipairs(prods) do
                if p.id == "DONATE" then donate = p break end
            end
            if not donate or type(donate.productId) ~= "number" or donate.productId <= 0 then
                return { ok = false, success = false, err = "NOT_CONFIGURED" }
            end
            local info = nil
            local okInfo, resInfo = pcall(function()
                return MarketplaceService:GetProductInfo(donate.productId, Enum.InfoType.Product)
            end)
            if okInfo then info = resInfo end
            return { ok = true, success = true, productId = donate.productId, info = info }
        end,
        opts = { requireProfile = false, rateLimitSec = 1.0, debugOnly = true },
    },

    -- Debug: Set per-player owned override for gamepasses in this session
    {
        name = "DebugSetGamepassOverride",
        validate = function(opts)
            return type(opts) == "table"
        end,
        handler = function(ctx, opts)
            local player = ctx.player
            debugOverrides[player.UserId] = {
                unownedAll = (opts and opts.unownedAll) or false,
                ownedIds = (opts and opts.ownedIds) or nil,
            }
            -- Invalidate cache so next GetGamepasses reflects overrides immediately
            gamepassCache[player.UserId] = nil
            return { ok = true, success = true }
        end,
        opts = { requireProfile = false, rateLimitSec = 0.2, debugOnly = true },
    },

    -- Debug: Clear the cached gamepass ownership for this player
    {
        name = "DebugClearGamepassCache",
        handler = function(ctx)
            local player = ctx.player
            gamepassCache[player.UserId] = nil
            return { ok = true, success = true }
        end,
        opts = { requireProfile = false, rateLimitSec = 0.2, debugOnly = true },
    },
    
    {
        name = "ClaimDailyReward",
        handler = function(ctx)
            local player = ctx.player
            
            -- Check if eligible
            local profile = DataService:GetPlayerData(player)
            if not profile then
                return {
                    ok = false,
                    success = false,
                    err = "NO_PROFILE",
                    reason = "Profile not found"
                }
            end
            
            local now = math.floor(Time.unix())
            local lastClaim = profile.lastDailyReward or 0
            local daysSinceLastClaim = math.floor((now - lastClaim) / 86400)
            
            if daysSinceLastClaim < 1 then
                local hoursUntilNext = math.ceil((86400 - (now - lastClaim)) / 3600)
                return {
                    ok = false,
                    success = false,
                    err = "NOT_READY",
                    reason = string.format("Next reward in %d hours", hoursUntilNext)
                }
            end
            
            -- Grant reward directly on profile and queue save
            local reward = GameConfig.DailyReward or { coins = 100 }
            profile.coins = (profile.coins or 0) + (reward.coins or 0)
            profile.lastDailyReward = now
            DataService:QueueSave(player)
            
            return {
                ok = true,
                success = true,
                coins = reward.coins or 0,
                nextClaimTime = now + 86400
            }
        end,
        opts = { requireProfile = true, rateLimitSec = 1.0 },
    },
}

-- Clean up cache for leaving players
game:GetService("Players").PlayerRemoving:Connect(function(player)
    gamepassCache[player.UserId] = nil
end)

    return specs
end -- End of factory function
