--!strict
-- ClientEconomy.lua
-- Centralized, reliable access to the player's soft currency (coins) and helpers

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Remotes = require(MiningGame:WaitForChild("Remotes"))
local ClientRF = require(MiningGame:WaitForChild("ClientRF"))
local PlayerProfileGuard = require(MiningGame:WaitForChild("PlayerProfileGuard"))

local ClientEconomy = {}

local function hasRF(name: string): boolean
    return Remotes and Remotes.RF and Remotes.RF[name] ~= nil
end

-- Returns the current coin balance, using the most stable provider available.
function ClientEconomy.getCoins(): number
    -- 1) Preferred: PlayerProfileGuard (central API with caching)
    if PlayerProfileGuard and typeof(PlayerProfileGuard.getCoins) == "function" then
        local amount, _ = PlayerProfileGuard.getCoins()
        if typeof(amount) == "number" then return amount end
    end

    -- 2) UIManager's account data provider snapshot (kept live elsewhere)
    local provider = (_G and _G.UIManager and _G.UIManager.accountDataProvider) or nil
    if provider and provider.getSnapshot then
        local snap = provider:getSnapshot()
        local coins = snap and snap.profile and snap.profile.coins
        if typeof(coins) == "number" then
            return coins
        end
    end

    -- 3) Fallback RF calls
    if hasRF("GetBalance") then
        local ok, res = pcall(function()
            return ClientRF.call("GetBalance")
        end)
        if ok and res and typeof(res.coins) == "number" then
            return res.coins
        end
    end
    if hasRF("GetProfile") then
        local ok, res = pcall(function()
            return ClientRF.call("GetProfile")
        end)
        if ok and res and res.profile and typeof(res.profile.coins) == "number" then
            return res.profile.coins
        end
    end

    return 0
end

return ClientEconomy

