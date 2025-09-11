# Mining Game

A mobile-optimized Roblox mining game with pay-to-progress mechanics.

## Setup
1. Run `rojo serve` in this directory
2. Connect Rojo plugin in Studio to localhost:34872

## Documentation
- 📚 **[DOCUMENTATION_INDEX.md](DOCUMENTATION_INDEX.md)** - Complete documentation index
- 🏗️ **[docs/SERVICE_ARCHITECTURE.md](docs/SERVICE_ARCHITECTURE.md)** - Service container & dependency injection
- 📡 **[docs/REMOTE_ARCHITECTURE.md](docs/REMOTE_ARCHITECTURE.md)** - RFRegistry & RemoteManager system
- 🚌 **[docs/EVENTBUS_SYSTEM.md](docs/EVENTBUS_SYSTEM.md)** - Event-driven communication
- 📖 **[docs/API_DOCUMENTATION.md](docs/API_DOCUMENTATION.md)** - Complete API reference

## Architecture

### Core Infrastructure (Q1 2025 Refactor)
- **ServiceContainer**: Dependency injection with topological initialization
- **RFRegistry**: Centralized RemoteFunction management with specs
- **RemoteManager**: Strict validation, rate limiting, Result normalization
- **EventBus**: Decoupled pub/sub system for all events
- **Time Module**: Standardized timing utilities (no tick())

### Server-Authoritative Systems
- **GridService**: Manages terrain voxels using WriteVoxels for performance
- **DataService**: Handles persistence with DataStore v2, emits EventBus events
- **LootService**: Deterministic drops based on cell coordinates
- **DigService**: Core game loop with rate limiting via RemoteManager
- **UpgradeService**: Player progression calculations
- **MonetizationService**: Robux purchases and gamepasses

### Client Systems
- **ClientRF**: Type-safe RemoteFunction calls with Result unwrapping
- **RemoteEventBridge**: EventBus connection for server events
- **AccountDataProvider**: Reactive data management with EventBus
- **Sound System**: 3D positional audio, ambient zones, time-based sounds
- **Movement System**: Double jump, terrain-based speed modifiers
- **UI System**: Modular components with BaseTabComponent patterns

### Optimizations
- Terrain-based voxel system (4x4x4 stud cells)
- Chunk-based state management (16x16x16 chunks)
- Instance streaming for mobile performance
- Deterministic loot (no per-cell storage needed)
- Sound pooling and efficient ambient zone management

## Structure
- `server/MiningGame/` - Server-side services with DI container
  - `RemoteFns/` - RemoteFunction specifications
  - `ServiceContainer.lua` - Dependency injection
  - `ServiceManager.lua` - Service registration and startup
  - `RemoteManager.lua` - Remote infrastructure
  - `RemoteEventBridge.lua` - EventBus <-> RemoteEvent bridge (server)
- `shared/MiningGame/` - Shared modules and config
  - `EventBus.lua` - Event system
  - `Time.lua` - Timing utilities
  - `Result.lua` - Result type
  - `ClientRF.lua` - Client remote helper
- `client/` - UI and client scripts
  - `RemoteEventBridge.client.lua` - Event routing
- `character/` - Character scripts (movement, etc.)
- `StarterPack/` - Player tools
- `Workspace/Map/` - World objects
- `ServerStorage/Items/` - Spawnable items
