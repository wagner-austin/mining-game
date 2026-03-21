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
local LoadingConstants = require(Shared:WaitForChild("LoadingConstants"))
local FallbackRegistry = require(script.Parent.FallbackRegistry)
local ErrorService = require(script.Parent.ErrorService)

local slog = Logger.new(Logger.CAT.ServiceContainer)

-- Optional config
local _DBG = GameConfig.Debug
local WARN_INIT_SEC = (_DBG and _DBG.WARN_INIT_SEC) or 0.25
local WARN_START_SEC = (_DBG and _DBG.WARN_START_SEC) or 0.25
local TIMEOUT_INIT = (LoadingConstants and LoadingConstants.TIMEOUTS and LoadingConstants.TIMEOUTS.ServiceInit) or 0
local TIMEOUT_START = (LoadingConstants and LoadingConstants.TIMEOUTS and LoadingConstants.TIMEOUTS.ServiceStart) or 0
local POLL_INTERVAL = (LoadingConstants and LoadingConstants.POLL_INTERVALS and LoadingConstants.POLL_INTERVALS.Fine)
	or 0

-- Type mapping for strongly-typed Get/tryGet is provided by ServiceIndex.lua
local ServiceIndex = require(Shared:WaitForChild("ServiceIndex"))
type ServiceName = ServiceIndex.ServiceName
type Services = ServiceIndex.Services
type ManagedService = ServiceIndex.ManagedService

-- Public API shape for consumers. Methods only; internal data is private.
export type ServiceContainerPublic = {
	register: (
		self: ServiceContainerPublic,
		name: string,
		mod: ManagedService,
		deps: { string }?
	) -> ServiceContainerPublic,
	build: (self: ServiceContainerPublic) -> (),
	start: (self: ServiceContainerPublic) -> (),
	stop: (self: ServiceContainerPublic) -> (),
	Get: (self: ServiceContainerPublic, name: ServiceName) -> (),
	get: (self: ServiceContainerPublic, name: ServiceName) -> (),
	tryGet: (self: ServiceContainerPublic, name: ServiceName) -> (),
}

-- Strict internal service interface expected by the container.
-- All lifecycle methods are present; missing ones are normalized to no-ops.
export type ManagedServiceExact = {
	Init: (ManagedServiceExact, ServiceContainerPublic) -> (),
	Start: (ManagedServiceExact, ServiceContainerPublic) -> (),
	Stop: (ManagedServiceExact) -> (),
}

type ServiceRec = {
	name: string,
	mod: ManagedServiceExact,
	deps: { string },
	inst: ManagedServiceExact?,
	_idx: number,
}

-- Container data shape (internal)
type ServiceContainerT = {
	_services: { [string]: ServiceRec },
	_regCount: number,
	_order: { ServiceRec }?,
	_stopped: boolean,
	_public: ServiceContainerPublic?,
}

local ServiceContainer = {}
ServiceContainer.__index = ServiceContainer

local health = { init = {}, start = {}, stop = {} }

function ServiceContainer.new(): ServiceContainerPublic
	local priv: ServiceContainerT = {
		_services = {} :: { [string]: ServiceRec },
		_regCount = 0,
		_order = nil :: { ServiceRec }?,
		_stopped = false,
		_public = nil,
	}

	local public: ServiceContainerPublic = {
		register = function(_self, name: string, mod: ManagedService, deps: { string }?)
			ServiceContainer.register(priv, name, mod, deps)
			return _self
		end,
		build = function(_self)
			ServiceContainer.build(priv)
		end,
		start = function(_self)
			ServiceContainer.start(priv)
		end,
		stop = function(_self)
			ServiceContainer.stop(priv)
		end,
		Get = function(_self, name: ServiceName)
			return ServiceContainer.Get(priv, name)
		end,
		get = function(_self, name: ServiceName)
			return ServiceContainer.get(priv, name)
		end,
		tryGet = function(_self, name: ServiceName)
			return ServiceContainer.tryGet(priv, name)
		end,
	}

	priv._public = public
	return public
end

local function validateServiceStrict(name: string, mod: ManagedService): ManagedServiceExact
	assert(type(mod) == "table", ("Service '%s' must return a table"):format(name))
	local errs = {}
	if type(mod.Init) ~= "function" then
		table.insert(errs, "missing Init(self, container)")
	end
	if mod.Start ~= nil and type(mod.Start) ~= "function" then
		table.insert(errs, "Start must be a function if present")
	end
	if mod.Stop ~= nil and type(mod.Stop) ~= "function" then
		table.insert(errs, "Stop must be a function if present")
	end
	if #errs > 0 then
		error(("Service '%s' failed interface: %s"):format(name, table.concat(errs, "; ")))
	end
	-- Safe by construction: we ensured required fields exist and are functions
	return mod :: ManagedServiceExact
end

function ServiceContainer.register(self: ServiceContainerT, name: string, mod: ManagedService, deps: { string }?)
	assert(type(name) == "string" and name ~= "", "Service name required")
	assert(mod ~= nil, ("Service '%s' module is nil"):format(name))
	assert(self._services[name] == nil, ("Service '%s' already registered"):format(name))
	local sc = self :: ServiceContainerT
	sc._regCount = sc._regCount + 1
	local checked = validateServiceStrict(name, mod)
	sc._services[name] = { name = name, mod = checked, deps = deps or {}, inst = nil, _idx = sc._regCount }
	return self
end

local function topoSort(services: { [string]: ServiceRec }): { ServiceRec }
	local indeg: { [string]: number } = {}
	local adj: { [string]: { string } } = {}
	for n, _ in pairs(services) do
		indeg[n] = 0
	end
	for n, rec in pairs(services) do
		for _, d in ipairs(rec.deps) do
			assert(services[d], ("Service '%s' depends on unknown '%s'"):format(n, d))
			indeg[n] = (indeg[n] or 0) + 1
			adj[d] = adj[d] or {}
			table.insert(adj[d], n)
		end
	end

	local function byStable(a: string, b: string)
		local ra, rb = services[a], services[b]
		if ra._idx ~= rb._idx then
			return ra._idx < rb._idx
		end
		return a < b
	end

	local q: { string } = {}
	for n, k in pairs(indeg) do
		if k == 0 then
			table.insert(q, n)
		end
	end
	table.sort(q, byStable)

	local out: { ServiceRec } = {}
	while #q > 0 do
		local n0 = q[1]
		if not n0 then
			break
		end
		table.remove(q, 1)
		local n = n0
		table.insert(out, services[n])
		for _, m in ipairs(adj[n] or {}) do
			indeg[m] = (indeg[m] or 0) - 1
			if indeg[m] == 0 then
				table.insert(q, m)
				table.sort(q, byStable)
			end
		end
	end

	local unresolved = {}
	for name, k in pairs(indeg) do
		if k and k > 0 then
			table.insert(unresolved, name)
		end
	end
	if #unresolved > 0 then
		table.sort(unresolved)
		error("Cyclic service dependency detected: " .. table.concat(unresolved, ", "))
	end

	return out
end

-- Ensure a service has the full ManagedServiceExact lifecycle shape.
-- Mutates the provided table only to add missing no-op lifecycle methods.
-- Strictness is enforced at registration; no shape normalization is performed here.

function ServiceContainer.build(self: ServiceContainerT)
	assert(self._order == nil, "ServiceContainer already built")
	local order = topoSort(self._services)
	self._order = order
	for _, rec in ipairs(order) do
		rec.inst = rec.mod
		local inst = rec.inst
		if inst and type(inst.Init) == "function" then
			local t0 = Time.mono()
			local ok, resOrErr
			local usedFallbackInit = false
			if TIMEOUT_INIT and TIMEOUT_INIT > 0 then
				local initFn = inst.Init
				ok, resOrErr = Timeout.run(function()
					local pub = assert(self._public, "ServiceContainer public API not set")
					initFn(inst, pub)
					return true
				end, TIMEOUT_INIT, POLL_INTERVAL)
				if not ok and resOrErr == "TIMEOUT" then
					if FallbackRegistry.has(rec.name) then
						slog:warn("%s.Init timed out (%.2fs). Falling back to stub.", rec.name, TIMEOUT_INIT)
						do
							local _stub = FallbackRegistry.get(rec.name)
						end
						health.init[rec.name] = "fallback"
						usedFallbackInit = true
					else
						error(
							("[ServiceContainer] %s.Init exceeded soft timeout (%.2fs)"):format(rec.name, TIMEOUT_INIT)
						)
					end
				end
			else
				local initFn = inst.Init
				ok, resOrErr = ErrorService.safecall("Service.Init:" .. rec.name, function()
					local pub = assert(self._public, "ServiceContainer public API not set")
					initFn(inst, pub)
					return true
				end)
			end
			local dt = Time.mono() - t0
			if dt > WARN_INIT_SEC then
				slog:warn("Slow Init (%.3fs): %s", dt, rec.name)
			end
			if not usedFallbackInit then
				if not ok then
					if FallbackRegistry.has(rec.name) then
						slog:warn("%s.Init failed: %s. Falling back to stub.", rec.name, tostring(resOrErr))
						do
							local _stub = FallbackRegistry.get(rec.name)
						end
						health.init[rec.name] = "fallback"
					else
						error(("[ServiceContainer] %s.Init failed: %s"):format(rec.name, tostring(resOrErr)))
					end
				else
					health.init[rec.name] = "ok"
				end
			end
		else
			health.init[rec.name] = "n/a"
		end
	end

	if RunService:IsStudio() then
		local names = table.create(#order)
		for i, r in ipairs(self._order :: { ServiceRec }) do
			names[i] = r.name
		end
		slog:info("Init order: %s", table.concat(names, ", "))
	end
end

function ServiceContainer.start(self: ServiceContainerT)
	local order = assert(self._order, "Call :build() before :start()")
	for _, rec in ipairs(order) do
		if rec.inst and type(rec.inst.Start) == "function" then
			local t0 = Time.mono()
			local ok, resOrErr
			local usedFallbackStart = false
			if TIMEOUT_START and TIMEOUT_START > 0 then
				local inst2 = rec.inst
				local startFn = inst2.Start
				ok, resOrErr = Timeout.run(function()
					local pub = assert(self._public, "ServiceContainer public API not set")
					startFn(inst2, pub)
					return true
				end, TIMEOUT_START, POLL_INTERVAL)
				if not ok and resOrErr == "TIMEOUT" then
					if FallbackRegistry.has(rec.name) then
						slog:warn("%s.Start timed out (%.2fs). Using stub.", rec.name, TIMEOUT_START)
						do
							local _stub = FallbackRegistry.get(rec.name)
						end
						health.start[rec.name] = "fallback"
						usedFallbackStart = true
					else
						error(
							("[ServiceContainer] %s.Start exceeded soft timeout (%.2fs)"):format(
								rec.name,
								TIMEOUT_START
							)
						)
					end
				end
			else
				local inst2 = rec.inst
				local startFn = inst2.Start
				ok, resOrErr = ErrorService.safecall("Service.Start:" .. rec.name, function()
					local pub = assert(self._public, "ServiceContainer public API not set")
					startFn(inst2, pub)
					return true
				end)
			end
			local dt = Time.mono() - t0
			if dt > WARN_START_SEC then
				slog:warn("Slow Start (%.3fs): %s", dt, rec.name)
			end
			if not usedFallbackStart then
				if not ok then
					if FallbackRegistry.has(rec.name) then
						slog:warn("%s.Start failed: %s. Using stub.", rec.name, tostring(resOrErr))
						do
							local _stub = FallbackRegistry.get(rec.name)
						end
						health.start[rec.name] = "fallback"
					else
						error(("[ServiceContainer] %s.Start failed: %s"):format(rec.name, tostring(resOrErr)))
					end
				else
					health.start[rec.name] = "ok"
				end
			end
		else
			health.start[rec.name] = "n/a"
		end
	end

	if RunService:IsStudio() then
		slog:info("Started")
		for _, rec in ipairs(order) do
			slog:info(
				"%s -> init=%s start=%s",
				rec.name,
				tostring(health.init[rec.name] or "n/a"),
				tostring(health.start[rec.name] or "n/a")
			)
		end
	else
		local ReplicatedStorage2 = game:GetService("ReplicatedStorage")
		local Shared2 = ReplicatedStorage2:WaitForChild("MiningGame")
		local Logger2 = require(Shared2:WaitForChild("Logger"))
		local slog2 = Logger2.new(Logger2.CAT.ServiceContainer)
		slog2:info("Service health summary (init/start):")
		for _, rec in ipairs(order) do
			slog2:info(
				"  %s -> init=%s start=%s",
				rec.name,
				tostring(health.init[rec.name] or "n/a"),
				tostring(health.start[rec.name] or "n/a")
			)
		end
	end
end

function ServiceContainer.stop(self: ServiceContainerT)
	if self._stopped then
		return
	end
	if not self._order then
		return
	end
	for i = #self._order, 1, -1 do
		local rec = (self._order :: { ServiceRec })[i]
		if rec.inst and type(rec.inst.Stop) == "function" then
			local ok, err = ErrorService.safecall("Service.Stop:" .. rec.name, function()
				local inst3 = rec.inst
				if inst3 then
					local stopFn = inst3.Stop
					stopFn(inst3)
				end
				return true
			end)
			if not ok and RunService:IsStudio() then
				warn(("[ServiceContainer] Stop '%s' error: %s"):format(rec.name, tostring(err)))
			end
		end
	end
	self._stopped = true
end

function ServiceContainer.Get(self: ServiceContainerT, name: string): any
	local rec = self._services[name]
	assert(rec and rec.inst, ("Service '%s' not available"):format(name))
	return rec.inst
end

function ServiceContainer.tryGet(self: ServiceContainerT, name: string): any
	local rec = self._services[name]
	return rec and rec.inst or nil
end

function ServiceContainer.get(self: ServiceContainerT, name: string): any
	return ServiceContainer.Get(self, name)
end

return ServiceContainer
