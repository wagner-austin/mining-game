--!strict
-- ServiceManager.lua
-- Dependency-aware service bootstrap with init/start/stop phases.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(MiningGame:WaitForChild("Logger"))
local log = Logger.new("ServiceManager")

local ServiceManager = {}
ServiceManager.__index = ServiceManager

export type ServiceSpec = {
    name: string,
    module: ModuleScript,
    deps: {string}?,
    priority: number?, -- lower runs earlier when order ties
}

export type LoadedService = {
    Name: string,
    Deps: {string}?,
    Init: ((self: any, ctx: any) -> ())?,
    Start: ((self: any) -> ())?,
    Stop: ((self: any) -> ())?,
}

local function topoSort(specs: {ServiceSpec}): {ServiceSpec}
    local incoming: {[string]: number} = {}
    local byName: {[string]: ServiceSpec} = {}
    local adj: {[string]: {string}} = {}

    -- Build dependency graph
    for _, s in ipairs(specs) do
        -- Check for duplicate names
        if byName[s.name] then 
            error(("[ServiceManager] Duplicate service: %s"):format(s.name))
        end
        byName[s.name] = s
        incoming[s.name] = 0
    end
    
    -- Validate dependencies exist and build adjacency
    for _, s in ipairs(specs) do
        for _, d in ipairs(s.deps or {}) do
            if not byName[d] then
                error(("[ServiceManager] '%s' depends on missing service '%s'"):format(s.name, d))
            end
            adj[d] = adj[d] or {}
            table.insert(adj[d], s.name)
            incoming[s.name] = (incoming[s.name] or 0) + 1
        end
    end

    -- Find roots (no incoming edges)
    local heap = {} :: {ServiceSpec}
    for _, s in ipairs(specs) do
        if incoming[s.name] == 0 then 
            table.insert(heap, s) 
        end
    end
    
    -- Sort roots by priority
    table.sort(heap, function(a, b)
        local pa = a.priority or 0
        local pb = b.priority or 0
        return pa < pb or (pa == pb and a.name < b.name)
    end)

    -- Process nodes
    local order = {}
    while #heap > 0 do
        local s = table.remove(heap, 1)
        table.insert(order, s)
        
        -- Process dependents
        for _, nxt in ipairs(adj[s.name] or {}) do
            incoming[nxt] = (incoming[nxt] or 0) - 1
            if incoming[nxt] == 0 then
                table.insert(heap, byName[nxt])
                -- Re-sort heap by priority
                table.sort(heap, function(a, b)
                    local pa = a.priority or 0
                    local pb = b.priority or 0
                    return pa < pb or (pa == pb and a.name < b.name)
                end)
            end
        end
    end

    -- Check for cycles
    if #order ~= #specs then
        local unresolved = {}
        for name, count in pairs(incoming) do
            if count > 0 then
                table.insert(unresolved, name)
            end
        end
        error(("[ServiceManager] Cycle or missing deps; unresolved: %s"):format(
            table.concat(unresolved, ", ")
        ))
    end
    
    return order
end

function ServiceManager.bootstrap(manifest: {ServiceSpec})
    log:info("Starting bootstrap...")
    
    -- 1) Require modules
    local loaded: {[string]: any} = {}
    for _, spec in ipairs(manifest) do
        log:debug("Loading %s...", spec.name)
        
        local ok, module = pcall(require, spec.module)
        if not ok then
            error(("[ServiceManager] Failed to require %s: %s"):format(spec.name, tostring(module)))
        end
        
        -- Check if module follows new pattern (has Init/Start/Stop)
        if type(module) == "table" and (module.Init or module.Start or module.Stop) then
            loaded[spec.name] = {
                Name = spec.name,
                Deps = spec.deps,
                Init = module.Init,
                Start = module.Start,
                Stop = module.Stop,
                _module = module, -- Keep reference to original module
            }
        else
            -- Legacy module - store as-is
            loaded[spec.name] = module
        end
    end

    -- 2) Resolve order
    local order = topoSort(manifest)
    
    -- Build order names for logging
    local names = {}
    for i = 1, #order do 
        names[i] = order[i].name 
    end
    log:info("Init order: %s", table.concat(names, ", "))

    -- 3) Init phase with context
    local ctx = {
        get = function(name: string) 
            local service = loaded[name]
            -- If it's a wrapped service, return the module
            if type(service) == "table" and service._module then
                return service._module
            end
            return service
        end,
        services = loaded, -- Internal/legacy - prefer ctx.get()
    }
    
    for _, spec in ipairs(order) do
        local svc = loaded[spec.name]
        if type(svc) == "table" and svc.Init then 
            log:debug("Init %s", spec.name)
            local ok, err = pcall(svc.Init, svc._module or svc, ctx)
            if not ok then
                error(("[ServiceManager] %s.Init failed: %s"):format(spec.name, tostring(err)))
            end
        end
    end

    -- 4) Start phase
    for _, spec in ipairs(order) do
        local svc = loaded[spec.name]
        if type(svc) == "table" and svc.Start then 
            log:debug("Start %s", spec.name)
            local ok, err = pcall(svc.Start, svc._module or svc)
            if not ok then
                error(("[ServiceManager] %s.Start failed: %s"):format(spec.name, tostring(err)))
            end
        end
    end

    log:info("Bootstrap complete!")

    -- Return stop function for cleanup
    return function()
        log:info("Shutting down services...")
        for i = #order, 1, -1 do
            local svc = loaded[order[i].name]
            if type(svc) == "table" and svc.Stop then
                log:debug("Stop %s", order[i].name)
                pcall(svc.Stop, svc._module or svc)
            end
        end
        log:info("Shutdown complete")
    end
end

return ServiceManager