# Playtime Tracking System Documentation

## Overview
A comprehensive playtime tracking system that monitors both session duration and lifetime playtime for players. The system provides real-time updates to the UI and persists lifetime totals across sessions.

## Architecture

### Server Components

#### SessionService (`server/MiningGame/SessionService.lua`)
**Type:** ModuleScript  
**Purpose:** Tracks player session times and manages lifetime playtime updates

**Key Functions:**
- `getSessionStartTime(userId: number): number?` - Returns when a player's current session started
- `getSessionElapsed(userId: number): number` - Returns seconds elapsed in current session

**Behavior:**
- Records `os.time()` when player joins
- Calculates session duration when player leaves
- Calls `DataService:AddPlaytime()` to persist session time to lifetime total
- Handles players already in-game (Studio test mode)

#### DataService Updates (`server/MiningGame/DataService.lua`)
**Added Method:**
- `AddPlaytime(player: Player, seconds: number)` - Adds session duration to lifetime playtime

**Behavior:**
- Increments `profile.playtime` field with session seconds
- Queues automatic save to DataStore
- Provides logging for debugging

#### DigService Integration (`server/MiningGame/DigService.lua`)
**Modified:** GetProfile handler (line ~294)

**Behavior:**
- Requires SessionService module
- Injects `sessionStartTime` into profile response
- Provides fallback to `os.time()` if session not found

### Shared Components

#### Types (`shared/MiningGame/Types.lua`)
**Added Field to PlayerStats:**
```lua
sessionStartTime: number? -- Session-scoped, sent to clients in GetProfile
```
- Not persisted to DataStore
- Injected at runtime by DigService

### Client Components

#### AccountDataProvider (`client/MiningGame/Data/AccountDataProvider.lua`)
**Purpose:** Centralized data management for account information

**Key Features:**
- Stores `_sessionStartTime` from server
- Includes session time in snapshots
- Provides reactive updates via `onChanged()` event
- Falls back to `os.time()` if no server value

**Snapshot Structure:**
```lua
{
    profile: Profile,
    cubeStats: {...},
    sessionStartTime: number,
    lastUpdated: number,
    isLoading: boolean
}
```

#### AccountTab (`client/MiningGame/UI/Components/AccountTab.lua`)
**Purpose:** Displays session and lifetime playtime in Settings panel

**Added Stats:**
1. **Session Time** - Time since joining current server
2. **Total Playtime** - Lifetime accumulation + current session

**Key Features:**
- Updates every second via `task.spawn` loop
- Stores `_baseLifetimeSeconds` from server profile
- Calculates total as: `baseLifetime + (now - sessionStart)`
- Formats duration as: "5m", "2h 30m", "3d 12h"

**Format Logic (`_formatDuration`):**
- < 1 hour: Shows minutes only
- < 1 day: Shows hours and minutes
- ≥ 1 day: Shows days and hours

#### SettingsPanel (`client/MiningGame/UI/Panels/SettingsPanel.lua`)
**Purpose:** Passes data provider to child components

**Dependency Injection:**
```lua
SettingsPanel.new({ accountDataProvider = accountDataProvider })
```
- Receives provider instance from ClientUI
- Passes to AccountTab for data binding

#### ClientUI (`client/MiningGame/UI/ClientUI.client.lua`)
**Purpose:** Bootstrap and wire up data providers

**Initialization:**
```lua
local accountDataProvider = AccountDataProvider.new(Remotes, UIUtils)
local settingsPanel = SettingsPanel.new({ accountDataProvider = accountDataProvider })
```

## Data Flow

### Session Start
1. Player joins server
2. SessionService records `userId -> os.time()`
3. Client requests profile via GetProfile
4. DigService fetches profile and adds `sessionStartTime`
5. Client receives authoritative session start time
6. AccountTab begins displaying session duration

### Live Updates
1. AccountTab runs update loop every second
2. Calculates: `sessionElapsed = os.time() - sessionStartTime`
3. Updates "Session Time" label
4. Calculates: `total = baseLifetime + sessionElapsed`
5. Updates "Total Playtime" label

### Session End
1. Player leaves server
2. SessionService calculates session duration
3. Calls `DataService:AddPlaytime(player, duration)`
4. DataService increments `profile.playtime`
5. Queues save to DataStore
6. Lifetime total persists for next session

## Implementation Details

### Time Synchronization
- Server provides authoritative `sessionStartTime`
- Client calculates elapsed time locally
- No network calls needed for updates
- Resilient to clock differences

### Performance Optimizations
- UI updates throttled to 1 Hz (once per second)
- No Heartbeat connections (uses task.wait loop)
- Single data provider instance shared across UI
- Reactive updates via BindableEvent

### Error Handling
- SessionService wrapped in pcall for DataService calls
- Fallback to `os.time()` if session time unavailable
- Safe type checking before method calls
- Graceful handling of missing data

## Testing Checklist

### Basic Functionality
- [ ] Session time starts at 0m when joining
- [ ] Session time increments every second
- [ ] Total playtime shows lifetime + session
- [ ] Both timers update simultaneously

### Persistence
- [ ] Leave server and check console for session duration log
- [ ] Rejoin and verify lifetime base increased
- [ ] Total playtime continues from new base

### Edge Cases
- [ ] Studio test mode (player already in game)
- [ ] Multiple rapid joins/leaves
- [ ] Long sessions (>24 hours formatting)
- [ ] DataStore unavailable (Studio offline)

## Console Outputs

### Expected Server Logs
```
[SessionService] Player GothicOptic session started at 1756475652
[SessionService] GothicOptic played for 300 seconds this session
[DataService] Added 300 seconds playtime for GothicOptic - Total: 3600
```

### Expected Client Logs
```
[ClientUI] Initial profile - Coins: 100 Gems: 0
[AccountDataProvider] Profile updated with session time: 1756475652
```

## Troubleshooting

### Issue: "Attempted to call require with invalid argument(s)"
**Cause:** SessionService was a Script instead of ModuleScript  
**Fix:** Renamed to SessionService.lua (ModuleScript)

### Issue: Session time shows wrong duration
**Cause:** Using client os.time() instead of server value  
**Fix:** Ensure DigService injects sessionStartTime

### Issue: Lifetime doesn't persist
**Cause:** DataService:AddPlaytime not called or failing  
**Fix:** Check SessionService PlayerRemoving handler

### Issue: UI doesn't update
**Cause:** Missing data provider or wrong snapshot structure  
**Fix:** Verify AccountDataProvider wiring in ClientUI

## Future Enhancements

### Potential Features
- Daily/weekly/monthly playtime statistics
- Playtime rewards and milestones
- AFK detection and exclusion
- Session history tracking
- Playtime leaderboards

### Optimization Opportunities
- Batch playtime updates for multiple players
- Compress historical data after time threshold
- Cache frequently accessed statistics
- Add playtime to player list displays

## Code Locations Summary

| Component | File Path | Purpose |
|-----------|-----------|---------|
| SessionService | `server/MiningGame/SessionService.lua` | Track sessions, update lifetime |
| DataService | `server/MiningGame/DataService.lua` | Persist playtime to DataStore |
| DigService | `server/MiningGame/DigService.lua` | Inject session time in GetProfile |
| Types | `shared/MiningGame/Types.lua` | Define sessionStartTime field |
| AccountDataProvider | `client/MiningGame/Data/AccountDataProvider.lua` | Manage account data client-side |
| AccountTab | `client/MiningGame/UI/Components/AccountTab.lua` | Display playtime statistics |
| SettingsPanel | `client/MiningGame/UI/Panels/SettingsPanel.lua` | Pass data provider to tabs |
| ClientUI | `client/MiningGame/UI/ClientUI.client.lua` | Initialize and wire providers |