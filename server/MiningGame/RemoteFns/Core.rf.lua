--!strict
-- Core.rf.lua
-- RemoteFunction specs for core/admin/debug operations

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Time = require(Shared:WaitForChild("Time"))
local Result = require(Shared:WaitForChild("Result"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local EventBus = require(Shared:WaitForChild("EventBus"))
local EventNames = require(Shared:WaitForChild("EventNames"))
local Contracts = require(Shared:WaitForChild("EventContracts"))
local Bus = EventBus.global()

-- Return a factory function that accepts the DI container
return function(container)
    -- Resolve services from the container
    local DataService = container:Get("DataService")
    local CurrencyService = container:Get("CurrencyService")
    local DigService = container:Get("DigService")
    local SpawnService = container:Get("SpawnService")
    local UserMetricsService = container:Get("UserMetricsService")
    local SpawnStrategies = require(script.Parent.Parent.SpawnStrategies) -- Not a service, just a module

    type RFSpec = {
        name: string,
        handler: (ctx: any, ...any) -> any,
        validate: ((...any) -> boolean)?,
        opts: {requireProfile: boolean?, rateLimitSec: number?, debugOnly: boolean?}?
    }

    -- Helper functions
    local function isDev(player: Player): boolean
        return RunService:IsStudio()
    end

    local function canSeeServerMetrics(player: Player): boolean
        return RunService:IsStudio()
    end

    local specs: {RFSpec} = {
    {
        name = "GetServerUnix",
        handler = function(ctx)
            return Result.ok(math.floor(Time.unix()))
        end,
        opts = { requireProfile = false, rateLimitSec = 1.0 },
    },
    
    {
        name = "TeleportToHome",
        handler = function(ctx)
            local ok, err, reason = SpawnService:TeleportHome(ctx.player)
            if ok then
                return { ok = true, success = true }
            else
                return { ok = false, success = false, err = err or "FAILED", reason = reason }
            end
        end,
        opts = { requireProfile = false, rateLimitSec = 0.2 },
    },
    
    {
        name = "DebugAddCurrency",
        handler = function(ctx, currencyType: string, amount: number)
            if not isDev(ctx.player) then
                return {
                    ok = false,
                    success = false,
                    err = "FORBIDDEN",
                    reason = "Not authorized"
                }
            end
            CurrencyService.add(ctx.player, currencyType, amount)
            -- Return at top level to match client expectations
            return {
                ok = true,
                success = true,
                added = amount
            }
        end,
        validate = function(currencyType, amount)
            if type(currencyType) ~= "string" then return false end
            if type(amount) ~= "number" or amount <= 0 then return false end
            return currencyType == "coins" or currencyType == "gems"
        end,
        opts = { requireProfile = true, rateLimitSec = 0.25, debugOnly = true },
    },
    
    {
        name = "DebugResetCube",
        handler = function(ctx)
            if not isDev(ctx.player) then
                return {
                    ok = false,
                    success = false,
                    err = "FORBIDDEN",
                    reason = "Not authorized"
                }
            end

            local cubeData = DataService:GetCubeData(ctx.player)
            if not cubeData then
                return {
                    ok = false,
                    success = false,
                    err = "NO_CUBE",
                    reason = "No cube data found"
                }
            end

            -- Reset on-disk state
            cubeData.chunks = {}
            cubeData.totalDug = 0
            DataService:SaveCubeAsync(ctx.player)

            -- Destroy model & reinitialize
            local playerCubes = DigService.playerCubes
            if playerCubes and playerCubes[ctx.player] then
                if playerCubes[ctx.player].model then
                    playerCubes[ctx.player].model:Destroy()
                end
                playerCubes[ctx.player] = nil
            end
            DigService:InitializePlayerCube(ctx.player)

            -- Return at top level to match client expectations
            return {
                ok = true,
                success = true,
                message = "Cube reset to fresh state"
            }
        end,
        opts = { requireProfile = true, rateLimitSec = 0.5, debugOnly = true },
    },
    
    {
        name = "DebugResetStats",
        handler = function(ctx)
            if not isDev(ctx.player) then
                return {
                    ok = false,
                    success = false,
                    err = "FORBIDDEN",
                    reason = "Not authorized"
                }
            end
            
            -- Use the new centralized reset method
            local success = DataService:ResetProfileToDefaults(ctx.player, {
                upgrades = true,
                currencies = true,
                boosts = true,
                -- inventory = false, -- Don't wipe inventory for "Reset Stats"
            })
            
            if success then
                -- Emit event for UI update
                Bus:emit(EventNames.DEBUG_RESET, {
                    to = { kind = "player", player = ctx.player },
                    payload = { type = "stats" }
                })
                -- Return at top level to match client expectations
                return {
                    ok = true,
                    success = true
                }
            end
            
            return {
                ok = false,
                success = false,
                err = "RESET_FAILED",
                reason = "Failed to reset stats"
            }
        end,
        opts = { requireProfile = true, rateLimitSec = 1.0, debugOnly = true },
    },

    {
        name = "DebugResetInventory",
        handler = function(ctx)
            if not isDev(ctx.player) then
                return {
                    ok = false,
                    success = false,
                    err = "FORBIDDEN",
                    reason = "Not authorized"
                }
            end

            -- Reset only inventory and equipped to defaults
            local ok = DataService:ResetProfileToDefaults(ctx.player, {
                upgrades = false,
                currencies = false,
                boosts = false,
                inventory = true,
            })
            if ok then
                -- Emit events for UI update
                local profile = DataService:GetPlayerData(ctx.player)
                local inv = (profile and profile.inventory) or {}
                Bus:emit(EventNames.INVENTORY_CHANGED, {
                    to = { kind = "player", player = ctx.player },
                    payload = Contracts.INVENTORY_CHANGED(inv),
                })
                Bus:emit(EventNames.PROFILE_UPDATED, {
                    to = { kind = "player", player = ctx.player },
                    payload = profile,
                })
                return { ok = true, success = true, message = "Inventory reset" }
            end
            return { ok = false, success = false, err = "RESET_FAILED", reason = "Failed to reset inventory" }
        end,
        opts = { requireProfile = true, rateLimitSec = 0.5, debugOnly = true },
    },
    
    -- Metrics RF endpoints removed in favor of EventBus push requests
    
    -- Spawn strategy management
    {
        name = "SpawnStrategy_Get",
        handler = function(ctx)
            if not isDev(ctx.player) then
                return { ok = false, success = false, err = "FORBIDDEN", reason = "Not authorized" }
            end
            
            -- Get current strategy from SpawnStrategies (which checks GameConfig as fallback)
            local current = SpawnStrategies.GetCurrentStrategyName()
            return { ok = true, success = true, current = current }
        end,
        opts = { requireProfile = false, rateLimitSec = 0.5, debugOnly = true },
    },
    
    {
        name = "SpawnStrategy_List",
        handler = function(ctx)
            if not isDev(ctx.player) then
                return { ok = false, success = false, err = "FORBIDDEN", reason = "Not authorized" }
            end
            
            -- Use the built-in ListStrategies method
            local strategies = SpawnStrategies.ListStrategies()
            return { ok = true, success = true, strategies = strategies }
        end,
        opts = { requireProfile = false, rateLimitSec = 0.5, debugOnly = true },
    },
    
    {
        name = "SpawnStrategy_Set",
        handler = function(ctx, strategy: string)
            if not isDev(ctx.player) then
                return { ok = false, success = false, err = "FORBIDDEN", reason = "Not authorized" }
            end
            
            -- Normalize strategy name (trim whitespace, lowercase for comparison)
            local requested = type(strategy) == "string" and strategy:match("^%s*(.-)%s*$"):lower() or nil
            if not requested or #requested == 0 then
                return { ok = false, success = false, err = "INVALID_STRATEGY", reason = "Missing or invalid strategy name" }
            end
            
            -- Get list of available strategies and find matching one (case-insensitive)
            local available = SpawnStrategies.ListStrategies()
            local actualName = nil
            for _, name in ipairs(available) do
                if name:lower() == requested then
                    actualName = name
                    break
                end
            end
            
            if not actualName then
                return { ok = false, success = false, err = "INVALID_STRATEGY", reason = "Unknown strategy: " .. requested }
            end
            
            -- Call SetStrategy with the proper case name
            local success = SpawnStrategies.SetStrategy(actualName)
            if success then
                -- Update GameConfig to make it the source of truth
                local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
                local GameConfig = require(MiningGame:WaitForChild("GameConfig"))
                GameConfig.Multiplayer = GameConfig.Multiplayer or {}
                GameConfig.Multiplayer.SPAWN_STRATEGY = actualName
                
                -- Set attribute for visibility
                MiningGame:SetAttribute("SpawnStrategy", actualName)
                
                return { 
                    ok = true,
                    success = true, 
                    current = actualName,
                    message = "Strategy changed to " .. actualName
                }
            end
            
            return { ok = false, success = false, err = "SET_FAILED", reason = "Failed to set strategy" }
        end,
        validate = function(strategy)
            local s = type(strategy) == "string" and strategy:match("^%s*(.-)%s*$"):lower() or nil
            return s ~= nil and #s > 0
        end,
        opts = { requireProfile = false, rateLimitSec = 1.0, debugOnly = true },
    },
}

    return specs
end -- End of factory function
