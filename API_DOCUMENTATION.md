# Mining Game API Documentation

## For Claude Opus (UI Implementation)

This document describes the complete Remote API for implementing the UI. All communication between client and server happens through these RemoteEvents and RemoteFunctions.

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

## UI Components Needed

### Main HUD
- **Dig Button**: Large, mobile-friendly button at `GameConfig.MobileUI.DIG_BUTTON_POSITION`
- **Currency Display**: Coins and gems at top
- **Stats Bar**: Current dig delay, size, luck
- **Boost Timers**: Active boosts with countdown

### Menus (Mobile-Optimized)
1. **Inventory**
   - Grid view of items
   - Tap to select, hold for info
   - Sell button
   - Equipment slots

2. **Shop**
   - Upgrades tab (speed/size)
   - Materials tab
   - Boosts tab (Robux products)
   - Gamepasses tab

3. **Pets**
   - Pet grid
   - Equip/unequip buttons
   - Star levels display

4. **Settings**
   - Sound toggle
   - Particle quality
   - Camera shake toggle
   - Haptics toggle (when available)

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

## Notes for Claude Opus

1. **All values in GameConfig are tunable** - Use them for UI positioning, colors, limits, etc.

2. **Server is authoritative** - Never trust client input, always validate server-side.

3. **Mobile-first design** - Buttons should be at least 120x120 pixels, important actions near thumb reach.

4. **Haptic feedback** - Use `HapticService` when available (check capability first).

5. **Batch updates** - Group multiple UI updates in same frame for performance.

6. **Error handling** - Always check `success`/`ok` fields before processing results.

7. **Asset preloading** - Preload particle effects, sounds, and UI assets on join.

8. **Responsive feedback** - Show immediate visual feedback even before server responds (then reconcile).

## Integration Steps

1. Connect to Rojo: `rojo serve` in the mining-game directory
2. Open Studio and connect to localhost:34872
3. Create UI in StarterGui
4. Implement client scripts in `client/` folder
5. Test on mobile emulator
6. Profile performance
7. Iterate on UX

The backend is fully modular and ready for UI integration!