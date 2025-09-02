# Mining Game API Documentation

⚠️ **NOTE: This document needs updating to match actual implementation**

## Remote API Overview

This document describes the Remote API for client-server communication. All communication happens through RemoteEvents and RemoteFunctions in `ReplicatedStorage.Remotes.MiningGame`.

## Remote Functions (Client → Server with return)

### `GetProfile()`
Get the player's complete profile and stats.

**Returns:**
```lua
{
    profile = PlayerStats,
    effectiveStats = EffectiveStats,
    cubeStats = {
        totalChunks = number,
        dugCells = number,
        compressedSize = number
    },
    gamepasses = {[string]: boolean}
}
```

### `RequestDig(worldPos: Vector3)`
Request to dig at a world position.

**Parameters:**
- `worldPos`: The world position where the player clicked/tapped

**Returns:**
```lua
{
    ok = boolean,
    reason = string?, -- If failed
    cellsDug = number?,
    lootGranted = {string}?, -- Array of item IDs
    nextAllowedAt = number?, -- Unix timestamp
    effectiveStats = EffectiveStats?
}
```

### `PurchaseUpgrade(upgradeType: string)`
Purchase an upgrade with coins.

**Parameters:**
- `upgradeType`: "speed" or "size"

**Returns:**
```lua
{
    success = boolean,
    newLevel = number?,
    costNext = number?,
    reason = string?
}
```

### `PurchaseProduct(purchaseType: string, purchaseId: string)`
Initiate a Robux purchase.

**Parameters:**
- `purchaseType`: "product" or "gamepass"
- `purchaseId`: ID from GameConfig

**Returns:**
```lua
{success = boolean}
```

### `PurchaseMaterial(materialId: string)`
Purchase a new cube material with coins.

**Parameters:**
- `materialId`: Material ID from GameConfig

**Returns:**
```lua
{
    success = boolean,
    reason = string?
}
```

### `SellItems(items: {[string]: number})`
Sell items for coins.

**Parameters:**
- `items`: Dictionary of itemId → count

**Returns:**
```lua
{
    success = boolean,
    coinsEarned = number?,
    reason = string?
}
```

### `EquipItem(itemId: string)`
Equip an item from inventory.

**Returns:**
```lua
{
    success = boolean,
    reason = string?
}
```

### `UnequipItem(slot: string)`
Unequip an item from a slot.

**Parameters:**
- `slot`: "pickaxe", "head", "back", "aura", or "trail"

**Returns:**
```lua
{
    success = boolean,
    reason = string?
}
```

### `UseConsumable(itemId: string)`
Use a consumable item.

**Returns:**
```lua
{
    success = boolean,
    reason = string?
}
```

### `EquipPet(petId: string)`
Equip a pet.

### `UnequipPet(petId: string)`
Unequip a pet.

### `VisitNeighbor(playerId: number)`
Visit another player's cube.

### `ReturnHome()`
Return to your own cube.

### `GetNeighborhood()`
Get list of players in neighborhood.

### `GetMetrics()`
Get comprehensive user metrics and statistics.

**Returns:**
```lua
{
    gameplay = {
        totalBlocksDug = number,
        dugThisSession = number,
        blocksPerMinute = number
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
        sessionStartTime = number,  -- Unix timestamp
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
        materialTier = number
    },
    world = {
        currentMaterial = string,
        cubeSize = number,
        totalChunks = number,
        dugCells = number
    }
}
```

### `GetServerMetrics()`
Get server-wide metrics (permission gated).

**Returns:**
```lua
{
    totalPlayers = number,
    serverUptimeSec = number,
    -- Additional fields for authorized users:
    activeDiggers = number?,
    totalBlocksDugServer = number?,
    avgSessionLength = number?,
    peakPlayers = number?,
    totalSessions = number?
}
```

## Remote Events (Server → Client)

### `OnProfileUpdate(profile: PlayerStats)`
Full profile update.

### `OnInventoryChanged(payload)`
Inventory change notification.
```lua
payload = {
    action = "add" | "remove" | "equip" | "unequip",
    itemId = string,
    count = number?,
    total = number?,
    slot = string?
}
```

### `OnUpgradesChanged(payload)`
Upgrades changed.
```lua
payload = {
    upgrades = {[string]: number},
    coins = number
}
```

### `OnBoostsChanged(boosts: {[string]: number})`
Active boosts updated (boost type → expiry timestamp).

### `OnDigFeedback(payload)`
Visual/audio feedback for dig.
```lua
payload = {
    cells = {{x=number, y=number, z=number}},
    shake = boolean,
    particles = boolean,
    sound = string?
}
```

### `OnLootDropped(payload)`
Loot drop animation trigger.
```lua
payload = {
    item = LootDrop,
    worldPos = Vector3
}
```

### `OnNotification(payload)`
General notification.
```lua
payload = {
    type = string,
    message = string,
    color = Color3,
    duration = number?
}
```

### `OnReward(payload)`
Reward granted notification.
```lua
payload = {
    type = "coins" | "gems" | "item",
    amount = number | string,
    source = string
}
```

### `OnCameraShake(intensity: number, duration: number)`
Trigger camera shake.

## UI Implementation Status

### ✅ Currently Implemented
- **Currency Display**: Coins and gems (top-right)
- **Settings Panel**: Basic settings menu
- **Home Button**: Teleport to cube functionality
- **Material Selection**: Through settings panel

### ❌ NOT Implemented (but API exists)
1. **Inventory UI** - Backend exists, no UI
2. **Shop/Upgrades UI** - Backend exists, no UI  
3. **Pets UI** - Backend exists, no UI
4. **Stats Display** - Data available, no UI
5. **Boost Timers** - System exists, no display
6. **Dig Button** - Uses click-to-dig, no button
7. **Equipment UI** - Backend exists, no UI

### Visual Effects
- **Dig Preview**: Show affected cells before digging
- **Loot Popup**: Animated item icon with rarity glow
- **Currency Changes**: +XXX animation when earning
- **Combo Counter**: Consecutive digs without missing

### Mobile Gestures
- **Tap**: Dig at location
- **Swipe**: Rotate camera
- **Pinch**: Zoom in/out
- **Hold**: Show dig preview

## Performance Guidelines

### Mobile Optimization
- Batch UI updates (max 30 FPS)
- Use `TweenService` for smooth animations
- Pool UI elements for loot drops
- Limit active particle emitters
- Use ViewportFrames for 3D item previews

### Network Optimization
- Cache `GetProfile()` results, update incrementally
- Batch `SellItems()` calls
- Debounce dig requests client-side
- Preload common assets

## Example Client Code Structure

```lua
-- client/MiningGame/UIManager.client.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("MiningGame")

-- Cache profile
local profile = Remotes.GetProfile:InvokeServer()

-- Listen for updates
Remotes.OnInventoryChanged.OnClientEvent:Connect(function(payload)
    -- Update inventory UI
end)

-- Dig on tap/click
local function onDigRequest(worldPos)
    local result = Remotes.RequestDig:InvokeServer(worldPos)
    if result.ok then
        -- Update UI with cooldown
        digButton.Cooldown = result.nextAllowedAt - os.time()
    end
end
```

## Testing Checklist

### Core Loop
- [ ] Dig request → terrain update → loot grant → UI update
- [ ] Cooldown enforcement
- [ ] Rate limiting on spam clicks

### Progression
- [ ] Upgrade purchase and application
- [ ] Material unlock and switch
- [ ] Pet equip/buff calculation

### Monetization
- [ ] Developer Product purchase flow
- [ ] Gamepass detection and bonuses
- [ ] Boost timer countdown

### Mobile
- [ ] Touch controls responsive
- [ ] UI scales properly
- [ ] Performance on low-end devices
- [ ] Network lag handling

## Implementation Notes

### ⚠️ Important Context
- **Most UI features are NOT built** despite backend support
- **No extraction/quota system** exists (despite documentation)
- **No AFK system** implemented
- **Sound system has no asset IDs** (all nil)

### Development Guidelines
1. **Server is authoritative** - Always validate server-side
2. **Mobile-first design** - Large touch targets (120x120px minimum)
3. **Error handling** - Check `success`/`ok` fields
4. **Use existing Theme system** - Located in `shared/MiningGame/UI/Theme.lua`

### What Actually Works
- Basic cube mining (click to remove voxels)
- Currency system (coins, gems)
- Material switching
- Basic loot drops
- Multiplayer cube positioning

## Integration Steps

1. Connect to Rojo: `rojo serve` in the mining-game directory
2. Open Studio and connect to localhost:34872
3. Create UI in StarterGui
4. Implement client scripts in `client/` folder
5. Test on mobile emulator
6. Profile performance
7. Iterate on UX

The backend is fully modular and ready for UI integration!