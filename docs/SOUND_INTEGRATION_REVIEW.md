# Sound Integration Review

## Overview
This document reviews the complete material-to-sound integration pipeline in the mining game, featuring a single-source-of-truth architecture where all material properties derive from MaterialDefinitions.

## Architecture

### Core Modules (Dependency Order)

#### 1. SoundCategories (shared/MiningGame/SoundCategories.lua)
- **Purpose**: Canonical list of sound categories and their event schemas
- **No Dependencies**: Base module that others build upon
- **Categories**: rock, ice, sand, mud, snow, water, grass, dirt, wood
- **Mining Events per Category**:
  - rock: hit, break, crumble
  - ice: hit, break, shatter
  - sand: hit, break, scatter
  - mud: hit, break, squish
  - snow: hit, break, crunch
  - water: hit, splash, flow
  - grass: hit, break, dig
  - dirt: hit, break, dig
  - wood: hit, break, crack
- **Validation**: Provides IsValid() to check category validity

#### 2. MaterialDefinitions (shared/MiningGame/MaterialDefinitions.lua)
- **Purpose**: Single source of truth for ALL terrain material properties
- **Dependencies**: SoundCategories (for validation)
- **Contains**: 22 terrain materials with properties:
  - `enum`: Roblox Enum.Material value
  - `displayName`: Human-readable name
  - `order`: UI sort order
  - `properties`:
    - `speedMultiplier`: Movement speed modifier
    - `soundCategory`: Valid category from SoundCategories
    - `digDifficulty`: Mining difficulty
    - `color`: UI display color
- **Precomputed Arrays**:
  - `AllTerrainEnums`: All Enum.Material values (sorted)
  - `KeysOrdered`: All material keys (sorted)
  - `KeyFromEnum`: Reverse lookup table
- **Validation**: All sound categories validated at startup
- **Immutability**: All tables frozen with table.freeze

#### 3. MaterialKeys (shared/MiningGame/MaterialKeys.lua)
- **Purpose**: Backwards compatibility layer
- **Dependencies**: MaterialDefinitions
- **Derives Everything**: All data comes from MaterialDefinitions
  - `TerrainKeys`: From MaterialDefinitions.KeysOrdered
  - `EnumFromKey`: From MaterialDefinitions materials
  - `DisplayNames`: From MaterialDefinitions materials
  - `KeyFromEnum`: From MaterialDefinitions.KeyFromEnum
- **Immutability**: All tables frozen

#### 4. SoundConfig (shared/MiningGame/SoundConfig.lua)
- **Purpose**: Sound configuration and asset management
- **Dependencies**: MaterialDefinitions, MaterialKeys, SoundCategories
- **Dynamic Generation**:
  - Mining sounds built from MaterialDefinitions + SoundCategories
  - Footstep mapping from material soundCategories
  - No hardcoded material lists
- **Validation at Startup**:
  - Every material has mining sounds
  - Every material has expected events
  - Every sound category has footstep sounds

### Material-to-Category Mapping
```
Rock category (11 materials): rock, sandstone, basalt, slate, limestone, 
                              cobblestone, brick, concrete, asphalt, pavement,
                              crackedlava
Ice category (2 materials): glacier, ice
Snow category (1 material): snow
Sand category (2 materials): sand, salt
Mud category (1 material): mud
Dirt category (1 material): ground
Grass category (2 materials): grass, leafygrass
Wood category (1 material): woodplanks
Water category (1 material): water
```

## Sound Flow

### Mining Sounds:
1. **Server Side** (server/MiningGame/DigService.lua):
   - Player digs → gets material key from terrain
   - Returns `soundMaterialKey` and `soundWorldPos` to client
   - Calls `SoundBroadcast.Mining(player, position, materialKey, "hit")`
   
2. **Broadcast** (server/MiningGame/SoundBroadcast.lua):
   - Rate limits sounds per player
   - Broadcasts to players within radius (120 studs)
   - Uses MaterialKeys.KeyFromEnum for terrain lookup

3. **Client Reception** (client/SoundReplication.client.lua):
   - Receives broadcast, skips own sounds (via originUserId)
   - Calls `SoundManager.PlayMining(materialKey, subtype, position)`

4. **Local Playback** (client/TestClient.client.lua):
   - **NEW**: Waits for server response before playing sound
   - **NEW**: Only plays sound on successful dig (ok = true)
   - **NEW**: Uses server's `soundMaterialKey` and `soundWorldPos` for accuracy
   - Includes local cooldown guard to prevent unnecessary requests
   - Falls back to local material detection if server data missing

5. **Sound Manager** (shared/MiningGame/SoundManager.lua):
   - Looks up sound ID via `SoundConfig.GetMiningSoundForMaterial()`
   - Creates 3D positioned sound at dig location
   - Applies volume falloff (50 studs max distance)

### Footstep Sounds:
1. **Material Detection**: Movement system detects terrain material
2. **Category Lookup**: Material key → soundCategory (via FOOTSTEP_MAP)
3. **Sound Selection**: soundCategory → footstep sound ID
4. **Playback**: Currently using test sounds (implementation ready)

## Service Integration

### CubeMaterialService (server/MiningGame/CubeMaterialService.lua)
- Uses `MaterialDefinitions.AllTerrainEnums` for terrain replacement
- Uses `MaterialKeys.EnumFromKey` for material lookup
- No hardcoded material lists

### Movement/Config (shared/Movement/Config.lua)
- Builds `TERRAIN_MULT` from MaterialDefinitions
- Preserves `PART_SURFACE_MULT` for non-terrain (Metal, Granite)
- Helper functions for speed lookup

### MaterialsTab UI (client/MiningGame/UI/Components/MaterialsTab.lua)
- Gets colors from `MaterialDefinitions.Materials[key].properties.color`
- No hardcoded color tables
- Uses MaterialKeys for display names

### GridService (server/MiningGame/GridService.lua)
- Uses MaterialKeys for terrain material conversion
- Maps terrain Enum to material keys for sound system

## Adding New Materials

### Simple Process:
1. Add ONE entry to `MaterialDefinitions.Materials`:
```lua
newmaterial = {
    enum = Enum.Material.Limestone,  -- Must be unused Roblox terrain material
    displayName = "New Material",
    order = 25,  -- Optional UI order
    properties = {
        speedMultiplier = 1.0,
        soundCategory = "rock",  -- Must be valid from SoundCategories
        digDifficulty = 1.0,
        color = Color3.fromRGB(200, 200, 200),
    }
}
```

2. **That's it!** Everything else happens automatically:
   - Added to MaterialKeys.TerrainKeys
   - Mining sounds generated
   - Footstep sounds mapped
   - UI shows with color
   - Movement speed applied
   - Full validation at startup

### Adding New Sound Categories:
1. Add to `SoundCategories.Categories` and `Ordered`
2. Define mining events in `SoundCategories.MiningEvents`
3. Add footstep sound in `SoundConfig.SoundIDs.movement.footstep`

## Sound Preloading

### SoundPreloader (client/SoundPreloader.client.lua)
- Automatically preloads all sound assets on client startup
- Prevents first-play audio hitches
- Safely handles missing sound categories
- Parents temporary sounds to SoundService for Studio compatibility
- Collects sounds from all categories: mining, movement, UI, ambient, music, pets, rewards, environment

## Current State

### ✅ Working:
- Single-source-of-truth architecture (MaterialDefinitions)
- Full validation at startup with helpful error messages
- Dynamic sound generation from material categories
- Immutable data structures with table.freeze()
- 22 terrain materials fully configured
- Footstep sound mapping via soundCategory
- **No phantom sounds** - Only plays on successful digs (server-validated)
- **Server-authoritative sounds** - Client uses server's material and position
- Server replication to other players (no double-play for digger)
- 3D positional audio with proper falloff (50 studs)
- UI sounds with button click feedback
- Audio preloading for smooth playback
- Test sound (rbxassetid://9120386436) for all effects

### ⚠️ Needs Implementation:
- Actual sound assets (currently all using test click sound)
- Custom footstep sounds (ready for assets)
- Movement sounds (jump, double jump, land)
- Ambient sounds based on location/time
- Music system

### 🔧 Key Files:
- `shared/MiningGame/MaterialDefinitions.lua` - Single source of truth
- `shared/MiningGame/SoundCategories.lua` - Sound category definitions
- `shared/MiningGame/MaterialKeys.lua` - Backwards compatibility
- `shared/MiningGame/SoundConfig.lua` - Sound configuration
- `shared/MiningGame/Types.lua` - Updated with soundMaterialKey and soundWorldPos
- `client/TestClient.client.lua` - Local sound playback logic
- `client/SoundPreloader.client.lua` - Audio asset preloading
- `server/MiningGame/DigService.lua` - Returns sound data to client
- `ADDING_NEW_MATERIALS.md` - Complete guide for adding materials

## Validation Features

The system validates at startup:
- All material sound categories are valid
- All materials have required properties
- All expected mining events exist
- All used categories have footstep sounds
- No duplicate Enum.Material values
- All tables are frozen (immutable)

Any configuration errors show clear messages in the console.

## Performance Optimizations

- Precomputed arrays (AllTerrainEnums, KeysOrdered)
- Frozen tables prevent runtime mutations
- Single-pass validation at startup
- Dynamic generation reduces memory footprint
- No redundant data storage
- SoundBroadcast required once at module top
- Audio assets preloaded to prevent hitches

## Distance Configuration

### Current Settings:
- **Local sound rolloff**: 50 studs (SoundConfig.Properties.Mining.RollOffMaxDistance)
- **Replication distance**: 120 studs (SoundReplication CATEGORY_MAX_DISTANCE)
- **Result**: Players hear their own digs within 50 studs, other players' digs up to 120 studs

### To Adjust:
- For consistent distances: Set both to same value
- For performance: Keep replication > rolloff (current setup)
- Files to modify: `SoundConfig.lua` (rolloff) and `SoundReplication.client.lua` (max distance)