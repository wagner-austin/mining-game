# Mining Game API Documentation

## Overview

This document provides an index to the comprehensive API documentation for all client-server communication in the Mining Game. The API uses a centralized RFRegistry pattern with strict validation, rate limiting, and Result normalization for all RemoteFunctions, while RemoteEvents are handled through the EventBus system.

## Documentation Structure

The API documentation is organized into several focused sections:

1. **[REMOTE_ARCHITECTURE.md](REMOTE_ARCHITECTURE.md)** - Complete remote system architecture (NEW)
2. **[API_REMOTE_FUNCTIONS.md](API_REMOTE_FUNCTIONS.md)** - Client→Server requests with responses
3. **[API_REMOTE_EVENTS.md](API_REMOTE_EVENTS.md)** - Server→Client notifications via EventBus
4. **[EVENTBUS_SYSTEM.md](EVENTBUS_SYSTEM.md)** - Event-driven communication system (NEW)
5. **[API_BEST_PRACTICES.md](API_BEST_PRACTICES.md)** - Best practices, examples, and testing

## Quick Reference

### Architecture

- **RFRegistry**: Centralized RF management with automatic discovery from `RemoteFns/` specs
- **RemoteManager**: Enforces schema validation, rate limiting, and profile requirements
- **EventBus**: Decoupled pub/sub system for all server→client events
- **ClientRF**: Client helper with Result unwrapping and retry logic
- **Security**: Strict server-side validation with schema validators
- **Rate Limiting**: Enforced on all RemoteFunctions via token bucket algorithm

### Client Usage

```lua
-- Modern approach with ClientRF
local ClientRF = require(MiningGame.ClientRF)
local EventBus = require(MiningGame.EventBus).global()
local EventNames = require(MiningGame.EventNames)

-- RemoteFunction calls with automatic Result unwrapping
local profile, err = ClientRF.call("GetProfile")
if not profile then
    warn("Failed:", err)
    return
end

-- EventBus for server events
EventBus:on(EventNames.CURRENCY_CHANGED, function(data)
    print("New balance:", data.payload.balance)
end)

-- Client to server events
local Bridge = require(MiningGame.RemoteEventBridge)
Bridge.send(RequestNames.INVENTORY_REQUEST_SELL, {
    itemId = "diamond",
    quantity = 5
})
```

## API Categories

### RemoteFunctions (59 total, organized in RemoteFns/)

#### Core Systems
- **Gameplay**: GetProfile, RequestDig, StartContinuousDig, StopContinuousDig
- **Inventory**: SellItems, EquipItem, UnequipItem, UseConsumable
- **Pets**: EquipPet, UnequipPet, UpgradePet
- **Purchases**: PurchaseUpgrade, PurchaseProduct, PurchaseGamepass
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

### RemoteEvents (via EventBus)

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
[See EventBus documentation →](EVENTBUS_SYSTEM.md)

## Implementation Status

### ✅ Fully Implemented
- RFRegistry pattern with automatic spec discovery
- RemoteManager with strict validation and rate limiting
- EventBus system for decoupled communication
- Result format normalization
- Core dig/mining system
- Currency and inventory management
- Material customization
- Theme settings
- Metrics tracking
- Debug tools (Studio-only)

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

- [Remote Architecture](REMOTE_ARCHITECTURE.md) - Complete remote system design
- [Service Architecture](SERVICE_ARCHITECTURE.md) - Service container and DI
- [EventBus System](EVENTBUS_SYSTEM.md) - Event-driven patterns
- [Error Handling Guide](API_BEST_PRACTICES.md#error-handling)
- [Performance Optimization](API_BEST_PRACTICES.md#performance-optimization)
- [Testing Checklist](API_BEST_PRACTICES.md#testing-checklist)
- [Migration Guide Q1 2025](MIGRATION_GUIDE_Q1_2025.md) - Migrating to new patterns

## Support

For questions about the API or to report issues:
1. Check the relevant documentation section
2. Review example code in `client/TestClient.client.lua`
3. Contact the development team with specific error messages and reproduction steps
