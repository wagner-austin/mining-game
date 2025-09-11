--!strict
-- ServiceContainer.lua
-- Dependency-aware lifecycle: :register() -> :build() -> :start() -> :stop() and :Get()
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Time = require(Shared:WaitForChild("Time"))
local Logger = require(Shared:WaitForChild("Logger"))
local Timeout = require(Shared:WaitForChild("Timeout"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local slog = Logger.new(Logger.CAT.ServiceContainer)

-- Optional config (from GameConfig.Debug if available, else defaults)
local WARN_INIT_SEC  = (GameConfig.Debug and GameConfig.Debug.WARN_INIT_SEC) or 0.25
local WARN_START_SEC = (GameConfig.Debug and GameConfig.Debug.WARN_START_SEC) or 0.25
local TIMEOUT_INIT   = (GameConfig.Debug and GameConfig.Debug.TIMEOUT_INIT) or 0  -- 0 = disabled
local TIMEOUT_START  = (GameConfig.Debug and GameConfig.Debug.TIMEOUT_START) or 0
local POLL_INTERVAL  = 0  -- 0 = yield until next frame

export type ServiceRec = {
    name: string,
    mod: any,
    deps: {string},
    inst: any?,
    _idx: number, -- registration order for stable topo
}

local ServiceContainer = {}
ServiceContainer.__index = ServiceContainer

-- Health tracking
local health = { init = {}, start = {}, stop = {} }

function ServiceContainer.new()
    return setmetatable({
        _services = {} :: {[string]: ServiceRec},
        _regCount = 0,
        _order = nil :: {ServiceRec}?,
        _stopped = false,
    }, ServiceContainer)
end

function ServiceContainer:register(name: string, mod: any, deps: {string}?): ServiceContainer
    assert(type(name) == "string" and name ~= "", "Service name required")
    assert(mod ~= nil, ("Service '%s' module is nil"):format(name))
    assert(self._services[name] == nil, ("Service '%s' already registered"):format(name))
    self._regCount = self._regCount + 1
    self._services[name] = { name = name, mod = mod, deps = deps or {}, inst = nil, _idx = self._regCount }
    return self
end

local function topoSort(services: {[string]: ServiceRec}): {ServiceRec}
    local indeg: {[string]: number} = {}
    local adj: {[string]: {string}} = {}
    for n,_ in pairs(services) do indeg[n] = 0 end
    for n,rec in pairs(services) do
        for _,d in ipairs(rec.deps) do
            assert(services[d], ("Service '%s' depends on unknown '%s'"):format(n, d))
            indeg[n] = (indeg[n] or 0) + 1
            adj[d] = adj[d] or {}
            table.insert(adj[d], n)
        end
    end

    -- use stable tie-break by registration order, then name
    local function byStable(a: string, b: string)
        local ra, rb = services[a], services[b]
        if ra._idx ~= rb._idx then return ra._idx < rb._idx end
        return a < b
    end

    local q: {string} = {}
    for n,k in pairs(indeg) do if k == 0 then table.insert(q, n) end end
    table.sort(q, byStable)

    local out: {ServiceRec} = {}
    while #q > 0 do
        local n = table.remove(q, 1)
        table.insert(out, services[n])
        for _,m in ipairs(adj[n] or {}) do
            indeg[m] = (indeg[m] or 0) - 1
            if indeg[m] == 0 then
                table.insert(q, m)
                table.sort(q, byStable)
            end
        end
    end

    -- cycle check
    local unresolved = {}
    for name,k in pairs(indeg) do if k and k > 0 then table.insert(unresolved, name) end end
    if #unresolved > 0 then
        table.sort(unresolved) -- stable error messages
        error("Cyclic service dependency detected: "..table.concat(unresolved, ", "))
    end

    return out
end

function ServiceContainer:build()
    assert(self._order == nil, "ServiceContainer already built")
    local order = topoSort(self._services)
    self._order = order
    for _,rec in ipairs(order) do
        rec.inst = rec.mod
        if type(rec.inst.Init) == "function" then
            local t0 = Time.mono()
            local ok, resOrErr
            if TIMEOUT_INIT and TIMEOUT_INIT > 0 then
                ok, resOrErr = Timeout.run(function()
                    rec.inst:Init(self)
                end, TIMEOUT_INIT, POLL_INTERVAL)
                if not ok and resOrErr == "TIMEOUT" then
                    error(("[ServiceContainer] %s.Init exceeded soft timeout (%.2fs)"):format(rec.name, TIMEOUT_INIT))
                end
            else
                ok, resOrErr = pcall(function() rec.inst:Init(self) end)
            end
            local dt = Time.mono() - t0
            if dt > WARN_INIT_SEC then
                slog:warn("Slow Init (%.3fs): %s", dt, rec.name)
            end
            if not ok then
                error(("[ServiceContainer] %s.Init failed: %s"):format(rec.name, tostring(resOrErr)))
            end
            health.init[rec.name] = "ok"
        else
            health.init[rec.name] = "n/a"
        end
    end
    
    if RunService:IsStudio() then
        local names = {}
        for i, r in ipairs(self._order :: {ServiceRec}) do names[i] = r.name end
        print("[ServiceContainer] Init order: " .. table.concat(names, ", "))
    end
end

function ServiceContainer:start()
    local order = assert(self._order, "Call :build() before :start()")
    for _, rec in ipairs(order) do
        if type(rec.inst.Start) == "function" then
            local t0 = Time.mono()
            local ok, resOrErr
            if TIMEOUT_START and TIMEOUT_START > 0 then
                ok, resOrErr = Timeout.run(function()
                    rec.inst:Start(self)
                end, TIMEOUT_START, POLL_INTERVAL)
                if not ok and resOrErr == "TIMEOUT" then
                    error(("[ServiceContainer] %s.Start exceeded soft timeout (%.2fs)"):format(rec.name, TIMEOUT_START))
                end
            else
                ok, resOrErr = pcall(function() rec.inst:Start(self) end)
            end
            local dt = Time.mono() - t0
            if dt > WARN_START_SEC then
                slog:warn("Slow Start (%.3fs): %s", dt, rec.name)
            end
            if not ok then
                error(("[ServiceContainer] %s.Start failed: %s"):format(rec.name, tostring(resOrErr)))
            end
            health.start[rec.name] = "ok"
        else
            health.start[rec.name] = "n/a"
        end
    end
    
    if RunService:IsStudio() then
        print("[ServiceContainer] Started")
        -- Pretty print in Studio
        for _, rec in ipairs(order) do
            print(("[ServiceContainer] %s -> init=%s start=%s")
                :format(rec.name, tostring(health.init[rec.name] or "n/a"), tostring(health.start[rec.name] or "n/a")))
        end
    else
        -- Log in production with Logger for searchable health
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local Shared = ReplicatedStorage:WaitForChild("MiningGame")
        local Logger = require(Shared:WaitForChild("Logger"))
        local slog = Logger.new(Logger.CAT.ServiceContainer)
        slog:info("Service health summary (init/start):")
        for _, rec in ipairs(order) do
            slog:info("  %s -> init=%s start=%s",
                rec.name, tostring(health.init[rec.name] or "n/a"), tostring(health.start[rec.name] or "n/a"))
        end
    end
end

function ServiceContainer:stop()
    if self._stopped then return end
    if not self._order then return end
    for i = #self._order, 1, -1 do
        local rec = (self._order :: {ServiceRec})[i]
        if rec.inst and type(rec.inst.Stop) == "function" then
            local ok, err = pcall(function() rec.inst:Stop() end)
            if not ok and RunService:IsStudio() then
                warn(("[ServiceContainer] Stop '%s' error: %s"):format(rec.name, tostring(err)))
            end
        end
    end
    self._stopped = true
end

function ServiceContainer:Get(name: string): any
    local rec = self._services[name]
    assert(rec and rec.inst, ("Service '%s' not available"):format(name))
    return rec.inst
end

function ServiceContainer:tryGet(name: string): any?
    local rec = self._services[name]
    return rec and rec.inst or nil
end

return ServiceContainer