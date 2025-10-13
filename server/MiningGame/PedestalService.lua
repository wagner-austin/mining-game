--!strict
-- PedestalService.lua
-- Spawns a themed Respawn pedestal at each player's base using normalized placement.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(MiningGame:WaitForChild("Logger"))
local EventBus = require(MiningGame:WaitForChild("EventBus"))
local EventNames = require(MiningGame:WaitForChild("EventNames"))
local ErrorService = require(script.Parent:WaitForChild("ErrorService"))
local BasePlacement = require(script.Parent:WaitForChild("BasePlacement"))
local ServiceValidator = require(MiningGame:WaitForChild("ServiceValidator"))
local GameConfig = require(MiningGame:WaitForChild("GameConfig"))

local ServerScriptService = game:GetService("ServerScriptService")
local BannerConfig = require(ServerScriptService:WaitForChild("Cloth"):WaitForChild("BannerConfig"))

local log = Logger.new("PedestalService")
local Bus = EventBus.global()

local PedestalService = {}
PedestalService.__index = PedestalService

-- Track spawned pedestals per player for cleanup
local spawned: {[Player]: Model} = {}
local vfxByModel: {[Model]: {origin: CFrame, start: number}} = {}
local hbConn: RBXScriptConnection? = nil

-- Cache Time module once; avoid requiring inside Heartbeat loop
local TimeMod = require(ReplicatedStorage:WaitForChild("MiningGame"):WaitForChild("Time"))

local function ensureVFXHeartbeat()
    if hbConn then return end
    hbConn = RunService.Heartbeat:Connect(function()
        if next(vfxByModel) == nil then
            if hbConn then hbConn:Disconnect(); hbConn = nil end
            return
        end
        local now = TimeMod.mono()
        -- Lightweight pedestal motion (faster spin, deeper bob)
        local spinSpeed = math.rad(30) -- ~30 deg/sec
        local bobAmp = 0.75            -- studs
        local bobHz = 0.5              -- 0.5 Hz
        local twoPi = 2*math.pi
        for model, rec in pairs(vfxByModel) do
            if model and model.Parent then
                local elapsed = now - rec.start
                local bob = math.sin(elapsed * twoPi * bobHz) * bobAmp
                local yaw = elapsed * spinSpeed
                local target = rec.origin * CFrame.new(0, bob, 0) * CFrame.Angles(0, yaw, 0)
                model:PivotTo(target)
            else
                vfxByModel[model] = nil
            end
        end
    end)
end

local function getBasesFolder(): Folder
    local f = workspace:FindFirstChild("PlayerBases")
    if not f then
        f = Instance.new("Folder")
        f.Name = "PlayerBases"
        f.Parent = workspace
    end
    return f
end

local function ensureParent(baseModel: Model): Instance
    -- Parent pedestal under the player's base model for streaming locality
    return baseModel
end

-- Compute current mined fraction for a player's cube (0..1)
function PedestalService:_getMinedFrac(player: Player): number
    local DS = self._DataService
    local GS = self._GridService
    if not DS or not GS then return 0 end
    local state = DS:GetCubeData(player)
    if not state then return 0 end
    local stats = GS:GetChunkStats(state)
    local ext = state.extentsCells
    local cell = GameConfig.Grid.CELL_SIZE_STUDS
    local total
    if ext and typeof(ext) == "Vector3" then
        total = math.max(1, (ext.X*2) * (ext.Y*2) * (ext.Z*2))
    else
        local perSide = math.floor(GameConfig.Grid.CUBE_SIZE_STUDS / cell)
        total = math.max(1, perSide * perSide * perSide)
    end
    local dug = math.max(0, stats.dugCells or 0)
    return math.clamp(dug / total, 0, 1)
end

-- Returns true if manual reset is currently usable for this player
function PedestalService:_isUsable(player: Player): boolean
    local minFrac = (GameConfig.Reset and GameConfig.Reset.MANUAL_RESET_MIN_MINED_FRAC) or 0.05
    local frac = self:_getMinedFrac(player)
    return frac >= minFrac
end

local function _getBaseModelFor(player: Player): Model?
    local bases = workspace:FindFirstChild("PlayerBases")
    if not bases then return nil end
    local m = bases:FindFirstChild("PlayerBase_" .. tostring(player.UserId))
    return (m and m:IsA("Model")) and m or nil
end

-- Ensure pedestal presence matches usability state
function PedestalService:_updateFor(player: Player)
    local baseModel = _getBaseModelFor(player)
    if not baseModel then return end
    local usable = self:_isUsable(player)
    local existing = spawned[player]
    if usable then
        if not existing or not existing.Parent then
            ErrorService.safecall("Pedestal.SpawnIfUsable", function()
                self:_spawnFor(player, baseModel)
            end)
        end
    else
        if existing then
            ErrorService.safecall("Pedestal.DestroyNotUsable", function()
                existing:Destroy()
            end)
            spawned[player] = nil
            -- Emit PEDESTAL_REMOVED so client can clean up billboard
            pcall(function()
                Bus:emit(EventNames.PEDESTAL_REMOVED, { to = { kind = "player", player = player }, payload = { pedestalName = existing.Name } })
            end)
        end
    end
end

function PedestalService:_spawnFor(player: Player, baseModel: Model)
    -- Cleanup any previous
    local prev = spawned[player]
    if prev then
        ErrorService.safecall("Pedestal.DestroyPrev", function()
            prev:Destroy()
        end)
    end

    -- Gate by usability: only spawn when manual reset is available
    if not self:_isUsable(player) then
        log:info("Pedestal not usable yet for %s; skipping spawn", player.Name)
        spawned[player] = nil
        return
    end

    local tune = BannerConfig.get()
    local pedCfg = (tune :: any).PEDESTAL
    if type(pedCfg) ~= "table" then
        log:warn("PEDESTAL config missing; skipping for %s", player.Name)
        return
    end
    if type(pedCfg.alongZT) ~= "number" or type(pedCfg.inwardXT) ~= "number" or type(pedCfg.insideZ) ~= "number" then
        log:warn("PEDESTAL config invalid; skipping for %s", player.Name)
        return
    end

    local flat, baseY = BasePlacement.compute(baseModel, {
        alongZT = pedCfg.alongZT,
        inwardXT = pedCfg.inwardXT,
        insideZ = pedCfg.insideZ,
    })
    if not flat or not baseY then
        log:warn("BasePlacement failed for pedestal; skipping for %s", player.Name)
        return
    end
    -- Compute base-local axes using anchors to avoid world-axis ambiguity
    local hs = baseModel:FindFirstChild("HighScoreAnchor_Anchor") :: BasePart?
    local shop = baseModel:FindFirstChild("ShopAnchor_Anchor") :: BasePart?
    local pets = baseModel:FindFirstChild("PetsAnchor_Anchor") :: BasePart?
    if not (hs and shop and pets) then
        log:warn("Missing base anchors for basis; skipping pedestal for %s", player.Name)
        return
    end
    local rVec = (shop.Position - hs.Position); rVec = Vector3.new(rVec.X, 0, rVec.Z)
    local zVec = (pets.Position - hs.Position); zVec = Vector3.new(zVec.X, 0, zVec.Z)
    if rVec.Magnitude < 1 or zVec.Magnitude < 1 then
        log:warn("Degenerate base vectors; skipping pedestal for %s", player.Name)
        return
    end
    rVec = rVec.Unit
    zVec = zVec.Unit
    -- Read offsets (support both new offsetX/offsetZ and older offsetRight/offsetAlong)
    local offRight = (type(pedCfg.offsetX) == "number") and pedCfg.offsetX
        or ((type(pedCfg.offsetRight) == "number") and pedCfg.offsetRight or 0)
    local offAlong = (type(pedCfg.offsetZ) == "number") and pedCfg.offsetZ
        or ((type(pedCfg.offsetAlong) == "number") and pedCfg.offsetAlong or 0)
    local posVec = Vector3.new(flat.X, 0, flat.Z) + rVec * offRight + zVec * offAlong
    local posX, posZ = posVec.X, posVec.Z
    log:info("Pedestal placement for %s flat=(%.1f, %.1f, %.1f) baseY=%.1f offsets=(X=%.1f, Z=%.1f) -> pos=(%.1f, %.1f)", player.Name, flat.X, flat.Y, flat.Z, baseY, offRight, offAlong, posX, posZ)

    local color = BannerConfig.getAccentColor(tonumber(pedCfg.colorSlotIndex))

    -- Compute terrain ground Y at this XZ to ensure pedestal bottom rests on visible ground
    local function sampleGroundY(x: number, z: number, fallback: number): number
        local origin = Vector3.new(x, (fallback or 0) + 1000, z)
        local direction = Vector3.new(0, -5000, 0)
        local params = RaycastParams.new()
        -- Only consider Terrain to avoid hitting trees/props
        params.FilterType = Enum.RaycastFilterType.Include
        params.FilterDescendantsInstances = { workspace.Terrain }
        local result = workspace:Raycast(origin, direction, params)
        if result and result.Position then
            return result.Position.Y
        end
        return fallback
    end
    local groundY = sampleGroundY(posX, posZ, baseY)
    log:info("Pedestal groundY sample for %s at XZ=(%.1f, %.1f): groundY=%.2f baseY=%.2f", player.Name, posX, posZ, groundY, baseY)

    local m = Instance.new("Model")
    m.Name = string.format("RespawnPedestal_%d", player.UserId)
    m.Parent = ensureParent(baseModel)

    local base = Instance.new("Part")
    base.Name = "PedestalBase"
    base.Anchored = true
    base.CanCollide = true
    base.Size = Vector3.new(5, 6, 5)
    base.Material = Enum.Material.Glass
    base.Transparency = 0.6
    base.Reflectance = 0.08
    base.Color = color
    -- Place pedestal on sampled ground (or base floor if sampling failed)
    local bottomY = groundY + 2.0
    local centerY = bottomY + (base.Size.Y * 0.5)
    base.CFrame = CFrame.new(Vector3.new(posX, centerY, posZ))
    base.Parent = m

    -- Set PrimaryPart for client helpers to resolve position reliably
    m.PrimaryPart = base

    -- Optional top plate for contrast
    local top = Instance.new("Part")
    top.Name = "PedestalTop"
    top.Anchored = true
    top.CanCollide = true
    top.Size = Vector3.new(4.5, 0.4, 4.5)
    top.Material = Enum.Material.Glass
    top.Transparency = 0.6
    top.Reflectance = 0.08
    top.Color = color
    top.CFrame = base.CFrame * CFrame.new(0, (base.Size.Y * 0.5) + (top.Size.Y * 0.5), 0)
    top.Parent = m

    -- Add a small point light for visibility
    local light = Instance.new("PointLight")
    light.Brightness = 2
    light.Range = 18
    light.Color = color
    light.Parent = base

    -- Optional GlowBar accent that auto-themes with MaterialManager
    do
        local GBS = self._GlowBarService
        if GBS and type(GBS.CreateRectAtY) == "function" then
            local rectSize = Vector3.new(7.5, 0, 7.5)
            -- Evenly distribute rings along pedestal height with a small margin
            local halfH = base.Size.Y * 0.5
            local baseBottom = centerY - halfH
            local baseTop = centerY + halfH
            local margin = math.min(0.6, math.max(0, halfH - 0.1))
            local usable = math.max(0, (baseTop - baseBottom) - (2 * margin))
            local glowY1 = baseBottom + margin
            local glowYMid = baseBottom + margin + (usable * 0.5)
            local glowY2 = baseBottom + margin + usable

            ErrorService.safecall("Pedestal.GlowBarLower", function()
                GBS.CreateRectAtY(m, Vector3.new(posX, glowY1, posZ), rectSize, glowY1, { name = "PedestalGlowLower", width = 1.2, thickness = 0.4 })
            end)
            ErrorService.safecall("Pedestal.GlowBarMiddle", function()
                GBS.CreateRectAtY(m, Vector3.new(posX, glowYMid, posZ), rectSize, glowYMid, { name = "PedestalGlowMiddle", width = 1.2, thickness = 0.4 })
            end)
            ErrorService.safecall("Pedestal.GlowBarUpper", function()
                GBS.CreateRectAtY(m, Vector3.new(posX, glowY2, posZ), rectSize, glowY2, { name = "PedestalGlowUpper", width = 1.2, thickness = 0.4 })
            end)
        end
    end

    spawned[player] = m
    -- Capture origin for server-driven lightweight motion
    local ok, origin = pcall(function() return m:GetPivot() end)
    if ok and typeof(origin) == "CFrame" then
        vfxByModel[m] = { origin = origin, start = TimeMod.mono() }
        ensureVFXHeartbeat()
    end
    log:info("Spawned RespawnPedestal for %s at (%.1f, %.1f, %.1f)", player.Name, flat.X, baseY, flat.Z)

    -- Emit PEDESTAL_READY event so client can attach billboard
    -- Emit multiple times with delays to handle replication/streaming (same pattern as BannerService)
    ErrorService.safecall("Pedestal.EmitReady", function()
        local target = { kind = "player", player = player }
        local payload = { pedestal = m }
        Bus:emit(EventNames.PEDESTAL_READY, { to = target, payload = payload })
        task.delay(1.0, function()
            Bus:emit(EventNames.PEDESTAL_READY, { to = target, payload = payload })
        end)
        task.delay(2.0, function()
            Bus:emit(EventNames.PEDESTAL_READY, { to = target, payload = payload })
        end)
    end)
end

function PedestalService:Init(container)
    -- Optional: theme-driven glow service
    self._GlowBarService = ServiceValidator.tryGet(container, "GlowBarService", {"CreateRectAtY"})
    -- Services used for gating
    self._DataService = ServiceValidator.tryGet(container, "DataService", {"GetCubeData"})
    self._GridService = ServiceValidator.tryGet(container, "GridService", {"GetChunkStats"})
    log:info("Initialized")
end

function PedestalService:Start(container)
    -- Cleanup on leave
    Players.PlayerRemoving:Connect(function(p)
        local m = spawned[p]
        spawned[p] = nil
        if m then
            local pedestalName = m.Name
            ErrorService.safecall("Pedestal.DestroyOnLeave", function()
                m:Destroy()
            end)
            vfxByModel[m] = nil
            -- Emit PEDESTAL_REMOVED (though player is leaving, good for cleanup)
            pcall(function()
                Bus:emit(EventNames.PEDESTAL_REMOVED, { to = { kind = "player", player = p }, payload = { pedestalName = pedestalName } })
            end)
        end
    end)

    -- Spawn when base is ready
    Bus:on(EventNames.PLAYER_BASE_READY, function(evt)
        local to = evt and evt.to
        local player = to and to.player
        local payload = evt and evt.payload
        local baseModel = payload and payload.baseModel
        if player and player.Parent and baseModel and baseModel:IsA("Model") then
            log:info("PLAYER_BASE_READY for %s; updating pedestal visibility", player.Name)
            self:_updateFor(player)
        end
    end)

    -- Update visibility on each dig feedback (per player)
    Bus:on(EventNames.DIG_FEEDBACK, function(evt)
        local to = evt and evt.to
        local player = to and to.player
        if player and player.Parent then
            self:_updateFor(player)
        end
    end)

    -- After cube resets (re-initialize), re-evaluate visibility
    Bus:on(EventNames.CUBE_ORIGIN_CHANGED, function(evt)
        local to = evt and evt.to
        local player = to and to.player
        if player and player.Parent then
            self:_updateFor(player)
        end
    end)

    -- Handle bases that already exist (Studio hot reload)
    local basesFolder = workspace:FindFirstChild("PlayerBases")
    if basesFolder then
        for _, m in ipairs(basesFolder:GetChildren()) do
            if m:IsA("Model") then
                local uid = m.Name:match("PlayerBase_(%d+)")
                local userId = uid and tonumber(uid) or nil
                local player = userId and Players:GetPlayerByUserId(userId) or nil
                if player then
                    self:_updateFor(player)
                end
            end
        end
    end

    log:info("Started")
end

return PedestalService
