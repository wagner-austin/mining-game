# Ambient Zone System Documentation

## Overview
The ambient zone system provides immersive, location-based environmental sounds that automatically change based on time of day. It supports overlapping zones with priority-based mixing and smooth volume transitions.

## Quick Start

### 1. Adding Ambient Sounds to Objects (e.g., Trees)

1. **Tag the object** in Roblox Studio:
   - Select the part/model
   - Add tag: `AmbientZone` (using Tag Editor or CollectionService)

2. **Set attributes** on the tagged part:
   - `SoundKey` (string): The ambient sound to play (e.g., "birds_morning")
   - `Radius` (number): How far the sound reaches in studs (default: 40)
   - `Priority` (number): Higher priority overrides lower zones (default: 1)
   - `BaseVolume` (number): Volume from 0-1 (default: 0.35)

### 2. Example: Tree with Bird/Cricket Sounds

```lua
-- In Studio, select your tree model's root part
-- Add tag: "AmbientZone"
-- Add attributes:
SoundKey = "birds_morning"  -- Will auto-switch based on time
Radius = 50                  -- Audible within 50 studs
Priority = 1                 -- Standard priority
BaseVolume = 0.3            -- 30% volume
```

## Available Ambient Sounds

### Time-Aware Sounds (auto-switch based on game time)
- `birds_morning` - Plays 6:00 AM → 6:00 PM
- `birds_evening` - Plays 5:00 PM → 8:00 PM  
- `crickets` - Plays 8:00 PM → 6:00 AM
- `owls` - Plays 10:00 PM → 4:00 AM
- `trees_rustling` - Always plays (has day/night variants)

### Location-Based Sounds (always play)
- `waterflow` - Rivers, streams
- `oceanwaves` - Ocean shores
- `lavaflow` - Lava pools
- `cave` - Cave ambience
- `wind` - Mountain peaks, open areas
- `desertwind` - Desert areas
- `icecracking` - Frozen lakes, glaciers

## How It Works

### Time-Based Switching
The system automatically switches sounds based on `game.Lighting.ClockTime`:
- A tree tagged with `birds_morning` will play:
  - Bird sounds during daytime (6 AM - 6 PM)
  - Nothing during night (or you could use a different zone)
- Multiple zones can overlap - highest priority wins

### Distance-Based Volume
- Full volume at the center of the zone
- Gradually fades as you approach the edge
- Completely silent outside the radius
- Smooth transitions when moving between zones

### Zone Priority
When multiple zones overlap:
1. Higher `Priority` zones override lower ones
2. If priorities are equal, louder volume wins
3. Maximum 2 concurrent ambient sounds (configurable)

## Advanced Usage

### Multiple Time Periods
For sounds that should change throughout the day, use the time rules in `SoundConfig.lua`:

```lua
-- Example: Forest that changes throughout the day
-- Tag: AmbientZone
-- SoundKey: "trees_rustling"
-- The system will automatically use variants:
-- - Day (6 AM - 6 PM): trees_rustling_gentle
-- - Night (6 PM - 6 AM): trees_rustling_eerie
```

### Overlapping Zones
```lua
-- Example: Waterfall near a forest
-- Waterfall part:
SoundKey = "waterflow"
Radius = 80
Priority = 2  -- Higher priority
BaseVolume = 0.5

-- Forest parts:
SoundKey = "birds_morning"  
Radius = 100
Priority = 1  -- Lower priority
BaseVolume = 0.3

-- Result: Near waterfall, you hear water. 
-- Further away, you hear birds.
```

### Dynamic Zones
Zones work on any BasePart, even moving ones:
```lua
-- Example: Moving storm cloud
-- Tag the cloud part with AmbientZone
SoundKey = "thunder"
Radius = 150
Priority = 3  -- High priority
BaseVolume = 0.6
-- As the cloud moves, the thunder follows!
```

## Performance

The system is optimized for performance:
- Only updates when player moves significantly (8+ studs)
- Maximum concurrent sounds limited (default: 2)
- Efficient distance checks using squared distances
- Automatic culling of distant zones

## Adding New Ambient Sounds

1. **Add sound ID** to `SoundConfig.lua`:
```lua
SoundConfig.SoundIDs.ambient = {
    -- ...existing sounds...
    mynewsound = SOUND_ASSETS.TEST_CLICK,  -- Your sound ID
}
```

2. **Optional: Add time rules** in `SoundConfig.lua`:
```lua
SoundConfig.TimeRules["mynewsound"] = {
    timeRanges = { { start = 9, stop = 17 } },  -- 9 AM to 5 PM
}
```

3. **Use in zones**:
```lua
SoundKey = "mynewsound"
```

## Debugging

Enable ambient logging to see what's playing:
```lua
-- In client console:
game.ReplicatedStorage.MiningGame.AmbientController:SetAttribute("Debug", true)
```

Check active ambient sounds:
```lua
local SoundManager = require(game.ReplicatedStorage.MiningGame.SoundManager)
print(SoundManager.GetActiveAmbient())
```

## Common Use Cases

### Forest Area
- Trees: `birds_morning` (Priority 1)
- Dense forest center: `trees_rustling` (Priority 2)
- Stream: `waterflow` (Priority 2)

### Cave System
- Cave entrance: `cave` with smaller radius
- Deep cave: `cave` with larger radius and higher volume
- Underground lake: `waterflow` (Priority 2)

### Mountain Peak
- Peak: `wind` (Priority 2)
- Trees below: `birds_morning` (Priority 1)
- Frozen areas: `icecracking` (Priority 2)

### Desert
- Open desert: `desertwind` (Priority 1)
- Oasis: `waterflow` (Priority 3)
- Palm trees: `trees_rustling` (Priority 2)

## Tips

1. **Start with lower volumes** (0.2-0.4) to avoid overwhelming players
2. **Use larger radii** (60-100) for area ambience, smaller (20-40) for specific objects
3. **Test different times** of day to ensure smooth transitions
4. **Layer zones** with different priorities for rich soundscapes
5. **Consider player movement** - sounds should enhance, not distract

## API Reference

### Attributes (on tagged parts)
- `SoundKey` (string, required): Ambient sound identifier
- `Radius` (number, optional): Detection radius in studs (default: 40)
- `Priority` (number, optional): Zone priority 0-10 (default: 1)
- `BaseVolume` (number, optional): Volume 0-1 (default: 0.35)

### AmbientController Methods
```lua
local AmbientController = require(game.ReplicatedStorage.MiningGame.AmbientController)

-- Enable/disable system
AmbientController.SetEnabled(true/false)

-- Set max concurrent sounds
AmbientController.SetMaxConcurrent(3)

-- Start/stop the system
AmbientController.Start()
AmbientController.Stop()
```

### SoundManager Methods
```lua
local SoundManager = require(game.ReplicatedStorage.MiningGame.SoundManager)

-- Get currently playing ambient sounds
SoundManager.GetActiveAmbient() -- Returns array of sound keys

-- Manually play/stop ambient
SoundManager.PlayAmbient(name, options)
SoundManager.StopAmbient(name, fadeOut)
```