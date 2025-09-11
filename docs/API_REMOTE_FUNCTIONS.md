# RemoteFunctions API Reference

[← Back to API Documentation](API_DOCUMENTATION.md)

## Overview

RemoteFunctions are managed through the RFRegistry system with centralized specifications in the `server/MiningGame/RemoteFns/` directory. All RemoteFunctions have strict schema validation, rate limiting, and automatic Result normalization.

## Architecture

All RemoteFunctions are:
- Defined in spec files (`RemoteFns/*.rf.lua`)
- Auto-discovered by RFRegistry at startup
- Wrapped with middleware for timing and error handling
- Validated with schema functions
- Rate limited with token bucket algorithm
- Return standardized Result format

## Client Usage

```lua
-- Modern approach with ClientRF
local ClientRF = require(MiningGame.ClientRF)

-- Call with automatic Result unwrapping
local profile, err = ClientRF.call("GetProfile")
if not profile then
    warn("Failed to get profile:", err)
    return
end

-- With parameters
local result, err = ClientRF.call("SellItems", { diamond = 5 })
if not result then
    if err == "INSUFFICIENT_ITEMS" then
        -- Handle specific error
    end
end

-- With retry on network failure
local data, err = ClientRF.callWithRetry("GetInventory", 3)
```

## RemoteFunction Categories

**Total Functions: 59 across 15 specification modules**

### Core Module (`Core.rf.lua`)
- `GetServerUnix` - Server timestamp
- `TeleportToHome` - Return to spawn
- `DebugAddCurrency` (debug-only)
- `DebugResetCube` (debug-only)
- `DebugResetStats` (debug-only)
- `GetMetrics` - Player metrics
- `GetServerMetrics` - Server performance metrics
- `SpawnStrategy_Get` (debug-only)
- `SpawnStrategy_List` (debug-only)
- `SpawnStrategy_Set` (debug-only)

### Digging (`Dig.rf.lua`)
- `GetProfile` - Complete player profile and stats
- `RequestDig` - Single dig action
- `StartContinuousDig` - Begin hold-to-dig
- `StopContinuousDig` - End hold-to-dig
- `RespawnCubeModel` - Reset cube visuals

### Inventory (`Inventory.rf.lua`)
- `GetInventory` - Full inventory data
- `SellItems` - Sell items for currency (expects `{[itemId]=count}`)
- `EquipItem` - Equip to slot
- `UnequipItem` - Remove from slot
- `UseConsumable` - Activate consumable item
- `GetEquippedItems` - Raw map (slot -> itemId)
- `GetAllEquipped` - Raw map (userId -> (slot -> itemId))

### Upgrades (`Upgrade.rf.lua`)
- `PurchaseUpgrade` - Buy player upgrade

### Monetization (`Monetization.rf.lua`)
- `PurchaseProduct` - Prompt developer product purchase
- `PurchaseGamepass` - Prompt gamepass purchase
- `GetPrices` - Available products/prices (from `GameConfig.Monetization.PRODUCTS`)
- `GetGamepasses` - Gamepass ownership via Roblox API (cached 120s)
  - Returns:
    - `ownedById`: `{ ["VIP"] = true, ... }`
    - `ownedByGamepassId`: `{ [123456] = true, ... }`
    - `list`: `[ { id, gamepassId, owned, robux }, ... ]`
    - `owned`: alias to `ownedByGamepassId` (back-compat)
- `ClaimDailyReward` - Daily reward claim

### Material Customization (`CubeMaterial.rf.lua`)
- `ApplyCubeSurfaceMaterial` - Apply cube surface material
- `ApplyFloorMaterial` - Apply floor material
- `GetMaterialPreferences` - Get current preferences
- `SetPalettePreference` - Choose palette

### Theme Settings (`ThemeSettings.rf.lua`)
- `GetThemeSettings` - Current theme settings
- `UpdateThemeSettings` - Patch theme (uiTheme, soundPack, volumes)
- `GetAvailableThemes` - Available UI themes
- `GetAvailableSoundPacks` - Available sound packs

### Composition (`Composition.rf.lua`)
- `ListCompositions` - Available themes/compositions
- `ApplyComposition` - Apply theme composition
- `RegenerateComposition` - Rebuild composition

### Pets (`Pets.rf.lua`)
- `EquipPet` (stub: NOT_IMPLEMENTED)
- `UnequipPet` (stub: NOT_IMPLEMENTED)
- `UpgradePet` (stub: NOT_IMPLEMENTED)

### Neighborhood (`Neighborhood.rf.lua`)
- `GetNeighborhood` (stub: enabled in Studio)
- `VisitNeighbor` (stub)
- `ReturnHome` (stub)

### Items (`Item.rf.lua`)
- `PickupItem` - Collect world item (validates instance & tag)
- `SpawnTestItem` (debug-only)

### Floating Islands (`FloatingIsland.rf.lua`)
- `Debug_SpawnIsland` (debug-only)

### Settings (`Settings.rf.lua`)
- `GetSettings` - Theme settings or defaults
- `UpdateGeneralSettings` - General/theme updates (validated)
- `GetAllSettings` - Merged settings view
- `ResetSettings` - Reset to defaults (all/theme)

### Debug Functions (Studio Only)

#### ClothDebug (`ClothDebug.rf.lua`)
- `ClothSpawn` - Create cloth instance
- `ClothDestroy` - Remove cloth

#### SimAgents (`SimAgents.rf.lua`)
- `SimAgents_SetCount`
- `SimAgents_GetStatus`
- `SimAgents_RespawnAll`
- `SimAgents_Clear`
- `SimAgents_SetTerrainCubes`

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

The ClientRF automatically unwraps this format, returning:
- `(data, nil)` on success
- `(nil, errorCode)` on failure

## Common Error Codes

| Code | Description |
|------|-------------|
| `RATE_LIMIT` | Too many requests |
| `INVALID_INPUT` | Failed schema validation |
| `NO_PROFILE` | Profile not loaded |
| `INSUFFICIENT_FUNDS` | Not enough currency |
| `INSUFFICIENT_ITEMS` | Not enough items |
| `ITEM_NOT_FOUND` | Invalid item ID |
| `ALREADY_OWNED` | Already purchased |
| `NOT_AVAILABLE` | Feature disabled |
| `INTERNAL` | Server error |

## Rate Limiting

Each RemoteFunction has a configured rate limit:

```lua
-- Examples from specs
RequestDig: 0.1 sec (10/sec max)
SellItems: 0.5 sec (2/sec max)
GetProfile: 1 sec (1/sec max)
PurchaseProduct: 2 sec (0.5/sec max)
```

Rate limited requests return:
```lua
{
    ok = false,
    err = "RATE_LIMIT",
    reason = "Too many requests"
}
```

## Schema Validation

All parameters are validated server-side:

```lua
-- Example from SellItems
validate = function(itemType: string?, count: number?)
    if not itemType then 
        return false, "Missing itemType"
    end
    if not count or count <= 0 then 
        return false, "Invalid count"
    end
    return true
end
```

Failed validation returns:
```lua
{
    ok = false,
    err = "INVALID_INPUT",
    reason = <validation error message>
}
```

## Context System

All handlers receive a context object:

```lua
handler = function(ctx, ...)
    -- ctx.player: Player instance (always present)
    -- ctx.profile: Player data (if requireProfile = true)
    
    local player = ctx.player
    local profile = ctx.profile
    
    -- Service access
    local service = getService("ServiceName")
    return service:DoSomething(player, ...)
end
```

## Examples

### Getting Player Data

```lua
-- Get full profile
local profile, err = ClientRF.call("GetProfile")
if profile then
    print("Coins:", profile.coins)
    print("Level:", profile.level)
end

-- Get just inventory
local inventory, err = ClientRF.call("GetInventory")
if inventory then
    for itemId, count in pairs(inventory) do
        print(itemId, "x", count)
    end
end
```

### Making Purchases

```lua
-- Buy an upgrade
local result, err = ClientRF.call("PurchaseUpgrade", "speed")
if result then
    print("Upgrade successful!")
elseif err == "INSUFFICIENT_FUNDS" then
    print("Not enough coins!")
end

-- Buy a product
local result, err = ClientRF.call("PurchaseProduct", "gem_pack_1")
if err == "ALREADY_OWNED" then
    print("You already own this!")
end
```

### Digging Operations

```lua
-- Single dig
local result, err = ClientRF.call("RequestDig", Vector3.new(10, 0, 10))
if result then
    print("Destroyed", result.cellsDestroyed, "cells")
    if result.loot then
        for item, count in pairs(result.loot) do
            print("Got", count, item)
        end
    end
elseif err == "ON_COOLDOWN" then
    print("Wait before digging again")
end

-- Continuous dig
ClientRF.call("StartContinuousDig", position)
-- ... later ...
ClientRF.call("StopContinuousDig")
```

### Error Handling Patterns

```lua
local function safePurchase(productId)
    local result, err = ClientRF.call("PurchaseProduct", productId)
    
    if result then
        return true, "Purchase successful"
    end
    
    -- Handle specific errors
    local errorMessages = {
        INSUFFICIENT_FUNDS = "Not enough currency",
        ALREADY_OWNED = "You already own this",
        ITEM_NOT_FOUND = "Product doesn't exist",
        RATE_LIMIT = "Too many purchases, please wait",
        NO_PROFILE = "Profile not loaded, try again",
        INTERNAL = "Server error, please try later"
    }
    
    return false, errorMessages[err] or "Unknown error: " .. tostring(err)
end
```

## Best Practices

1. **Always handle errors** - Network calls can fail
2. **Use specific error checks** - Handle known error codes appropriately
3. **Implement retry logic** - Use `ClientRF.callWithRetry` for critical operations
4. **Cache when appropriate** - Some data doesn't change frequently
5. **Batch operations** - Use bulk endpoints when available (e.g., `SellAllItems`)
6. **Respect rate limits** - Don't spam requests in loops

## See Also

- [Remote Architecture](REMOTE_ARCHITECTURE.md) - Complete remote system design
- [EventBus System](EVENTBUS_SYSTEM.md) - Server→Client events
- [API Best Practices](API_BEST_PRACTICES.md) - Guidelines and patterns
- [Service Architecture](SERVICE_ARCHITECTURE.md) - Server-side services
