--!strict
-- CurrencyService.lua - canonical currency ops (preserves coin achievements)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(Shared:WaitForChild("Logger"))
local MathUtils = require(Shared:WaitForChild("MathUtils"))
local EventBus = require(Shared:WaitForChild("EventBus"))
local EventNames = require(Shared:WaitForChild("EventNames"))
local Contracts = require(Shared:WaitForChild("EventContracts"))
local ServiceValidator = require(Shared:WaitForChild("ServiceValidator"))

local log = Logger.new("CurrencyService")
local Bus = EventBus.global()

-- deps resolved via DI in Init
local DataService
local ErrorService = require(script.Parent.ErrorService)  -- OK: ErrorService is a foundation service
local UserMetricsService  -- Optional dependency

export type Currency = "coins" | "gems"

local CurrencyService = {}

type CurrencyServiceT = {
    Init: (self: CurrencyServiceT, container: any) -> (),
    add: (player: Player, currency: Currency, amount: number) -> boolean,
    canAfford: (player: Player, currency: Currency, amount: number) -> boolean,
}

function CurrencyService:Init(container)
    -- Hard dependencies - fail fast if missing with validation
    DataService = ServiceValidator.get(container, "DataService", {"GetPlayerData", "QueueSave"})
    
    -- Optional dependency - won't fail if missing
    UserMetricsService = ServiceValidator.tryGet(container, "UserMetricsService", {"Invalidate"})
    
    log:info("Initialized with dependencies")
end

function CurrencyService.add(player: Player, currency: Currency, amount: number): boolean
    local profile = DataService:GetPlayerData(player)
    if not profile then return false end

    if currency == "coins" then
        local before = profile.coins
        local after = MathUtils.saturatingAdd(before, amount)
        profile.coins = after

        local delta = after - before
        if delta >= 0 then
            profile.totalCoinsEarned = (profile.totalCoinsEarned or 0) + delta
        else
            profile.totalCoinsSpent = (profile.totalCoinsSpent or 0) + (-delta)
        end

        Bus:emit(EventNames.CURRENCY_CHANGED, {
            to = { kind = "player", player = player },
            payload = Contracts.CURRENCY_CHANGED({ currency = "coins", balance = profile.coins, delta = delta })
        })
        Bus:emit(EventNames.PROFILE_UPDATED, {
            to = { kind = "player", player = player },
            payload = profile
        })

    elseif currency == "gems" then
        local before = profile.gems
        local after = MathUtils.saturatingAdd(before, amount)
        profile.gems = after

        local delta = after - before
        if delta >= 0 then
            profile.totalGemsEarned = (profile.totalGemsEarned or 0) + delta
        else
            profile.totalGemsSpent = (profile.totalGemsSpent or 0) + (-delta)
        end

        Bus:emit(EventNames.CURRENCY_CHANGED, {
            to = { kind = "player", player = player },
            payload = Contracts.CURRENCY_CHANGED({ currency = "gems", balance = profile.gems, delta = delta })
        })
        Bus:emit(EventNames.PROFILE_UPDATED, {
            to = { kind = "player", player = player },
            payload = profile
        })

    else
        return false
    end

    DataService:QueueSave(player)
    
    -- Invalidate metrics cache for snappier UI updates (optional dependency)
    if UserMetricsService then
        ErrorService.safecall("UserMetricsService:Invalidate", function()
            UserMetricsService:Invalidate(player, "currency_change")
        end, { uid = player.UserId, currency = currency, amount = amount })
    end
    
    return true
end

function CurrencyService.canAfford(player: Player, currency: Currency, amount: number): boolean
    -- Fast-path for non-positive amounts (free/refund)
    if amount <= 0 then return true end
    
    local p = DataService:GetPlayerData(player)
    if not p then return false end
    
    if currency == "coins" then
        return p.coins >= amount
    elseif currency == "gems" then
        return p.gems >= amount
    end
    
    return false
end

return CurrencyService
