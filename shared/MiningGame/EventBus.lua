--!strict
--[[
    EventBus.lua
    A decoupled event system for inter-service communication.
    
    Features:
    - Type-safe event definitions
    - Pub/sub pattern with event namespacing
    - Middleware support for logging/metrics
    - Event priority and ordering
    - Non-yielding handlers for sync emit, deferred for async
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Time = require(MiningGame:WaitForChild("Time"))
local ClientError = require(MiningGame:WaitForChild("ClientError"))

local EventBus = {}
EventBus.__index = EventBus

export type EventHandler<T> = (data: T) -> ()
export type MiddlewareContext = {
	event: string,
	data: any,
	source: string?,
	timestamp: number,
}
export type Middleware = (ctx: MiddlewareContext, next: () -> ()) -> ()
export type Priority = number

export type EventBus = {
	on: <T>(self: EventBus, event: string, handler: EventHandler<T>, priority: Priority?) -> () -> (),
	once: <T>(self: EventBus, event: string, handler: EventHandler<T>) -> () -> (),
	emit: <T>(self: EventBus, event: string, data: T) -> (),
	emitDeferred: <T>(self: EventBus, event: string, data: T) -> (),
	emitCollect: <T>(self: EventBus, event: string, data: T) -> { any },
	off: (self: EventBus, event: string, handler: EventHandler<any>) -> (),
	offAll: (self: EventBus, event: string?) -> (),
	use: (self: EventBus, middleware: Middleware) -> (),
	destroy: (self: EventBus) -> (),
	configure: (self: EventBus, opts: { maxQueue: number?, onDrop: ((string, any, number) -> ())? }) -> (),
	markFastPath: (self: EventBus, event: string) -> (),
	-- internal helpers (private)
	_processQueue: (self: EventBus) -> (),
	_processEvent: (self: EventBus, event: string, data: any, deferred: boolean) -> (),
}

type HandlerEntry = {
	handler: EventHandler<any>,
	priority: Priority,
	once: boolean,
}

type EventBusImpl = EventBus & {
	_listeners: { [string]: { HandlerEntry } },
	_middleware: { Middleware },
	_q: { any },
	_qh: number,
	_qt: number,
	_processing: boolean,
	_fastPathEvents: { [string]: boolean },
	_maxQueue: number,
	_onDrop: ((string, any, number) -> ())?,
	_validators: { [string]: (any) -> any },
}

local DEFAULT_PRIORITY = 50 -- Lower number runs first
local MAX_QUEUE_LENGTH = 1000

function EventBus.new(): EventBus
	local self = setmetatable({} :: EventBusImpl, EventBus)
	self._listeners = {}
	self._middleware = {}
	self._q = {}
	self._qh = 1
	self._qt = 0
	self._processing = false
	self._fastPathEvents = {}
	self._maxQueue = MAX_QUEUE_LENGTH
	self._onDrop = nil :: ((string, any, number) -> ())?
	self._validators = {}
	return self
end

local function insertByPriority(handlers: { HandlerEntry }, entry: HandlerEntry)
	for i, existing in ipairs(handlers) do
		if entry.priority < existing.priority then
			table.insert(handlers, i, entry)
			return
		end
	end
	table.insert(handlers, entry)
end

function EventBus:on<T>(event: string, handler: EventHandler<T>, priority: Priority?): () -> ()
	local handlers = self._listeners[event]
	if not handlers then
		handlers = {}
		self._listeners[event] = handlers
	end

	local entry: HandlerEntry = {
		handler = handler,
		priority = priority or DEFAULT_PRIORITY,
		once = false,
	}

	insertByPriority(handlers, entry)

	-- Return unsubscribe function
	return function()
		self:off(event, handler)
	end
end

function EventBus:once<T>(event: string, handler: EventHandler<T>): () -> ()
	local handlers = self._listeners[event]
	if not handlers then
		handlers = {}
		self._listeners[event] = handlers
	end

	local entry: HandlerEntry = {
		handler = handler,
		priority = DEFAULT_PRIORITY,
		once = true,
	}

	insertByPriority(handlers, entry)

	return function()
		self:off(event, handler)
	end
end

function EventBus:off(event: string, handler: EventHandler<any>)
	local handlers = self._listeners[event]
	if not handlers then
		return
	end

	for i = #handlers, 1, -1 do
		if handlers[i].handler == handler then
			table.remove(handlers, i)
		end
	end

	if #handlers == 0 then
		self._listeners[event] = nil
	end
end

function EventBus:offAll(event: string?)
	if event then
		self._listeners[event] = nil
	else
		table.clear(self._listeners)
	end
end

-- Mark events that should skip middleware for performance
function EventBus:markFastPath(event: string)
	self._fastPathEvents[event] = true
end

-- Install a validators map keyed by event name; validators should throw on invalid data
-- Runtime dispatch table for dynamic event validation
function EventBus.useContracts(validators: { [string]: (any) -> any })
	local g = EventBus.global() :: EventBusImpl
	g._validators = validators or {}
end

-- Configure queue size and overflow behavior
function EventBus:configure(opts: { maxQueue: number?, onDrop: ((string, any, number) -> ())? })
	local impl = self :: EventBusImpl
	if opts and typeof(opts.maxQueue) == "number" and opts.maxQueue > 0 then
		impl._maxQueue = opts.maxQueue
	end
	if opts and typeof(opts.onDrop) == "function" then
		impl._onDrop = opts.onDrop
	end
end

local function runMiddleware(middleware: { Middleware }, ctx: MiddlewareContext, finalHandler: () -> ())
	local index = 1

	local function next()
		if index > #middleware then
			finalHandler()
			return
		end

		local currentMiddleware = middleware[index]
		index = index + 1
		ClientError.try("EventBus:middleware", function()
			currentMiddleware(ctx, next)
			return true
		end)
	end

	next()
end

local function queueLength(self: EventBusImpl): number
	return self._qt - self._qh + 1
end

-- Internal queue processor
function EventBus:_processQueue()
	local selfImpl = self :: EventBusImpl
	selfImpl._processing = true
	while selfImpl._qh <= selfImpl._qt do
		local item = selfImpl._q[selfImpl._qh]
		selfImpl._q[selfImpl._qh] = nil
		selfImpl._qh = selfImpl._qh + 1
		self:_processEvent(item.event, item.data, false)
	end
	selfImpl._qh = 1
	selfImpl._qt = 0
	selfImpl._processing = false
end

-- Synchronous emit - handlers MUST NOT yield
function EventBus:emit<T>(event: string, data: T)
	-- Queue event for processing
	local impl = self :: EventBusImpl
	if queueLength(impl) >= (impl._maxQueue or MAX_QUEUE_LENGTH) then
		local onDrop = impl._onDrop
		if onDrop then
			ClientError.try("EventBus:onDrop", function()
				onDrop(event, data, queueLength(impl))
				return true
			end)
		else
			warn(("[EventBus] Queue overflow, dropping event '%s'"):format(event))
		end
		return
	end

	impl._qt = impl._qt + 1
	impl._q[impl._qt] = { event = event, data = data }

	-- Process queue if not already processing
	if not impl._processing then
		self:_processQueue()
	end
end

-- Internal event processor
function EventBus:_processEvent(event: string, data: any, deferred: boolean)
	-- Validate data against a registered validator when present
	local impl = self :: EventBusImpl
	local validator = impl._validators and impl._validators[event]
	if validator then
		local candidate = data
		if type(data) == "table" and data.payload ~= nil then
			candidate = data.payload
		end
		local ok, err = ClientError.try("EventBus:validate", function()
			validator(candidate)
			return true
		end)
		if not ok then
			warn(("[EventBus] Dropping invalid payload for '%s': %s"):format(event, tostring(err)))
			return
		end
	end
	local handlers = self._listeners[event]
	if not handlers or #handlers == 0 then
		return
	end

	-- Make a copy to avoid mutation during iteration
	local handlersCopy = table.clone(handlers)

	-- Remove once handlers from the original list
	for i = #handlers, 1, -1 do
		if handlers[i].once then
			table.remove(handlers, i)
		end
	end

	-- Clean up empty handler lists
	if #handlers == 0 then
		self._listeners[event] = nil
	end

	local ctx: MiddlewareContext = {
		event = event,
		data = data,
		source = nil,
		timestamp = Time.mono(),
	}

	-- Fast path skips middleware
	local skipMiddleware = self._fastPathEvents[event]

	local function executeHandlers()
		if deferred then
			-- Use task.defer for better scheduling (avoids preemption storms)
			for _, entry in ipairs(handlersCopy) do
				task.defer(function()
					local ok = ClientError.try("EventBus:handler(deferred)", function()
						entry.handler(data)
						return true
					end)
					if not ok then
						warn(("[EventBus] Handler error for '%s' (deferred)"):format(event))
					end
				end)
			end
		else
			-- Execute synchronously (no yielding allowed)
			for _, entry in ipairs(handlersCopy) do
				local ok = ClientError.try("EventBus:handler", function()
					entry.handler(data)
					return true
				end)
				if not ok then
					warn(("[EventBus] Sync handler error for '%s'"):format(event))
				end
			end
		end
	end

	if deferred then
		-- Spawn the entire middleware chain + handlers to avoid yielding on caller's thread
		task.spawn(function()
			if skipMiddleware then
				executeHandlers()
			else
				runMiddleware(self._middleware, ctx, executeHandlers)
			end
		end)
	else
		-- Sync path: middleware must not yield
		if skipMiddleware then
			executeHandlers()
		else
			runMiddleware(self._middleware, ctx, executeHandlers)
		end
	end
end

-- Deferred emit - handlers and middleware can yield, run in spawned tasks
function EventBus:emitDeferred<T>(event: string, data: T)
	self:_processEvent(event, data, true)
end

-- Synchronous emit that collects return values (no yielding)
function EventBus:emitCollect<T>(event: string, data: T): { any }
	-- Validate first if a validator exists
	local impl = self :: EventBusImpl
	local validator = impl._validators and impl._validators[event]
	if validator then
		local candidate: any = data
		if type(candidate) == "table" and candidate.payload ~= nil then
			candidate = candidate.payload
		end
		local ok, err = ClientError.try("EventBus:validate", function()
			validator(candidate)
			return true
		end)
		if not ok then
			warn(("[EventBus] Dropping invalid payload for '%s' (collect): %s"):format(event, tostring(err)))
			return {}
		end
	end

	local handlers = self._listeners[event]
	if not handlers or #handlers == 0 then
		return {}
	end

	-- Make a copy to avoid mutation during iteration
	local handlersCopy = table.clone(handlers)

	-- Remove once handlers from the original list
	for i = #handlers, 1, -1 do
		if handlers[i].once then
			table.remove(handlers, i)
		end
	end

	-- Clean up empty handler lists
	if #handlers == 0 then
		self._listeners[event] = nil
	end

	local results = {}
	local ctx: MiddlewareContext = {
		event = event,
		data = data,
		source = nil,
		timestamp = Time.mono(),
	}

	local skipMiddleware = self._fastPathEvents[event]

	local function executeHandlers()
		for _, entry in ipairs(handlersCopy) do
			local success, result = ClientError.try("EventBus:handler(collect)", function()
				return entry.handler(data)
			end)
			if success then
				table.insert(results, result)
			else
				warn(("[EventBus] Handler error for '%s' (collect)"):format(event))
			end
		end
	end

	if skipMiddleware then
		executeHandlers()
	else
		runMiddleware(self._middleware, ctx, executeHandlers)
	end

	return results
end

function EventBus:use(middleware: Middleware)
	table.insert(self._middleware, middleware)
end

function EventBus:destroy()
	table.clear(self._listeners)
	table.clear(self._middleware)
	table.clear(self._q)
	table.clear(self._fastPathEvents)
	self._qh = 1
	self._qt = 0
	self._processing = false
end

-- Global singleton instance
local globalBus: EventBus? = nil

function EventBus.global(): EventBus
	if not globalBus then
		globalBus = EventBus.new()
	end
	return globalBus :: EventBus
end

-- Event namespace helper
function EventBus.namespace(prefix: string): (event: string) -> string
	return function(event: string)
		return prefix .. "." .. event
	end
end

-- Validators are installed by bootstrap code (server/client) via EventBus.useContracts

return EventBus
