# Mining Game API Documentation

## Overview

This document provides an index to the comprehensive API documentation for all client-server communication in the Mining Game. All communication occurs through RemoteEvents and RemoteFunctions located in `ReplicatedStorage.Remotes.MiningGame`.

## Documentation Structure

The API documentation is split into focused sections for easier navigation:

1. **[API_REMOTE_FUNCTIONS.md](API_REMOTE_FUNCTIONS.md)** - Client→Server requests with responses
2. **[API_REMOTE_EVENTS.md](API_REMOTE_EVENTS.md)** - Server→Client notifications
3. **[API_BEST_PRACTICES.md](API_BEST_PRACTICES.md)** - Best practices, examples, and testing

## Quick Reference

### Architecture

- **RemoteFunctions**: Used for client→server requests that require a response
- **RemoteEvents**: Used for server→client notifications (fire-and-forget)
- **Security**: All validation happens server-side; never trust client input
- **Rate Limiting**: Built into critical functions like digging

### Client Usage

```lua
-- Getting remotes
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Remotes = require(MiningGame:WaitForChild("Remotes"))

-- Using RemoteFunctions
local result = Remotes.RF.RequestDig:InvokeServer(worldPos)

-- Listening to RemoteEvents
Remotes.RE.OnCurrencyChanged.OnClientEvent:Connect(function(data)
    -- Handle update
end)
```

## API Categories

### RemoteFunctions (42 total)

#### Core Systems
- **Gameplay**: GetProfile, RequestDig, StartContinuousDig, StopContinuousDig
- **Inventory**: SellItems, EquipItem, UnequipItem, UseConsumable
- **Pets**: EquipPet, UnequipPet, UpgradePet
- **Purchases**: PurchaseUpgrade, PurchaseProduct, PurchaseMaterial
- **Social**: VisitNeighbor, ReturnHome, GetNeighborhood
- **Customization**: Material settings, theme settings, UpdateSettings
- **Movement**: TeleportToHome, RespawnCubeModel
- **Metrics**: GetMetrics, GetServerMetrics
- **Cloth**: ClothSpawn, ClothDestroy

#### Debug & Testing (Studio/Developer only)
- **Debug Tools**: Currency, stats, and cube reset
- **Simulation**: Agent management and spawn strategies
- **Items**: PickupItem, SpawnTestItem

[See full RemoteFunction documentation →](API_REMOTE_FUNCTIONS.md)

### RemoteEvents (26 total)

#### State Updates
- Profile, currency, inventory, upgrades, boosts, pets

#### Gameplay Events
- Dig feedback, terrain updates, loot drops, first dig

#### Social Events
- Neighbor joined/left, cube updates

#### Notifications
- General notifications, rewards, achievements

#### UI & Items
- Item collection, pickup prompts, sounds

#### Effects & Visuals
- Sound effects, particles, camera shake, cloth updates

[See full RemoteEvent documentation →](API_REMOTE_EVENTS.md)

## Implementation Status

### ✅ Fully Implemented
- Core dig/mining system
- Currency and inventory management
- Material customization
- Theme settings
- Metrics tracking
- Debug tools

### ⚠️ Partially Implemented
- Pet system (backend exists, no UI)
- Equipment system (backend exists, limited UI)
- Boost system (backend exists, no UI)

### ❌ Not Implemented
- Multiplayer visiting (VisitNeighbor, ReturnHome)
- Achievement system
- Trading system
- Clan/guild functionality

## Quick Links

- [Error Handling Guide](API_BEST_PRACTICES.md#error-handling)
- [Performance Optimization](API_BEST_PRACTICES.md#performance-optimization)
- [Testing Checklist](API_BEST_PRACTICES.md#testing-checklist)
- [Migration Notes](API_BEST_PRACTICES.md#migration-notes)

## Support

For questions about the API or to report issues:
1. Check the relevant documentation section
2. Review example code in `client/TestClient.client.lua`
3. Contact the development team with specific error messages and reproduction steps