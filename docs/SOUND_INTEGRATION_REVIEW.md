# Sound Integration Review

## Overview
This document reviews the complete material-to-sound integration pipeline in the mining game, featuring a single-source-of-truth architecture where all material properties derive from MaterialDefinitions. The system now includes a comprehensive theme system for dynamic sound pack switching.

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
- **Purpose**: Default sound configuration and asset management
- **Dependencies**: MaterialDefinitions, MaterialKeys, SoundCategories
- **Dynamic Generation**:
  - Mining sounds built from MaterialDefinitions + SoundCategories
  - Footstep mapping from material soundCategories
  - No hardcoded material lists
- **Validation at Startup**:
  - Every material has mining sounds
  - Every material has expected events
  - Every sound category has footstep sounds
- **Note**: Currently uses placeholder sounds (rbxassetid://9120386436) for development

### NEW: Theme System Modules

#### 5. SoundThemeManager (shared/MiningGame/SoundThemeManager.lua) 🆕
- **Purpose**: Dynamic sound theme/pack management system
- **Features**:
  - Runtime theme switching without restart
  - Hierarchical sound ID resolution with intelligent fallback
  - Partial override support (themes only override specific sounds)
  - Changed signal for reactive updates
  - Preloading optimization via GetAllIds() and GetCategoryIds()
- **API**:
  - `SetTheme(packModule)`: Switch to a new sound pack
  - `GetId(path)`: Resolve sound ID with theme overrides and fallbacks
  - `GetAllIds()`: Get all sound IDs for preloading
  - `Changed`: Signal fired when theme changes

#### 6. SoundManager (shared/MiningGame/SoundManager.lua) - UPDATED
- **Purpose**: Central sound management with pooling and 3D spatial audio
- **Theme Integration**: Now uses `SoundTheme.GetId()` for all sound resolution
- **Categories**: UI, Mining, Movement, Ambient, Music, Pets, Rewards, Environment
- **Features**:
  - Object pooling for performance
  - 3D spatial audio with custom emitters
  - Sound groups for volume mixing (SFX, UI, Ambient, Music)
  - Crossfading for music transitions
  - Automatic theme-aware sound resolution

#### 7. Sound Packs (shared/MiningGame/SoundPacks/*.lua) 🆕
- **Available Packs**:
  - `default`: Base sounds (inherits from SoundConfig)
  - `retro`: 8-bit style sounds (example partial override)
  - Additional packs can be added as ModuleScripts
- **Structure**: Mirrors SoundConfig category hierarchy
- **Partial Overrides**: Packs only need to define sounds they want to change

### Server-Side Components

#### 8. ThemeSettingsService (server/MiningGame/ThemeSettingsService.lua) 🆕
- **Purpose**: Server-side validation and persistence of theme settings
- **Features**:
  - Whitelist validation of available sound packs
  - Integration with DataService for persistence
  - GetThemeSettings/UpdateThemeSettings remotes
- **Validation**: Only allows valid sound packs from SoundPacks folder

#### 9. SoundBroadcast (server/MiningGame/SoundBroadcast.lua)
- **Purpose**: Server-side sound broadcasting with optimization
- **Features**:
  - Distance-based filtering (120 stud radius)
  - Rate limiting (mining: 33/sec, movement: 12/sec)
  - Payload sanitization and validation
  - Category-specific broadcast utilities

### Client-Side Components

#### 10. SoundPreloader (client/SoundPreloader.client.lua) - UPDATED 🆕
- **Dynamic Preloading**: Now reacts to theme changes
- **Features**:
  - Automatically preloads sounds from active theme
  - Re-preloads when theme changes
  - Non-blocking with busy/dirty flags
  - Handles both SoundConfig and theme-provided IDs

#### 11. SoundReplication (client/SoundReplication.client.lua)
- **Purpose**: Client-side handling of replicated sounds
- **Features**:
  - Distance-based culling with category-specific ranges
  - Spam prevention with client-side rate limiting
  - Routes sounds to appropriate SoundManager functions
  - Skips own sounds via originUserId check

#### 12. ThemeBootstrap (client/MiningGame/UI/ThemeBootstrap.client.lua) 🆕
- **Purpose**: Early theme initialization before UI loads
- **Features**:
  - Loads saved themes immediately on join
  - Applies both UI and sound themes
  - Fallback handling for missing packs
  - Prevents theme "flash" on startup

### UI Integration

#### 13. ThemeTab (client/MiningGame/UI/Components/ThemeTab.lua) 🆕
- **Purpose**: User interface for theme selection
- **Features**:
  - Dropdown for UI theme selection
  - Dropdown for sound pack selection
  - Real-time preview and application
  - Automatic discovery of available packs
  - Server persistence of preferences

## Material-to-Category Mapping
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

## Sound Flow with Theme System

### Mining Sounds:
1. **Server Side** (server/MiningGame/DigService.lua):
   - Player digs → gets material key from terrain
   - Returns `soundMaterialKey` and `soundWorldPos` to client
   - Calls `SoundBroadcast.MiningLocal(player, position, materialKey, subtype)`
   - MiningLocal culls by distance server-side and plays 2D/local on recipients
   
2. **Broadcast** (server/MiningGame/SoundBroadcast.lua):
   - Rate limits sounds per player
   - Broadcasts to players within radius (120 studs)
   - Uses MaterialKeys.KeyFromEnum for terrain lookup

3. **Client Reception** (client/SoundReplication.client.lua):
   - Receives broadcast, skips own sounds (via originUserId)
   - Calls `SoundManager.PlayMining(materialKey, subtype, position)`

4. **Theme Resolution** (NEW):
   - SoundManager calls `SoundTheme.GetId({"mining", materialKey, subtype})`
   - SoundThemeManager checks active theme for override
   - Falls back through: Theme → Category → Default → Placeholder
   - Returns appropriate sound ID for current theme

5. **Local Playback** (client/TestClient.client.lua):
   - Waits for server response before playing sound
   - Uses server-provided material key or local probe
   - Sound played through theme-aware SoundManager

### Footstep Sounds:
1. Material detected from Humanoid.FloorMaterial
2. MaterialKeys.KeyFromEnum converts to key
3. SoundTheme.GetId({"movement", "footstep", soundCategory}) resolves
4. Theme-specific footstep sound plays

### Ambient/Music:
1. Time/weather conditions determine ambient selection
2. SoundTheme.GetId({"ambient", condition}) resolves
3. Theme-specific ambient/music tracks play
4. Automatic restart when theme changes

## Theme System Features

### Runtime Theme Switching
- No restart required to change sound packs
- All active sounds automatically update
- Music/ambient crossfades to new theme tracks
- Preloader automatically fetches new assets

### Hierarchical Fallback
Sound resolution follows this path:
1. **Theme Override**: Check if active theme defines the sound
2. **Category Fallback**: Try theme's category-level sound
3. **Default Sound**: Use SoundConfig default
4. **Placeholder**: Final fallback to test sound

Example resolution for `{"mining", "rock", "hit"}`:
```lua
-- Try these in order:
theme.mining.rock.hit       -- Specific override
theme.mining.rock           -- Rock category default
SoundConfig.mining.rock.hit -- System default
TEST_CLICK                  -- Placeholder
```

### Creating New Sound Packs
1. Create ModuleScript in `shared/MiningGame/SoundPacks/`
2. Define partial or complete sound hierarchy:
```lua
return {
    name = "MyPack",
    mining = {
        rock = {
            hit = "rbxassetid://123456",  -- Override specific sound
        }
    }
    -- Don't need to define everything - falls back to default
}
```
3. Pack automatically appears in ThemeTab UI
4. Server validates and persists user selection

## Integration Points

### Data Persistence
- User preferences stored via DataService
- Theme settings persist across sessions
- Server-side validation prevents invalid themes

### Performance Optimizations
- Sound preloading adapts to active theme
- Object pooling reduces instance creation
- Rate limiting prevents spam
- Distance culling reduces network traffic

### Developer Experience
- Hot-swappable themes for rapid iteration
- Partial overrides for incremental development
- Comprehensive validation catches errors early
- Changed signals enable reactive UI updates

## Testing Sound Themes

### In Studio:
1. Open Settings Panel (gear icon)
2. Navigate to Theme tab
3. Select sound pack from dropdown
4. Changes apply immediately
5. Test sounds through gameplay

### Adding Test Sounds:
1. Create pack in `SoundPacks/` folder
2. Add sound IDs for testing
3. Pack appears in UI automatically
4. No server restart required

## Future Enhancements

### Planned Features:
- User-created sound packs
- Sound pack marketplace
- Volume mixing per pack
- Seasonal/event themes
- Sound effect chains
- Dynamic music layers

### API Stability:
- Theme system designed for backward compatibility
- New features won't break existing packs
- Fallback system ensures sounds always play
- Validation prevents runtime errors
