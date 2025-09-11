--!strict
-- CharacterStateClient.lua
-- Client-side character state interface for UI and movement

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local CharacterTypes = require(MiningGame:WaitForChild("Character"):WaitForChild("Types"))
local Effects = require(MiningGame:WaitForChild("Character"):WaitForChild("Effects"))
local EventBus = require(MiningGame:WaitForChild("EventBus"))
local EventNames = require(MiningGame:WaitForChild("EventNames"))
local Bus = EventBus.global()

type EffectSnapshot = CharacterTypes.EffectSnapshot
local player = Players.LocalPlayer

-- State
local changedBE = Instance.new("BindableEvent")
changedBE.Name = "CharacterStateClientChanged"

local snapshot: EffectSnapshot = {} :: EffectSnapshot
local offEffects: (() -> ())? = nil

-- Handle effect updates from server via EventBus
offEffects = Bus:on(EventNames.RUNTIME_EFFECTS_CHANGED, function(effects: EffectSnapshot)
    snapshot = effects or {}
    changedBE:Fire()
end)

-- Cleanup on script destroy
if script and script.Destroying then
    script.Destroying:Connect(function()
        if offEffects then
            offEffects()
            offEffects = nil
        end
        if changedBE then
            changedBE:Destroy()
            changedBE = nil
        end
    end)
end

-- Module API
local CharacterStateClient = {} :: {
    changed: () -> RBXScriptSignal,
    getEffects: () -> EffectSnapshot,
    getMovementMods: () -> (number, number, number, number),
    getVitals: () -> { health: number, maxHealth: number, stamina: number, maxStamina: number },
    getNextDigAllowedAt: () -> (number?),
}

function CharacterStateClient.changed(): RBXScriptSignal
    return changedBE.Event
end

function CharacterStateClient.getEffects(): EffectSnapshot
    return snapshot
end

function CharacterStateClient.getMovementMods(): (number, number, number, number)
    local speedMult, speedAdd, jumpMult, jumpAdd = 1.0, 0.0, 1.0, 0.0
    
    for id in pairs(snapshot) do
        local def = Effects.get((id :: any)) -- cast to EffectId
        if def and def.movement then
            local m = def.movement
            if m.speedMult then speedMult *= m.speedMult end
            if m.speedAdd then speedAdd += m.speedAdd end
            if m.jumpMult then jumpMult *= m.jumpMult end
            if m.jumpAdd then jumpAdd += m.jumpAdd end
        end
    end
    
    return speedMult, speedAdd, jumpMult, jumpAdd
end

function CharacterStateClient.getVitals(): { health: number, maxHealth: number, stamina: number, maxStamina: number }
    return {
        health = player:GetAttribute("Char_Health") or 0,
        maxHealth = player:GetAttribute("Char_MaxHealth") or 0,
        stamina = player:GetAttribute("Char_Stamina") or 0,
        maxStamina = player:GetAttribute("Char_MaxStamina") or 0,
    }
end

function CharacterStateClient.getNextDigAllowedAt(): number?
    return player:GetAttribute("Char_NextDigAllowedAt")
end

return CharacterStateClient