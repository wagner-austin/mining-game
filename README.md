# Mining Game

A mobile-optimized Roblox mining game with pay-to-progress mechanics.

## Setup
1. `aftman install` once, to fetch the pinned toolchain from `aftman.toml`
2. `make wally-install` to fetch Lua packages
3. `make run` (or `rojo serve`) in this directory
4. Connect the Rojo plugin in Studio to `localhost:34873` — the port is set by
   `servePort` in `default.project.json`

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
- `coordination/` - Engineering standards and design notes
- `docs/` - System documentation (47 files; start at `DOCUMENTATION_INDEX.md`)
- `scripts/` - Build and dev scripts
- `tools/` - Analysis helpers
- `tests/` - TestEZ specs
- `deprecated/` - Retired scripts kept for reference, `.disabled` so Studio ignores them

## Dev Tooling
- Lint: `selene .` (config: `.selene.toml`)
- Format: `stylua .` (config: `.stylua.toml`)
- Packages: `wally install` (installs into `Packages/`)
- Make targets: `make check` (the gate), `fmt`, `lint`, `analyze`, `analyze-server`,
  `test`, `wally-install`, `run`, `help`

### Toolchain via Aftman (recommended)
- Install Aftman once, then run `aftman install` to fetch pinned tool versions defined in `aftman.toml`.
- On Windows PowerShell:
  - `iwr https://raw.githubusercontent.com/LPGhatguy/aftman/main/install.ps1 -UseBasicParsing | iex`
  - Then `aftman install`
- Makefile commands use `aftman run ...` so you don’t need global installs.

### Running Tests (TestEZ)
1. Run `wally install` to fetch `Roblox/TestEZ` into `Packages/`.
2. Ensure Rojo maps `Packages` and `tests` into `ReplicatedStorage` (already in `default.project.json`).
3. In Studio, enable `ServerScriptService/TestRunner.server.lua` (remove `.disabled` or uncheck Disabled) and play; results print to the Output window.
   - Tests live in `tests/` (example: `tests/MathUtils.spec.lua`).
