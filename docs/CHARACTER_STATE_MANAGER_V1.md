# Character State Manager V1 - Lean Implementation Plan

## Overview
A minimal, practical character state system that integrates cleanly with existing systems without duplicating sources of truth.

## Core Principles
1. **DataService remains the source of truth for persistent data**
2. **DigService keeps ownership of dig cooldowns**
3. **Use Attributes for simple replication (no complex diff system yet)**
4. **Bridge to existing movement system rather than replace**
5. **Start with 4-5 files, not 10+**

## V1 Scope (Thin Slice)
- ✅ Health & Stamina systems
- ✅ Runtime effect materialization from `profile.boosts`
- ✅ UI health/stamina bars
- ✅ Read-only dig cooldown exposure for UI
- ✅ Movement modifier bridge to existing system
- ❌ No abilities yet
- ❌ No complex replication
- ❌ No temperature/depth tracking
- ❌ No inventory changes

## Implementation Files

### 1. CharacterStateManager.lua (Server)
**Location**: `server/MiningGame/CharacterStateManager.lua`

**Responsibilities**:
- Authoritative character state
- Materialize runtime effects from `profile.boosts`
- Write Attributes for client replication
- Expose read-only dig cooldown for UI

**Key Features**:
- Integrates with DataService for boost persistence
- Uses Attributes for efficient replication
- Provides bridge to existing movement system

### 2. Effects.lua (Shared)
**Location**: `shared/MiningGame/Character/Effects.lua`

**Initial Effects** (just 3 for V1):
- `speed_boost`: Multiplies walk speed
- `mining_fever`: Affects dig efficiency (flag only, DigService computes)
- `wet`: Speed multiplier 0.8 for short duration

### 3. CharacterStateClient.lua (Client)
**Location**: `client/MiningGame/Character/CharacterStateClient.lua`

**Responsibilities**:
- Watch Attributes for changes
- Provide UI-friendly API
- Bridge effects to MovementModifiers folder
- Cache state for UI components

### 4. UI Components
**Location**: `client/MiningGame/UI/Components/`
- `HealthBar.lua`: Simple health display
- `StaminaBar.lua`: Simple stamina display

## Integration Points

### DataService Integration
- No structural changes needed
- Add helper: `DataService:GetActiveBoosts(player)`
- CharacterStateManager reads boosts to materialize effects

### DigService Integration
- DigService remains authority on cooldowns
- After cooldown calc: `CharacterStateManager:SetNextDigAllowedAt(player, timestamp)`
- UI reads this for countdown display

### Movement System Bridge
- CharacterStateClient writes NumberValues to `MovementModifiers` folder
- Example: `SpeedMult_FromEffects`
- ApplyStats.client.lua continues working unchanged

### Remotes
Add to existing remotes:
- `RE.OnRuntimeEffectsChanged`: Server → Client effect list updates

## Attributes Used
On `Player` instance:
- `Char_Health`: Current health
- `Char_MaxHealth`: Maximum health
- `Char_Stamina`: Current stamina
- `Char_MaxStamina`: Maximum stamina
- `Char_NextDigAllowedAt`: Unix timestamp for dig cooldown

On `Humanoid` (already exist):
- `EffectiveWalkSpeed`
- `EffectiveJumpHeight`

## Effect Materialization Flow
1. Player joins → read `profile.boosts` from DataService
2. Every 1 second, check boost expiration
3. Map boost IDs to Effects.lua definitions
4. Apply runtime modifiers
5. Fire `RE.OnRuntimeEffectsChanged` to client
6. Client updates MovementModifiers folder

## Configuration
```lua
-- Add to GameConfig.lua
GameConfig.Character = {
    Health = {
        BASE = 100,
        REGEN_RATE = 5,     -- per second
        REGEN_DELAY = 3,    -- seconds after damage
    },
    Stamina = {
        BASE = 100,
        REGEN_RATE = 10,    -- per second
        JUMP_COST = 10,
        DIG_COST = 5,
    },
    Effects = {
        TICK_RATE = 1,      -- Check effects every 1 second
    }
}
```

## Development Checklist

### Phase 1: Core Setup
- [ ] Create CharacterStateManager.lua with vitals management
- [ ] Implement effect materialization from profile.boosts
- [ ] Set up Attribute writing for replication
- [ ] Add SetNextDigAllowedAt API

### Phase 2: Shared Definitions
- [ ] Create Effects.lua with 3 base effects
- [ ] Define effect modifier structure
- [ ] Add effect-to-boost mapping

### Phase 3: Client Bridge
- [ ] Create CharacterStateClient.lua
- [ ] Implement Attribute watching
- [ ] Add movement modifier bridge (NumberValue writer)
- [ ] Create UI-friendly API methods

### Phase 4: Remote Communication
- [ ] Add RE.OnRuntimeEffectsChanged to Remotes
- [ ] Implement server-side effect change notifications
- [ ] Handle client-side effect updates

### Phase 5: Integration
- [ ] Update DigService to call SetNextDigAllowedAt
- [ ] Test movement modifier bridge
- [ ] Verify boost materialization

### Phase 6: UI Components
- [ ] Create HealthBar.lua component
- [ ] Create StaminaBar.lua component
- [ ] Mount in MainHUD
- [ ] Add dig cooldown display

### Phase 7: Testing
- [ ] Test vitals display on join
- [ ] Test boost → effect → movement speed flow
- [ ] Test dig cooldown countdown
- [ ] Test multiplayer synchronization

## Security Considerations
- All state changes are server-authoritative
- Clients can only read Attributes, not write
- No client-side stamina validation (server checks)
- Rate limiting prepared for future ability requests

## Performance Notes
- 1-second tick rate for effects (not 0.1s)
- Attributes handle replication efficiently
- Maximum 10 updates/second per player
- Coalesce effect changes before sending

## Future Expansions (V2/V3)
After V1 is stable:
- Remove NumberValue bridge, integrate directly with movement
- Add ability system with cooldowns
- Implement diff-based replication if needed
- Add more complex effects and interactions

## Success Metrics
- Vitals visible immediately on join
- Effects apply within 1 second
- Movement changes feel responsive
- No state desync issues
- Dig cooldown UI updates smoothly

## Migration Path
1. Deploy CharacterStateManager alongside existing systems
2. Run in parallel for testing
3. Gradually move UI to read from new state
4. Remove old systems only after full validation