# API Best Practices & Examples

[← Back to API Documentation](API_DOCUMENTATION.md)

## Table of Contents

- [Client Implementation](#client-implementation)
- [Performance Optimization](#performance-optimization)
- [Error Handling](#error-handling)
- [Testing Checklist](#testing-checklist)
- [Complete Client Example](#complete-client-example)
- [Migration Notes](#migration-notes)

---

## Client Implementation

### 1. Always Check Responses

Never assume a RemoteFunction call succeeded:

```lua
local result = Remotes.RF.PurchaseUpgrade:InvokeServer("speed")
if result.success then
    -- Handle success
    updateUpgradeUI(result.newLevel, result.nextCost)
else
    -- Handle failure
    warn("Purchase failed:", result.reason)
    showErrorMessage(result.reason)
end
```

### 2. Cache GetProfile() Results

Avoid unnecessary network calls by caching profile data:

```lua
local ProfileCache = {}
ProfileCache.data = nil
ProfileCache.lastUpdate = 0
ProfileCache.UPDATE_INTERVAL = 60 -- seconds

function ProfileCache:get()
    local now = tick()
    if not self.data or (now - self.lastUpdate) > self.UPDATE_INTERVAL then
        local success, result = pcall(function()
            return Remotes.RF.GetProfile:InvokeServer()
        end)
        
        if success and result then
            self.data = result
            self.lastUpdate = now
        end
    end
    return self.data
end

-- Usage
local profile = ProfileCache:get()
if profile then
    displayStats(profile.effectiveStats)
end
```

### 3. Debounce User Actions

Prevent spam and improve UX:

```lua
local Debounce = {}
Debounce.__index = Debounce

function Debounce.new(cooldown)
    return setmetatable({
        cooldown = cooldown or 0.1,
        active = false
    }, Debounce)
end

function Debounce:run(callback)
    if self.active then return false end
    self.active = true
    
    task.spawn(function()
        callback()
        task.wait(self.cooldown)
        self.active = false
    end)
    
    return true
end

-- Usage
local digDebounce = Debounce.new(0.1)

mouse.Button1Down:Connect(function()
    digDebounce:run(function()
        local result = Remotes.RF.RequestDig:InvokeServer(targetPos)
        handleDigResult(result)
    end)
end)
```

### 4. Handle Connection Failures

Wrap remote calls in pcall for safety:

```lua
local function safeInvoke(remoteFunction, ...)
    local success, result = pcall(function()
        return remoteFunction:InvokeServer(...)
    end)
    
    if not success then
        warn("Remote invoke failed:", result)
        return {
            success = false,
            reason = "Connection error"
        }
    end
    
    return result
end

-- Usage
local result = safeInvoke(Remotes.RF.GetProfile)
if result and result.success ~= false then
    updateUI(result)
end
```

---

## Performance Optimization

### 1. Batch Operations

Combine multiple operations when possible:

```lua
-- BAD: Multiple individual sells
for itemId, count in pairs(itemsToSell) do
    Remotes.RF.SellItems:InvokeServer({[itemId] = count})
end

-- GOOD: Single batched sell
Remotes.RF.SellItems:InvokeServer(itemsToSell)
```

### 2. Use Events Instead of Polling

Listen to events rather than repeatedly requesting data:

```lua
-- BAD: Polling for currency
while true do
    local profile = Remotes.RF.GetProfile:InvokeServer()
    updateCurrency(profile.coins)
    wait(1)
end

-- GOOD: Event-driven updates
Remotes.RE.OnCurrencyChanged.OnClientEvent:Connect(function(data)
    if data.coins then
        updateCurrency(data.coins)
    end
end)
```

### 3. Implement Client-Side Validation

Validate before sending to reduce failed requests:

```lua
local function purchaseUpgrade(upgradeType)
    local profile = ProfileCache:get()
    if not profile then return end
    
    local currentLevel = profile.upgrades[upgradeType]
    local cost = calculateUpgradeCost(upgradeType, currentLevel)
    
    -- Client-side validation
    if profile.coins < cost then
        showErrorMessage("Not enough coins!")
        return
    end
    
    -- Server will still validate, but this improves UX
    local result = Remotes.RF.PurchaseUpgrade:InvokeServer(upgradeType)
    handlePurchaseResult(result)
end
```

### 4. Connection Management

Store and clean up connections properly:

```lua
local ConnectionManager = {}
ConnectionManager.connections = {}

function ConnectionManager:connect(name, event, handler)
    -- Disconnect existing if any
    if self.connections[name] then
        self.connections[name]:Disconnect()
    end
    
    -- Store new connection
    self.connections[name] = event:Connect(handler)
end

function ConnectionManager:disconnect(name)
    if self.connections[name] then
        self.connections[name]:Disconnect()
        self.connections[name] = nil
    end
end

function ConnectionManager:disconnectAll()
    for name, connection in pairs(self.connections) do
        connection:Disconnect()
    end
    self.connections = {}
end

-- Usage
ConnectionManager:connect("currency", 
    Remotes.RE.OnCurrencyChanged.OnClientEvent,
    onCurrencyChanged
)

-- Clean up when UI is destroyed
gui.AncestryChanged:Connect(function()
    if not gui.Parent then
        ConnectionManager:disconnectAll()
    end
end)
```

---

## Error Handling

### Standard Error Response Pattern

All RemoteFunctions follow this pattern:

```lua
-- Success response
{
    success = true,
    -- ... additional data
}

-- Error response
{
    success = false,
    reason = string  -- Human-readable error message
}
```

### Error Handler Example

```lua
local ErrorHandler = {}

ErrorHandler.messages = {
    ["Not enough coins"] = "You need more coins to purchase this!",
    ["On cooldown"] = "Please wait before trying again.",
    ["Data not loaded"] = "Your data is still loading, please wait.",
    ["Studio only"] = "This feature is only available in Studio.",
    ["Not authorized"] = "You don't have permission to do this."
}

function ErrorHandler:handle(result)
    if result.success then
        return true
    end
    
    local message = self.messages[result.reason] or result.reason
    
    -- Show error to player
    game.StarterGui:SetCore("SendNotification", {
        Title = "Error",
        Text = message,
        Duration = 3
    })
    
    warn("API Error:", result.reason)
    return false
end

-- Usage
local result = Remotes.RF.PurchaseUpgrade:InvokeServer("speed")
if ErrorHandler:handle(result) then
    -- Success path
    updateUpgradeUI(result)
end
```

---

## Testing Checklist

### Core Functionality
- [ ] Dig request → terrain update → loot grant
- [ ] Currency updates propagate to UI
- [ ] Inventory operations (add/remove/equip)
- [ ] Purchase flows complete successfully
- [ ] Rate limiting prevents spam

### Error Handling
- [ ] Network failures handled gracefully
- [ ] Invalid input shows appropriate errors
- [ ] Insufficient funds prevented client-side
- [ ] Cooldowns enforced properly

### Performance
- [ ] No memory leaks from event connections
- [ ] Debouncing prevents request spam
- [ ] UI updates batched appropriately
- [ ] Profile caching reduces network calls

### Mobile
- [ ] Touch inputs trigger correct functions
- [ ] UI scales properly on different screens
- [ ] Performance acceptable on low-end devices
- [ ] Network lag doesn't break functionality

---

## Complete Client Example

Here's a complete example of a well-structured client:

```lua
--!strict
-- MiningGameClient.client.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Remotes = require(MiningGame:WaitForChild("Remotes"))

-- Modules
local ProfileCache = {}
local ConnectionManager = {}
local Debounce = {}

-- Profile Cache Implementation
ProfileCache.data = nil
ProfileCache.lastUpdate = 0

function ProfileCache:get()
    if not self.data or tick() - self.lastUpdate > 60 then
        local success, result = pcall(function()
            return Remotes.RF.GetProfile:InvokeServer()
        end)
        
        if success and result then
            self.data = result
            self.lastUpdate = tick()
        end
    end
    return self.data
end

-- Connection Manager Implementation
ConnectionManager.connections = {}

function ConnectionManager:init()
    -- Currency updates
    self:connect("currency", Remotes.RE.OnCurrencyChanged.OnClientEvent, function(data)
        if data.coins then
            updateCoinDisplay(data.coins)
        end
        if data.gems then
            updateGemDisplay(data.gems)
        end
    end)
    
    -- Inventory updates
    self:connect("inventory", Remotes.RE.OnInventoryChanged.OnClientEvent, function(payload)
        updateInventoryUI(payload)
    end)
    
    -- Dig feedback
    self:connect("dig", Remotes.RE.OnDigFeedback.OnClientEvent, function(feedback)
        if feedback.shake then
            applyCameraShake(feedback.shake)
        end
        if feedback.particles then
            spawnParticles(feedback.cells)
        end
    end)
    
    -- Notifications
    self:connect("notification", Remotes.RE.OnNotification.OnClientEvent, function(notif)
        showNotification(notif)
    end)
end

function ConnectionManager:connect(name, event, handler)
    if self.connections[name] then
        self.connections[name]:Disconnect()
    end
    self.connections[name] = event:Connect(handler)
end

function ConnectionManager:cleanup()
    for _, connection in pairs(self.connections) do
        connection:Disconnect()
    end
    self.connections = {}
end

-- Debounce Implementation
function createDebounce(cooldown)
    local active = false
    return function(callback)
        if active then return end
        active = true
        callback()
        task.wait(cooldown)
        active = false
    end
end

-- Game Functions
local requestDig = createDebounce(0.1)

local function handleClick(hit, worldPos)
    requestDig(function()
        local result = Remotes.RF.RequestDig:InvokeServer(worldPos)
        if not result.ok then
            warn("Dig failed:", result.reason)
        end
    end)
end

local function purchaseUpgrade(upgradeType)
    local profile = ProfileCache:get()
    if not profile then return end
    
    -- Client-side validation
    local cost = getUpgradeCost(upgradeType, profile.upgrades[upgradeType])
    if profile.coins < cost then
        showNotification({
            type = "error",
            message = "Not enough coins!"
        })
        return
    end
    
    local result = Remotes.RF.PurchaseUpgrade:InvokeServer(upgradeType)
    if result.success then
        showNotification({
            type = "success",
            message = "Upgrade purchased!"
        })
    else
        showNotification({
            type = "error",
            message = result.reason
        })
    end
end

-- Initialize
ConnectionManager:init()

-- Initial profile load
task.spawn(function()
    local profile = ProfileCache:get()
    if profile then
        initializeUI(profile)
    end
end)

-- Cleanup on leave
game.AncestryChanged:Connect(function()
    if not game.Parent then
        ConnectionManager:cleanup()
    end
end)
```

---

## Migration Notes

### Deprecated Functions
None currently - all listed functions are active.

### Future Additions
The following features are planned but not yet implemented:
- **Pet Management**: `EquipPet`, `UnequipPet`, `UpgradePet`
- **Multiplayer**: `VisitNeighbor`, `ReturnHome`, `GetNeighborhood`
- **Social**: Achievement system, Trading, Clans/Guilds

### Version Compatibility
- Current API Version: 1.0
- Minimum Client Version: 1.0
- Breaking changes will increment major version

### Upgrading Guidelines
When new API versions are released:
1. Check migration notes for breaking changes
2. Update client code to handle new response formats
3. Test thoroughly in Studio before production
4. Consider backward compatibility for older clients

[← RemoteEvents](API_REMOTE_EVENTS.md) | [Back to API Documentation](API_DOCUMENTATION.md)