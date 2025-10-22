# API Best Practices & Examples

[← Back to API Documentation](API_DOCUMENTATION.md)

[← Back to API Documentation](API_DOCUMENTATION.md)

## Table of Contents

- [Architecture Patterns](#architecture-patterns)
- [Client Implementation](#client-implementation)
- [Server Implementation](#server-implementation)
- [EventBus Patterns](#eventbus-patterns)
- [Performance Optimization](#performance-optimization)
- [Error Handling](#error-handling)
- [Testing](#testing)
- [Complete Examples](#complete-examples)

---

## Architecture Patterns

### Use the Modern Stack

```lua
-- Client-side
local ClientRF = require(MiningGame.ClientRF)
local EventBus = require(MiningGame.EventBus).global()
local EventNames = require(MiningGame.EventNames)
local RequestNames = require(MiningGame.RequestNames)
local Bridge = require(MiningGame.RemoteEventBridge)

-- Server-side (in services)
local EventBus = require(Shared.EventBus).global()
local Result = require(Shared.Result)
local Time = require(Shared.Time)
```

### Service Architecture

```lua
-- Services use dependency injection
function MyService:Init(container)
    self.DataService = container:Get("DataService")
    self.EventBus = EventBus.global()
    self._connections = {}
end

function MyService:Start(container)
    -- Safe to use dependencies
    table.insert(self._connections, 
        self.EventBus:on(EventNames.SOME_EVENT, function(data)
            self:HandleEvent(data)
        end))
end

function MyService:Stop()
    -- Clean up
    for _, conn in ipairs(self._connections) do
        conn:Disconnect()
    end
end
```

## Client Implementation

### 1. Always Use ClientRF

```lua
-- Good: Using ClientRF with automatic Result unwrapping
local profile, err = ClientRF.call("GetProfile")
if not profile then
    warn("Failed to get profile:", err)
    return
end

-- Bad: Direct RemoteFunction invoke
local result = Remotes.RF.GetProfile:InvokeServer() -- Don't do this
```

### 2. Handle Errors Appropriately

```lua
local function safePurchase(itemId)
    local result, err = ClientRF.call("PurchaseItem", itemId)
    
    if result then
        return true, "Purchase successful"
    end
    
    -- Handle specific errors
    if err == "INSUFFICIENT_FUNDS" then
        showNotification("Not enough coins!")
    elseif err == "ITEM_NOT_FOUND" then
        showNotification("Item not available")
    elseif err == "RATE_LIMIT" then
        showNotification("Too many requests, please wait")
    else
        showNotification("Purchase failed")
    end
    
    return false, err
end
```

### 3. Use EventBus for State Updates

```lua
local UIComponent = {}

function UIComponent:Init()
    self.subscriptions = {}
    
    -- Subscribe to events
    table.insert(self.subscriptions,
        EventBus:on(EventNames.CURRENCY_CHANGED, function(data)
            self:UpdateCurrency(data.payload)
        end))
    
    table.insert(self.subscriptions,
        EventBus:on(EventNames.INVENTORY_CHANGED, function(data)
            self:UpdateInventory(data.payload)
        end))
end

function UIComponent:Destroy()
    -- Always clean up subscriptions
    for _, unsub in ipairs(self.subscriptions) do
        unsub()
    end
end
```

### 4. Cache When Appropriate

```lua
local ProfileCache = {
    data = nil,
    lastUpdate = 0,
    UPDATE_INTERVAL = 60 -- seconds
}

function ProfileCache:get()
    local now = Time.mono()
    
    if not self.data or (now - self.lastUpdate) > self.UPDATE_INTERVAL then
        local profile, err = ClientRF.call("GetProfile")
        
        if profile then
            self.data = profile
            self.lastUpdate = now
        elseif self.data then
            -- Use stale data if fetch fails
            warn("Using cached profile due to error:", err)
        end
    end
    
    return self.data
end
```

### 5. Implement Retry Logic

```lua
-- For critical operations
local inventory, err = ClientRF.callWithRetry("GetInventory", 3)
if not inventory then
    -- All retries failed
    showErrorScreen("Failed to load inventory")
    return
end

-- Custom retry with backoff
local function retryWithBackoff(rfName, ...)
    local args = {...}
    local maxRetries = 3
    
    for attempt = 1, maxRetries do
        local result, err = ClientRF.call(rfName, table.unpack(args))
        
        if result then
            return result, nil
        end
        
        -- Don't retry on logical errors
        if err ~= "TIMEOUT" and not err:match("^RF call failed") then
            return nil, err
        end
        
        if attempt < maxRetries then
            task.wait(math.pow(2, attempt - 1)) -- Exponential backoff
        end
    end
    
    return nil, "Max retries exceeded"
end
```

## Server Implementation

### 1. Define RF Specs Properly

```lua
-- In RemoteFns/MyFeature.rf.lua
return {
    {
        name = "MyFunction",
        validate = function(param1: string?, param2: number?)
            if not param1 or #param1 == 0 then
                return false, "param1 required"
            end
            if param2 and param2 < 0 then
                return false, "param2 must be non-negative"
            end
            return true
        end,
        rateLimitSec = 1, -- Required field
        requireProfile = true, -- Default true
        handler = function(ctx, param1: string, param2: number?)
            -- ctx.player always available
            -- ctx.profile available if requireProfile = true
            
            local service = getService("MyService")
            local result = service:DoSomething(ctx.player, param1, param2)
            
            if result then
                return Result.ok(result)
            else
                return Result.err("OPERATION_FAILED", "Could not complete")
            end
        end
    }
}
```

### 2. Emit Events Properly

```lua
-- In service methods
function InventoryService:AddItem(player, itemId, quantity)
    -- Business logic
    local success = self:InternalAddItem(player, itemId, quantity)
    
    if success then
        -- Emit event for UI updates
        self.EventBus:emit(EventNames.INVENTORY_CHANGED, {
            to = {kind = "player", player = player},
            payload = {
                action = "add",
                itemId = itemId,
                quantity = quantity,
                total = self:GetItemCount(player, itemId)
            }
        })
    end
    
    return success
end
```

### 3. Use Result Consistently

```lua
-- Good: Explicit Result usage
function handler(ctx, itemId: string)
    if not isValidItem(itemId) then
        return Result.err("INVALID_ITEM", "Item does not exist")
    end
    
    local owned = InventoryService:HasItem(ctx.player, itemId)
    if owned then
        return Result.err("ALREADY_OWNED", "You already have this item")
    end
    
    local success = InventoryService:GrantItem(ctx.player, itemId)
    if success then
        return Result.ok({itemId = itemId, granted = true})
    else
        return Result.err("GRANT_FAILED", "Could not grant item")
    end
end
```

## EventBus Patterns

### 1. Event Priority

```lua
-- Critical handlers run first
EventBus:on(EventNames.CURRENCY_CHANGED, criticalHandler, 10)

-- Normal priority (default 50)
EventBus:on(EventNames.CURRENCY_CHANGED, normalHandler)

-- Low priority cleanup
EventBus:on(EventNames.CURRENCY_CHANGED, cleanupHandler, 100)
```

### 2. One-Time Subscriptions

```lua
-- Auto-unsubscribe after first event
EventBus:once(EventNames.FIRST_DIG, function(data)
    showTutorial("Great job! You dug your first block!")
end)
```

### 3. Fast Path for Performance

```lua
-- Mark high-frequency events
EventBus:markFastPath(EventNames.DIG_FEEDBACK)
EventBus:markFastPath(EventNames.PARTICLE_EFFECT)
```

### 4. Middleware for Debugging

```lua
-- Development only
if RunService:IsStudio() then
    EventBus:use(function(ctx, next)
        local start = Time.mono()
        next()
        local elapsed = Time.mono() - start
        
        if elapsed > 0.016 then -- Longer than a frame
            warn(string.format("Slow event handler: %s took %.2fms", 
                ctx.event, elapsed * 1000))
        end
    end)
end
```

## Performance Optimization

### 1. Batch Operations

```lua
-- Good: Single call for multiple items
local results, err = ClientRF.call("SellMultipleItems", {
    ["diamond"] = 5,
    ["gold"] = 10,
    ["iron"] = 20
})

-- Bad: Multiple individual calls
for itemId, count in pairs(items) do
    ClientRF.call("SellItems", itemId, count) -- Inefficient
end
```

### 2. Debounce User Input

```lua
local Debounce = {}
Debounce.__index = Debounce

function Debounce.new(cooldown)
    return setmetatable({
        cooldown = cooldown,
        nextAllowed = 0
    }, Debounce)
end

function Debounce:run(callback)
    local now = Time.mono()
    if now < self.nextAllowed then
        return false
    end
    
    self.nextAllowed = now + self.cooldown
    callback()
    return true
end

-- Usage
local digDebounce = Debounce.new(0.1)

UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        digDebounce:run(function()
            local ClientRF = require(MiningGame.ClientRF)
            ClientRF.call("RequestDig", targetPosition)
        end)
    end
end)
```

### 3. Connection Pooling

```lua
-- Reuse event connections
local ConnectionPool = {}

function ConnectionPool:get(event, handler)
    local key = tostring(event) .. tostring(handler)
    
    if not self[key] then
        self[key] = EventBus:on(event, handler)
    end
    
    return self[key]
end

function ConnectionPool:cleanup()
    for _, unsub in pairs(self) do
        if type(unsub) == "function" then
            unsub()
        end
    end
end
```

## Error Handling

### 1. Comprehensive Error Codes

```lua
local ErrorCodes = {
    -- Network/System
    TIMEOUT = "Request timed out",
    RATE_LIMIT = "Too many requests",
    NO_PROFILE = "Profile not loaded",
    INTERNAL = "Server error",
    
    -- Validation
    INVALID_INPUT = "Invalid input",
    MISSING_PARAM = "Required parameter missing",
    
    -- Business Logic
    INSUFFICIENT_FUNDS = "Not enough currency",
    INSUFFICIENT_ITEMS = "Not enough items",
    ITEM_NOT_FOUND = "Item doesn't exist",
    ALREADY_OWNED = "Already purchased",
    MAX_LEVEL = "Maximum level reached",
    ON_COOLDOWN = "Action on cooldown"
}

function handleError(err)
    local message = ErrorCodes[err] or "Unknown error"
    showNotification(message)
end
```

### 2. Graceful Degradation

```lua
-- Fall back to defaults on error
local function getPlayerSettings()
    local settings, err = ClientRF.call("GetSettings")
    
    if not settings then
        warn("Failed to load settings:", err)
        -- Use defaults
        return {
            soundEnabled = true,
            particlesEnabled = true,
            theme = "default"
        }
    end
    
    return settings
end
```

## Testing

### 1. Unit Test RF Specs

```lua
-- Test validation
local spec = require(RemoteFns.Inventory)[1]

-- Valid inputs
assert(spec.validate("sword", 5) == true)
assert(spec.validate("shield", 1) == true)

-- Invalid inputs
local valid, err = spec.validate(nil, 5)
assert(valid == false)
assert(err == "Missing itemType")

local valid, err = spec.validate("sword", -1)
assert(valid == false)
assert(err == "Invalid count")
```

### 2. Integration Testing

```lua
-- In Studio console
local ClientRF = require(game.ReplicatedStorage.MiningGame.ClientRF)

-- Test successful flow
local profile = ClientRF.call("GetProfile")
assert(profile, "Should get profile")
assert(profile.coins >= 0, "Coins should be non-negative")

-- Test error handling
local result, err = ClientRF.call("PurchaseItem", "invalid_item_xyz")
assert(not result, "Should fail for invalid item")
assert(err == "ITEM_NOT_FOUND", "Should return correct error")

-- Test rate limiting
for i = 1, 20 do
    local _, err = ClientRF.call("RequestDig", Vector3.new(0,0,0))
    if err == "RATE_LIMIT" then
        print("Rate limited at request", i)
        break
    end
end
```

### 3. Event Testing

```lua
-- Test event flow
local received = false
local unsub = EventBus:on("test.event", function(data)
    received = true
    assert(data.value == 123)
end)

EventBus:emit("test.event", {value = 123})
assert(received, "Should receive event")

unsub()
```

## Complete Examples

### Client UI Component

```lua
local CurrencyDisplay = {}
CurrencyDisplay.__index = CurrencyDisplay

function CurrencyDisplay.new(gui)
    local self = setmetatable({}, CurrencyDisplay)
    
    self.gui = gui
    self.coinsLabel = gui.CoinsLabel
    self.gemsLabel = gui.GemsLabel
    self.subscriptions = {}
    
    self:init()
    return self
end

function CurrencyDisplay:init()
    -- Initial load
    local profile, err = ClientRF.call("GetProfile")
    if profile then
        self:updateDisplay(profile.coins, profile.gems)
    else
        warn("Failed to load initial currency:", err)
    end
    
    -- Subscribe to updates
    table.insert(self.subscriptions,
        EventBus:on(EventNames.CURRENCY_CHANGED, function(data)
            local p = data.payload
            if p.currency == "coins" then
                self:updateCoins(p.balance, p.delta)
            elseif p.currency == "gems" then
                self:updateGems(p.balance, p.delta)
            end
        end))
end

function CurrencyDisplay:updateDisplay(coins, gems)
    self.coinsLabel.Text = tostring(coins or 0)
    self.gemsLabel.Text = tostring(gems or 0)
end

function CurrencyDisplay:updateCoins(balance, delta)
    self.coinsLabel.Text = tostring(balance)
    
    if delta and delta > 0 then
        self:showAnimation(self.coinsLabel, "+" .. delta, Color3.new(1, 1, 0))
    end
end

function CurrencyDisplay:updateGems(balance, delta)
    self.gemsLabel.Text = tostring(balance)
    
    if delta and delta > 0 then
        self:showAnimation(self.gemsLabel, "+" .. delta, Color3.new(0, 1, 1))
    end
end

function CurrencyDisplay:showAnimation(label, text, color)
    -- Create floating text animation
    local floater = label:Clone()
    floater.Text = text
    floater.TextColor3 = color
    floater.Parent = label.Parent
    
    -- Animate
    local tween = TweenService:Create(floater, 
        TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {
            Position = UDim2.new(floater.Position.X.Scale, 
                               floater.Position.X.Offset,
                               floater.Position.Y.Scale - 0.1,
                               floater.Position.Y.Offset),
            TextTransparency = 1
        })
    
    tween:Play()
    tween.Completed:Connect(function()
        floater:Destroy()
    end)
end

function CurrencyDisplay:destroy()
    for _, unsub in ipairs(self.subscriptions) do
        unsub()
    end
end

return CurrencyDisplay
```

### Server Service with Events

```lua
local InventoryService = {}
InventoryService.__index = InventoryService

function InventoryService.new()
    return setmetatable({
        inventories = {},
        maxStackSize = 999
    }, InventoryService)
end

function InventoryService:Init(container)
    self.DataService = container:Get("DataService")
    self.EventBus = EventBus.global()
end

function InventoryService:Start(container)
    -- Service is ready
end

function InventoryService:AddItem(player: Player, itemId: string, quantity: number)
    assert(quantity > 0, "Quantity must be positive")
    
    local inventory = self:GetInventory(player)
    local current = inventory[itemId] or 0
    local new = math.min(current + quantity, self.maxStackSize)
    local added = new - current
    
    if added > 0 then
        inventory[itemId] = new
        
        -- Emit event
        self.EventBus:emit(EventNames.INVENTORY_CHANGED, {
            to = {kind = "player", player = player},
            payload = {
                action = "add",
                itemId = itemId,
                quantity = added,
                total = new
            }
        })
        
        -- Check achievements
        self.EventBus:emit(EventNames.ACHIEVEMENT_CHECK, {
            to = {kind = "server"},
            payload = {
                player = player,
                type = "inventory",
                itemId = itemId,
                count = new
            }
        })
    end
    
    return added
end

function InventoryService:RemoveItem(player: Player, itemId: string, quantity: number)
    assert(quantity > 0, "Quantity must be positive")
    
    local inventory = self:GetInventory(player)
    local current = inventory[itemId] or 0
    
    if current < quantity then
        return false, "Insufficient items"
    end
    
    inventory[itemId] = current - quantity
    
    if inventory[itemId] == 0 then
        inventory[itemId] = nil
    end
    
    -- Emit event
    self.EventBus:emit(EventNames.INVENTORY_CHANGED, {
        to = {kind = "player", player = player},
        payload = {
            action = "remove",
            itemId = itemId,
            quantity = quantity,
            total = inventory[itemId] or 0
        }
    })
    
    return true
end

function InventoryService:GetInventory(player: Player)
    if not self.inventories[player] then
        local profile = self.DataService:GetPlayerData(player)
        self.inventories[player] = profile and profile.inventory or {}
    end
    return self.inventories[player]
end

function InventoryService:Stop()
    -- Save all inventories
    for player, inventory in pairs(self.inventories) do
        local profile = self.DataService:GetPlayerData(player)
        if profile then
            profile.inventory = inventory
        end
    end
end

return InventoryService.new()
```

## See Also

- [Remote Architecture](REMOTE_ARCHITECTURE.md) - Complete remote system
- [EventBus System](EVENTBUS_SYSTEM.md) - Event patterns
- [Service Architecture](SERVICE_ARCHITECTURE.md) - Service patterns
- [API RemoteFunctions](API_REMOTE_FUNCTIONS.md) - RF reference
- [API RemoteEvents](API_REMOTE_EVENTS.md) - Event reference
