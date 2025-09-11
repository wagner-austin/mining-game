# EventBus System

## Overview

The EventBus is a decoupled publish-subscribe event system that enables communication between services without direct dependencies. It supports type-safe events, middleware, priority handling, and seamless server-to-client event bridging.

## Quick Start

### Basic Usage

```lua
-- Get the global EventBus instance
local EventBus = require(MiningGame.EventBus)
local Bus = EventBus.global()

-- Subscribe to an event
Bus:on("player.joined", function(data)
    print("Player joined:", data.player.Name)
end)

-- Emit an event
Bus:emit("player.joined", {
    player = player,
    timestamp = os.time()
})
```

### Using Event Names

```lua
local EventNames = require(MiningGame.EventNames)

-- Subscribe using constants
Bus:on(EventNames.CURRENCY_CHANGED, function(data)
    print("Currency updated:", data.payload.balance)
end)

-- Emit using constants
Bus:emit(EventNames.CURRENCY_CHANGED, {
    to = {kind = "player", player = player},
    payload = {currency = "coins", balance = 100, delta = 10}
})
```

## Architecture

### Core Components

#### EventBus (`shared/MiningGame/EventBus.lua`)
The main event system with:
- Publisher-subscriber pattern
- Event priority and ordering
- Middleware support
- Synchronous and deferred emission
- Memory-efficient queue system

#### EventNames (`shared/MiningGame/EventNames.lua`)
Centralized event name constants:
```lua
-- Server → Client events
CURRENCY_CHANGED = "currency.changed"
PROFILE_UPDATED = "profile.updated"
INVENTORY_CHANGED = "inventory.changed"
DIG_FEEDBACK = "dig.feedback"
ACHIEVEMENT_UNLOCKED = "achievement.unlocked"
```

#### RequestNames (`shared/MiningGame/RequestNames.lua`)
Client → Server request names:
```lua
-- Client → Server requests
INVENTORY_REQUEST_SELL = "inventory.request.sell"
DIG_REQUEST = "dig.request"
UPGRADE_REQUEST_PURCHASE = "upgrade.request.purchase"
```

#### RemoteEventBridge
Bridges EventBus across network boundary:
- **Server** (`server/MiningGame/RemoteEventBridge.lua`): Routes events to specific clients
- **Client** (`client/MiningGame/RemoteEventBridge.client.lua`): Receives server events, sends requests

## Event Flow

### Server to Client

```mermaid
Server Service → EventBus.emit() → RemoteEventBridge → RemoteEvent → Client EventBus → UI Components
```

1. Service emits event with target specification
2. RemoteEventBridge checks target (player/broadcast/team)
3. Event sent via RemoteEvent to appropriate clients
4. Client EventBus distributes to local subscribers

### Client to Server

```mermaid
UI Action → RemoteEventBridge.send() → RemoteEvent → Server Handler → Service Method
```

1. UI triggers action
2. RemoteEventBridge validates and sends request
3. Server receives and processes
4. Response sent back via EventBus if needed

## API Reference

### EventBus Methods

#### Subscribing to Events

```lua
-- Subscribe with default priority
local unsubscribe = Bus:on(eventName, handler)

-- Subscribe with priority (lower = earlier)
local unsubscribe = Bus:on(eventName, handler, 10)

-- Subscribe once (auto-unsubscribe after first call)
local unsubscribe = Bus:once(eventName, handler)

-- Unsubscribe
unsubscribe()
-- or
Bus:off(eventName, handler)

-- Remove all handlers for an event
Bus:offAll(eventName)

-- Remove all handlers
Bus:offAll()
```

#### Emitting Events

```lua
-- Synchronous emit (handlers must not yield)
Bus:emit(eventName, data)

-- Deferred emit (handlers can yield, run in spawned tasks)
Bus:emitDeferred(eventName, data)

-- Collect return values from handlers
local results = Bus:emitCollect(eventName, data)
```

#### Performance Optimization

```lua
-- Mark high-frequency events to skip middleware
Bus:markFastPath("dig.feedback")
```

### Event Data Structures

#### Server Event with Target

```lua
Bus:emit(EventNames.CURRENCY_CHANGED, {
    to = {
        kind = "player",     -- "player" | "broadcast" | "team"
        player = player,     -- Required for "player"
        team = "red"        -- Required for "team"
    },
    payload = {
        currency = "coins",
        balance = 1000,
        delta = 100
    }
})
```

#### Client Request

```lua
Bridge.send(RequestNames.INVENTORY_REQUEST_SELL, {
    itemId = "diamond_ore",
    quantity = 5
})
```

## Event Patterns

### Service-to-Service Communication

```lua
-- In InventoryService
function InventoryService:AddItem(player, itemId, quantity)
    -- Add item logic...
    
    -- Notify other services
    self.Bus:emit(EventNames.INVENTORY_CHANGED, {
        to = {kind = "player", player = player},
        payload = {
            action = "add",
            itemId = itemId,
            quantity = quantity,
            inventory = self:GetInventory(player)
        }
    })
end

-- In AchievementService
function AchievementService:Init(container)
    self.Bus = EventBus.global()
    
    self.Bus:on(EventNames.INVENTORY_CHANGED, function(data)
        self:CheckInventoryAchievements(data.to.player, data.payload)
    end)
end
```

### UI Updates

```lua
-- In client UI component
function InventoryPanel:Init()
    self.Bus = EventBus.global()
    
    -- Subscribe to inventory changes
    self._unsubscribe = self.Bus:on(EventNames.INVENTORY_CHANGED, function(data)
        self:UpdateDisplay(data.payload.inventory)
    end)
end

function InventoryPanel:Destroy()
    -- Clean up subscription
    if self._unsubscribe then
        self._unsubscribe()
    end
end
```

### Request-Response Pattern

```lua
-- Client side
local Bridge = require(MiningGame.RemoteEventBridge)

-- Send request
Bridge.send(RequestNames.INVENTORY_REQUEST_SELL, {
    itemId = "iron_ore",
    quantity = 10
})

-- Listen for response
Bus:once(EventNames.INVENTORY_CHANGED, function(data)
    if data.payload.action == "sold" then
        print("Sold items for", data.payload.value)
    end
end)
```

## Middleware

### Creating Middleware

```lua
-- Logging middleware
local function loggingMiddleware(ctx, next)
    print(string.format("[Event] %s at %.2f", ctx.event, ctx.timestamp))
    next()
end

-- Metrics middleware
local function metricsMiddleware(ctx, next)
    local start = os.clock()
    next()
    local duration = os.clock() - start
    
    if duration > 0.1 then
        warn(string.format("Slow event handler: %s took %.2fms", 
            ctx.event, duration * 1000))
    end
end

-- Register middleware
Bus:use(loggingMiddleware)
Bus:use(metricsMiddleware)
```

### Middleware Context

```lua
type MiddlewareContext = {
    event = "event.name",
    data = {}, -- Event payload
    source = "ServiceName", -- Optional
    timestamp = 12345.67 -- Time.mono()
}
```

## Event Priority

Events are processed in priority order (lower number = higher priority):

```lua
-- High priority handler (runs first)
Bus:on("game.tick", updatePhysics, 10)

-- Normal priority
Bus:on("game.tick", updateUI, 50)

-- Low priority handler (runs last)
Bus:on("game.tick", updateMetrics, 100)
```

Default priority is 50 if not specified.

## Performance Considerations

### Fast Path Events

High-frequency events can skip middleware for better performance:

```lua
-- Mark as fast path
Bus:markFastPath(EventNames.DIG_FEEDBACK)

-- This event will skip all middleware
Bus:emit(EventNames.DIG_FEEDBACK, {
    position = Vector3.new(10, 0, 10),
    material = "Stone"
})
```

### Queue Management

- Events are queued to prevent recursion issues
- Maximum queue length: 1000 events
- Queue processed synchronously in order
- Overflow events are dropped with warning

### Memory Management

```lua
-- Always store unsubscribe functions
local connections = {}

function Component:Init()
    -- Good: Store unsubscribe function
    table.insert(connections, Bus:on("event", handler))
end

function Component:Destroy()
    -- Good: Clean up all subscriptions
    for _, unsubscribe in ipairs(connections) do
        unsubscribe()
    end
end
```

## Best Practices

### 1. Use Event Constants

```lua
-- Good: Use constants
Bus:emit(EventNames.CURRENCY_CHANGED, data)

-- Bad: Magic strings
Bus:emit("currency.changed", data)
```

### 2. Type Your Event Data

```lua
-- Define event payload types
export type CurrencyChangedEvent = {
    to: {kind: "player", player: Player},
    payload: {
        currency: string,
        balance: number,
        delta: number
    }
}

-- Use in handlers
Bus:on(EventNames.CURRENCY_CHANGED, function(data: CurrencyChangedEvent)
    -- Type-safe access
    print(data.payload.balance)
end)
```

### 3. Clean Up Subscriptions

```lua
-- Good: Track and clean up
function Service:Start()
    self._connections = {}
    table.insert(self._connections, Bus:on(...))
end

function Service:Stop()
    for _, unsub in ipairs(self._connections) do
        unsub()
    end
end
```

### 4. Avoid Yielding in Sync Handlers

```lua
-- Bad: Yielding in sync handler
Bus:on("event", function(data)
    task.wait(1) -- Don't do this!
    processData(data)
end)

-- Good: Use deferred for async work
Bus:on("event", function(data)
    task.spawn(function()
        task.wait(1)
        processData(data)
    end)
end)

-- Or use emitDeferred
Bus:emitDeferred("event", data) -- Handlers can yield
```

### 5. Validate Event Data

```lua
-- In RemoteEventBridge
local SENDABLE_EVENTS = {
    [RequestNames.INVENTORY_REQUEST_SELL] = true,
    [RequestNames.DIG_REQUEST] = true,
}

function Bridge.send(requestName, payload)
    -- Validate event is allowed
    if not SENDABLE_EVENTS[requestName] then
        warn("Invalid request:", requestName)
        return
    end
    
    -- Send validated event
    RE:FireServer(requestName, payload)
end
```

## Common Event Flows

### Currency Update Flow

1. Player earns currency (e.g., selling items)
2. `DataService:AddCurrency()` updates balance
3. DataService emits `CURRENCY_CHANGED` event
4. RemoteEventBridge routes to player's client
5. Client EventBus distributes to UI components
6. Currency display updates automatically

### Dig Action Flow

1. Player clicks to dig
2. Client sends `DIG_REQUEST` via RemoteEventBridge
3. Server `DigService` validates and processes
4. DigService emits `DIG_FEEDBACK` event
5. Client receives feedback and shows visual effect
6. If successful, `INVENTORY_CHANGED` event follows

### Achievement Unlock Flow

1. Player action triggers achievement check
2. `AchievementService` validates completion
3. Service emits `ACHIEVEMENT_UNLOCKED` event
4. Multiple subscribers react:
   - UI shows achievement popup
   - Sound system plays fanfare
   - Analytics logs achievement
   - Currency service awards bonus

## Debugging

### Event Monitoring

```lua
-- Log all events (development only)
Bus:use(function(ctx, next)
    print(string.format("[EventBus] %s → %s", 
        ctx.event, 
        HttpService:JSONEncode(ctx.data)))
    next()
end)
```

### Check Active Handlers

```lua
-- In Studio console
local Bus = require(game.ReplicatedStorage.MiningGame.EventBus).global()

-- Check handlers for specific event
local handlers = Bus._listeners["currency.changed"]
print("Handler count:", handlers and #handlers or 0)

-- List all events with handlers
for event, handlers in pairs(Bus._listeners) do
    print(event, "→", #handlers, "handlers")
end
```

### Trace Event Path

```lua
-- Add source tracking
Bus:emit(EventNames.CURRENCY_CHANGED, {
    to = {kind = "player", player = player},
    payload = data,
    _source = "DataService:AddCurrency", -- Debug info
    _trace = debug.traceback()
})
```

## Integration Examples

### Service Integration

```lua
-- In service Init
function MyService:Init(container)
    self.Bus = EventBus.global()
    self.DataService = container:Get("DataService")
    
    -- Subscribe to relevant events
    self.Bus:on(EventNames.PROFILE_UPDATED, function(data)
        self:OnProfileUpdate(data.to.player, data.payload)
    end)
end

-- In service methods
function MyService:DoAction(player)
    -- Perform action...
    
    -- Emit event for other systems
    self.Bus:emit(EventNames.ACTION_COMPLETED, {
        to = {kind = "player", player = player},
        payload = {actionId = "test", result = "success"}
    })
end
```

### UI Component Integration

```lua
local EventBus = require(MiningGame.EventBus)
local EventNames = require(MiningGame.EventNames)

function UIComponent:Init()
    self.Bus = EventBus.global()
    self._connections = {}
    
    -- Subscribe to multiple events
    local events = {
        [EventNames.CURRENCY_CHANGED] = self.OnCurrencyChanged,
        [EventNames.INVENTORY_CHANGED] = self.OnInventoryChanged,
        [EventNames.PROFILE_UPDATED] = self.OnProfileUpdated,
    }
    
    for event, handler in pairs(events) do
        table.insert(self._connections, 
            self.Bus:on(event, function(data)
                handler(self, data)
            end))
    end
end

function UIComponent:Destroy()
    for _, unsub in ipairs(self._connections) do
        unsub()
    end
end
```

## See Also

- [Service Architecture](SERVICE_ARCHITECTURE.md) - Service system overview
- [Remote Architecture](REMOTE_ARCHITECTURE.md) - Client-server communication
- [API Documentation](API_DOCUMENTATION.md) - Remote functions and events
- [Migration Guide Q1 2025](MIGRATION_GUIDE_Q1_2025.md) - Migration to EventBus
