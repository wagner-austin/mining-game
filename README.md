# Mining Game

A mobile-optimized Roblox mining game with pay-to-progress mechanics.

## Setup
1. Run `rojo serve` in this directory
2. Connect Rojo plugin in Studio to localhost:34872

## Documentation
- 📚 **[DOCUMENTATION_INDEX.md](DOCUMENTATION_INDEX.md)** - Complete documentation index
- 🎵 **[AMBIENT_ZONE_DOCUMENTATION.md](AMBIENT_ZONE_DOCUMENTATION.md)** - Ambient sound zones
- ⛏️ **[ADDING_NEW_MATERIALS.md](ADDING_NEW_MATERIALS.md)** - How to add terrain materials
- 🔊 **[SOUND_INTEGRATION_REVIEW.md](SOUND_INTEGRATION_REVIEW.md)** - Sound system architecture

## Architecture

### Server-Authoritative Systems
- **GridService**: Manages terrain voxels using WriteVoxels for performance
- **DataService**: Handles persistence with DataStore v2
- **LootService**: Deterministic drops based on cell coordinates
- **DigService**: Core game loop with rate limiting
- **UpgradeService**: Player progression calculations
- **MonetizationService**: Robux purchases and gamepasses

### Client Systems
- **Sound System**: 3D positional audio, ambient zones, time-based sounds
- **Movement System**: Double jump, terrain-based speed modifiers
- **UI System**: Modular components with hot-reloadable design

### Optimizations
- Terrain-based voxel system (4x4x4 stud cells)
- Chunk-based state management (16x16x16 chunks)
- Instance streaming for mobile performance
- Deterministic loot (no per-cell storage needed)
- Sound pooling and efficient ambient zone management

## Structure
- `server/MiningGame/` - Server-side services
- `shared/MiningGame/` - Shared modules and config
- `client/` - UI and client scripts
- `character/` - Character scripts (movement, etc.)
- `StarterPack/` - Player tools
- `Workspace/Map/` - World objects
- `ServerStorage/Items/` - Spawnable items