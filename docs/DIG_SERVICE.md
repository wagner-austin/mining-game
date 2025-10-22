# Dig Service Documentation

## Overview

The DigService manages all mining/digging mechanics in the game, including:
- Processing dig requests from clients
- Validating dig positions within mineable volumes (player cubes; islands when enabled)
- Managing dig cooldowns and rate limiting
- Handling terrain modification through GridService
- Distributing loot via LootService

## Quick Start

### Client-Side Usage
```lua
-- Using ClientRF and the Dig RFs
local ClientRF = require(MiningGame.ClientRF)

-- Single dig
local res, err = ClientRF.call("RequestDig", worldPos)
if res then
    -- res.ok/res.success are top-level in service returns
else
    warn("Dig failed:", err)
end

-- Continuous dig
ClientRF.call("StartContinuousDig", worldPos)
-- ... later ...
ClientRF.call("StopContinuousDig")
```

### Server-Side API
The service is initialized via `ServiceManager` and exposes methods used by RF specs in `server/MiningGame/RemoteFns/Dig.rf.lua`:

```lua
-- Process a single dig request (called by RF handler)
function DigService:ProcessDigRequest(player: Player, worldPos: Vector3): Types.DigResult

-- Start/stop hold-to-dig loops (called by RF handlers)
function DigService:StartHoldDig(player: Player, worldPos: Vector3)
function DigService:StopHoldDig(player: Player)

-- Respawn the client’s cube model (called by RF handler)
function DigService:
```

## Architecture

### Core Components

1. **Boundary Validation System**
   - Uses smart single-axis snapping to handle edge cases
   - Prevents exploitation while allowing legitimate boundary clicks
   - Adaptive tolerance based on cell size

2. **Cooldown Management**
   - Per-player cooldown tracking
   - Respects upgraded dig speeds
   - Prevents rapid-fire digging exploits

3. **Grid Integration**
   - Converts world positions to cell coordinates
   - Manages terrain destruction through GridService
   - Handles multi-cell dig patterns for upgraded tools

## Boundary Validation System

### The Problem
When players click on the outer faces of their cube (especially at the lowest dig level), the click position after normal offset could fall slightly outside the cube boundary, causing false rejections.

### The Solution
A multi-tiered approach that maintains security while fixing edge cases:

#### Client-Side Cell Snapping
```lua
-- Snap to cell center for perfect alignment with server
local cx, cy, cz = GridMath.worldToCell(aim, playerCubeOrigin, CELL_SIZE)
local center = GridMath.cellToWorld(cx, cy, cz, playerCubeOrigin, CELL_SIZE)
```

#### Server-Side Smart Snapping
```lua
-- Accepts positions with different tolerances based on location
local function snapInsideIfNearCube(worldPos, cubeOrigin, cubeSize, faceEps, edgeEps, cornerEps)
    -- Calculate outside distance per axis
    -- Different tolerances for faces, edges, and corners
    -- Snap to just inside the cube
    -- Higher tolerance for faces where terrain extends most
end
```

### Security Features
- **Tiered tolerances**: 
  - Faces: 2.5 studs (terrain extends most here)
  - Edges: 2.0 studs or 45% of cell size
  - Corners: 1.5 studs or 35% of cell size
- **Debug logging**: Monitors when snapping occurs for analysis
- **Origin validation**: Checks for mismatches between stored and computed origins

## Configuration

Located in `shared/MiningGame/GameConfig.lua`:

```lua
GameConfig.Grid = {
    CELL_SIZE_STUDS = 4,        -- Terrain voxel size
    CUBE_SIZE_STUDS = 128,       -- Player cube size
}

GameConfig.Digging = {
    BASE_DIG_DELAY = 1.0,        -- Seconds between digs
    BASE_DIG_SIZE_CELLS = 1,     -- Base dig radius
    MAX_RANGE_STUDS = 200,       -- Anti-cheat: max click distance from HRP
}
```

## API Reference

### ProcessDigRequest
```lua
function DigService:ProcessDigRequest(player: Player, worldPos: Vector3): Types.DigResult
```

**Parameters:**
- `player`: The player making the dig request
- `worldPos`: World position where the player clicked

**Returns:** `Types.DigResult`
```lua
{
    ok: boolean,
    reason?: string,            -- Error message if not ok ("Out of range", "Outside your cube", ...)
    nextAllowedAt?: number,     -- Cooldown timestamp
    cellsDug?: number,          -- Number of cells dug
    lootCounts?: {[string]: number},
    centerCell?: {x:number,y:number,z:number},
    volumeId?: string,          -- Selected volume id (cube:<uid> or island:...)
    volumeOrigin?: CFrame,      -- Volume origin used for world<->cell transforms
}

### Volume Query RF (client preview)

```
QueryVolumeAt(position: Vector3)
  -> { ok=true, success=true, hit=false }
  or { ok=true, success=true, hit=true, id, kind, origin, size, public }
```
Uses server picker for exact preview snapping.
```

### InitializePlayerCube
```lua
function DigService:InitializePlayerCube(player: Player)
```
Initializes a player's mining cube when they join or respawn.

### CleanupPlayerCube
```lua
function DigService:CleanupPlayerCube(player: Player)
```
Removes a player's cube data when they leave.

## Common Issues & Solutions

### Issue: "Outside your cube" when clicking on cube faces
**Cause:** Client offset not large enough to keep position inside after normal adjustment  
**Solution:** Implemented in latest update - client uses 45% of cell size offset, server snaps near-face positions

### Issue: Dig cooldown feels inconsistent
**Cause:** Server tracks individual cooldowns per player  
**Solution:** Check player's upgrade stats - higher tier tools have shorter cooldowns

### Issue: Multi-cell digs not working
**Cause:** Dig size increases with tool upgrades  
**Solution:** Verify player has appropriate tool level via UpgradeService

## Testing Checklist

When modifying dig mechanics, test:

1. ✅ Face center clicks (should work)
2. ✅ Near-corner clicks on faces (should work)  
3. ✅ Corner/edge clicks (should reject)
4. ✅ Clicks >1.25 studs outside (should reject)
5. ✅ Different tool levels maintain consistent behavior
6. ✅ Cooldowns apply correctly
7. ✅ Loot distribution works
8. ✅ Terrain actually gets destroyed

## Recent Updates

### Volume-Aware Digging (Latest)
- Added volume registry in DigService; player cubes registered automatically; floating islands register when `Features.ENABLE_ISLAND_MINING = true`.
- `ProcessDigRequest` now selects a volume (cube first; islands if enabled), snaps inside AABB, and clamps per-axis via `state.extentsCells`.
- GridService clamps per-axis when `extentsCells` present; falls back to cube size otherwise.
- Anti-cheat: range limit via `GameConfig.Digging.MAX_RANGE_STUDS`.

### Boundary Fix
- **Problem:** False rejections when clicking cube face at lowest dig level
- **Solution:** 
  - Client: Increased offset from 1.0 to 1.8 studs (45% of cell)
  - Server: Added single-axis snap tolerance (max 1.25 studs)
- **Impact:** Eliminates false rejections while maintaining exploit prevention

## Dependencies

- **GridService**: Handles actual terrain destruction
- **DataService**: Provides player profiles and cube data  
- **UpgradeService**: Calculates effective dig stats
- **LootService**: Determines and grants dig rewards
- **GameConfig**: Central configuration values

## Future Improvements

- [ ] Add dig pattern shapes (sphere, cone, etc.)
- [ ] Implement dig combo system for bonus rewards
- [ ] Add visual preview of dig area before clicking
- [ ] Support for special dig modes (precision, area clear)
- [ ] Optimize network traffic for high-frequency diggers

