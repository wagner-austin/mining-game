--!strict
-- SpawnOrchestrator.lua
-- Encapsulates spawn readiness orchestration and finalization.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(MiningGame:WaitForChild("Logger"))
local log = Logger.new("SpawnOrchestrator")
local Time = require(MiningGame:WaitForChild("Time"))
local LoadCfg = require(MiningGame:WaitForChild("LoadingConstants"))
local GameConfig = require(MiningGame:WaitForChild("GameConfig"))
local WorldGenUtils = require(MiningGame:WaitForChild("WorldGenUtils"))
local ErrorService = require(script.Parent:WaitForChild("ErrorService"))
-- (no EventBus interactions needed here)

type SpawnState = {
    active: boolean,
    originReady: boolean,
    clientReady: boolean,
    pendingCF: CFrame?,
    anchoredAt: number,
    deadline: number,
    safetyPad: BasePart?,
}

local Orchestrator = {}

local state: {[Player]: SpawnState} = {}
local didFirstSpawn: {[Player]: boolean} = {}
local metrics = {
    enabled = true,
    active_flows = 0,

    success_count = 0,
    timeout_count = 0,
    safety_pad_count = 0,
    first_join_map_spawn_count = 0,
    duplicate_spawn_skipped_count = 0,

    hrp_missing_count = 0,
    anchor_fail_count = 0,
    unanchor_fail_count = 0,

    anchor_to_origin_ready_ms_sum = 0,
    anchor_to_origin_ready_count = 0,
    anchor_to_client_ready_ms_sum = 0,
    anchor_to_client_ready_count = 0,
    anchor_to_finalize_ms_sum = 0,
    anchor_to_finalize_count = 0,
}

local function isEnabled(): boolean
    local s = GameConfig.Spawn
    local en = (s == nil or s.ORCHESTRATED ~= false)
    metrics.enabled = en
    return en
end

local function yForPosXZ(pos: Vector3): number
    -- Prefer shared utility (DRY)
    local p = WorldGenUtils.findGroundPosition(pos.X, pos.Z, { allowWater = false })
    if p then return (p :: Vector3).Y + 3 end
    local c = WorldGenUtils.getSpawnBounds()
    if typeof(c) == "Vector3" then return c.Y + 3 end
    return 5
end

local function tryFinalize(player: Player)
    local st = state[player]
    if not st or not st.active then return end
    local now = Time.mono()
    local timedOut = now >= st.deadline

    if not st.pendingCF and st.originReady then
        -- Defensive only; pendingCF should be set by caller
        return
    end

    if (st.originReady and st.clientReady) or timedOut then
        local cf = st.pendingCF
        if not cf then
            -- Should not happen; synthesize a minimal CF
            local center = WorldGenUtils.getSpawnBounds()
            local pos = typeof(center) == "Vector3" and center or Vector3.new(0, 10, 0)
            cf = CFrame.new(pos)
        end

        -- Optional: spawn at map bounds on first join instead of cube
        if (GameConfig.Spawn and GameConfig.Spawn.SPAWN_AT_MAP_ON_FIRST_JOIN) and not didFirstSpawn[player] then
            local center = WorldGenUtils.getSpawnBounds()
            local pos = typeof(center) == "Vector3" and center or Vector3.new(0, 10, 0)
            cf = CFrame.new(pos.X, yForPosXZ(pos), pos.Z)
            metrics.first_join_map_spawn_count += 1
        end

        local char = player.Character
        if not char then metrics.hrp_missing_count += 1; return end
        local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
        if not hrp then metrics.hrp_missing_count += 1; return end

        -- Optional safety pad if timed out (client didn’t report ready)
        if timedOut then
            local pad = Instance.new("Part")
            pad.Name = string.format("SpawnSafetyPad_%d", player.UserId)
            pad.Anchored = true
            pad.CanCollide = true
            pad.Transparency = 1
            pad.Size = Vector3.new(6, 1, 6)
            pad.CFrame = CFrame.new(cf.Position.X, yForPosXZ(cf.Position), cf.Position.Z)
            pad.Parent = Workspace
            st.safetyPad = pad
            metrics.safety_pad_count += 1
            -- Cleanup later
            local ttl = (GameConfig.Spawn and GameConfig.Spawn.SAFETY_PAD_DURATION) or 12
            task.delay(ttl, function()
                local st2 = state[player]
                if st2 and st2.safetyPad then
                    ErrorService.safecall("SpawnOrchestrator.PadDestroy", function()
                        st2.safetyPad:Destroy()
                    end)
                    st2.safetyPad = nil
                end
            end)
            -- Continue to finalize normally below (unanchor), relying on safety pad + spawn clearance
        end

        hrp.CFrame = cf
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if humanoid then humanoid:Move(Vector3.zero, true) end
        local okUnanchor = ErrorService.safecall("SpawnOrchestrator.UnanchorFinalize", function()
            hrp.Anchored = false
        end)
        if not okUnanchor then metrics.unanchor_fail_count += 1 end

        log:info("Finalize spawn for %s (timedOut=%s)", player.Name, tostring(timedOut))
        didFirstSpawn[player] = true
        if timedOut then metrics.timeout_count += 1 else metrics.success_count += 1 end

        -- Reset
        st.active = false
        st.originReady = false
        st.clientReady = false
        st.pendingCF = nil
        metrics.anchor_to_finalize_ms_sum += ((Time.mono() - st.anchoredAt) * 1000)
        metrics.anchor_to_finalize_count += 1
        metrics.active_flows = math.max(0, metrics.active_flows - 1)
    end
end

function Orchestrator.IsEnabled(): boolean
    return isEnabled()
end

function Orchestrator.IsActive(player: Player): boolean
    local st = state[player]
    return st ~= nil and st.active == true
end

function Orchestrator.StartForCharacter(player: Player, hrp: BasePart)
    if not isEnabled() then return end
    local st = state[player] or {
        active = true,
        originReady = false,
        clientReady = false,
        pendingCF = nil,
        anchoredAt = Time.mono(),
        deadline = Time.mono() + LoadCfg.TIMEOUTS.SpawnFinalize,
        safetyPad = nil,
    }
    st.active = true
    st.originReady = false
    st.clientReady = false
    st.pendingCF = nil
    st.anchoredAt = Time.mono()
    st.deadline = st.anchoredAt + LoadCfg.TIMEOUTS.SpawnFinalize
    state[player] = st
    local okAnchor = ErrorService.safecall("SpawnOrchestrator.AnchorOnJoin", function()
        hrp.Anchored = true
    end)
    if not okAnchor then metrics.anchor_fail_count += 1 end
    metrics.active_flows += 1
end

function Orchestrator.OnOriginReady(player: Player, cf: CFrame)
    if not isEnabled() then return end
    local st = state[player]
    if not st then return end
    st.pendingCF = cf
    st.originReady = true
    metrics.anchor_to_origin_ready_ms_sum += ((Time.mono() - st.anchoredAt) * 1000)
    metrics.anchor_to_origin_ready_count += 1
    tryFinalize(player)
end

function Orchestrator.MarkClientReady(player: Player)
    if not isEnabled() then return end
    local st = state[player]
    if not st then return end
    st.clientReady = true
    metrics.anchor_to_client_ready_ms_sum += ((Time.mono() - st.anchoredAt) * 1000)
    metrics.anchor_to_client_ready_count += 1
    tryFinalize(player)
end

function Orchestrator.Cleanup(player: Player)
    local st = state[player]
    if not st then return end
    if st.active then
        metrics.active_flows = math.max(0, metrics.active_flows - 1)
    end
    if st.safetyPad then
        ErrorService.safecall("SpawnOrchestrator.PadDestroy", function()
            st.safetyPad:Destroy()
        end)
    end
    state[player] = nil
    didFirstSpawn[player] = nil
end

function Orchestrator.IncDuplicateSkipped()
    metrics.duplicate_spawn_skipped_count += 1
end

local function avg(sum: number, count: number): number
    if count <= 0 then return 0 end
    return sum / count
end

function Orchestrator.GetMetrics(): {[string]: any}
    return {
        enabled = metrics.enabled,
        active_flows = metrics.active_flows,

        success_count = metrics.success_count,
        timeout_count = metrics.timeout_count,
        safety_pad_count = metrics.safety_pad_count,
        first_join_map_spawn_count = metrics.first_join_map_spawn_count,
        duplicate_spawn_skipped_count = metrics.duplicate_spawn_skipped_count,

        hrp_missing_count = metrics.hrp_missing_count,
        anchor_fail_count = metrics.anchor_fail_count,
        unanchor_fail_count = metrics.unanchor_fail_count,

        anchor_to_origin_ready_ms_avg = avg(metrics.anchor_to_origin_ready_ms_sum, metrics.anchor_to_origin_ready_count),
        anchor_to_client_ready_ms_avg = avg(metrics.anchor_to_client_ready_ms_sum, metrics.anchor_to_client_ready_count),
        anchor_to_finalize_ms_avg = avg(metrics.anchor_to_finalize_ms_sum, metrics.anchor_to_finalize_count),
    }
end

return Orchestrator
