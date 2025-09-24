--!strict
-- CosmeticController.lua
-- Registry-driven controller that auto-loads renderers and handles equipment changes

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local CosmeticDefinitions = require(MiningGame:WaitForChild("CosmeticDefinitions"))
local Logger = require(MiningGame:WaitForChild("Logger"))
local EventBus = require(MiningGame:WaitForChild("EventBus"))
local EventNames = require(MiningGame:WaitForChild("EventNames"))
local ClientRF = require(MiningGame:WaitForChild("ClientRF"))
local Timeout = require(MiningGame:WaitForChild("Timeout"))
local LoadCfg = require(MiningGame:WaitForChild("LoadingConstants"))
local Time = require(MiningGame:WaitForChild("Time"))
local Bus = EventBus.global()

-- Type definitions for RF responses
type ItemsBySlot = {[string]: string}
type AllEquipped = {[string]: {[string]: string}}
type EquipResponse = {success: boolean, reason: string?}
type TypedCaller<T> = (...any) -> (T?, string?)

-- Typed RF calls for cosmetics
local Calls = {
    GetEquippedItems = ClientRF.typed("GetEquippedItems") :: TypedCaller<ItemsBySlot>,
    GetAllEquipped = ClientRF.typed("GetAllEquipped") :: TypedCaller<AllEquipped>,
    EquipItem = ClientRF.typed("EquipItem") :: TypedCaller<EquipResponse>,
    UnequipItem = ClientRF.typed("UnequipItem") :: TypedCaller<EquipResponse>,
}

-- Helper for consistent RF logging
local function rfOk(okMsg)
    return function(data, err)
        if err then 
            log:warn("✗ %s", err)
        else 
            log:debug("✓ %s", okMsg)
        end
    end
end

local CosmeticsFolder = script.Parent
local RendererRegistry = require(CosmeticsFolder:WaitForChild("RendererRegistry"))
local RenderersFolder = CosmeticsFolder:WaitForChild("Renderers")

local log = Logger.new("CosmeticController")

local CosmeticController = {}
CosmeticController._enabled = true
CosmeticController._appliedCosmetics = {} -- [player][slot] = cleanup function
CosmeticController._connections = {}
CosmeticController._preloadCache = {} -- Track preloaded assets
CosmeticController._slotVersion = {} -- [player][slot] = version number for staleness check

type CosmeticControllerT = typeof(CosmeticController) & {
    init: (self: CosmeticControllerT) -> (),
    enable: (self: CosmeticControllerT) -> (),
    disable: (self: CosmeticControllerT) -> (),
    toggle: (self: CosmeticControllerT) -> boolean,
    cleanup: (self: CosmeticControllerT) -> (),
}

-- Helper: preload cosmetic assets with timeout
local function preloadCosmeticAsset(instances: {Instance}, showPlaceholder: (() -> ())?): boolean
    -- Skip empty preloads (PreloadAsync can throw on empty arrays)
    if not instances or #instances == 0 then 
        return true 
    end
    
    -- Validate, dedupe, and filter to ensure only valid Instances
    local seen, filtered = {}, {}
    for _, inst in ipairs(instances) do
        if typeof(inst) == "Instance" and inst.Parent and not seen[inst] then 
            seen[inst] = true
            table.insert(filtered, inst)
        end
    end
    
    if #filtered == 0 then
        return true -- Nothing to preload
    end
    
    local t = LoadCfg.TIMEOUTS.CosmeticClient
    local t0 = Time.mono()
    
    local ok = Timeout.run(function()
        ContentProvider:PreloadAsync(filtered)
    end, t, LoadCfg.POLL_INTERVALS.Default)
    
    local dt = Time.mono() - t0
    
    if not ok then
        log:debug("Cosmetic preload timeout (%.1fs) - showing placeholder", t)
        if showPlaceholder then
            showPlaceholder()
        end
        return false
    end
    
    -- Warn on slow loads (non-timeout)
    if dt > 0.5 then
        log:warn("Slow cosmetic preload (%.2fs) for %d assets", dt, #filtered)
    end
    
    return true
end

-- Auto-load all renderer modules
function CosmeticController:_loadRenderers()
    for _, module in ipairs(RenderersFolder:GetChildren()) do
        if module:IsA("ModuleScript") then
            local ok, exported = pcall(require, module) -- modules self-register
            if ok then
                log:info("Loaded %s (priority: %s)", module.Name, tostring(exported and exported.priority or "n/a"))
            else
                log:warn("Failed to load renderer %s: %s", module.Name, tostring(exported))
            end
        end
    end
end

-- Apply cosmetics to a character
function CosmeticController:_applyCosmetics(player: Player, equipped: {[string]: string})
    -- Debug: Log what's being equipped
    log:debug("Applying cosmetics for %s", player.Name)
    for slot, itemId in pairs(equipped) do
        log:debug("  - %s : %s", tostring(slot), tostring(itemId))
    end
    local character = player.Character
    if not character then return end
    
    -- All cosmetics re-enabled after fixing Aura renderer
    -- The issue was in Aura.lua setting CFrame after creating the weld
    
    -- Clean up existing cosmetics for this player
    self:_removeAllCosmetics(player)
    
    -- Create player entry if needed
    if not self._appliedCosmetics[player] then
        self._appliedCosmetics[player] = {}
    end
    
    -- Initialize slot versions for staleness checking
    self._slotVersion[player] = self._slotVersion[player] or {}
    
    -- Sort items by renderer priority
    local sortedItems = {}
    for slot, itemId in pairs(equipped) do
        local renderer = RendererRegistry.get(slot)
        if renderer then
            table.insert(sortedItems, {
                slot = slot,
                itemId = itemId,
                priority = renderer.priority or 0
            })
        end
    end
    table.sort(sortedItems, function(a, b) 
        return a.priority > b.priority 
    end)
    
    -- Apply cosmetics in priority order
    for _, item in ipairs(sortedItems) do
        local renderer = RendererRegistry.get(item.slot)
        if renderer then
            local itemDef = CosmeticDefinitions.Get(item.itemId)
            if itemDef then
                -- Increment slot version for staleness check
                local version = (self._slotVersion[player][item.slot] or 0) + 1
                self._slotVersion[player][item.slot] = version
                
                -- Preload assets if not cached (consider variant for cache key)
                local key = item.itemId .. ":" .. (itemDef.variant or "default")
                if not self._preloadCache[key] then
                    -- Let renderer provide assets to preload (optional, wrapped in pcall)
                    local toPreload = {}
                    if renderer.preload and type(renderer.preload) == "function" then
                        local okPre, assets = pcall(function() 
                            return renderer.preload(itemDef, character) 
                        end)
                        if okPre and assets then
                            toPreload = assets
                        end
                    end
                    
                    -- Preload with timeout and optional placeholder
                    preloadCosmeticAsset(toPreload, function()
                        if renderer.showPlaceholder then
                            pcall(renderer.showPlaceholder, character, itemDef)
                        end
                    end)
                    self._preloadCache[key] = true
                end
                
                -- Apply cosmetic asynchronously to avoid blocking
                task.spawn(function()
                    -- Race condition guards
                    if not character or not character.Parent then return end
                    if not self._appliedCosmetics[player] then return end
                    
                    -- Check if slot is still current
                    if self._slotVersion[player][item.slot] ~= version then
                        return -- Slot changed, skip stale apply
                    end
                    
                    local success, result = pcall(renderer.apply, character, itemDef)
                    if success then
                        -- Double-check staleness after apply
                        if self._slotVersion[player][item.slot] ~= version then
                            -- Became stale during apply, clean up
                            if renderer.remove then
                                pcall(renderer.remove, result)
                            end
                            -- Hide placeholder if renderer supports it
                            if renderer.hidePlaceholder then
                                pcall(renderer.hidePlaceholder, character)
                            end
                            return
                        end
                        
                        self._appliedCosmetics[player][item.slot] = result
                        log:debug("Applied %s to %s", item.itemId, player.Name)
                        
                        -- Hide placeholder on successful apply
                        if renderer.hidePlaceholder then
                            pcall(renderer.hidePlaceholder, character)
                        end
                    else
                        log:warn("Failed to apply %s: %s", item.itemId, tostring(result))
                    end
                end)
            else
                log:warn("Unknown cosmetic: %s", item.itemId)
            end
        else
            log:debug("No renderer for slot: %s", item.slot)
        end
    end
end

-- Remove all cosmetics from a player
function CosmeticController:_removeAllCosmetics(player: Player)
    local playerCosmetics = self._appliedCosmetics[player]
    if not playerCosmetics then return end
    
    for slot, ctx in pairs(playerCosmetics) do
        local renderer = RendererRegistry.get(slot)
        if renderer and renderer.remove then
            local ok, err = pcall(renderer.remove, ctx) -- ctx only
            if not ok then 
                log:warn("Error removing %s: %s", slot, tostring(err)) 
            end
        end
    end
    
    self._appliedCosmetics[player] = {}
    self._slotVersion[player] = {}  -- Invalidate any in-flight applies
end

-- Handle equipment changes
function CosmeticController:_removeSlot(player: Player, slot: string)
    local bySlot = self._appliedCosmetics[player]
    if not bySlot then return end
    
    -- Bump version so any pending apply for this slot is considered stale
    self._slotVersion[player] = self._slotVersion[player] or {}
    self._slotVersion[player][slot] = (self._slotVersion[player][slot] or 0) + 1
    
    local ctx = bySlot[slot]
    if not ctx then return end
    
    local renderer = RendererRegistry.get(slot)
    if not renderer or not renderer.remove then return end
    
    local ok, err = pcall(renderer.remove, ctx) -- remove(ctx) only, no character arg
    if not ok then
        log:warn("Remove %s failed: %s", slot, tostring(err))
    end
    bySlot[slot] = nil
end

function CosmeticController:_applySingleSlot(player: Player, slot: string, itemId: string)
    local character = player.Character
    if not character then return end
    
    local renderer = RendererRegistry.get(slot)
    if not renderer then return end
    
    local def = CosmeticDefinitions.Get(itemId)
    if not def then return end
    
    -- Clear old ctx for this slot
    self:_removeSlot(player, slot)
    
    -- Apply
    local ok, ctx = pcall(renderer.apply, character, def)
    if ok then
        self._appliedCosmetics[player] = self._appliedCosmetics[player] or {}
        self._appliedCosmetics[player][slot] = ctx
    else
        log:warn("Apply %s failed: %s", itemId, tostring(ctx))
    end
end

-- Handle character spawning
function CosmeticController:_onCharacterAdded(player: Player)
    -- Clean up any previous character data
    self:_removeAllCosmetics(player)
    self._slotVersion[player] = {}  -- Reset slot versions on respawn
    
    -- Wait for character to load
    local character = player.Character
    if not character then return end
    
    local hrp = character:WaitForChild("HumanoidRootPart")
    character:WaitForChild("Humanoid")
    
    
    -- Request and apply this player's equipment
    task.spawn(function()
        local equipped
        if player == Players.LocalPlayer then
            log:debug("Getting equipped items for local player")
            equipped, _ = Calls.GetEquippedItems()
            log:debug("Equipped items: %s", tostring(equipped))
        else
            local all, _ = Calls.GetAllEquipped()
            equipped = all and all[player.UserId]
        end
        
        if equipped and self._enabled then
            self:_applyCosmetics(player, equipped)
        else
            log:debug("No equipped items or controller disabled")
        end
    end)
end

-- Handle player removing
function CosmeticController:_onPlayerRemoving(player: Player)
    self:_removeAllCosmetics(player)
    self._appliedCosmetics[player] = nil
    self._slotVersion[player] = nil  -- Clean up slot versions
end

-- Initialize the controller
function CosmeticController:init()
    -- Load all renderer modules
    self:_loadRenderers()
    
    local localPlayer = Players.LocalPlayer
    
    -- Listen for equipment changes from any player (EventBus)
    local offEquip = Bus:on(EventNames.EQUIPMENT_CHANGED, function(payload)
        if not payload or not payload.playerUserId or not payload.slot then return end
        
        local p = Players:GetPlayerByUserId(payload.playerUserId)
        if not p then return end
        
        -- If a model swap changed, rebuild layering from scratch for that player
        local needsRelayer = false -- modelSwap removed
        
        if payload.itemId then
            -- Only (re)apply this slot
            self:_applySingleSlot(p, payload.slot, payload.itemId)
        else
            self:_removeSlot(p, payload.slot)
        end
    end)
    table.insert(self._connections, offEquip)
    
    -- Handle character spawning for all players
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            self:_onCharacterAdded(player)
        end
        
        local charConn = player.CharacterAdded:Connect(function()
            self:_onCharacterAdded(player)
        end)
        table.insert(self._connections, charConn)
        
        local charRemConn = player.CharacterRemoving:Connect(function()
            self:_removeAllCosmetics(player)
        end)
        table.insert(self._connections, charRemConn)
    end
    
    -- Handle new players joining
    local playerAddedConn = Players.PlayerAdded:Connect(function(player)
        local charConn = player.CharacterAdded:Connect(function()
            self:_onCharacterAdded(player)
        end)
        table.insert(self._connections, charConn)
        
        local charRemConn = player.CharacterRemoving:Connect(function()
            self:_removeAllCosmetics(player)
        end)
        table.insert(self._connections, charRemConn)
        
        if player.Character then
            self:_onCharacterAdded(player)
        end
    end)
    table.insert(self._connections, playerAddedConn)
    
    -- Handle players leaving
    local playerRemovingConn = Players.PlayerRemoving:Connect(function(player)
        self:_onPlayerRemoving(player)
    end)
    table.insert(self._connections, playerRemovingConn)
    
    -- Initial sync: get all players' equipped items
    -- COMMENTED OUT: This causes double application since _onCharacterAdded already handles this!
    -- The _onCharacterAdded function is already called for existing players above (line 429)
    -- and it fetches and applies cosmetics. This second application was causing issues.
    --[[
    task.spawn(function()
        local allEquipped, err = Calls.GetAllEquipped()
        
        if not err and allEquipped and self._enabled then
            for userIdRaw, equipped in pairs(allEquipped) do
                -- Properly decode userId from remote payload (keys are serialized as strings)
                local userId = (typeof(userIdRaw) == "number") and userIdRaw or tonumber(userIdRaw)
                assert(userId, ("GetAllEquipped: bad userId key %s"):format(tostring(userIdRaw)))
                
                local player = Players:GetPlayerByUserId(userId)
                if player and player.Character then
                    self:_applyCosmetics(player, equipped)
                end
            end
        elseif err then
            log:warn("Failed to get initial equipped items: %s", err)
        end
    end)
    --]]
    
    log:info("CosmeticController initialized with %d renderers", RendererRegistry.count())
end

-- Enable cosmetic rendering
function CosmeticController:enable()
    if self._enabled then return end
    
    self._enabled = true
    log:info("Cosmetics enabled")
    
    -- Re-apply cosmetics to all players
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            task.spawn(function()
                local equipped = nil
                if player == Players.LocalPlayer then
                    equipped, _ = Calls.GetEquippedItems()
                else
                    -- Get from cached data or request fresh
                    local allEquipped, _ = Calls.GetAllEquipped()
                    equipped = allEquipped and allEquipped[player.UserId]
                end
                
                if equipped then
                    self:_applyCosmetics(player, equipped)
                end
            end)
        end
    end
end

-- Disable cosmetic rendering
function CosmeticController:disable()
    if not self._enabled then return end
    
    self._enabled = false
    log:info("Cosmetics disabled")
    
    -- Remove all cosmetics from all players
    for player, _ in pairs(self._appliedCosmetics) do
        self:_removeAllCosmetics(player)
    end
end

-- Toggle cosmetic rendering
function CosmeticController:toggle()
    if self._enabled then
        self:disable()
    else
        self:enable()
    end
    return self._enabled
end

-- Cleanup
function CosmeticController:cleanup()
    -- Remove all cosmetics
    for player, _ in pairs(self._appliedCosmetics) do
        self:_removeAllCosmetics(player)
    end
    self._appliedCosmetics = {}
    
    -- Disconnect all connections (handle both RBXScriptConnections and functions)
    for _, conn in ipairs(self._connections) do
        if typeof(conn) == "function" then
            conn() -- EventBus off() function
        elseif conn and conn.Disconnect then
            conn:Disconnect() -- Legacy RBXScriptConnection
        end
    end
    self._connections = {}
end

-- Hook cleanup to script destroy
if script and script.Destroying then
    script.Destroying:Connect(function()
        CosmeticController:cleanup()
    end)
end

return CosmeticController
