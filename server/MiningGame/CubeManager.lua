--!strict
-- CubeManager.server.lua
-- Manages spawning/despawning of player cubes based on rules (phase/events) and provides a reliable index.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(Shared:WaitForChild("Logger"))
local ServiceValidator = require(Shared:WaitForChild("ServiceValidator"))
local WorldGenUtils = require(Shared:WaitForChild("WorldGenUtils"))
local EventBus = require(Shared:WaitForChild("EventBus"))
local EventNames = require(Shared:WaitForChild("EventNames"))

local log = Logger.new("CubeManager")
local DigPerformance = require(script.Parent.DigPerformance)

local CubeManager = {}

local DigService
local CubePositionService
local Bus = EventBus.global()

-- Internal state
local registry: {[Player]: { id: string, model: Model? }} = {}

-- Optional phase rule; when enabled, spawns or despawns all player cubes based on phase
local phaseRule: { spawn: {[string]: boolean}, despawn: {[string]: boolean} }? = nil
local _phaseConn: RBXScriptConnection?

function CubeManager:Init(container)
    DigService = ServiceValidator.get(container, "DigService")
    CubePositionService = ServiceValidator.get(container, "CubePositionService")
    self._container = container
    log:info("Initialized")
end

function CubeManager:Start()
    -- Listen to player leaving to ensure cleanup mirrors DigService
    Players.PlayerRemoving:Connect(function(player)
        registry[player] = nil
    end)
    log:info("Started")
    -- Event-driven spawn/despawn
    local EventContracts = require(Shared:WaitForChild("EventContracts"))
    Bus:on(require(Shared:WaitForChild("EventNames")).CUBE_SPAWN_REQUEST, function(msg)
        local ok, payload = pcall(EventContracts.CUBE_SPAWN_REQUEST, msg.payload)
        if not ok then
            log:warn("Invalid CUBE_SPAWN_REQUEST payload")
            return
        end
        if payload.all then
            for _, plr in ipairs(Players:GetPlayers()) do self:SpawnForPlayer(plr) end
        elseif payload.player then
            self:SpawnForPlayer(payload.player)
        elseif payload.userId then
            local plr = Players:GetPlayerByUserId(payload.userId)
            if plr then self:SpawnForPlayer(plr) end
        end
    end)
    Bus:on(require(Shared:WaitForChild("EventNames")).CUBE_DESPAWN_REQUEST, function(msg)
        local ok, payload = pcall(EventContracts.CUBE_DESPAWN_REQUEST, msg.payload)
        if not ok then
            log:warn("Invalid CUBE_DESPAWN_REQUEST payload")
            return
        end
        if payload.all then
            for plr, _ in pairs(registry) do self:DespawnForPlayer(plr) end
        elseif payload.player then
            self:DespawnForPlayer(payload.player)
        elseif payload.userId then
            local plr = Players:GetPlayerByUserId(payload.userId)
            if plr then self:DespawnForPlayer(plr) end
        end
    end)
end

function CubeManager:Stop()
    if _phaseConn then pcall(function() _phaseConn:Disconnect() end) end
    _phaseConn = nil
    log:info("Stopped")
end

-- Public API
function CubeManager:SpawnForPlayer(player: Player)
    DigService:InitializePlayerCube(player)
    local id = string.format("cube:%d", player.UserId)
    local cube = DigService.playerCubes[player]
    registry[player] = { id = id, model = cube and cube.model or nil }
    log:debug("Spawned cube for %s id=%s", player.Name, id)
end

function CubeManager:DespawnForPlayer(player: Player)
    local rec = registry[player]
    if not rec then return end
    local cube = DigService.playerCubes[player]
    if cube and cube.model then
        cube.model:Destroy()
    end
    if rec.id then
        pcall(function() DigService:UnregisterVolume(rec.id) end)
    end
    DigService.playerCubes[player] = nil
    registry[player] = nil
    log:debug("Despawned cube for %s id=%s", player.Name, tostring(rec.id))
end

-- Enable phase-based cube visibility control
-- rule = { spawn = {"Dawn","Day"}, despawn = {"Dusk","Night"} }
function CubeManager:SetPhaseControl(rule: { spawn: {string}, despawn: {string} })
    local spawnSet, despawnSet = {}, {}
    for _, p in ipairs(rule.spawn or {}) do spawnSet[p] = true end
    for _, p in ipairs(rule.despawn or {}) do despawnSet[p] = true end
    phaseRule = { spawn = spawnSet, despawn = despawnSet }

    if _phaseConn then pcall(function() _phaseConn:Disconnect() end) end
    _phaseConn = RunService.Heartbeat:Connect(function()
        DigPerformance.measureSection("CM_Heartbeat", function()
            local phase = WorldGenUtils.getDayNightPhase()
            if phaseRule and phaseRule.spawn[phase] then
                for _, plr in ipairs(Players:GetPlayers()) do
                    if not registry[plr] then
                        self:SpawnForPlayer(plr)
                    end
                end
            elseif phaseRule and phaseRule.despawn[phase] then
                for plr, _ in pairs(registry) do
                    self:DespawnForPlayer(plr)
                end
            end
        end)
    end)
    log:info("Phase control enabled: spawn=%d, despawn=%d", (rule.spawn and #rule.spawn or 0), (rule.despawn and #rule.despawn or 0))
end

return CubeManager

