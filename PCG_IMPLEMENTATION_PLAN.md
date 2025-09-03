# Procedural Content Generation (PCG) Implementation Plan

## Overview
Implement a modular, deterministic PCG system for the mining game that generates terrain, resources, decorations, rivers, and fauna around player mining cubes while maintaining compatibility with the existing cube-based mining system.

## Goals
- **Modular Architecture**: Separate concerns into reusable modules
- **Deterministic Generation**: Same seed = same world every time
- **Performance Optimized**: Chunk-based with budgets and yielding
- **Extensible Design**: Easy to add new features without touching core
- **Mining Cube Integration**: Never interfere with player mining cubes

## Directory Structure
```
server/MiningGame/pcg/
├── Core/
│   ├── RNG.lua              # Deterministic random number generation
│   ├── Noise.lua            # Noise functions (FBM, domain warp, Voronoi)
│   ├── Sampler.lua          # Blue noise, Poisson disk, jittered grid
│   ├── Surface.lua          # Terrain sampling and slope calculation
│   ├── Scatter.lua          # Generic scatter with filters
│   └── ChunkManager.lua     # Chunk lifecycle management
├── Generators/
│   ├── TerrainGen.lua       # Height-based terrain generation
│   ├── RiverGen.lua         # River carving system
│   └── BiomeGen.lua         # Biome determination
├── Spawners/
│   ├── ResourceSpawner.lua  # Minable resource nodes
│   ├── DecorationSpawner.lua # Trees, rocks, grass variants
│   └── FaunaSpawner.lua     # Animals with AI
├── ProceduralGenerationService.lua # Main orchestrator
└── PCGDebug.lua             # Debug visualization tools

shared/MiningGame/
├── PCGConfig.lua            # All tunables in one place
└── PCGTypes.lua             # Type definitions
```

## Phase 1: Core Infrastructure (Week 1)

### 1.1 Configuration System
- [x] Create `PCGConfig.lua` with all tunables
  - World settings (seed, chunk size, heights)
  - Terrain layers and materials
  - Resource definitions with spawn rules
  - Decoration definitions
  - Performance budgets
  - Debug settings

### 1.2 Deterministic RNG
- [ ] Implement `RNG.lua` with chunk-based seeding
  - Never use `math.randomseed` globally
  - Each chunk gets deterministic seed: `hash(worldSeed, chunkX, chunkZ)`
  - Support salt for different systems (terrain vs resources)

### 1.3 Noise & Sampling
- [ ] Create `Noise.lua` with FBM, domain warp, Voronoi
- [ ] Implement `Sampler.lua` with Poisson disk, blue noise
  - All sampling must accept RNG parameter
  - Support min/max bounds and spacing

### 1.4 Surface Interaction
- [ ] Build `Surface.lua` for terrain queries
  - Raycast with proper blacklisting
  - Slope calculation
  - Material detection
  - Keep-out zone checking

## Phase 2: Terrain Generation (Week 1-2)

### 2.1 Height-Based Terrain
- [ ] Multi-octave noise for realistic heightmaps
- [ ] Material layers by elevation
- [ ] Underground material progression by depth
- [ ] Water at sea level

### 2.2 Chunk Management
- [ ] Implement lazy chunk generation
- [ ] Track generated chunks to avoid duplicates
- [ ] Support radius-based generation around players
- [ ] Add cleanup for distant chunks (future)

### 2.3 Mining Cube Integration
- [ ] Define keep-out AABB around each cube
- [ ] Never write terrain inside cube bounds
- [ ] Exclude cube parts from raycasts
- [ ] Generate terrain ring around cubes

## Phase 3: Resource & Decoration Spawning (Week 2)

### 3.1 Resource Nodes
- [ ] Spawn minable nodes based on height/slope/material
- [ ] Tag **Parts** not Models for click detection
- [ ] Implement proper `ClickDetector` or `ProximityPrompt`
- [ ] Connect to existing `ItemService` for drops
- [ ] Visual variations by resource tier

### 3.2 Decorations
- [ ] Trees with multiple model variants
- [ ] Rocks and boulders
- [ ] Grass tufts and bushes
- [ ] Biome-specific decorations
- [ ] Scale/rotation variety

### 3.3 Scatter System
- [ ] Generic scatter pipeline with filters:
  - Height range filter
  - Slope limit filter
  - Material/biome filter
  - Density function (noise-based)
  - Stochastic acceptance

## Phase 4: Advanced Features (Week 3)

### 4.1 River Generation
- [ ] Trace paths from high elevation to sea
- [ ] Follow terrain gradient
- [ ] Carve channels with `WriteVoxels`
- [ ] Fill with water material
- [ ] Add river decorations (rocks, plants)

### 4.2 Fauna System
- [ ] Spawn animals per biome rules
- [ ] Simple wander AI
- [ ] LOD system for performance
- [ ] Unload beyond distance
- [ ] Per-chunk population caps

### 4.3 Biome System
- [ ] Define biomes by height + moisture
- [ ] Biome-specific resource multipliers
- [ ] Unique decoration sets per biome
- [ ] Smooth biome transitions

## Phase 5: Optimization & Polish (Week 4)

### 5.1 Performance
- [ ] Implement generation yielding
- [ ] Add per-chunk budgets (max objects)
- [ ] LOD system for distant objects
- [ ] Streaming support preparation
- [ ] Profile and optimize hot paths

### 5.2 Debug Tools
- [ ] Chunk border visualization
- [ ] Density map overlay
- [ ] Spawn point debugging
- [ ] Generation time tracking
- [ ] Biome visualization mode

### 5.3 Integration
- [ ] Hook into `SpawnService` for auto-generation
- [ ] Connect to `GridService` for cube bounds
- [ ] Update `ItemService` for resource mining
- [ ] Add admin commands for regeneration

## Implementation Notes

### Critical Fixes from Review

1. **Tag Parts, not Models**
```lua
-- WRONG: CollectionService:AddTag(model, "ResourceNode")
-- RIGHT:
CollectionService:AddTag(part, "ResourceNode")
```

2. **No Global RNG Pollution**
```lua
-- WRONG: math.randomseed(hash)
-- RIGHT:
local rng = Random.new(hash)
local value = rng:NextNumber()
```

3. **Exclude Folders from Raycasts**
```lua
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances = {
    workspace.ProceduralResources,
    workspace.MiningCube,
}
```

4. **Keep-Out Zones**
```lua
local function isInsideCubeKeepOut(x, z, cubeOrigin, cubeSize, margin)
    local p = Vector3.new(x, 0, z)
    local c = Vector3.new(cubeOrigin.X, 0, cubeOrigin.Z)
    local half = cubeSize/2 + margin
    return math.abs(p.X - c.X) <= half and math.abs(p.Z - c.Z) <= half
end
```

### Resource Mining Flow
1. Player clicks resource node (Part with ClickDetector)
2. Validate tool requirement
3. Play mining animation/sound
4. Call `ItemService:SpawnStackedDrop()` for loot
5. Destroy or respawn node

### Model Organization
```
ReplicatedStorage/MiningGame/
├── Deco/
│   ├── tree/
│   │   ├── Tree1 (Model)
│   │   ├── Tree2 (Model)
│   │   └── Tree3 (Model)
│   ├── rock/
│   │   ├── Rock1 (Model)
│   │   └── Rock2 (Model)
│   └── grass/
│       └── GrassTuft1 (Model)
├── Fauna/
│   ├── deer (Model with Humanoid)
│   ├── wolf (Model with Humanoid)
│   └── rabbit (Model with Humanoid)
└── Resources/
    ├── IronOreNode (Model)
    ├── CopperOreNode (Model)
    ├── GoldOreNode (Model)
    └── CrystalNode (Model)
```

## Testing Plan

### Unit Tests
- [ ] RNG determinism across server restarts
- [ ] Noise function continuity at chunk borders
- [ ] Sampler distribution uniformity
- [ ] Keep-out zone validation

### Integration Tests
- [ ] Chunk generation consistency
- [ ] Resource mining flow
- [ ] Multi-player chunk sharing
- [ ] Performance under load

### Manual Testing
- [ ] Visual inspection of terrain variety
- [ ] Resource distribution balance
- [ ] River flow naturalism
- [ ] Fauna behavior
- [ ] No interference with mining cubes

## Success Metrics
- Chunk generation < 100ms per chunk
- No lag spikes during generation
- Consistent world across server restarts
- Zero terrain/resource spawns inside cube bounds
- Natural-looking distribution of objects
- Easy to add new content types

## Future Enhancements
- Cave system generation
- Dungeons and structures
- Weather effects
- Day/night cycle integration
- Seasonal variations
- Player-built structure protection
- Chunk caching/saving
- Procedural quests/events