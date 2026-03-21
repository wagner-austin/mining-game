# Migration Guide (Q1 2025 Refactor)

## Overview
This guide explains how to migrate legacy scripts to the new architecture introduced in Q1 2025:
- ServiceContainer + ServiceManager for dependency injection and lifecycle
- RFRegistry + RemoteManager for RemoteFunctions
- EventBus + RemoteEventBridge for events
- ClientRF for client calls with automatic Result unwrapping

## Services

### Before (manual requires and ordering)
```lua
-- init.server.lua (legacy)
local DataService = require(script.DataService)
local GridService = require(script.GridService)
local DigService = require(script.DigService)

DataService:Init()
GridService:Init()
DigService:Init(DataService, GridService)
```

### After (ServiceManager + ServiceContainer)
```lua
-- init.server.lua (refactored)
local ServiceManager = require(script.ServiceManager)
local container = ServiceManager.start()
_G.MiningGameServices = { container = container } -- Studio only
```

```lua
-- DigService.lua (refactored)
function DigService:Init(container)
    self.DataService = container:Get("DataService")
    self.GridService = container:Get("GridService")
end
```

## RemoteFunctions

### Before (scattered remotes)
```lua
-- In some server script
Remotes.RF.SellItems.OnServerInvoke = function(player, itemId, count)
    return InventoryService:SellItems(player, itemId, count)
end
```

### After (specs + RFRegistry + RemoteManager)
```lua
-- server/MiningGame/RemoteFns/Inventory.rf.lua
return function(container)
    local InventoryService = container:Get("InventoryService")
    return {
        {
            name = "SellItems",
            validate = function(items)
                return type(items) == "table" and next(items) ~= nil
            end,
            opts = { requireProfile = true, rateLimitSec = 0.5 },
            handler = function(ctx, items)
                local ok, value = InventoryService:SellItems(ctx.player, items)
                return ok and { ok = true, success = true, coins = value } or
                       { ok = false, success = false, err = "SELL_FAILED" }
            end
        }
    }
end
```

```lua
-- init.server.lua (registration)
local RFRegistry = require(script.RFRegistry)
local stats = RFRegistry.register(container) -- after services are started
```

## Events

### Before (multiple RemoteEvents)
```lua
-- Server fires individual RemoteEvents
InventoryChangedRE:FireClient(player, payload)
```

### After (EventBus + RemoteEventBridge)
```lua
-- Server-side service
local Bus = require(Shared.EventBus).global()
local EventNames = require(Shared.EventNames)

Bus:emit(EventNames.INVENTORY_CHANGED, {
    to = { kind = "player", player = player },
    payload = { action = "add", itemId = itemId, quantity = qty }
})
```

```lua
-- Bridge (server) lives at server/MiningGame/RemoteEventBridge.lua
-- Client receives via client/MiningGame/RemoteEventBridge.client.lua
```

## Client Calls

### Before
```lua
local result = Remotes.RF.GetProfile:InvokeServer()
if result.ok then print(result.data) end
```

### After (ClientRF)
```lua
local ClientRF = require(MiningGame.ClientRF)
local profile, err = ClientRF.call("GetProfile")
```

## Validation & Rate Limiting
- Every RF with parameters must provide a validator (via `spec.validate`)
- Every RF must have `opts.rateLimitSec` set
- RemoteManager enforces schema validation and token-bucket rate limits per player

## Order of Operations (Server)
1. Ensure `ReplicatedStorage.MiningGame.Remotes` exists
2. Precreate RemoteFunctions: `RFRegistry.precreate(remotesFolder)`
3. Start services: `ServiceManager.start()`
4. Register RFs: `RFRegistry.register(container)`
5. Mark server ready: `MiningGame:SetAttribute("ServerReady", true)`

## Helpful Paths
- RFRegistry: `server/MiningGame/RFRegistry.lua`
- RemoteManager: `server/MiningGame/RemoteManager.lua`
- ServiceContainer: `server/MiningGame/ServiceContainer.lua`
- ServiceManager: `server/MiningGame/ServiceManager.lua`
- RemoteFns specs: `server/MiningGame/RemoteFns/*.rf.lua`
- RemoteEventBridge (server): `server/MiningGame/RemoteEventBridge.lua`
- RemoteEventBridge (client): `client/MiningGame/RemoteEventBridge.client.lua`
- ClientRF: `shared/MiningGame/ClientRF.lua`

## Notes
- Some RFs intentionally return raw maps or scalars; ClientRF unwraps these as plain values
- Most user-facing RFs return top-level `{ ok, success, ... }` shapes
- In Studio, access the container via `_G.MiningGameServices.container`

### Typing the container (optional)
The container module exports a public API type you can reference if you want method-level type annotations without exposing internals:

```lua
-- server/MiningGame/SomeService.lua
type ServiceContainerPublic = require(script.Parent.ServiceContainer).ServiceContainerPublic

function SomeService:Init(container: ServiceContainerPublic)
    local DataService = container:Get("DataService")
    -- ...
end
```

This keeps consumer code strictly typed while the internal container data shape remains private and decoupled.

### Typed service lookups (Get/tryGet)
The container’s public API supports typed lookups using a service name → type map. Calls with string literals return the correct service type without casts.

```lua
-- server/MiningGame/SomeService.lua
type ServiceContainerPublic = require(script.Parent.ServiceContainer).ServiceContainerPublic

function SomeService:Init(container: ServiceContainerPublic)
    -- This is typed as typeof(require(script.Parent.DataService))
    local DataService = container:Get("DataService")
end

-- If you want to annotate a local explicitly:
type Services = require(script.Parent.ServiceIndex).Services
local InventoryService: Services["InventoryService"] = container:Get("InventoryService")
```

Notes:
- The service index lives at `server/MiningGame/ServiceIndex.lua` and is type-only (no runtime values).
- Generic typing kicks in when you pass a string literal; variables typed as `string` will widen the result.

### Strict service validation
The container validates service shape at registration (no normalization). At minimum, `Init(self, container)` is required. If `Start`/`Stop` are present, they must be functions. We can optionally enforce `Start` and `Stop` as required once all services adopt stubs.

### Strict service interface (optional, recommended)
If you want full internal strictness, services can implement the exact lifecycle interface the container enforces. This avoids optional lifecycle methods and guarantees uniform shapes.

```lua
-- server/MiningGame/MyService.lua
type ServiceContainerPublic = require(script.Parent.ServiceContainer).ServiceContainerPublic
type ManagedServiceExact = require(script.Parent.ServiceContainer).ManagedServiceExact

local MyService: ManagedServiceExact = {} :: any

function MyService:Init(container: ServiceContainerPublic)
    -- wiring
end

function MyService:Start(container: ServiceContainerPublic)
    -- start work
end

function MyService:Stop()
    -- cleanup
end

return MyService
```
