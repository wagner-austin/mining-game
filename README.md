# Mining Game

A mobile-optimized Roblox mining game with pay-to-progress mechanics.

## Setup
1. Run `rojo serve` in this directory
2. Connect Rojo plugin in Studio to localhost:34872

## Architecture

### Server-Authoritative Systems
- **GridService**: Manages terrain voxels using WriteVoxels for performance
- **DataService**: Handles persistence with DataStore v2
- **LootService**: Deterministic drops based on cell coordinates
- **DigService**: Core game loop with rate limiting
- **UpgradeService**: Player progression calculations
- **MonetizationService**: Robux purchases and gamepasses

### Optimizations
- Terrain-based voxel system (4x4x4 stud cells)
- Chunk-based state management (16x16x16 chunks)
- Instance streaming for mobile performance
- Deterministic loot (no per-cell storage needed)

## Structure
- `server/MiningGame/` - Server-side services
- `shared/MiningGame/` - Shared modules and config
- `client/` - UI and client scripts (for Claude Opus)
- `StarterPack/` - Player tools
- `Workspace/Map/` - World objects
- `ServerStorage/Items/` - Spawnable items