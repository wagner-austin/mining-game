--!strict
-- init.server.lua
-- Bootstrap script using new ServiceContainer architecture

-- NOTE:
-- Service boot is driven by ServiceManager + ServiceContainer.
-- The old ServicesManifest.lua is deprecated and has been removed.
-- To register/reorder services, edit server/MiningGame/ServiceManager.lua.
-- RFs are precreated/registered via RFRegistry after services start.
-- In Studio, use _G.MiningGameServices.container to inspect services.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Wait for shared modules
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame", 30)
local Logger = require(MiningGame:WaitForChild("Logger"))
local Time = require(MiningGame:WaitForChild("Time"))
local log = Logger.new("Bootstrap")

log:info("Starting MiningGame server initialization...")

-- Assert correct Rojo mapping
assert(MiningGame, "Missing ReplicatedStorage.MiningGame (check Rojo mapping)")

-- Step 1: Ensure ReplicatedStorage.MiningGame.Remotes folder exists
local remotesFolder = MiningGame:FindFirstChild("Remotes")
if not remotesFolder then
    remotesFolder = Instance.new("Folder")
    remotesFolder.Name = "Remotes"
    remotesFolder.Parent = MiningGame
end
log:info("Remotes folder ensured")

-- Ensure EventBus RemoteEvent exists early (RemoteEventBridge will use it)
if not remotesFolder:FindFirstChild("EventBus") then
    local eventBusRE = Instance.new("RemoteEvent")
    eventBusRE.Name = "EventBus"
    eventBusRE.Parent = remotesFolder
    log:info("EventBus RemoteEvent created")
end

-- Pre-create RemoteFunction instances (with temporary error handlers)
-- This prevents "Missing RemoteFunction" errors while services initialize
local RFRegistry = require(script.RFRegistry)
local precreateStats = RFRegistry.precreate(remotesFolder)
log:info("RF precreate complete: %d created, %d existed", precreateStats.created, precreateStats.existed)

-- Step 1.5: Configure EventBus before services start
local EventBus = require(MiningGame:WaitForChild("EventBus"))
-- DigPerformance lives as a sibling ModuleScript under this Script container
local DigPerformance = require(script:WaitForChild("DigPerformance"))
local GameConfig = require(MiningGame:WaitForChild("GameConfig"))
local Bus = EventBus.global()
local EventMetrics = require(script.EventMetrics)

-- Throttled drop logging to prevent spam during event floods
do
    local lastDropLog, dropCount = 0, 0
    Bus:configure({
        maxQueue = (GameConfig.Debug and GameConfig.Debug.EVENTBUS_MAX_QUEUE) or 1000,
        onDrop = function(evt, _, qlen)
            dropCount = dropCount + 1
            local now = Time.mono()
            if now - lastDropLog > 1 then -- Log at most once per second
                log:warn("[EventBus] Dropped %d events (last='%s') at queue length %d", dropCount, evt, qlen)
                lastDropLog = now
                dropCount = 0
            end
        end
    })
end
log:info("EventBus configured with maxQueue=%d", (GameConfig.Debug and GameConfig.Debug.EVENTBUS_MAX_QUEUE) or 1000)

-- Add lightweight metrics middleware to count events (server-side only)
Bus:use(function(ctx, next)
    pcall(function()
        EventMetrics.Inc(ctx.event)
    end)
    next()
end)

-- Step 2: Start services via the new container
local ServiceManager = require(script.ServiceManager)
local container = ServiceManager.start()

-- Export for Studio debugging (per doc)
if RunService:IsStudio() then
    _G.MiningGameServices = { container = container }
end

-- Step 3: Register RFs AFTER services are live
local rfStats = RFRegistry.register(container)  -- pass DI container
log:info("RF registration complete: %d registered, %d skipped", 
    rfStats.registeredCount, 
    rfStats.skippedCount)

-- Mark server as ready for clients
MiningGame:SetAttribute("ServerReady", true)
log:info("ServerReady attribute set")

-- Step 4: Bind cleanup on shutdown
game:BindToClose(function()
    log:info("Server shutting down...")
    pcall(function() container:stop() end)
    task.wait(1) -- Give services time to clean up
end)

-- Step 5: Report initialization complete
log:info("MiningGame server initialization complete!")
if RunService:IsStudio() then
    log:debug("Running in Studio mode - debug features enabled")
    log:debug("Access services via: _G.MiningGameServices.container:Get('ServiceName')")
end

-- Step 6: Heartbeat spike monitor
do
    local GameConfig = require(MiningGame:WaitForChild("GameConfig"))
    local hlog = Logger.new(Logger.CAT.Heartbeat)
    local THRESH = (GameConfig.Performance and GameConfig.Performance.HEARTBEAT_WARN_DT) or 0.066 -- ~15 FPS
    local startMono = Time.mono()
    RunService.Heartbeat:Connect(function(dt)
        -- Ignore early warm-up spikes for the first few seconds
        if (Time.mono() - startMono) < 5 then return end
        if dt > THRESH then
            hlog:warn("Heartbeat spike: dt=%.3f (threshold=%.3f)", dt, THRESH)
            -- Attach last-section timings to help diagnose spikes
            if DigPerformance and DigPerformance.getRecent then
                local recent = DigPerformance.getRecent(math.max(0.05, dt * 1.5))
                -- Pick a few key sections to report
                local keys = {
                    "PickVolume","SnapInside","SurfaceCheck","CellIteration",
                    "ReadVoxels","WriteVoxels","LootContextBuild","LootPickLoop",
                    "SpawnEntries","CreateDropModel","AC_Tick",
                    "IS_Rotations","IS_AutoCollector","IS_Sweeper",
                    "GS_Heartbeat","CM_Heartbeat","CSM_Heartbeat",
                    "RF_Invoke",
                    "PCG_Tree_Create","PCG_Rock_Create","PCG_Firefly_Create",
                    "PCG_EnsureBaseplate","PCG_Trees_Call","PCG_Rocks_Call","PCG_Flies_Call",
                    "PCG_Rock_Generate"
                }
                local parts = {}
                for _, k in ipairs(keys) do
                    local t = recent[k]
                    if t and (t.last or 0) > 0 then
                        table.insert(parts, string.format("%s=%.2fms", k, (t.last or 0)*1000))
                    end
                end
                if #parts > 0 then
                    local accountedMs = 0
                    for _, t in pairs(recent) do
                        accountedMs += ((t.last or 0) * 1000)
                    end
                    local unaccountedMs = math.max(0, (dt * 1000) - accountedMs)
                    hlog:warn("Spike context: %s | accounted=%.2fms, unaccounted=%.2fms", table.concat(parts, ", "), accountedMs, unaccountedMs)
                end
            end
        end
    end)
end
