--!strict
-- Monetization.rf.lua
-- RemoteFunction specs for monetization and purchase operations
-- Contract: top-level { ok, success, ... }. Exceptions: GetServerUnix (scalar), Equipped maps (raw).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local MaterialDefinitions = require(Shared:WaitForChild("MaterialDefinitions"))
local Time = require(Shared:WaitForChild("Time"))

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

-- Valid material keys from MaterialDefinitions
local VALID_MATERIALS = {}
for key, _ in pairs(MaterialDefinitions.Materials) do
    VALID_MATERIALS[key] = true
end

-- Gamepass ownership cache to reduce API calls
local gamepassCache: {[number]: { time: number, owned: {[number]: boolean} }} = {}
local GAMEPASS_CACHE_TTL = 120 -- 2 minutes

    local specs: {RFSpec} = {
    {
        name = "PurchaseProduct",
        handler = function(ctx, productId: string)
            local player = ctx.player
            
            -- Validate product exists (by string id in GameConfig.Monetization.PRODUCTS)
            local product = PRODUCTS_BY_ID[productId]
            if not product then
                return {
                    ok = false,
                    success = false,
                    err = "INVALID_PRODUCT",
                    reason = "Unknown product: " .. productId
                }
            end
            
            -- Prompt the purchase via MonetizationService (uses GameConfig.Monetization.PRODUCTS)
            local prompted = MonetizationService:PromptPurchase(player, "product", productId)
            if prompted then
                return { ok = true, success = true, prompted = true }
            end
            return { ok = false, success = false, err = "PROMPT_FAILED", reason = "Failed to prompt product purchase" }
        end,
        validate = function(productId)
            return type(productId) == "string" and VALID_PRODUCTS[productId] == true
        end,
        opts = { requireProfile = true, rateLimitSec = 2.0 }, -- Higher limit to prevent double-taps
    },
    
    {
        name = "PurchaseMaterial",
        handler = function(ctx, materialKey: string)
            local player = ctx.player
            
            -- TODO: Implement material purchases when system is ready
            -- For now, return not implemented
            return {
                ok = false,
                success = false,
                err = "NOT_IMPLEMENTED",
                reason = "Material purchases coming soon"
            }
        end,
        validate = function(materialKey)
            return type(materialKey) == "string" and VALID_MATERIALS[materialKey] == true
        end,
        opts = { requireProfile = true, rateLimitSec = 1.0 },
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
                    prices[id] = {
                        id = id,
                        name = product.name,
                        price = product.robux or product.price,
                        currency = product.currency or (product.robux and "robux" or "coins"),
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
                    owned = cached.owned,
                    cached = true
                }
            end
            
            -- Check owned gamepasses
            local owned = {}
            local passes = (GameConfig.Monetization and GameConfig.Monetization.GAMEPASSES) or {}
            for _, pass in ipairs(passes) do
                local passId = pass.gamepassId
                if type(passId) == "number" and passId > 0 then
                    local hasPass = false
                    -- Check if player owns it
                    local success, ownsPass = pcall(function()
                        return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
                    end)
                    if success then
                        hasPass = ownsPass
                    end
                    owned[passId] = hasPass
                end
            end
            
            -- Update cache
            gamepassCache[player.UserId] = {
                time = now,
                owned = owned
            }
            
            return {
                ok = true,
                success = true,
                owned = owned,
                cached = false
            }
        end,
        opts = { requireProfile = false, rateLimitSec = 5.0 }, -- Cache-friendly rate limit
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
