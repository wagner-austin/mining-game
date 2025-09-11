# RemoteEvents API Reference

[← Back to API Documentation](API_DOCUMENTATION.md)

[← Back to API Documentation](API_DOCUMENTATION.md)

## Overview

Server→Client events are managed through the EventBus system with a single RemoteEvent bridge. All events follow a pub/sub pattern with type-safe event names, structured payloads, and automatic routing to appropriate clients.

## Architecture

- **Single RemoteEvent**: All events flow through `Remotes.EventBus`
- **EventBus Distribution**: Client-side EventBus distributes to subscribers
- **Type-Safe Names**: Events use constants from `EventNames.lua`
- **Target Routing**: Server specifies target (player/broadcast/team)
- **Fast Path**: High-frequency events skip middleware for performance

## Client Usage

```lua
-- Modern EventBus approach
local EventBus = require(MiningGame.EventBus).global()
local EventNames = require(MiningGame.EventNames)

-- Subscribe to events
local unsubscribe = EventBus:on(EventNames.CURRENCY_CHANGED, function(data)
    print("New balance:", data.payload.balance)
end)

-- Clean up when done
unsubscribe()

-- For components with multiple subscriptions
local subscriptions = {}

function Component:Init()
    table.insert(subscriptions, EventBus:on(EventNames.INVENTORY_CHANGED, function(data)
        self:UpdateInventory(data.payload)
    end))
    
    table.insert(subscriptions, EventBus:on(EventNames.PROFILE_UPDATED, function(data)
        self:UpdateProfile(data.payload)
    end))
end

function Component:Destroy()
    for _, unsub in ipairs(subscriptions) do
        unsub()
    end
end
```

## Event Categories

### State Updates

#### `PROFILE_UPDATED`
Complete profile data update.

**Payload:**
```lua
{
    to = {kind = "player", player = Player},
    payload = {
        stats = PlayerStats,
        inventory = Inventory,
        upgrades = Upgrades,
        settings = Settings
    }
}
```

#### `CURRENCY_CHANGED`
Currency balance changes.

**Payload:**
```lua
{
    to = {kind = "player", player = Player},
    payload = {
        currency = "coins" | "gems",
        balance = number,
        delta = number  -- Change amount (+/-)
    }
}
```

#### `INVENTORY_CHANGED`
Inventory modifications.

**Payload:**
```lua
{
    to = {kind = "player", player = Player},
    payload = {
        action = "add" | "remove" | "equip" | "unequip" | "sold",
        itemId = string,
        quantity = number?,
        total = number?,
        slot = string?,
        value = number?  -- For sold action
    }
}
```

#### `UPGRADES_CHANGED`
Upgrade purchases or changes.

**Payload:**
```lua
{
    to = {kind = "player", player = Player},
    payload = {
        upgradeType = string,
        level = number,
        stats = EffectiveStats
    }
}
```

#### `BOOSTS_CHANGED`
Active boost modifications.

**Payload:**
```lua
{
    to = {kind = "player", player = Player},
    payload = {
        boostType = string,
        expiresAt = number?,  -- Unix timestamp
        active = boolean
    }
}
```

### Gameplay Events

#### `DIG_FEEDBACK`
Digging action feedback (fast-path optimized).

**Payload:**
```lua
{
    to = {kind = "player", player = Player},
    payload = {
        position = Vector3,
        material = string,
        cellsDestroyed = number,
        cooldownEnds = number?
    }
}
```

#### `CUBE_ORIGIN_CHANGED`
Cube position update.

**Payload:**
```lua
{
    to = {kind = "player", player = Player},
    payload = {
        origin = Vector3,
        playerId = number
    }
}
```

#### `LOOT_DROPPED`
Item drop notification.

**Payload:**
```lua
{
    to = {kind = "player", player = Player},
    payload = {
        itemId = string,
        quantity = number,
        position = Vector3,
        rarity = string
    }
}
```

#### `FIRST_DIG`
First dig achievement.

**Payload:**
```lua
{
    to = {kind = "player", player = Player},
    payload = {
        position = Vector3,
        reward = {coins = number}
    }
}
```

### Notifications

#### `NOTIFICATION_PUSH`
General notifications.

**Payload:**
```lua
{
    to = {kind = "player", player = Player},
    payload = {
        type = "info" | "success" | "warning" | "error",
        title = string,
        message = string,
        duration = number?,
        icon = string?
    }
}
```

#### `ACHIEVEMENT_UNLOCKED`
Achievement completion.

**Payload:**
```lua
{
    to = {kind = "player", player = Player},
    payload = {
        achievementId = string,
        name = string,
        description = string,
        reward = {
            coins = number?,
            gems = number?,
            items = {[string]: number}?
        }
    }
}
```

#### `ANNOUNCEMENT_BROADCAST`
Server-wide announcements.

**Payload:**
```lua
{
    to = {kind = "broadcast"},
    payload = {
        message = string,
        priority = "low" | "normal" | "high",
        duration = number,
        color = Color3?
    }
}
```

### Social Events

#### `NEIGHBOR_JOINED`
Player joined neighborhood.

**Payload:**
```lua
{
    to = {kind = "broadcast"},
    payload = {
        playerId = number,
        playerName = string,
        origin = Vector3
    }
}
```

#### `NEIGHBOR_LEFT`
Player left neighborhood.

**Payload:**
```lua
{
    to = {kind = "broadcast"},
    payload = {
        playerId = number,
        playerName = string
    }
}
```

### UI & Interaction

#### `ITEM_COLLECTED`
Item pickup confirmation.

**Payload:**
```lua
{
    to = {kind = "player", player = Player},
    payload = {
        itemId = string,
        quantity = number,
        source = "pickup" | "reward" | "purchase"
    }
}
```

#### `PICKUP_PROMPT`
Show pickup UI.

**Payload:**
```lua
{
    to = {kind = "player", player = Player},
    payload = {
        itemModel = Instance,
        itemId = string,
        quantity = number
    }
}
```

### Effects & Feedback

#### `SOUND_EFFECT`
Trigger client-side sound.

**Payload:**
```lua
{
    to = {kind = "player", player = Player},
    payload = {
        soundId = string,
        position = Vector3?,
        volume = number?,
        pitch = number?
    }
}
```

#### `PARTICLE_EFFECT`
Spawn particle effect.

**Payload:**
```lua
{
    to = {kind = "player", player = Player},
    payload = {
        effectType = string,
        position = Vector3,
        color = Color3?,
        size = number?
    }
}
```

#### `CAMERA_SHAKE`
Camera shake effect.

**Payload:**
```lua
{
    to = {kind = "player", player = Player},
    payload = {
        intensity = number,
        duration = number,
        fadeIn = number?,
        fadeOut = number?
    }
}
```

#### `RUNTIME_EFFECTS_CHANGED`
Visual effects update.

**Payload:**
```lua
{
    to = {kind = "player", player = Player},
    payload = {
        effects = {
            [effectId]: {
                enabled = boolean,
                intensity = number?
            }
        }
    }
}
```

## Event Patterns

### Subscribing to Events

```lua
local EventBus = require(MiningGame.EventBus).global()
local EventNames = require(MiningGame.EventNames)

-- Basic subscription
EventBus:on(EventNames.CURRENCY_CHANGED, function(data)
    updateUI(data.payload)
end)

-- With priority (lower = earlier)
EventBus:on(EventNames.DIG_FEEDBACK, handleDigFeedback, 10)

-- One-time subscription
EventBus:once(EventNames.FIRST_DIG, function(data)
    showTutorial("Great job on your first dig!")
end)
```

### Managing Subscriptions

```lua
local Component = {}

function Component:Init()
    self.subscriptions = {}
    
    -- Store all unsubscribe functions
    local events = {
        [EventNames.CURRENCY_CHANGED] = self.OnCurrencyChanged,
        [EventNames.INVENTORY_CHANGED] = self.OnInventoryChanged,
        [EventNames.PROFILE_UPDATED] = self.OnProfileUpdated
    }
    
    for event, handler in pairs(events) do
        table.insert(self.subscriptions, 
            EventBus:on(event, function(data)
                handler(self, data)
            end))
    end
end

function Component:Destroy()
    -- Clean up all subscriptions
    for _, unsub in ipairs(self.subscriptions) do
        unsub()
    end
end
```

### Client to Server Requests

```lua
-- Use RemoteEventBridge for client→server
local Bridge = require(MiningGame.RemoteEventBridge)
local RequestNames = require(MiningGame.RequestNames)

-- Send request to server
Bridge.send(RequestNames.INVENTORY_REQUEST_SELL, {
    itemId = "diamond",
    quantity = 5
})

-- Convenience methods
Bridge.requestSell("diamond", 5)
Bridge.requestEquip("sword", "weapon")
Bridge.requestDig(Vector3.new(10, 0, 10))
```

## Performance Considerations

### Fast Path Events

High-frequency events skip middleware for performance:

```lua
-- On client initialization
local Bus = EventBus.global()
Bus:markFastPath(EventNames.DIG_FEEDBACK)
```

### Event Batching

Server can batch related updates:

```lua
-- Server-side
EventBus:emit(EventNames.PROFILE_UPDATED, {
    to = {kind = "player", player = player},
    payload = {
        stats = stats,
        inventory = inventory,
        upgrades = upgrades
    }
})
-- Instead of three separate events
```

## Error Handling

```lua
-- Defensive event handling
EventBus:on(EventNames.INVENTORY_CHANGED, function(data)
    -- Validate payload
    if not data.payload or not data.payload.itemId then
        warn("Invalid inventory event payload")
        return
    end
    
    -- Safe property access
    local quantity = data.payload.quantity or 0
    local action = data.payload.action or "unknown"
    
    -- Handle event
    processInventoryChange(action, data.payload.itemId, quantity)
end)
```

## Best Practices

1. **Use Event Constants** - Always use EventNames/RequestNames
2. **Clean Up Subscriptions** - Prevent memory leaks
3. **Validate Payloads** - Don't assume data structure
4. **Handle Missing Data** - Use defensive programming
5. **Batch Related Updates** - Reduce event count
6. **Mark Fast Paths** - For high-frequency events

## Debugging

```lua
-- Log all events (dev only)
if RunService:IsStudio() then
    EventBus:use(function(ctx, next)
        print(string.format("[Event] %s", ctx.event))
        next()
    end)
end

-- Monitor specific event
EventBus:on(EventNames.CURRENCY_CHANGED, function(data)
    print("Currency event:", data)
end, 1) -- High priority to log first
```

## See Also

- [EventBus System](EVENTBUS_SYSTEM.md) - Complete EventBus documentation
- [Remote Architecture](REMOTE_ARCHITECTURE.md) - Client-server communication
- [API RemoteFunctions](API_REMOTE_FUNCTIONS.md) - Request-response patterns
- [Service Architecture](SERVICE_ARCHITECTURE.md) - Server-side services
