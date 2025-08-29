--!strict
-- AmbientController.lua
-- Pluggable, efficient ambient system (client-owned)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local SoundManager = require(MiningGame:WaitForChild("SoundManager"))
local SoundConfig = require(MiningGame:WaitForChild("SoundConfig"))

local LocalPlayer = Players.LocalPlayer

type Target = { soundKey: string, volume: number, priority: number }
type Targets = { [string]: Target }
type Provider = { id: string, poll: () -> Targets }

local M = {}

-- Tunables
local MAX_CONCURRENT = 2
local MOVE_THRESHOLD = 8.0                     -- studs before recompute
local BASE_INTERVAL = 0.1                      -- Fast updates for volume changes
local SLOW_INTERVAL = 0.2                      -- Still fairly quick when idle
local RAY_DISTANCE = 48.0

-- State
local _enabled = false
local _providers: {Provider} = {}
local _active: {[string]: {sound: Sound, volume: number}} = {}
local _lastEar: Vector3? = nil
local _accum = 0.0
local _conn: RBXScriptConnection? = nil

-- Utils
local function earPos(): Vector3?
    local cam = workspace.CurrentCamera
    if cam then return cam.CFrame.Position end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
    return hrp and hrp.Position or nil
end

local function lerp(a: number, b: number, t: number): number
    return a + (b - a) * t
end

-- Merge targets from all providers: keep highest priority, then highest volume
local function mergeTargets(list: {Targets}): Targets
    local merged: Targets = {}
    for _, t in ipairs(list) do
        for key, v in pairs(t) do
            local cur = merged[key]
            if not cur or v.priority > cur.priority or (v.priority == cur.priority and v.volume > cur.volume) then
                merged[key] = v
            end
        end
    end
    return merged
end

-- Pick top-N by (priority, volume)
local function pickTopN(targets: Targets, n: number): Targets
    local arr = {}
    for _, v in pairs(targets) do table.insert(arr, v) end
    table.sort(arr, function(a, b)
        if a.priority ~= b.priority then return a.priority > b.priority end
        return a.volume > b.volume
    end)
    local out: Targets = {}
    for i = 1, math.min(n, #arr) do
        out[arr[i].soundKey] = arr[i]
    end
    return out
end

-- Apply targets: start/stop/fade volumes
local function applyTargets(targets: Targets)
    -- stop that are no longer needed
    for key, info in pairs(_active) do
        if not targets[key] then
            SoundManager.StopAmbient(key, false) -- fade out
            _active[key] = nil
        end
    end
    -- start/update those we need
    for key, t in pairs(targets) do
        local cur = _active[key]
        if not cur then
            local s = SoundManager.PlayAmbient(key, { volume = t.volume })
            if s then _active[key] = { sound = s, volume = t.volume } end
        else
            -- DIRECTLY update the sound volume each frame
            if cur.sound then
                -- Smooth lerp towards target volume
                cur.sound.Volume = lerp(cur.sound.Volume, t.volume, 0.25)
                cur.volume = cur.sound.Volume
            end
        end
    end
end

-- ===== Provider: Ambient Zones (designer-placed) =====
-- Parts tagged "AmbientZone" with attributes:
--   String  SoundKey     e.g., "waterflow", "lavaflow"
--   Number  Radius       default 40
--   Number  Priority     default 1
--   Number  BaseVolume   default 0.35
local ZonesProvider: Provider = { id = "zones", poll = function(): Targets
    local ear = earPos()
    if not ear then return {} end
    local targets: Targets = {}
    
    for _, p in ipairs(CollectionService:GetTagged("AmbientZone")) do
        local part = p :: BasePart
        if part:IsA("BasePart") and part:IsDescendantOf(workspace) then
            local key = part:GetAttribute("SoundKey")
            if typeof(key) == "string" and key ~= "" then
                -- Check time rules BEFORE calculating distance
                local shouldPlay, resolvedKey = SoundConfig.ShouldSoundPlay(key)
                
                if shouldPlay and resolvedKey then
                    local radius = tonumber(part:GetAttribute("Radius")) or 40
                    local priority = tonumber(part:GetAttribute("Priority")) or 1
                    local baseVol = tonumber(part:GetAttribute("BaseVolume")) or 0.35
                    local dp = ear - part.Position
                    local d2 = dp.X*dp.X + dp.Y*dp.Y + dp.Z*dp.Z
                    local r2 = radius * radius
                    
                    if d2 < r2 then
                        local dist = math.sqrt(d2)
                        -- More gradual falloff: at edge = 0.3x volume, at center = 1x volume
                        local falloff = 1 - (dist / radius) * 0.7  -- Only reduce by up to 70%
                        local vol = baseVol * falloff
                        if vol > 0.01 then
                            -- Use the resolved key (might be a variant)
                            -- Keep the best one if multiple zones resolve to same key
                            local prev = targets[resolvedKey]
                            if not prev 
                               or priority > prev.priority 
                               or (priority == prev.priority and vol > prev.volume) then
                                targets[resolvedKey] = { soundKey = resolvedKey, volume = vol, priority = priority }
                            end
                        end
                    end
                end
            end
        end
    end
    return targets
end }

-- ===== Provider: Terrain quick probe (cheap raycasts) =====
-- Looks for Water / CrackedLava / Ice nearby; outputs keys that match your SoundConfig:
--   waterflow, lavaflow, icecracking
local TerrainProvider: Provider = { id = "terrain", poll = function(): Targets
    local ear = earPos()
    if not ear then return {} end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    local char = LocalPlayer.Character
    if char then params.FilterDescendantsInstances = { char } end

    local headings = UserInputService.TouchEnabled and 6 or 8
    local closest: {[Enum.Material]: number} = {}
    for i=1, headings do
        local ang = (i-1) * (math.pi*2/ headings)
        local dir = Vector3.new(math.cos(ang), 0, math.sin(ang))
        local origin = ear + Vector3.new(0, 3, 0)
        local res = workspace:Raycast(origin, dir * RAY_DISTANCE, params)
        if res and res.Instance then
            local mat = res.Material
            if mat == Enum.Material.Water or mat == Enum.Material.CrackedLava or mat == Enum.Material.Ice then
                local d = (res.Position - ear).Magnitude
                local prev = closest[mat]
                if not prev or d < prev then closest[mat] = d end
            end
        end
    end

    local targets: Targets = {}
    for mat, dist in pairs(closest) do
        local key, base, priority =
            (mat == Enum.Material.Water and "waterflow" or
             mat == Enum.Material.CrackedLava and "lavaflow" or
             "icecracking"),
            (mat == Enum.Material.CrackedLava and 0.5 or mat == Enum.Material.Water and 0.4 or 0.3),
            (mat == Enum.Material.CrackedLava and 3 or mat == Enum.Material.Water and 2 or 1)

        local vol = math.clamp(1 - (dist / RAY_DISTANCE), 0, 1) * base
        if vol > 0.01 then
            targets[key] = { soundKey = key, volume = vol, priority = priority }
        end
    end
    return targets
end }

-- Public
function M.RegisterProvider(p: Provider)
    table.insert(_providers, p)
end

function M.SetEnabled(v: boolean)
    _enabled = v
end

function M.SetMaxConcurrent(n: number)
    MAX_CONCURRENT = math.max(1, n)
end

function M.Start()
    if _conn then return end
    -- ALWAYS ensure zone providers are registered
    local hasZones = false
    local hasTerrain = false
    for _, p in ipairs(_providers) do
        if p.id == "zones" then hasZones = true end
        if p.id == "terrain" then hasTerrain = true end
    end
    if not hasZones then
        M.RegisterProvider(ZonesProvider)
    end
    if not hasTerrain then
        M.RegisterProvider(TerrainProvider)
    end
    _enabled = true
    _accum = 0; _lastEar = earPos()

    _conn = RunService.Heartbeat:Connect(function(dt)
        if not _enabled then return end
        _accum += dt

        -- adaptive interval: recompute faster on movement, slower when idle
        local ear = earPos()
        local moved = false
        if ear and _lastEar then
            moved = (ear - _lastEar).Magnitude >= MOVE_THRESHOLD
        end
        local interval = moved and BASE_INTERVAL or SLOW_INTERVAL
        if _accum < interval then return end
        _accum = 0
        _lastEar = ear

        -- poll providers
        local lists = {}
        for i = 1, #_providers do
            lists[i] = _providers[i].poll() or {}
        end
        local merged = mergeTargets(lists)
        local top = pickTopN(merged, MAX_CONCURRENT)
        applyTargets(top)
    end)
end

function M.Stop()
    if _conn then _conn:Disconnect(); _conn = nil end
    for key in pairs(_active) do
        SoundManager.StopAmbient(key, true)
        _active[key] = nil
    end
    _enabled = false
end

return M