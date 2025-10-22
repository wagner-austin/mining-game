# Service Architecture

## Overview

The Mining Game uses a sophisticated service architecture with dependency injection, lifecycle management, and topological sorting to ensure services initialize in the correct order. This system was implemented in Q1 2025 to replace manual service initialization.

## Quick Start

### Accessing Services

```lua
-- From within a service (using DI container)
function MyService:Init(container)
    self.DataService = container:Get("DataService")
    self.GridService = container:Get("GridService")
end

-- From Studio console (debugging)
local container = _G.MiningGameServices.container
local dataService = container:Get("DataService")
```

## Architecture Components

### ServiceContainer (`server/MiningGame/ServiceContainer.lua`)

The core dependency injection container that manages service lifecycle:

- **Dependency Resolution**: Topological sort ensures services initialize in dependency order
- **Cycle Detection**: Prevents circular dependencies at registration time
- **Lifecycle Management**: Init → Start → Stop phases
- **Safe Access**: `Get()` and `tryGet()` methods for required/optional services

#### Key Methods

```lua
-- Register a service with dependencies
container:register(name: string, module: any, deps: {string}?)

-- Build all services (calls Init on each)
container:build()

-- Start all services (calls Start on each)
container:start()

-- Stop all services in reverse order (calls Stop on each)
container:stop()

-- Get a required service (errors if not found)
container:Get(name: string): any

-- Try to get an optional service (returns nil if not found)
container:tryGet(name: string): any?
```

### ServiceManager (`server/MiningGame/ServiceManager.lua`)

Thin orchestration layer that registers all services with their dependencies:

```lua
function ServiceManager.start()
    local container = ServiceContainer.new()
    
    -- Infrastructure first (no dependencies)
    regReq(container, "RemoteEventBridge", parent.RemoteEventBridge, {})
    regReq(container, "ErrorService", parent.ErrorService, {})
    
    -- Foundation services
    regReq(container, "DataService", parent.DataService, {})
    regReq(container, "SessionService", parent.SessionService, {"DataService"})
    
    -- Game services with complex dependencies
    regReq(container, "DigService", parent.DigService, {
        "GridService", "DataService", "InventoryService", 
        "UpgradeService", "LootService", "AchievementService", 
        "ItemService", "CubePositionService"
    })
    
    -- Optional services (won't fail if missing)
    regOpt(container, "RateLimitService", parent:FindFirstChild("RateLimitService"), {})
    
    container:build()
    container:start()
    return container
end
```

## Service Lifecycle

### 1. Registration Phase
Services are registered with their dependencies but not yet instantiated.

### 2. Build Phase (`Init`)
- Services sorted topologically by dependencies
- Each service's `Init` method called with the container
- Services can store references to dependencies

```lua
function MyService:Init(container)
    -- Store service dependencies
    self.DataService = container:Get("DataService")
    self.EventBus = require(Shared.EventBus).global()
    
    -- Initialize internal state
    self._cache = {}
    self._connections = {}
end
```

### 3. Start Phase (`Start`)
- Called after all services are initialized
- Services can now interact with their dependencies
- Connect to events, start background tasks

```lua
function MyService:Start(container)
    -- Safe to use dependencies now
    local profile = self.DataService:GetPlayerData(player)
    
    -- Start listening to events
    self.EventBus:on("SomeEvent", function(data)
        self:HandleEvent(data)
    end)
end
```

### 4. Stop Phase (`Stop`)
- Called in reverse dependency order
- Clean up connections, save state
- Graceful shutdown

```lua
function MyService:Stop()
    -- Clean up connections
    for _, conn in ipairs(self._connections) do
        conn:Disconnect()
    end
    
    -- Save any pending data
    self:FlushCache()
end
```

## Dependency Management

### Declaring Dependencies

Dependencies are declared during registration:

```lua
-- Service with no dependencies
container:register("GridService", GridService, {})

-- Service with single dependency
container:register("SessionService", SessionService, {"DataService"})

-- Service with multiple dependencies
container:register("InventoryService", InventoryService, {
    "DataService", "LootService", "AchievementService", "CurrencyService"
})
```

### Dependency Order

The topological sort ensures:
1. Services with no dependencies initialize first
2. Services only initialize after all their dependencies
3. Circular dependencies are detected and cause an error

Example initialization order:
```
1. RemoteEventBridge (no deps)
2. ErrorService (no deps)
3. DataService (no deps)
4. GridService (no deps)
5. SessionService (depends on DataService)
6. CurrencyService (depends on DataService)
7. AchievementService (depends on DataService, CurrencyService)
8. InventoryService (depends on DataService, LootService, AchievementService, CurrencyService)
```

## Service Categories

### Infrastructure Services
Core system services that other services depend on:
- `RemoteEventBridge` - Event routing infrastructure
- `ErrorService` - Centralized error handling
- `RemoteManager` - Remote function/event management
- `RateLimitService` - Rate limiting (optional)

### Foundation Services
Essential game services:
- `DataService` - Player data persistence
- `SessionService` - Session management
- `GridService` - Voxel grid management
- `CurrencyService` - Virtual currency

### Game Services
Core gameplay systems:
- `DigService` - Mining mechanics
- `InventoryService` - Item management
- `LootService` - Drop tables and rewards
- `UpgradeService` - Player progression
- `ItemService` - World items
- `SpawnService` - Player spawning

### Optional Services
Services that may not be present in all environments:
- `SimAgents` - Studio-only testing agents
- `WorldGenerationService` - Procedural generation
- `FloatingIslandService` - Special world features
- `RateLimitService` - Request throttling

## Best Practices

### 1. Service Design

```lua
local MyService = {}
MyService.__index = MyService

function MyService.new()
    local self = setmetatable({}, MyService)
    -- Don't initialize here, use Init
    return self
end

function MyService:Init(container)
    -- Store dependencies
    self.OtherService = container:Get("OtherService")
    
    -- Initialize state
    self._state = {}
end

function MyService:Start(container)
    -- Start operations
    self:BeginProcessing()
end

function MyService:Stop()
    -- Cleanup
    self:EndProcessing()
end

-- Public API
function MyService:DoSomething()
    return self.OtherService:GetData()
end

return MyService.new()
```

### 2. Dependency Access

```lua
-- Good: Store in Init, use in Start
function Service:Init(container)
    self.DataService = container:Get("DataService")
end

function Service:Start()
    local data = self.DataService:GetPlayerData(player)
end

-- Bad: Direct access in methods
function Service:SomeMethod()
    local data = container:Get("DataService"):GetPlayerData(player) -- Don't do this
end
```

### 3. Optional Dependencies

```lua
function Service:Init(container)
    -- Required dependency (will error if missing)
    self.DataService = container:Get("DataService")
    
    -- Optional dependency (nil if missing)
    self.RateLimitService = container:tryGet("RateLimitService")
end

function Service:HandleRequest(player, request)
    -- Check optional dependency before use
    if self.RateLimitService then
        if not self.RateLimitService:Allow(player, "action") then
            return Result.err("RATE_LIMITED")
        end
    end
    
    -- Process request...
end
```

### 4. Testing Services

```lua
-- Create test container
local container = ServiceContainer.new()

-- Register mock services
container:register("DataService", MockDataService, {})
container:register("MyService", MyService, {"DataService"})

-- Build and test
container:build()
container:start()

local service = container:Get("MyService")
assert(service:DoSomething() == expectedResult)

container:stop()
```

## Debugging

### Studio Access

In Studio, the service container is exposed globally:

```lua
-- Access from command bar
local container = _G.MiningGameServices.container
local service = container:Get("DigService")

-- List all services
for name, _ in pairs(container._services) do
    print(name)
end

-- Check dependencies
local serviceRec = container._services["DigService"]
print("Dependencies:", table.concat(serviceRec.deps, ", "))
```

### Common Issues

#### Circular Dependency
**Error**: "Cyclic service dependency detected"
**Solution**: Review service dependencies, refactor to break the cycle

#### Missing Service
**Error**: "Service 'X' not available"
**Solution**: Ensure service is registered in ServiceManager

#### Init Order Issues
**Symptom**: Nil reference errors during Init
**Solution**: Access dependencies in Start, not Init

#### Optional Service Missing
**Symptom**: Attempt to index nil value
**Solution**: Use `tryGet()` and check for nil before use

## Migration Guide

### From Manual Requires

Before:
```lua
-- In init.server.lua
local DataService = require(script.DataService)
local GridService = require(script.GridService)
local DigService = require(script.DigService)

DataService:Init()
GridService:Init()
DigService:Init(DataService, GridService) -- Manual dependency passing
```

After:
```lua
-- In ServiceManager.lua
container:register("DataService", DataService, {})
container:register("GridService", GridService, {})
container:register("DigService", DigService, {"DataService", "GridService"})

-- In DigService.lua
function DigService:Init(container)
    self.DataService = container:Get("DataService")
    self.GridService = container:Get("GridService")
end
```

### Adding a New Service

1. Create service module in `server/MiningGame/`
2. Add registration in `ServiceManager.lua`
3. Declare dependencies
4. Implement Init/Start/Stop methods

```lua
-- 1. Create NewService.lua
local NewService = {}
NewService.__index = NewService

function NewService.new()
    return setmetatable({}, NewService)
end

function NewService:Init(container)
    self.DataService = container:Get("DataService")
end

function NewService:Start(container)
    print("NewService started")
end

return NewService.new()

-- 2. Register in ServiceManager.lua
regReq(container, "NewService", parent.NewService, {"DataService"})
```

## Performance Considerations

- Services are singletons (one instance per server)
- Init/Start only called once at server startup
- Dependency resolution happens once during build
- No runtime dependency lookup overhead
- Services remain in memory for server lifetime

## See Also

- [EventBus System](EVENTBUS_SYSTEM.md) - Event-driven communication
- [Remote Architecture](REMOTE_ARCHITECTURE.md) - Client-server communication
- [Migration Guide Q1 2025](MIGRATION_GUIDE_Q1_2025.md) - Detailed migration steps