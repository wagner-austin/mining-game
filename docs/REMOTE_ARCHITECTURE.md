# Remote Architecture

## Overview

The Mining Game uses a sophisticated remote communication architecture with centralized management, strict validation, rate limiting, and automatic Result normalization. This system ensures type-safe, performant client-server communication.

## Quick Start

### Client Usage

```lua
-- Using ClientRF for RemoteFunction calls
local ClientRF = require(MiningGame.ClientRF)

-- Make a call with automatic Result unwrapping
local profile, err = ClientRF.call("GetProfile")
if not profile then
    warn("Failed to get profile:", err)
    return
end

-- Use the data
print("Player level:", profile.level)
```

### Server Registration

```lua
-- In a RemoteFns spec file (factory form is supported)
return function(container)
    return {
        {
            name = "GetProfile",
            validate = SchemaValidators.Any, -- no params
            opts = { requireProfile = true, rateLimitSec = 1 },
            handler = function(ctx)
                return ctx.profile
            end
        }
    }
end
```

## Architecture Components

Current implementation (as of this refactor): 15 spec modules registering 59 RemoteFunctions.

### RFRegistry (`server/MiningGame/RFRegistry.lua`)

Central registration system that:
- Auto-discovers RF specs from `RemoteFns/` directory
- Wraps handlers with timing/error-capture middleware
- Relies on RemoteManager for response normalization
- Filters debug-only RFs in production
- Bridges spec.validate to RemoteManager's required `opts.schema`

### RemoteManager (`server/MiningGame/RemoteManager.lua`)

Core infrastructure providing:
- Strict schema validation and rate limiting enforcement
- Context injection (player, profile)
- Automatic RemoteFunction/Event creation
- Registry tracking for runtime inspection
- Defensive error handling

### RemoteFns Directory

Organized specification modules:
```
server/MiningGame/RemoteFns/
├── Core.rf.lua           # Profile, metrics, server time
├── Dig.rf.lua            # Mining mechanics
├── Inventory.rf.lua      # Item management
├── Monetization.rf.lua   # Purchases, products
├── Settings.rf.lua       # User preferences
├── ThemeSettings.rf.lua  # Visual customization
├── Composition.rf.lua    # Material mixing
├── Upgrade.rf.lua        # Player progression
├── Item.rf.lua           # World items
├── FloatingIsland.rf.lua # Special features
└── [Debug modules]       # Studio-only features
```

### ClientRF (`shared/MiningGame/ClientRF.lua`)

Client helper providing:
- Automatic Result unwrapping
- Timeout protection
- Retry with exponential backoff
- Type-safe wrappers
- Clean error messages

## Remote Function Lifecycle

### Server Startup Sequence

- Ensure `ReplicatedStorage.MiningGame.Remotes` exists (and `Remotes.EventBus` RemoteEvent).
- Precreate RemoteFunctions via `RFRegistry.precreate(remotesFolder)` to avoid missing-remote races during boot.
- Configure EventBus (queue limits, optional drop logging).
- Start services with `ServiceManager.start()` (dependency injection container).
- In Studio, expose `_G.MiningGameServices = { container = ... }` for debugging.
- Register RFs after services are live: `RFRegistry.register(container)`.
- Mark readiness: `MiningGame:SetAttribute("ServerReady", true)`.

```lua
-- init.server.lua (excerpt)
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local remotesFolder = MiningGame:FindFirstChild("Remotes") or Instance.new("Folder")
remotesFolder.Name = "Remotes"
remotesFolder.Parent = MiningGame

-- Ensure EventBus RemoteEvent exists
if not remotesFolder:FindFirstChild("EventBus") then
    local re = Instance.new("RemoteEvent"); re.Name = "EventBus"; re.Parent = remotesFolder
end

local RFRegistry = require(script.RFRegistry)
RFRegistry.precreate(remotesFolder)

local ServiceManager = require(script.ServiceManager)
local container = ServiceManager.start()

local stats = RFRegistry.register(container)
MiningGame:SetAttribute("ServerReady", true)
```

### 1. Specification Definition

```lua
-- In server/MiningGame/RemoteFns/Inventory.rf.lua
local SchemaValidators = require(Shared.SchemaValidators)

return {
    {
        name = "SellItems",
        validate = function(itemType: string?, count: number?)
            if not itemType then return false, "Missing itemType" end
            if not count or count <= 0 then return false, "Invalid count" end
            return true
        end,
        rateLimitSec = 0.5,
        handler = function(ctx, itemType: string, count: number)
            local InventoryService = getService("InventoryService")
            return InventoryService:SellItems(ctx.player, itemType, count)
        end
    }
}
```

### 2. Registration via RFRegistry

```lua
-- RFRegistry automatically:
-- 1. Discovers spec files
-- 2. Wraps with middleware (timing, error capture)
-- 3. Registers with RemoteManager

local function wrapWithMiddleware(spec, handler)
    return function(ctx, ...)
        local t0 = Time.mono()
        local ok, res = pcall(handler, ctx, ...)
        local dt = (Time.mono() - t0) * 1000

        if not ok then
            -- Return a top-level shape for consistency in Studio logs
            return { ok = false, success = false, err = tostring(res), time_ms = dt }
        end

        -- Pass through Result-like tables (have ok field) and raw values/maps.
        if type(res) == "table" and res.ok ~= nil then
            res.time_ms = res.time_ms or dt
            return res
        end
        return res
    end
end
```

### 3. RemoteManager Processing

```lua
-- RemoteManager enforces:
-- 1. Rate limiting (token bucket)
-- 2. Schema validation
-- 3. Optional profile loading (default true)
-- 4. Error boundaries

rf.OnServerInvoke = function(player: Player, ...: any)
    -- Rate limit: 1 token per rateLimitSec, burst 1
    local rate = (rateLimitSec and rateLimitSec > 0) and (1 / rateLimitSec) or math.huge
    if (rate ~= math.huge) and RateLimitService and not RateLimitService.allow(player.UserId, "rf:"..name, rate, 1) then
        return Result.err("RATE_LIMIT", "Too many requests")
    end

    -- Schema validation
    local valid, msg = schema(...)
    if not valid then
        return Result.err("INVALID_INPUT", msg or "Invalid input")
    end

    -- Build context
    local ctx = { player = player, profile = nil }
    if requireProfile then
        if not DataService:EnsureLoaded(player) then
            return Result.err("NO_PROFILE", "Profile not loaded")
        end
        local profile = DataService:GetPlayerData(player)
        if not profile then
            return Result.err("NO_PROFILE", "Profile unavailable")
        end
        ctx.profile = profile
    end

    -- Execute handler with error catching
    local ok, res = xpcall(function()
        return handler(ctx, ...)
    end, debug.traceback)

    if not ok then
        return Result.err("INTERNAL", "Something went wrong")
    end

    -- Pass through Result objects or top-level shapes unchanged
    if Result.isResult(res) then return res end
    if type(res) == "table" and (res.ok ~= nil or res.err ~= nil or res.success ~= nil) then
        return res
    end

    -- Wrap scalars/raw maps so ClientRF unwraps to value
    return Result.ok(res)
end
```

### 4. Client Invocation

```lua
-- Client makes call
local inventory, err = ClientRF.call("GetInventory")

-- ClientRF automatically:
-- 1. Finds the RemoteFunction
-- 2. Applies timeout protection
-- 3. Unwraps Result format
-- 4. Returns (value, error) tuple
```

## Result Format

All RemoteFunctions return standardized Result format:

```lua
-- Success
{
    ok = true,
    data = <value>
}

-- Error
{
    ok = false,
    err = "ERROR_CODE",
    reason = "Human readable message"
}
```

### Result Utility

```lua
local Result = require(MiningGame.Result)

-- Creating results
return Result.ok(value)                    -- Success
return Result.err("CODE", "message")       -- Error

-- Checking results
if Result.isOk(result) then ... end
if Result.isErr(result) then ... end

-- Unwrapping
local value = Result.unwrap(result)        -- Errors if not ok
local value = Result.unwrapOr(result, default)
```

## Schema Validation

### Built-in Validators

```lua
local SchemaValidators = require(MiningGame.SchemaValidators)

-- No parameters / any params
validate = SchemaValidators.Any

-- Common types
validate = SchemaValidators.String
validate = SchemaValidators.PositiveNumber
validate = SchemaValidators.PositiveInteger
validate = SchemaValidators.Vector3

-- Multiple parameters
validate = SchemaValidators.Multiple(
    SchemaValidators.String,
    SchemaValidators.PositiveInteger
)
```

### Custom Validators

```lua
validate = function(itemId: string?, quantity: number?)
    -- Check required parameters
    if not itemId then 
        return false, "itemId required"
    end
    
    -- Validate types
    if type(itemId) ~= "string" then
        return false, "itemId must be string"
    end
    
    -- Validate values
    if quantity and quantity <= 0 then
        return false, "quantity must be positive"
    end
    
    return true
end
```

## Rate Limiting

### Configuration

```lua
-- In RF spec
{
    name = "RequestDig",
    rateLimitSec = 0.1,  -- Max 10 requests per second
    -- ...
}

-- Special values
rateLimitSec = 0      -- No rate limiting
rateLimitSec = 60     -- Once per minute
rateLimitSec = 3600   -- Once per hour
```

### Rate Limit Service

```lua
-- RateLimitService (when available)
-- Uses token bucket algorithm
-- 1 token per rateLimitSec, burst of 1

function RateLimitService:allow(userId: number, key: string, rate: number, burst: number)
    local bucket = self:getBucket(userId, key)
    
    -- Refill tokens based on time elapsed
    local now = os.clock()
    local elapsed = now - bucket.lastRefill
    bucket.tokens = math.min(burst, bucket.tokens + elapsed * rate)
    bucket.lastRefill = now
    
    -- Check if request allowed
    if bucket.tokens >= 1 then
        bucket.tokens = bucket.tokens - 1
        return true
    end
    
    return false
end
```

## Context System

### Context Structure

```lua
export type Context = {
    player: Player,           -- Always present
    profile: PlayerStats?     -- Present if requireProfile = true
}
```

### Using Context

```lua
handler = function(ctx: Context, ...)
    -- Access player
    local player = ctx.player
    
    -- Access profile (if required)
    local profile = ctx.profile
    if not profile then
        return Result.err("NO_PROFILE", "Profile not loaded")
    end
    
    -- Use services
    local inventory = InventoryService:GetInventory(player)
    
    return Result.ok({
        level = profile.level,
        inventory = inventory
    })
end
```

### Profile Requirements

```lua
-- Profile required (default)
{
    name = "GetInventory",
    requireProfile = true,  -- Can be omitted (default true)
    handler = function(ctx)
        -- ctx.profile guaranteed to exist
        return ctx.profile.inventory
    end
}

-- Profile not required
{
    name = "GetServerTime", 
    requireProfile = false,  -- Must be explicit
    handler = function(ctx)
        -- ctx.profile may be nil
        return os.time()
    end
}
```

## Debug-Only RemoteFunctions

### Defining Debug RFs

```lua
-- In RemoteFns/Debug.rf.lua
return {
    {
        name = "DebugResetProfile",
        debugOnly = true,  -- Only available in Studio
        validate = SchemaValidators.None,
        rateLimitSec = 1,
        handler = function(ctx)
            DataService:ResetProfile(ctx.player)
            return Result.ok("Profile reset")
        end
    }
}
```

### Studio Detection

```lua
-- RFRegistry filters debug RFs
if spec.debugOnly and not RunService:IsStudio() then
    log:debug("Skipping debug-only RF: %s", spec.name)
    continue
end
```

## Error Handling

### Server-Side Errors

```lua
handler = function(ctx, itemId: string)
    -- Explicit error
    if not isValidItem(itemId) then
        return Result.err("INVALID_ITEM", "Item does not exist")
    end
    
    -- Caught errors become INTERNAL
    error("Unexpected error") -- Becomes Result.err("INTERNAL", "Server error")
end
```

### Client-Side Handling

```lua
local data, err = ClientRF.call("PurchaseItem", "sword")

if not data then
    -- Handle specific errors
    if err == "INSUFFICIENT_FUNDS" then
        showNotification("Not enough coins!")
    elseif err == "INVALID_ITEM" then
        showNotification("Item not available")
    elseif err == "RATE_LIMIT" then
        showNotification("Too many requests, please wait")
    else
        showNotification("Purchase failed: " .. tostring(err))
    end
    return
end

-- Success
showNotification("Purchase successful!")
```

## Best Practices

### 1. Spec Organization

```lua
-- Group related RFs in single file
-- RemoteFns/Inventory.rf.lua
return {
    { name = "GetInventory", ... },
    { name = "SellItems", ... },
    { name = "EquipItem", ... },
    { name = "UnequipItem", ... },
}
```

### 2. Validation Patterns

```lua
-- Reusable validator
local function validateItemOperation(itemId: string?, quantity: number?)
    if not itemId or type(itemId) ~= "string" then
        return false, "Invalid itemId"
    end
    if quantity and (type(quantity) ~= "number" or quantity <= 0) then
        return false, "Invalid quantity"
    end
    return true
end

-- Use in multiple specs
{ validate = validateItemOperation, ... }
```

### 3. Error Codes

```lua
-- Define consistent error codes
local ErrorCodes = {
    -- Input validation
    INVALID_INPUT = "INVALID_INPUT",
    MISSING_PARAM = "MISSING_PARAM",
    
    -- Business logic
    INSUFFICIENT_FUNDS = "INSUFFICIENT_FUNDS",
    ITEM_NOT_FOUND = "ITEM_NOT_FOUND",
    ALREADY_OWNED = "ALREADY_OWNED",
    
    -- System
    RATE_LIMIT = "RATE_LIMIT",
    NOT_AVAILABLE = "NOT_AVAILABLE",
    INTERNAL = "INTERNAL",
}
```

### 4. Service Access

```lua
-- Cache service references
local InventoryService
local function getInventoryService()
    if not InventoryService then
        InventoryService = getService("InventoryService")
    end
    return InventoryService
end

-- Use in handler
handler = function(ctx)
    local service = getInventoryService()
    return service:GetInventory(ctx.player)
end
```

## Testing

### Unit Testing Specs

```lua
-- Test validation
local spec = require(RemoteFns.Inventory)[1]
assert(spec.validate("sword", 5) == true)
assert(spec.validate(nil, 5) == false)
assert(spec.validate("sword", -1) == false)
```

### Integration Testing

```lua
-- In Studio console
local ClientRF = require(game.ReplicatedStorage.MiningGame.ClientRF)

-- Test successful call
local inventory, err = ClientRF.call("GetInventory")
assert(inventory and not err)

-- Test error handling
local result, err = ClientRF.call("SellItems", { invalid_item = 999 })
assert(not result)

-- Test rate limiting
for i = 1, 20 do
    local _, err = ClientRF.call("RequestDig", Vector3.new(0,0,0))
    if err == "RATE_LIMIT" then
        print("Rate limited at request", i)
        break
    end
end
```

## Migration from Legacy Pattern

### Before (Scattered Remotes)

```lua
-- In InventoryRemotes.lua
local RF = Remotes.RF.SellItems

RF.OnServerInvoke = function(player, itemType, count)
    -- No validation
    -- No rate limiting
    -- No error handling
    return InventoryService:SellItems(player, itemType, count)
end
```

### After (RFRegistry Pattern)

```lua
-- In RemoteFns/Inventory.rf.lua
{
    name = "SellItems",
    validate = validateItemOperation,
    rateLimitSec = 0.5,
    handler = function(ctx, itemType: string, count: number)
        return getService("InventoryService"):SellItems(
            ctx.player, itemType, count
        )
    end
}
```

## Performance Monitoring

### Timing Middleware

```lua
-- RFRegistry adds automatic timing
-- Warns on slow RFs (>100ms)
[RFRegistry] GetInventory took 150ms (slow!)
```

### Debug Output

```lua
-- In Studio with verbose logging
[RFRegistry] Loaded 15 specs from RemoteFns/
[RFRegistry] Registered RF: GetProfile
[RFRegistry] Registered RF: SellItems
[RemoteManager] RF SellItems rate limited Player1
```

### Metrics Collection

```lua
-- Add custom metrics
local metrics = {}

local function metricsMiddleware(spec, handler)
    return function(ctx, ...)
        metrics[spec.name] = (metrics[spec.name] or 0) + 1
        return handler(ctx, ...)
    end
end
```

## Common Patterns

### Batch Operations

```lua
{
    name = "SellMultipleItems",
    validate = function(items: {[string]: number}?)
        if type(items) ~= "table" then
            return false, "Expected table of items"
        end
        for itemId, count in pairs(items) do
            if type(itemId) ~= "string" or type(count) ~= "number" then
                return false, "Invalid item entry"
            end
        end
        return true
    end,
    opts = { rateLimitSec = 1 },
    handler = function(ctx, items)
        local results = {}
        for itemId, count in pairs(items) do
            results[itemId] = InventoryService:SellItems(
                ctx.player, itemId, count
            )
        end
        return Result.ok(results)
    end
}
```

### Pagination

```lua
{
    name = "GetLeaderboard",
    validate = function(offset: number?, limit: number?)
        if offset ~= nil and (type(offset) ~= "number" or offset < 0) then return false, "Invalid offset" end
        if limit  ~= nil and (type(limit)  ~= "number" or limit  <= 0) then return false, "Invalid limit"  end
        return true
    end,
    opts = { rateLimitSec = 2 },
    handler = function(ctx, offset: number?, limit: number?)
        offset = offset or 0
        limit = math.min(limit or 50, 100) -- Cap at 100
        
        local entries = LeaderboardService:GetEntries(offset, limit)
        return Result.ok({
            entries = entries,
            offset = offset,
            hasMore = #entries == limit
        })
    end
}
```

## See Also

- [Service Architecture](SERVICE_ARCHITECTURE.md) - Service system
- [EventBus System](EVENTBUS_SYSTEM.md) - Event communication
- [API Documentation](API_DOCUMENTATION.md) - Complete RF/RE reference
- [Migration Guide Q1 2025](MIGRATION_GUIDE_Q1_2025.md) - Migration steps
