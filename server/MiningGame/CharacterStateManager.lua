--!strict
-- CharacterStateManager.lua
-- Server-authoritative character state management with single heartbeat

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local MathUtils = require(Shared:WaitForChild("MathUtils"))
local Time = require(Shared:WaitForChild("Time"))

-- Types
local CharacterTypes = require(Shared:WaitForChild("Character"):WaitForChild("Types"))
type EffectId = CharacterTypes.EffectId
type EffectSnapshot = CharacterTypes.EffectSnapshot
type State = CharacterTypes.State
type ManagerApi = CharacterTypes.ManagerApi

-- Safely require Effects module
local okEffects, Effects = pcall(function()
    return require(Shared:WaitForChild("Character"):WaitForChild("Effects"))
end)
if not okEffects then
    Effects = nil
end

local Logger = require(Shared:WaitForChild("Logger"))
local log = Logger.new("CharacterStateManager")
local DigPerformance = require(script.Parent.DigPerformance)
local ServiceValidator = require(Shared:WaitForChild("ServiceValidator"))

-- Ensure server creates the Remote instances before we access them (startup race guard)
local _ServerRemotes = require(Shared:WaitForChild("Remotes"))

-- Event Bus for decoupled communication
local EventBus = require(Shared:WaitForChild("EventBus"))
local EventNames = require(Shared:WaitForChild("EventNames"))
local Bus = EventBus.global()

-- Services (injected via Init)
local DataService

-- Module table with private + public methods
local CharacterStateManager = {} :: ManagerApi & {
    _initPlayer: (self: any, p: Player) -> (),
    _seedFromProfileBoosts: (self: any, p: Player) -> (),
    SyncProfileBoosts: (self: any, p: Player) -> (),
    Has: (self: any, p: Player, effectId: EffectId) -> boolean,
    Remaining: (self: any, p: Player, effectId: EffectId) -> number,
    changed: () -> RBXScriptSignal,
}
CharacterStateManager.__index = CharacterStateManager

-- State tracking (moved before functions that use them)
local stateByPlayer: {[Player]: State} = {}
local lastSentEffects: {[Player]: EffectSnapshot} = {}

-- Server-side change signal for event-driven updates
local changedEvent = Instance.new("BindableEvent")
function CharacterStateManager.changed() return changedEvent.Event end

-- Helper to set attributes only when changed (prevents network spam)
local function setAttr(p: Player, name: string, value: any): ()
    if p:GetAttribute(name) ~= value then
        p:SetAttribute(name, value)
    end
end

-- Shallow equality check for effects tables
local function effectsEqual(a: EffectSnapshot?, b: EffectSnapshot?): boolean
    if a == b then return true end
    if not a or not b then return false end
    
    local count = 0
    for k, v in pairs(a) do
        count += 1
        if b[k] ~= v then return false end
    end
    
    for _ in pairs(b) do
        count -= 1
    end
    
    return count == 0
end

-- Get current time with sub-second precision
local function now(): number
    return Time.unix()
end

-- Initialize with DI container
function CharacterStateManager:Init(container)
    DataService = ServiceValidator.get(container, "DataService", {"GetPlayerData", "GetActiveBoosts"})
    log:info("Initialized with dependencies")
end

-- Single heartbeat for all players (moved here before Start method that uses it)
local heartbeatConnection: RBXScriptConnection? = nil
local function startHeartbeat()
    if heartbeatConnection then return end  -- Guard against duplicate connections
    
    heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
        DigPerformance.measureSection("CSM_Heartbeat", function()
        local t = now()
        
        -- Use plr to avoid shadowing
        for plr, st in pairs(stateByPlayer) do
            local changed = false
            
            -- Expire effects
            for id, exp in pairs(st.effects) do
                if exp <= t then
                    st.effects[id] = nil
                    changed = true
                end
            end
            
            -- Stamina regen (use stored rate, not config lookup)
            if st.stamina < st.maxStamina then
                local before = st.stamina
                st.stamina = math.min(st.maxStamina, st.stamina + (st.regenPerSec or 10) * dt)
                if st.stamina ~= before then
                    setAttr(plr, "Char_Stamina", math.floor(st.stamina))
                end
            end
            
            -- Broadcast effect changes only when needed
            local last = lastSentEffects[plr]
            if changed or not effectsEqual(st.effects, last) then
                lastSentEffects[plr] = table.clone(st.effects)
                Bus:emit(EventNames.RUNTIME_EFFECTS_CHANGED, {
                    to = { kind = "player", player = plr },
                    payload = st.effects
                })
                changedEvent:Fire(plr) -- Notify server listeners
            end
        end
        end)
    end)
end

-- Start method to connect events after all services are initialized
function CharacterStateManager:Start(container)
    -- Connect player events now that dependencies are ready
    Players.PlayerAdded:Connect(function(p)
        CharacterStateManager:_initPlayer(p)
    end)
    
    Players.PlayerRemoving:Connect(function(p)
        stateByPlayer[p] = nil
        lastSentEffects[p] = nil
    end)
    
    -- Initialize already-present players (Studio safety)
    for _, p in ipairs(Players:GetPlayers()) do
        CharacterStateManager:_initPlayer(p)
    end
    
    -- Start the single heartbeat for all players
    startHeartbeat()
    
    log:info("Started with player connections and heartbeat")
end

-- Initialize player state
function CharacterStateManager:_initPlayer(p: Player): ()
    -- Use config values if available, otherwise defaults
    local healthConfig = GameConfig.Character and GameConfig.Character.Health
    local staminaConfig = GameConfig.Character and GameConfig.Character.Stamina
    
    local baseH = (healthConfig and healthConfig.BASE) or 100
    local baseS = (staminaConfig and staminaConfig.BASE) or 100
    local regenPerSec = (staminaConfig and staminaConfig.REGEN_PER_SEC) or 10
    
    stateByPlayer[p] = {
        maxHealth = baseH,
        health = baseH,
        maxStamina = baseS,
        stamina = baseS,
        regenPerSec = regenPerSec,  -- Store it in state
        nextDigAllowedAt = nil,
        effects = {} :: EffectSnapshot,
    }
    
    -- Set initial attributes
    setAttr(p, "Char_MaxHealth", baseH)
    setAttr(p, "Char_Health", baseH)
    setAttr(p, "Char_MaxStamina", baseS)
    setAttr(p, "Char_Stamina", baseS)  -- Set initial stamina so HUD isn't nil
    
    -- Seed effects from profile boosts
    self:_seedFromProfileBoosts(p)
    
    -- Cache initial effect snapshot
    lastSentEffects[p] = table.clone(stateByPlayer[p].effects)
    
    -- Send initial effects to client via EventBus
    Bus:emit(EventNames.RUNTIME_EFFECTS_CHANGED, {
        to = { kind = "player", player = p },
        payload = stateByPlayer[p].effects
    })
    
    log:debug("Initialized character state for %s", p.Name)
end

-- Sync effects from DataService profile.boosts
function CharacterStateManager:_seedFromProfileBoosts(p: Player): ()
    local st = stateByPlayer[p]
    if not st then return end
    
    -- Expecting { [string]: number } from DataService
    local boosts: { [string]: number } = DataService.GetActiveBoosts and DataService:GetActiveBoosts(p) or {}
    local t = now()
    
    for boostId, expiry in pairs(boosts) do
        -- Check if this boost ID is a known effect (guard Effects usage)
        if okEffects and Effects and Effects.exists((boostId :: any) :: EffectId) and expiry > t then
            local effectId = (boostId :: any) :: EffectId
            st.effects[effectId] = expiry
        end
    end
end

-- Public: re-sync the runtime effects snapshot from profile boosts (speed/size/luck)
function CharacterStateManager:SyncProfileBoosts(p: Player): ()
    local st = stateByPlayer[p]
    if not st then return end
    
    -- Remove existing persisted boost entries so we can refresh cleanly
    local persisted = { speed = true, size = true, luck = true }
    for id, _ in pairs(st.effects) do
        if persisted[(id :: any)] then
            st.effects[(id :: any)] = nil
        end
    end

    -- Seed again from profile
    self:_seedFromProfileBoosts(p)

    -- Broadcast to client immediately
    Bus:emit(EventNames.RUNTIME_EFFECTS_CHANGED, {
        to = { kind = "player", player = p },
        payload = st.effects
    })
end

-- Removed _expireAndBroadcast - now handled by heartbeat

-- === Public API ===

-- Get player state (read-only)
function CharacterStateManager:Get(p: Player): State?
    return stateByPlayer[p]
end

-- Set next allowed dig time (called by DigService)
function CharacterStateManager:SetNextDigAllowedAt(p: Player, ts: number): ()
    local st = stateByPlayer[p]
    if not st then return end
    
    st.nextDigAllowedAt = ts
    setAttr(p, "Char_NextDigAllowedAt", ts)
end

-- Damage player
function CharacterStateManager:Damage(p: Player, amt: number): ()
    local st = stateByPlayer[p]
    if not st then return end
    
    local newH = MathUtils.saturatingSub(st.health or 0, MathUtils.nonNegative(amt))
    st.health = newH
    setAttr(p, "Char_Health", newH)
    
    log:debug("%s took %d damage, health now %d/%d", p.Name, amt, newH, st.maxHealth)
end

-- Heal player
function CharacterStateManager:Heal(p: Player, amt: number): ()
    local st = stateByPlayer[p]
    if not st then return end
    
    local newH = MathUtils.clampRange((st.health or 0) + MathUtils.nonNegative(amt), 0, st.maxHealth)
    st.health = newH
    setAttr(p, "Char_Health", newH)
    
    log:debug("%s healed for %d, health now %d/%d", p.Name, amt, newH, st.maxHealth)
end

-- Apply timed, server-authored effects (e.g., "wet")
function CharacterStateManager:ApplyTimedEffect(p: Player, effectId: EffectId, durationSec: number?): boolean
    if not okEffects or not Effects or not Effects.exists(effectId) then
        log:warn("Attempted to apply unknown effect: %s", tostring(effectId))
        return false
    end
    
    local st = stateByPlayer[p]
    if not st then return false end
    
    -- Use provided duration, or effect's default duration, or 1 second minimum
    local effectDef = okEffects and Effects and Effects.get(effectId)
    local dur = durationSec or (effectDef and effectDef.duration) or 1
    
    st.effects[effectId] = now() + math.max(1, dur)
    
    -- Immediately broadcast update
    lastSentEffects[p] = table.clone(st.effects)
    Bus:emit(EventNames.RUNTIME_EFFECTS_CHANGED, {
        to = { kind = "player", player = p },
        payload = st.effects
    })
    changedEvent:Fire(p)
    
    log:debug("Applied effect %s to %s for %s s", tostring(effectId), p.Name, tostring(dur))
    return true
end

-- Remove an effect
function CharacterStateManager:RemoveEffect(p: Player, effectId: EffectId): ()
    local st = stateByPlayer[p]
    if not st then return end
    
    if st.effects[effectId] then
        st.effects[effectId] = nil
        
        -- Immediately broadcast update
        lastSentEffects[p] = table.clone(st.effects)
        Bus:emit(EventNames.RUNTIME_EFFECTS_CHANGED, {
            to = { kind = "player", player = p },
            payload = st.effects
        })
        changedEvent:Fire(p)
        
        log:debug("Removed effect %s from %s", tostring(effectId), p.Name)
    end
end

-- Helper methods for checking effects
function CharacterStateManager:Has(p: Player, effectId: EffectId): boolean
    local st = stateByPlayer[p]
    if not st then return false end
    
    local expiry = st.effects[effectId]
    return expiry and expiry > now() or false
end

function CharacterStateManager:Remaining(p: Player, effectId: EffectId): number
    local st = stateByPlayer[p]
    if not st then return 0 end
    
    local expiry = st.effects[effectId]
    return expiry and MathUtils.nonNegative(expiry - now()) or 0
end

-- === Wiring ===
-- (Moved to Start method to ensure dependencies are ready)

log:info("CharacterStateManager initialized with single heartbeat")

return (CharacterStateManager :: any) :: ManagerApi
