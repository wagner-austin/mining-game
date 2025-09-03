# RemoteFunctions API Reference

[← Back to API Documentation](API_DOCUMENTATION.md)

## Overview

RemoteFunctions are used for client→server communication that requires a response. The client invokes the function and waits for the server to return data.

## Table of Contents

- [Core Gameplay](#core-gameplay)
- [Inventory Management](#inventory-management)
- [Pet Management](#pet-management)
- [Purchases & Upgrades](#purchases--upgrades)
- [Material & Theme Customization](#material--theme-customization)
- [Player Movement & Spawning](#player-movement--spawning)
- [Social & Neighbors](#social--neighbors)
- [Metrics & Analytics](#metrics--analytics)
- [Item Drops](#item-drops)
- [Cloth Simulation](#cloth-simulation)
- [Debug Functions](#debug-functions-studiodeveloper-only)
- [Spawn Strategy](#spawn-strategy-developer-only)
- [Simulation Agents](#simulation-agents-studio-only)

**Total Functions: 42**

---

## Core Gameplay

### `GetProfile()`
Returns the player's complete profile including stats, inventory, and current state.

**Returns:**
```lua
{
    profile = {
        coins = number,
        gems = number,
        blocksDestroyed = number,
        totalBlocksDestroyed = number,
        upgrades = {
            speed = number,
            size = number
        },
        inventory = {[itemId] = count},
        equipment = {[slot] = itemId},
        materials = {[materialId] = boolean},
        currentMaterial = string,
        pets = {[petId] = PetData},
        activePets = {string},
        boosts = {[boostType] = expiryTime}
    },
    cubeState = {
        chunksData = table,
        totalChunks = number,
        dugCells = number,
        compressedSize = number
    },
    effectiveStats = {
        speed = number,
        delay = number,
        size = number,
        multiplier = number
    },
    gamepasses = {[gamepassId] = boolean}
}
```

### `RequestDig(worldPos: Vector3)`
Process a dig request at the specified world position.

**Parameters:**
- `worldPos`: Vector3 position where the player wants to dig

**Returns:**
```lua
{
    ok = boolean,                      -- Success status
    reason = string?,                   -- Error message if failed
    cellsDestroyed = number?,          -- Number of cells destroyed
    loot = {[itemId] = count}?,        -- Items received
    nextAllowedAt = number?,           -- Unix timestamp for cooldown
    effectiveStats = EffectiveStats?   -- Updated player stats
}
```

**Error Reasons:**
- `"No cube data"` - Player cube not initialized
- `"Outside your cube"` - Position outside player's cube
- `"On cooldown"` - Dig cooldown not expired
- `"Protected cell"` - Trying to dig a protected cell

---

### `StartContinuousDig(worldPos: Vector3)`
Start continuous digging at a position (hold to dig).

**Parameters:**
- `worldPos`: World position to start digging

**Returns:**
```lua
{
    success: boolean,
    reason: string?  -- Error reason if failed
}
```

---

### `StopContinuousDig()`
Stop continuous digging.

**Returns:**
```lua
{
    success: boolean
}
```

---

## Inventory Management

### `SellItems(items: {[string]: number})`
Sell items from inventory for coins.

**Parameters:**
- `items`: Dictionary mapping itemId → quantity to sell

**Returns:**
```lua
{
    success = boolean,
    coinsEarned = number?,
    totalValue = number?,
    reason = string?  -- Error message if failed
}
```

### `EquipItem(itemId: string)`
Equip an item from inventory.

**Parameters:**
- `itemId`: ID of the item to equip

**Returns:**
```lua
{
    success = boolean,
    slot = string?,      -- Slot where item was equipped
    unequipped = string?, -- Previous item that was unequipped
    reason = string?      -- Error message if failed
}
```

### `UnequipItem(slot: string)`
Unequip an item from a specific slot.

**Parameters:**
- `slot`: Equipment slot ("pickaxe", "head", "back", "aura", "trail")

**Returns:**
```lua
{
    success = boolean,
    itemId = string?,    -- Item that was unequipped
    reason = string?     -- Error message if failed
}
```

### `UseConsumable(itemId: string)`
Use a consumable item from inventory.

**Parameters:**
- `itemId`: ID of the consumable to use

**Returns:**
```lua
{
    success = boolean,
    effect = string?,     -- Effect applied
    duration = number?,   -- Duration in seconds
    reason = string?      -- Error message if failed
}
```

---

## Pet Management

### `EquipPet(petId: string)`
Equip a pet from inventory.

**Parameters:**
- `petId`: ID of the pet to equip

**Returns:**
```lua
{
    success: boolean,
    reason: string?  -- Error reason if failed
}
```

---

### `UnequipPet(petId: string)`
Unequip an active pet.

**Parameters:**
- `petId`: ID of the pet to unequip

**Returns:**
```lua
{
    success: boolean,
    reason: string?
}
```

---

### `UpgradePet(petId: string)`
Upgrade a pet's level or abilities.

**Parameters:**
- `petId`: ID of the pet to upgrade

**Returns:**
```lua
{
    success: boolean,
    newLevel: number?,
    cost: number?,
    reason: string?
}
```

---

## Purchases & Upgrades

### `PurchaseUpgrade(upgradeType: string)`
Purchase a tool upgrade with coins.

**Parameters:**
- `upgradeType`: "speed" or "size"

**Returns:**
```lua
{
    success = boolean,
    newLevel = number?,     -- New upgrade level
    cost = number?,         -- Cost paid
    nextCost = number?,     -- Cost for next upgrade
    reason = string?        -- Error message if failed
}
```

### `PurchaseProduct(purchaseType: string, purchaseId: string)`
Initiate a Robux purchase (Developer Product or Gamepass).

**Parameters:**
- `purchaseType`: "product" or "gamepass"
- `purchaseId`: Product/gamepass ID from GameConfig

**Returns:**
```lua
{
    success = boolean,
    reason = string?  -- Error message if failed
}
```

### `PurchaseMaterial(materialId: string)`
Purchase a cube material skin with coins.

**Parameters:**
- `materialId`: Material ID from GameConfig

**Returns:**
```lua
{
    success = boolean,
    cost = number?,      -- Amount paid
    reason = string?     -- Error message if failed
}
```

---

## Material & Theme Customization

### `ApplyCubeSurfaceMaterial(materialKey: string)`
Apply a surface material to the player's cube.

**Parameters:**
- `materialKey`: Key from MaterialDefinitions

**Returns:**
```lua
{
    success = boolean,
    materialKey = string?,
    reason = string?
}
```

### `ApplyFloorMaterial(materialKey: string)`
Apply a floor material to the player's cube.

**Parameters:**
- `materialKey`: Key from MaterialDefinitions

**Returns:**
```lua
{
    success = boolean,
    materialKey = string?,
    reason = string?
}
```

### `GetMaterialPreferences()`
Get the player's material preferences.

**Returns:**
```lua
{
    surfaceMaterial = string,
    floorMaterial = string,
    palette = string
}
```

### `SetPalettePreference(paletteKey: string)`
Set the player's color palette preference.

**Parameters:**
- `paletteKey`: Palette key identifier

**Returns:**
```lua
boolean  -- Success status
```

### `GetThemeSettings()`
Get the player's theme settings.

**Returns:**
```lua
{
    soundTheme = string,      -- Current sound theme
    visualTheme = string,     -- Current visual theme
    particleLevel = string,   -- Particle effect level
    screenShake = boolean     -- Screen shake enabled
}
```

### `UpdateThemeSettings(patch: table)`
Update theme settings with a partial update.

**Parameters:**
- `patch`: Table with theme settings to update

**Returns:**
```lua
{
    success = boolean,
    settings = ThemeSettings?,
    reason = string?
}
```

---

## Player Movement & Spawning

### `TeleportToHome()`
Teleport the player to their cube spawn point.

**Returns:**
```lua
{
    success = true
}
```

### `RespawnCubeModel()`
Regenerate the player's cube visual model.

**Returns:**
```lua
{
    success = boolean,
    message = string
}
```

---

## Social & Neighbors

### `VisitNeighbor(playerId: number)`
Visit another player's cube.

**Parameters:**
- `playerId`: UserId of the player to visit

**Returns:**
```lua
{
    success: boolean,
    reason: string?  -- Error if failed
}
```

---

### `ReturnHome()`
Return from visiting a neighbor to your own cube.

**Returns:**
```lua
{
    success: boolean
}
```

---

### `GetNeighborhood()`
Get list of available neighbors to visit.

**Returns:**
```lua
{
    neighbors: {
        {
            userId: number,
            username: string,
            cubeLevel: number,
            online: boolean
        }
    }
}
```

---

### `UpdateSettings(settings: table)`
Update player's game settings.

**Parameters:**
- `settings`: Table of settings to update

**Returns:**
```lua
{
    success: boolean,
    updated: table  -- Settings that were updated
}
```

---

## Metrics & Analytics

### `GetMetrics()`
Get comprehensive player metrics and statistics.

**Returns:**
```lua
{
    gameplay = {
        totalBlocksDug = number,
        dugThisSession = number,
        blocksPerMinute = number,
        digAccuracy = number,
        longestStreak = number
    },
    economy = {
        coins = number,
        gems = number,
        totalCoinsEarned = number,
        totalCoinsSpent = number,
        totalGemsEarned = number,
        totalGemsSpent = number,
        netWorth = number
    },
    session = {
        sessionStartTime = number,
        sessionDurationSec = number,
        totalPlaytimeSec = number,
        totalSessions = number,
        avgSessionLengthSec = number
    },
    progression = {
        speedLevel = number,
        sizeLevel = number,
        petsOwned = number,
        activePets = number,
        materialTier = number,
        totalUpgrades = number
    },
    world = {
        currentMaterial = string,
        cubeSize = number,
        totalChunks = number,
        dugCells = number,
        cubeProgress = number  -- Percentage
    }
}
```

### `GetServerMetrics()`
Get server-wide metrics (limited for regular players, full for developers).

**Returns (Regular Players):**
```lua
{
    totalPlayers = number,
    serverUptimeSec = number
}
```

**Returns (Developers):**
```lua
{
    totalPlayers = number,
    serverUptimeSec = number,
    activeDiggers = number,
    totalBlocksDugServer = number,
    avgSessionLength = number,
    peakPlayers = number,
    totalSessions = number,
    serverStartTime = number
}
```

---

## Item Drops

### `PickupItem(dropModel: Model)`
Collect a dropped item in the world.

**Parameters:**
- `dropModel`: The Model instance of the drop to collect

**Returns:**
```lua
boolean  -- Collection success
```

### `SpawnTestItem(itemId: string)` *(Debug Only)*
Spawn a test item near the player for testing.

**Parameters:**
- `itemId`: ID of the item to spawn

**Returns:**
```lua
{
    success = boolean,
    reason = string?
}
```

---

## Cloth Simulation

### `ClothSpawn(opts: table?)`
Spawn a cloth simulation for the player.

**Parameters:**
- `opts`: Optional configuration (not used in simple version)

**Returns:**
```lua
{
    success: boolean
}
```

---

### `ClothDestroy()`
Destroy the player's active cloth simulation.

**Returns:**
```lua
{
    success: boolean
}
```

---

## Debug Functions *(Studio/Developer Only)*

### `DebugAddCurrency(currencyType: string, amount: number)`
Add currency for testing (Studio only).

**Parameters:**
- `currencyType`: "coins" or "gems"
- `amount`: Amount to add

**Returns:**
```lua
{
    success = boolean,
    added = number?,
    reason = string?
}
```

### `DebugResetCube()`
Reset the player's cube to default state (Studio only).

**Returns:**
```lua
{
    success = boolean,
    message = string
}
```

### `DebugResetStats()`
Reset all player stats to default (Studio only).

**Returns:**
```lua
{
    success = boolean,
    message = string
}
```

---

## Spawn Strategy *(Developer Only)*

### `SpawnStrategy_Get()`
Get the current spawn strategy.

**Returns:**
```lua
string  -- Current strategy name
```

### `SpawnStrategy_List()`
Get list of available spawn strategies.

**Returns:**
```lua
{string}  -- Array of strategy names
```

### `SpawnStrategy_Set(strategy: string)`
Set the spawn strategy (Studio only).

**Parameters:**
- `strategy`: Strategy name to set

**Returns:**
```lua
{
    success = boolean,
    strategy = string?,
    reason = string?
}
```

---

## Simulation Agents *(Studio Only)*

### `SimAgents_SetCount(count: number)`
Set the number of simulation agents.

**Parameters:**
- `count`: Number of agents (0-50)

**Returns:**
```lua
boolean, number|string  -- Success, new count or error message
```

### `SimAgents_GetStatus()`
Get simulation agent status.

**Returns:**
```lua
{
    count = number,
    config = {
        digCooldown = number,
        digRadius = number,
        autoRespawn = boolean,
        createTerrainCubes = boolean
    },
    activeAgents = {
        {
            name = string,
            state = string,
            blocksDestroyed = number,
            lastDig = number
        }
    }
}
```

### `SimAgents_RespawnAll()`
Respawn all simulation agents.

**Returns:**
```lua
boolean, string?  -- Success, error message if failed
```

### `SimAgents_Clear()`
Remove all simulation agents.

**Returns:**
```lua
boolean, string?  -- Success, error message if failed
```

### `SimAgents_SetTerrainCubes(enabled: boolean)`
Toggle terrain cube creation for agents.

**Parameters:**
- `enabled`: Whether to create terrain cubes

**Returns:**
```lua
boolean, string?  -- Success, error message if failed
```

---

## Common Error Responses

All RemoteFunctions that can fail follow this pattern:

```lua
-- Success
{
    success = true,
    -- ... additional data
}

-- Failure
{
    success = false,
    reason = string  -- Human-readable error message
}
```

### Common Error Reasons

- **Authentication**
  - `"Not authorized"` - Missing permissions
  - `"Studio only"` - Function only available in Studio
  
- **Data Validation**
  - `"Invalid parameters"` - Missing or invalid input
  - `"Item not found"` - Referenced item doesn't exist
  - `"Invalid amount"` - Number out of valid range
  
- **State Errors**
  - `"Not enough coins"` - Insufficient currency
  - `"Already equipped"` - Item already in use
  - `"On cooldown"` - Action rate limited
  - `"Inventory full"` - No space for items
  
- **System Errors**
  - `"Data not loaded"` - Player data not ready
  - `"Service unavailable"` - Backend service error

[← Back to API Documentation](API_DOCUMENTATION.md) | [RemoteEvents →](API_REMOTE_EVENTS.md)