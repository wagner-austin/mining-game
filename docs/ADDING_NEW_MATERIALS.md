# Adding New Materials to the Mining Game

## Overview
The material system uses a single source of truth design. You only need to add your material in ONE place, and everything else picks it up automatically with full validation.

## ⚠️ Important Limitation
You can ONLY use Roblox's built-in Enum.Material values for terrain. The 22 available terrain materials are:
- Asphalt, Basalt, Brick, Cobblestone, Concrete, CrackedLava, Glacier, Grass, Ground, Ice, LeafyGrass, Limestone, Mud, Pavement, Rock, Salt, Sand, Sandstone, Slate, Snow, Water, WoodPlanks

You CANNOT create custom terrain materials - only use what Roblox provides.

## Step-by-Step Guide

### Step 1: Choose Your Material
Check `shared/MiningGame/MaterialDefinitions.lua` to see what's already used. As of the latest update, ALL 22 Enum.Material values are currently in use, so you would need to either:
- Replace an existing material
- Create a variant using the same enum (see Advanced section)

### Step 2: Add to MaterialDefinitions
Edit `shared/MiningGame/MaterialDefinitions.lua` and add your material entry:

```lua
-- Example: Adding a new "crystal" material using the Glacier enum
crystal = {
    enum = Enum.Material.Glacier,  -- Must be a valid Enum.Material
    displayName = "Crystal",        -- Human-readable name for UI
    order = 15,                     -- Optional: controls UI sort order (lower = earlier)
    properties = {
        speedMultiplier = 1.1,      -- Movement speed multiplier (1.0 = normal)
        soundCategory = "ice",       -- Must match a category from SoundCategories
        digDifficulty = 1.4,        -- Mining difficulty (1.0 = normal)
        color = Color3.fromRGB(200, 230, 255),  -- UI color for material
    }
},
```

### Step 3: Verify Sound Category
Make sure your `soundCategory` is valid. Check `shared/MiningGame/SoundCategories.lua` for available categories:
- rock, ice, sand, mud, snow, water, grass, dirt, wood

If you need a new sound category, see "Adding a New Sound Category" below.

### Step 4: That's It!
The system automatically:
- ✅ Adds to MaterialKeys.TerrainKeys
- ✅ Creates mining sounds with appropriate events (hit, break, shatter, etc.)
- ✅ Maps to footstep sounds via soundCategory
- ✅ Adds to UI material lists with your color
- ✅ Sets movement speed from speedMultiplier
- ✅ Validates everything at startup

### Step 5: Test Your Material
1. Start the game
2. Check console for any validation errors
3. Test in-game:
   - Can you select it in the materials UI?
   - Does digging produce sounds?
   - Is movement speed correct?
   - Do footsteps play?

## Adding a New Sound Category (Optional)

If your material needs a unique sound category:

### 1. Edit SoundCategories.lua
```lua
-- Add to Categories enum
SoundCategories.Categories = table.freeze({
    -- ... existing ...
    CRYSTAL = "crystal",  -- NEW
})

-- Add to Ordered list
SoundCategories.Ordered = table.freeze({
    -- ... existing ...
    "crystal",  -- NEW
})

-- Define mining events for your category
SoundCategories.MiningEvents = table.freeze({
    -- ... existing ...
    crystal = {"hit", "break", "shatter", "ring"},  -- NEW
})
```

### 2. Add Footstep Sound
Edit `shared/MiningGame/SoundConfig.lua`:
```lua
movement = {
    footstep = {
        -- ... existing ...
        crystal = SOUND_ASSETS.TEST_CLICK,  -- NEW (replace with real sound later)
    },
}
```

## Example: Modifying an Existing Material

Since all materials are in use, let's say we want to modify the existing basalt to be "Volcanic Rock":

```lua
-- In MaterialDefinitions.lua, modify the existing basalt entry:
basalt = {
    enum = Enum.Material.Basalt,
    displayName = "Volcanic Rock",  -- Changed from "Basalt"
    order = 3,
    properties = {
        speedMultiplier = 0.85,     -- Adjusted for rough volcanic terrain
        soundCategory = "rock",      -- Keep rock sounds
        digDifficulty = 1.5,        -- Increased from 1.3
        color = Color3.fromRGB(50, 30, 30),  -- Darker reddish-black
    }
},
```

That's it! The material is now fully integrated.

## Using Materials in Game Progression

Materials can be referenced in `shared/MiningGame/GameConfig.lua` for progression tiers:

```lua
{
    id = "tier_volcanic",
    name = "Volcanic Tier",
    terrainKey = "volcanicrock",  -- Use your material key here
    lootMultiplier = 2.5,
    unlockCost = 50000,
    hardness = 1.5,
}
```

## Validation Checklist

When you start the game, the system validates:
- ✅ Material has all required fields (enum, displayName, properties)
- ✅ soundCategory exists in SoundCategories
- ✅ Mining sounds are generated for all events
- ✅ Footstep sound exists for the category
- ✅ No duplicate Enum.Material values

Any errors will show in the console with helpful messages.

## Common Errors

### "Invalid soundCategory 'X' for material 'Y'"
- Your soundCategory doesn't exist in SoundCategories
- Either use an existing category or add a new one

### "Duplicate Enum.Material: X used by both 'Y' and 'Z'"
- You're trying to use an Enum.Material with different keys
- This is only allowed if you understand the limitations (see Advanced: Material Variants)
- Otherwise, modify the existing material or replace it

### "Missing footstep sound for category 'X'"
- You added a new sound category but didn't add its footstep sound
- Add it to SoundConfig.lua's movement.footstep table

## Material Properties Reference

### speedMultiplier
- `< 1.0` = Slower movement (e.g., 0.6 for mud)
- `1.0` = Normal speed
- `> 1.0` = Faster movement (e.g., 1.2 for ice)

### soundCategory
Determines mining and footstep sounds:
- `"rock"` - Hard hitting sounds with crumble
- `"ice"` - Crystalline sounds with shatter
- `"sand"` - Soft sounds with scatter
- `"mud"` - Wet sounds with squish
- `"snow"` - Soft sounds with crunch
- `"water"` - Liquid sounds with splash
- `"grass"` - Soft earth sounds with dig
- `"dirt"` - Earth sounds with dig
- `"wood"` - Wooden sounds with crack

### digDifficulty
- `< 1.0` = Easier to dig (e.g., 0.3 for sand)
- `1.0` = Normal difficulty
- `> 1.0` = Harder to dig (e.g., 1.5 for basalt)

### color
- Used in UI for material swatches and previews
- Should be representative of the material's appearance

## Advanced: Material Variants

**⚠️ Current Status: All 22 Enum.Material values are in use**

If you need variants, you have limited options:

### Option 1: Replace an Existing Material
Simply overwrite a material you don't need in MaterialDefinitions.lua.

### Option 2: Context-Based Materials (Future Enhancement)
The system could be extended to support context-based materials:
- Same Enum.Material but different properties based on depth/biome
- Would require additional systems beyond the current implementation

### Option 3: Visual-Only Variants (Not Currently Supported)
While technically possible to have multiple keys with the same enum:
```lua
-- WARNING: This will cause validation errors in current implementation
darkslate = {
    enum = Enum.Material.Slate,  -- Already used by 'slate'
    displayName = "Dark Slate",
    ...
}
```
The current validation prevents duplicate enums to maintain consistency.

## Files Affected by Material Changes

When you modify a material in MaterialDefinitions.lua, these systems automatically update:
- ✅ `MaterialKeys.lua` - Auto-derives compatibility tables
- ✅ `SoundConfig.lua` - Generates appropriate mining sounds
- ✅ `CubeMaterialService.lua` - Can apply your material to terrain
- ✅ `Movement/Config.lua` - Uses your speed multiplier
- ✅ `MaterialsTab.lua` - Shows in UI with your color and name
- ✅ `AccountTab.lua` - May track material-specific stats
- ✅ All validated at startup for consistency!

You only edit MaterialDefinitions.lua - everything else updates automatically!