# Material System Quick Reference

## Module Dependency Hierarchy
```
SoundCategories (no deps)
    ↑
MaterialDefinitions (requires SoundCategories) - Single source of truth
    ↑
MaterialKeys (requires MaterialDefinitions) - Auto-derived for compatibility
    ↑
SoundConfig (requires all above) - Sound asset mappings
    ↑
Movement Config (uses MaterialDefinitions) - Speed multipliers
```

## Key Files & Their Roles

| File | Location | Purpose | Edit When |
|------|----------|---------|-----------|
| `MaterialDefinitions.lua` | `shared/MiningGame/` | Single source of truth for all materials | Adding/modifying materials |
| `SoundCategories.lua` | `shared/MiningGame/` | Sound category definitions | Adding new sound categories |
| `MaterialKeys.lua` | `shared/MiningGame/` | Backwards compatibility layer | Never (auto-derived from MaterialDefinitions) |
| `SoundConfig.lua` | `shared/MiningGame/` | Sound asset IDs and mappings | Adding actual sound assets |
| `Movement/Config.lua` | `shared/Movement/` | Movement speeds per material | Never (uses MaterialDefinitions) |

## Current Materials (22 Total)

All 22 available Roblox terrain materials are configured in the system:

### By Sound Category:
- **Rock (11)**: rock, sandstone, basalt, slate, limestone, cobblestone, brick, concrete, asphalt, pavement, crackedlava
- **Sand (2)**: sand, salt
- **Ice (2)**: glacier, ice
- **Grass (2)**: grass, leafygrass
- **Snow (1)**: snow
- **Mud (1)**: mud
- **Dirt (1)**: ground
- **Water (1)**: water
- **Wood (1)**: woodplanks

### Implementation Notes:
- All 22 Roblox Enum.Material values are in use
- Materials are defined with properties: speedMultiplier, soundCategory, digDifficulty, color
- Order property controls UI display sequence
- Materials automatically propagate to UI, movement, and sound systems

## Common Tasks

### View Current Material Configuration
```lua
-- Check MaterialDefinitions.lua for the complete list
local MaterialDefinitions = require(game.ReplicatedStorage.MiningGame.MaterialDefinitions)
local props = MaterialDefinitions.GetProperties("rock")
print(props.speedMultiplier, props.soundCategory, props.digDifficulty)
```

### Note on Material Variants
Since all 22 Enum.Material values are in use, creating true variants would require:
1. Custom material system beyond Roblox terrain
2. Visual differentiation through textures/colors
3. Separate tracking from terrain materials

### Change Material Properties
Edit in `MaterialDefinitions.lua`:
- `speedMultiplier`: Movement speed modifier (<1.0 slower, >1.0 faster, 1.0 = normal)
- `digDifficulty`: Mining difficulty (<1.0 easier, >1.0 harder, 1.0 = standard)
- `soundCategory`: Must match a valid category from SoundCategories
- `color`: Color3 value for UI display
- `order`: Display order in UI lists (lower = earlier)

### Add Sound Assets
In `SoundConfig.lua`, replace test sounds:
```lua
local SOUND_ASSETS = {
    -- Replace this:
    TEST_CLICK = "rbxassetid://9120386436",
    
    -- With real assets:
    MINING_ROCK_HIT = "rbxassetid://YOUR_ID",
    FOOTSTEP_ROCK = "rbxassetid://YOUR_ID",
}
```

## Key APIs

### MaterialDefinitions API (Primary)
```lua
local MaterialDefinitions = require(game.ReplicatedStorage.MiningGame.MaterialDefinitions)

-- Get all properties for a material
local props = MaterialDefinitions.GetProperties("rock")
local speed = props.speedMultiplier
local difficulty = props.digDifficulty
local color = props.color

-- Get specific property
local soundCat = MaterialDefinitions.GetProperty("rock", "soundCategory")

-- Get enum from key
local enum = MaterialDefinitions.GetEnum("rock")

-- Get display name
local name = MaterialDefinitions.GetDisplayName("rock")

-- Get speed from enum directly
local speed = MaterialDefinitions.GetSpeedFromEnum(Enum.Material.Rock)
```

### MaterialKeys API (Compatibility)
```lua
local MaterialKeys = require(game.ReplicatedStorage.MiningGame.MaterialKeys)

-- Get enum from key
local enum = MaterialKeys.EnumFromKey["rock"]

-- Get key from enum  
local key = MaterialKeys.KeyFromEnum[Enum.Material.Rock]

-- Get display name
local name = MaterialKeys.DisplayNames["rock"]

-- Get ordered list of all material keys
local allKeys = MaterialKeys.TerrainKeys
```

### Sound System
```lua
-- Get mining sound for material
local sound = SoundConfig.GetMiningSoundForMaterial("rock")

-- Get footstep sound
local footstep = SoundConfig.GetFootstepSoundForMaterial("rock")
```

### Movement Speed
```lua
local Movement = require(game.ReplicatedStorage.Movement)
local Config = Movement.Config

-- Get speed from material key
local speed = Config.GetSpeedFromKey("rock")

-- Get speed from Enum.Material
local speed = Config.GetSpeedFromEnum(Enum.Material.Rock)

-- Note: Movement speeds are automatically derived from MaterialDefinitions
-- No need to update Movement/Config.lua when changing material speeds
```

## Validation Errors

| Error | Cause | Fix |
|-------|-------|-----|
| "Invalid soundCategory 'X'" | Unknown sound category | Use valid category or add new one |
| "Duplicate Enum.Material" | Reusing same enum incorrectly | Each material needs unique key |
| "Missing footstep sound" | Category without footstep | Add to SoundConfig footsteps |
| "Missing mining event" | Event not defined for category | Check SoundCategories.MiningEvents |

## Testing Checklist

When modifying materials in MaterialDefinitions.lua:
- [ ] Game starts without errors (validation passes)
- [ ] Material appears in Materials Tab UI with correct color
- [ ] Display name shows correctly in UI
- [ ] Mining produces appropriate sounds for the soundCategory
- [ ] Footsteps play correct sounds when walking on material
- [ ] Movement speed matches speedMultiplier value
- [ ] Dig difficulty affects mining rate appropriately
- [ ] Material can be applied to terrain cubes
- [ ] Material appears in correct order in UI lists

## Performance Notes

- All data structures are frozen (immutable) using table.freeze()
- Precomputed arrays (KeysOrdered, AllTerrainEnums) avoid runtime generation
- Single validation pass at startup catches configuration errors early
- No duplicate data storage - everything derives from MaterialDefinitions
- MaterialKeys auto-generates compatibility tables from MaterialDefinitions
- Movement Config dynamically reads from MaterialDefinitions (no duplication)

## Common Pitfalls

1. **Don't edit MaterialKeys.lua** - It's auto-derived from MaterialDefinitions
2. **Don't edit Movement/Config.lua speeds** - They come from MaterialDefinitions
3. **Don't hardcode material lists** - Use MaterialDefinitions.KeysOrdered or AllTerrainEnums
4. **Don't skip validation** - Startup checks prevent runtime errors
5. **Don't use raw Enum.Material for lookups** - Use MaterialKeys.KeyFromEnum
6. **Don't duplicate colors/names** - Always get from MaterialDefinitions
7. **Don't forget order property** - It controls UI display sequence

## Related Documentation

- `ADDING_NEW_MATERIALS.md` - Detailed guide for the material addition process
- `SOUND_INTEGRATION_REVIEW.md` - Complete sound system architecture
- `AMBIENT_ZONE_DOCUMENTATION.md` - Ambient sound zones system
- `shared/MiningGame/MaterialDefinitions.lua` - Source of truth with inline docs
- `shared/MiningGame/SoundCategories.lua` - Sound category definitions
- `shared/Movement/Config.lua` - Movement system integration