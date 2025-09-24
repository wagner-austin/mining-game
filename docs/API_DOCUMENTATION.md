# Mining Game API Documentation

## Overview

This document indexes the API used by the Mining Game. Request/response calls use RemoteFunctions (RF) with strict validation and rate limiting. Server->client notifications use a single bridged RemoteEvent and the in-repo EventBus for decoupled pub/sub.

## Documentation Structure

1. **[REMOTE_ARCHITECTURE.md](REMOTE_ARCHITECTURE.md)** – Remote system architecture
2. **[API_REMOTE_FUNCTIONS.md](API_REMOTE_FUNCTIONS.md)** – Client->Server requests (RF)
3. **[API_REMOTE_EVENTS.md](API_REMOTE_EVENTS.md)** – Server->Client notifications (EventBus)
4. **[EVENTBUS_SYSTEM.md](EVENTBUS_SYSTEM.md)** – Event-driven patterns
5. **[API_BEST_PRACTICES.md](API_BEST_PRACTICES.md)** – Guidance and examples

## Quick Reference

### Architecture

- RFRegistry: Auto-discovers `RemoteFns/*` specs
- RemoteManager: Schema validation and rate limiting
- EventBus: Decoupled pub/sub, bridged over one RemoteEvent
- ClientRF: Client helper for RF calls

### Client Usage

```lua
-- RF call
local ClientRF = require(MiningGame.ClientRF)
local profile, err = ClientRF.call("GetProfile")

-- EventBus subscription
local Bus = require(MiningGame.EventBus).global()
local EventNames = require(MiningGame.EventNames)
Bus:on(EventNames.CURRENCY_CHANGED, function(data)
    print("Coins:", data.balance)
end)

-- EventBus request via bridge
local Bridge = require(MiningGame.RemoteEventBridge)
Bridge.requestMetrics() -- server pushes metrics.updated
```

## API Categories

### RemoteFunctions (organized in RemoteFns/)

Examples:
- Gameplay: GetProfile, RequestDig
- Inventory: SellItems, EquipItem, UseConsumable
- Purchases: PurchaseUpgrade, PurchaseProduct, PurchaseGamepass
- Social: VisitNeighbor, ReturnHome
- Customization: UpdateSettings
- Movement: TeleportToHome

[See RemoteFunction reference](API_REMOTE_FUNCTIONS.md)

### RemoteEvents (via EventBus)

State updates:
- Profile, currency, inventory, upgrades, boosts, pets

Gameplay events:
- Dig feedback, terrain updates, loot drops

Notifications & UI:
- Announcements, rewards, item collection, sounds

[See RemoteEvent reference](API_REMOTE_EVENTS.md)
[See EventBus documentation](EVENTBUS_SYSTEM.md)

### EventBus Requests (Client->Server via RemoteEventBridge)

- `metrics.request` -> push `metrics.updated` (user metrics)
- `metrics.server.request` -> push `metrics.server.updated` (aggregate server metrics; Studio-only visibility)

## Support

For questions:
- Review examples in `client/TestClient.client.lua`
- Check the reference pages above

