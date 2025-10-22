# Master Implementation Roadmap - Mining Game Launch

## Overview
This document provides the exact implementation path from current state to launch-ready game. Each phase builds on the previous one with no temporary code - everything is production-ready.

## Current State
- ✅ Basic cube mining works (click to remove voxels)
- ✅ Multiplayer cube positioning fixed
- ✅ 128-stud cubes with proper CFrame origins
- ✅ Material customization system
- ❌ No extraction system
- ❌ No HP/damage tracking
- ❌ No UI beyond basic currency display
- ❌ No drop table implementation
- ❌ No AFK system

## Phase 1: Core Extraction System (2-3 days)

### Step 1.1: Update Type Definitions
**File:** `shared/MiningGame/Types.lua`
```lua
-- Add to EffectiveStats
power: number -- Mining power per click

-- Add to CubeState  
tier: number -- Current cube tier (1-4)
extraction: {
    current: number,  -- Current extraction points
    quota: number,    -- Required points to complete
    percentage: number -- 0-100 completion percentage
}

-- Add to Chunk type
damage: {[number]: number} -- Sparse map: cellIndex -> accumulated damage
```

### Step 1.2: Create ExtractionService
**File:** `server/MiningGame/Services/ExtractionService.lua`
```lua
-- Core functions:
- CalculateQuota(tier, cubeSize) -> number
- CalculateCellHP(depth, tier) -> number  
- ProcessDamage(cell, damage, tier) -> {destroyed: boolean, points: number}
- CheckCompletion(cubeState) -> boolean
- ProgressToNextTier(player) -> void
```

### Step 1.3: Update DigService
**File:** `server/MiningGame/Services/DigService.lua`
- Replace voxel removal with damage application
- Track extraction points
- Send damage feedback to client
- Check for cube completion

### Step 1.4: Add Damage Tracking to CubeService
**File:** `server/MiningGame/Services/CubeService.lua`
- Store damage in chunk data (sparse map)
- Sync damage state to clients
- Clear damage on cube reset

## Phase 2: Visual Feedback System (2 days)

### Step 2.1: Create DamageVisualService (Client)
**File:** `client/MiningGame/Services/DamageVisualService.lua`
```lua
-- Object pools for performance:
- DamageNumberPool (100 TextLabels)
- CrackOverlayPool (50 crack decals)
- SelectionBoxPool (20 selection boxes)

-- Functions:
- ShowDamageNumber(position, damage, isCrit)
- ShowCrackOverlay(cell, damagePercent)
- ShowMiningProgress(cell, progress)
```

### Step 2.2: Update Mining Visual Feedback
**File:** `client/MiningGame/DigClient.client.lua`
- Listen for damage events from server
- Trigger visual feedback for each hit
- Show cell HP bars on hover
- Add screen shake for powerful hits

### Step 2.3: Add Particle Effects
**File:** `client/MiningGame/Effects/ParticleEffects.lua`
- Rock debris particles on hit
- Sparkle effect for rare drops
- Dust clouds for area damage
- Completion celebration effect

## Phase 3: UI Implementation (3 days)

### Step 3.1: Create Core UI Architecture
**File:** `client/MiningGame/UI/UIManager.lua`
```lua
-- Scene management system
- MainHUD (always visible)
- MenuScene (radial menu)
- InventoryScene
- ShopScene
- StatsScene
```

### Step 3.2: Implement Main HUD
**File:** `client/MiningGame/UI/MainHUD.lua`
- Currency display (coins, gems)
- Extraction progress bar
- Tier indicator
- Quick action buttons
- Mobile-optimized layout

### Step 3.3: Create Inventory System
**Files:** 
- `client/MiningGame/UI/Scenes/InventoryScene.lua`
- `shared/MiningGame/InventoryTypes.lua`
- `server/MiningGame/Services/InventoryService.lua`

Features:
- Grid-based display
- Stack management
- Quick sell functionality
- Item tooltips
- Rarity indicators

### Step 3.4: Implement Shop & Upgrades
**Files:**
- `client/MiningGame/UI/Scenes/ShopScene.lua`
- `client/MiningGame/UI/Scenes/UpgradesScene.lua`
- `server/MiningGame/Services/UpgradeService.lua`

Upgrade paths:
- Mining Power (damage per click)
- Mining Speed (click cooldown)
- Mining Size (area of effect)
- Luck (drop rates)
- AFK Efficiency

## Phase 4: Drop Table System (2 days)

### Step 4.1: Create DropTableService
**File:** `server/MiningGame/Services/DropTableService.lua`
```lua
-- Implement unified drop table from DROP_TABLE_SYSTEM.md
- Single drop table for all contexts
- 40% nothing rolls
- Depth-based eligibility
- Luck modifiers
```

### Step 4.2: Integrate Drops with Mining
**File:** `server/MiningGame/Services/DigService.lua`
- Roll drops when cells destroyed
- Apply player luck modifiers
- Send loot to inventory
- Trigger visual feedback

### Step 4.3: Create Loot Visual System
**File:** `client/MiningGame/Effects/LootEffects.lua`
- Object pool for loot orbs
- Physics-based drop animation
- Auto-collect after 2 seconds
- Rarity-based colors/effects

## Phase 5: AFK System (1 day)

### Step 5.1: Implement AFK Tracking
**File:** `server/MiningGame/Services/AFKService.lua`
```lua
- Track last activity timestamp
- Calculate rolls on return (1/minute, max 4 hours)
- Apply diminishing returns
- Generate loot summary
```

### Step 5.2: Create Welcome Back UI
**File:** `client/MiningGame/UI/WelcomeBackScreen.lua`
- Show time away
- Display roll count
- Loot summary with categories
- Quick collect / View details options

## Phase 6: Sound System (PARTIALLY COMPLETE)

### ✅ COMPLETED Components:
- **SoundConfig.lua** - Complete configuration structure with all categories
- **SoundManager.lua** - Pooling system, 3D emitters, group management
- **SoundBroadcast.lua** - Server-side sound broadcasting system
- **SoundReplication.client.lua** - Client-side sound replication
- **AmbientController.lua** - Ambient zone management with spatial audio
- **Sound groups** - SFX, UI, Ambient, Music mixer groups

### ❌ MISSING Components:

#### Step 6.1: Add Sound Asset IDs
**File:** `shared/MiningGame/SoundConfig.lua`
- ALL sound IDs are currently `nil` - need actual rbxassetid:// values
- Priority sounds needed:
  - Mining hit sounds (rock, sand, ice, etc.)
  - UI button clicks/hovers
  - Footstep sounds for movement
  - Coin/gem collection sounds
  - At least one music track

#### Step 6.2: Connect Sounds to Game Systems
**Required connections:**
- **DigService** → Trigger mining sounds on hit
- **UI Components** → Play sounds on button interactions
- **Movement scripts** → Footstep sounds on walk/jump
- **LootService** → Collection sounds when items picked up
- **InventoryService** → Sounds for item management

#### Step 6.3: Add Music System
**File:** `client/MiningGame/Services/MusicService.lua` (NEW)
- Background music player with crossfade
- Dynamic volume based on activity
- Time-of-day based track selection

## Phase 7: Polish & Optimization (2 days)

### Step 7.1: Performance Optimization
- Implement LOD for distant cubes
- Optimize damage number pooling
- Batch network updates
- Profile and fix memory leaks

### Step 7.2: Mobile Optimization
- Touch control refinements
- UI scaling for various devices
- Reduced particle counts on low-end
- Battery saving mode

### Step 7.3: Tutorial System
**File:** `client/MiningGame/Tutorial/TutorialManager.lua`
- First-time player onboarding
- Highlight UI elements
- Step-by-step progression
- Skippable for returning players

## Phase 8: Monetization (1 day)

### Step 8.1: Implement Robux Shop
**File:** `server/MiningGame/Services/PurchaseService.lua`
- Process developer products
- Handle gamepasses
- Secure transaction validation
- Receipt processing

### Step 8.2: Add Premium Features
- VIP (2x rewards, exclusive areas)
- Boosts (temporary multipliers)
- Cosmetics (cube skins, effects)
- Instant tier unlock

## Testing Checklist

### Core Systems
- [ ] Mining damages cells instead of destroying
- [ ] Extraction points accumulate correctly
- [ ] Cube completes at quota
- [ ] Tier progression works
- [ ] HP scales with depth

### Visual Feedback
- [ ] Damage numbers appear
- [ ] Cracks show on damaged cells
- [ ] Selection boxes highlight targets
- [ ] Particles spawn on hit
- [ ] Screen shake works

### UI Systems
- [ ] All menus open/close properly
- [ ] Inventory displays items
- [ ] Shop purchases work
- [ ] Stats update in real-time
- [ ] Mobile controls responsive

### Progression
- [ ] Upgrades affect gameplay
- [ ] Currency accumulates
- [ ] Items drop at correct rates
- [ ] AFK rewards calculate properly
- [ ] Leaderboard updates

### Performance
- [ ] 60 FPS with UI open
- [ ] No memory leaks
- [ ] Network traffic optimized
- [ ] Mobile performance acceptable
- [ ] Loading times under 3s

## File Structure Summary

```
MiningGame/
├── server/
│   └── MiningGame/
│       └── Services/
│           ├── ExtractionService.lua (NEW)
│           ├── DropTableService.lua (NEW)
│           ├── AFKService.lua (NEW)
│           ├── UpgradeService.lua (NEW)
│           ├── PurchaseService.lua (NEW)
│           ├── DigService.lua (MODIFY)
│           └── CubeService.lua (MODIFY)
├── client/
│   └── MiningGame/
│       ├── UI/
│       │   ├── UIManager.lua (NEW)
│       │   ├── MainHUD.lua (NEW)
│       │   └── Scenes/
│       │       ├── InventoryScene.lua (NEW)
│       │       ├── ShopScene.lua (NEW)
│       │       └── UpgradesScene.lua (NEW)
│       ├── Services/
│       │   ├── DamageVisualService.lua (NEW)
│       │   ├── SoundService.lua (NEW)
│       │   └── MusicService.lua (NEW)
│       ├── Effects/
│       │   ├── ParticleEffects.lua (NEW)
│       │   └── LootEffects.lua (NEW)
│       └── Tutorial/
│           └── TutorialManager.lua (NEW)
└── shared/
    └── MiningGame/
        ├── Types.lua (MODIFY)
        └── InventoryTypes.lua (NEW)
```

## Launch Criteria

### Must Have (Day 1)
- ✅ Extraction system fully functional
- ✅ Visual feedback for all actions  
- ✅ Complete UI with all screens
- ✅ Drop table with correct rates
- ✅ Basic monetization
- ✅ Mobile compatibility

### Nice to Have (Post-Launch)
- Advanced particle effects
- Social features (friends, chat)
- Events and competitions
- Additional cube themes
- Prestige system
- Achievements

## Implementation Order

1. **Start Here:** Phase 1 - Core Extraction System
2. **Then:** Phase 2 - Visual Feedback (can partially overlap with Phase 1)
3. **Critical Path:** Phase 3 - UI Implementation
4. **Core Loop:** Phase 4 - Drop Table System  
5. **Retention:** Phase 5 - AFK System
6. **Polish:** Phases 6-8 can be done in parallel

## Time Estimate

- **Total Development Time:** 12-14 days
- **Testing & Refinement:** 2-3 days
- **Launch Ready:** ~2.5 weeks

## Notes

- No temporary code - build everything production-ready
- Mobile-first design for all UI
- Performance targets must be met before launch
- All monetization must be fair and transparent
- Focus on fun, not FOMO mechanics

---
*Last Updated: September 3, 2025*
*This is the authoritative implementation guide - supersedes all other planning documents*