# Mining Game - UI Design Document

⚠️ **NOTE: This document shows both IMPLEMENTED (✅) and PLANNED (🔴) features**

## Current UI Implementation Summary

### ✅ What's Actually Built:
- Basic MainHUD with currency display (coins, gems)
- Settings button and settings panel
- Home/teleport button  
- Theme system with colors and styling
- UIManager with scene management (but few scenes)
- Basic mobile touch controls

### 🔴 What's NOT Built (Planned Features):
- Extraction/quota progress bar
- Level/XP system
- Active boosts display
- Inventory system
- Shop/upgrades interface
- Equipment/cosmetics
- Pets system
- Stats/achievements
- Leaderboard
- AFK/welcome back system
- Tier selection
- Damage feedback visuals
- Bottom navigation bar

## Visual Style Guide ✅ PARTIALLY IMPLEMENTED

### Color Palette
```
Primary:    #6C63FF (Vibrant Purple) - Main actions, buttons
Secondary:  #FF6B9D (Bubblegum Pink) - Highlights, special items
Accent:     #FFD93D (Golden Yellow) - Rewards, achievements
Success:    #6BCF7F (Mint Green) - Positive feedback, purchases
Error:      #FF6B6B (Soft Red) - Errors, warnings
Background: #1A1B2E (Deep Navy) - Main background
Surface:    #0F2C4F (Card Blue) - UI panels
Text:       #FFFFFF (White) - Primary text
TextDim:    #B0B0B0 (Gray) - Secondary text
```

### Rarity Colors (Consistent Everywhere)
```
Common:     #808080 (Gray)
Uncommon:   #6BCF7F (Green)
Rare:       #4A90E2 (Blue)
Epic:       #6C63FF (Purple)
Legendary:  #FFA500 (Orange)
Mythic:     #FF6B6B (Red) + Rainbow animation
```

## Main Game Screen (HUD)

### Current Implementation Status:
- ✅ **IMPLEMENTED**: Currency display (coins, gems), Settings button, Home button
- 🔴 **NOT IMPLEMENTED**: Level/XP, Active boosts, Extraction bar, Bottom navigation

### Layout Overview
```
┌─────────────────────────────────────────────────────────┐
│ [💰 12,345] [💎 567] [Lv.15 ████░░]    [🎁] [🔔] [⚙️]  │ <- Top Bar (Always visible)
│                                                         │
│ [🔥 2:45] [🍀 5:30] [👑 VIP]                          │ <- Active Boosts (Under top bar)
│                                                         │
│                                                         │
│              3D GAME WORLD                              │
│          (Click/Tap to mine)                           │
│                                                         │
│                                                         │
│ EXTRACTION: ████████░░░░ 15,234 / 35,000 (43.5%)     │ <- Progress Bar (Bottom-center)
│                                                         │
│ [🏠]                                              [💬]  │ <- Corner Buttons
│     [📦][🛍️][⚔️][🐾][📊][🏆]                          │ <- Bottom Navigation
└─────────────────────────────────────────────────────────┘
```

### Top Bar Details ✅ PARTIALLY IMPLEMENTED
```
┌─────────────────────────────────────────────────────────┐
│ ┌──────────┐ ┌──────────┐ ┌─────────────────┐         │
│ │ 💰 12,345│ │ 💎 567   │ │ Lv.15 ████░░░░ │         │
│ └──────────┘ └──────────┘ └─────────────────┘         │
│                                     [🎁] [🔔] [⚙️]     │
└─────────────────────────────────────────────────────────┘
```
- Currencies animate when changed (+100 floats up)
- Level bar shows exact XP on hover
- Gift box has red dot when rewards available
- Bell shows event notifications
- Gear opens settings

### Extraction Progress Bar 🔴 NOT IMPLEMENTED
```
┌─────────────────────────────────────────────────────────┐
│ ╔═══════════════════════════════════════════════════╗ │
│ ║ EXTRACTION: ████████████░░░░░░░░░░               ║ │
│ ║ Tier 2: Bronze Depths                            ║ │
│ ║ 15,234 / 35,000 (43.5%)                         ║ │
│ ╚═══════════════════════════════════════════════════╝ │
└─────────────────────────────────────────────────────────┘
```
- Glows when near completion (>90%)
- Shows current tier name
- Exact numbers + percentage

### Bottom Navigation Icons 🔴 NOT IMPLEMENTED
```
[📦] Inventory - Your items
[🛍️] Shop - Upgrades & purchases  
[⚔️] Equipment - Gear & cosmetics
[🐾] Pets - Pet management
[📊] Stats - Profile & achievements
[🏆] Leaderboard - Rankings
```

## Inventory Screen 🔴 NOT IMPLEMENTED

### Full Layout (PLANNED)
```
┌─────────────────────────────────────────────────────────┐
│ INVENTORY                                    [🔍] [❌]  │
├─────────────────────────────────────────────────────────┤
│ [All] [Ores] [Tools] [Special] [Consumables]           │ <- Tab Bar
├─────────────────────────────────────────────────────────┤
│ Sort: [Rarity ▼] Filter: [All ▼]      Value: 💰 45,678 │
├─────────────────────────────────────────────────────────┤
│ ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐     │
│ │ 🪨 │ │ 🪨 │ │ 🟫 │ │ ⚪ │ │ 🟡 │ │ 💎 │ │ 💎 │     │ <- Item Grid
│ │ 99 │ │ 99 │ │ 45 │ │ 23 │ │ 12 │ │  5 │ │  3 │     │    6x8 mobile
│ └────┘ └────┘ └────┘ └────┘ └────┘ └────┘ └────┘     │    8x6 tablet
│ ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐     │    10x8 PC
│ │ 💚 │ │ ❤️  │ │ 💙 │ │ 💜 │ │ 🧡 │ │ ❤️  │ │    │     │
│ │  2 │ │  1 │ │  1 │ │  1 │ │  1 │ │  1 │ │    │     │
│ └────┘ └────┘ └────┘ └────┘ └────┘ └────┘ └────┘     │
│                                                         │
│ [Additional rows scroll...]                            │
│                                                         │
├─────────────────────────────────────────────────────────┤
│ [Select All] [Sell Selected] [Sell All Common]         │ <- Action Bar
└─────────────────────────────────────────────────────────┘
```

### Item Details Popup (On tap/hover)
```
┌─────────────────────┐
│   💎 Diamond        │
│   ─────────────     │
│   Rarity: Epic      │
│   Value: 💰 1,000   │
│   Owned: 5          │
│   ─────────────     │
│   "A precious gem   │
│    found deep in    │
│    the earth"       │
│   ─────────────     │
│   [Sell] [Sell All] │
└─────────────────────┘
```

## Shop & Upgrades Screen 🔴 NOT IMPLEMENTED

### Layout with Tabs (PLANNED)
```
┌─────────────────────────────────────────────────────────┐
│ SHOP                                             [❌]   │
├─────────────────────────────────────────────────────────┤
│ [Upgrades] [Boosts] [Currency] [Passes] [VIP]          │
├─────────────────────────────────────────────────────────┤
│                                                         │
│ UPGRADES TAB:                                           │
│ ┌───────────────────────────────────────────────────┐  │
│ │ ⛏️ Mining Power              Level 5 → 6          │  │
│ │ ▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░░ 33%              │  │
│ │                                                   │  │
│ │ Current: 1.5x damage                              │  │
│ │ Next: 1.8x damage                                 │  │
│ │ Cost: 💰 5,000                                    │  │
│ │                                                   │  │
│ │ [UPGRADE]                                         │  │
│ └───────────────────────────────────────────────────┘  │
│                                                         │
│ ┌───────────────────────────────────────────────────┐  │
│ │ 📦 Dig Size                   Level 2 → 3         │  │
│ │ ▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░░░░░░ 20%              │  │
│ │                                                   │  │
│ │ Current: 5x5x5 blocks                             │  │
│ │ Next: 7x7x7 blocks                                │  │
│ │ Cost: 💰 15,000                                   │  │
│ │                                                   │  │
│ │ [UPGRADE]                                         │  │
│ └───────────────────────────────────────────────────┘  │
│                                                         │
│ BOOSTS TAB (Robux):                                    │
│ ┌───────────────────────────────────────────────────┐  │
│ │ ⚡ SPEED BOOST                    [R$ 25]        │  │
│ │ 2x faster mining for 1 hour                      │  │
│ │ [PURCHASE]                                        │  │
│ └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

## Equipment Screen 🔴 NOT IMPLEMENTED

```
┌─────────────────────────────────────────────────────────┐
│ EQUIPMENT                                        [❌]   │
├─────────────────────────────────────────────────────────┤
│                                                         │
│           ┌─────────────────┐                          │
│           │                 │                          │
│           │   CHARACTER     │                          │
│           │    PREVIEW      │                          │
│           │                 │                          │
│           └─────────────────┘                          │
│                                                         │
│ ┌─────────────────────────────────────────────────┐   │
│ │ Pickaxe: [🔶 Golden Pickaxe         ▼]         │   │
│ │ Effect: +30% mining power, +10% luck            │   │
│ └─────────────────────────────────────────────────┘   │
│                                                         │
│ ┌─────────────────────────────────────────────────┐   │
│ │ Hat:     [🎩 Miner's Helmet         ▼]         │   │
│ │ Effect: Light in dark areas                     │   │
│ └─────────────────────────────────────────────────┘   │
│                                                         │
│ ┌─────────────────────────────────────────────────┐   │
│ │ Back:    [🎒 Large Backpack         ▼]         │   │
│ │ Effect: +50 inventory slots                     │   │
│ └─────────────────────────────────────────────────┘   │
│                                                         │
│ Total Bonuses:                                         │
│ • Mining Power: +30%                                   │
│ • Luck: +10%                                          │
│ • Inventory: +50 slots                                │
└─────────────────────────────────────────────────────────┘
```

## Pet Management Screen

```
┌─────────────────────────────────────────────────────────┐
│ PETS                                             [❌]   │
├─────────────────────────────────────────────────────────┤
│ Active Pets (3/3):            [Manage Slots]           │
├─────────────────────────────────────────────────────────┤
│ ┌──────────┐ ┌──────────┐ ┌──────────┐               │
│ │    🐕    │ │    🐉    │ │    🦄    │               │
│ │  Buddy   │ │  Draco   │ │  Sparkle │               │
│ │  Lv. 15  │ │  Lv. 8   │ │  Lv. 12  │               │
│ │  ⭐⭐⭐   │ │  ⭐⭐     │ │  ⭐⭐⭐⭐  │               │
│ │ +5% coins│ │ +3% gems │ │ +2% luck │               │
│ │          │ │          │ │          │               │
│ │ [Remove] │ │ [Remove] │ │ [Remove] │               │
│ └──────────┘ └──────────┘ └──────────┘               │
├─────────────────────────────────────────────────────────┤
│ Inventory (15 pets):                  Sort: [Rarity ▼] │
├─────────────────────────────────────────────────────────┤
│ ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐     │
│ │ 🐱 │ │ 🐭 │ │ 🐹 │ │ 🐰 │ │ 🦊 │ │ 🐻 │ │ 🐼 │     │
│ │Lv.5│ │Lv.3│ │Lv.7│ │Lv.2│ │Lv.9│ │Lv.1│ │Lv.4│     │
│ └────┘ └────┘ └────┘ └────┘ └────┘ └────┘ └────┘     │
│                                                         │
│ [Hatch Egg] [Upgrade Pet] [Fuse Pets]                 │
└─────────────────────────────────────────────────────────┘
```

## Stats & Profile Screen

```
┌─────────────────────────────────────────────────────────┐
│ PROFILE & STATS                                  [❌]   │
├─────────────────────────────────────────────────────────┤
│ [Overview] [Achievements] [Statistics] [Settings]      │
├─────────────────────────────────────────────────────────┤
│                                                         │
│ OVERVIEW:                                              │
│ ┌─────────────────────────────────────────────────┐   │
│ │ Player: [Username]                               │   │
│ │ Level: 15 (3,456 / 10,000 XP)                   │   │
│ │ ▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░ 34.56%                │   │
│ │                                                  │   │
│ │ Cubes Completed: 47                              │   │
│ │ Current Tier: Bronze Depths (T2)                 │   │
│ │ Total Playtime: 12h 34m                          │   │
│ └─────────────────────────────────────────────────┘   │
│                                                         │
│ CURRENT BOOSTS:                                        │
│ ┌─────────────────────────────────────────────────┐   │
│ │ 🔥 Speed Boost: 5:30 remaining                  │   │
│ │ 🍀 Luck Boost: 12:45 remaining                  │   │
│ │ 👑 VIP Status: Active                           │   │
│ └─────────────────────────────────────────────────┘   │
│                                                         │
│ ACHIEVEMENTS (45/120):                                 │
│ ┌─────────────────────────────────────────────────┐   │
│ │ 🏆 Speed Demon - Mine 100 blocks in 1 minute   │   │
│ │ ▓▓▓▓▓▓▓▓▓▓ 100/100 ✓                          │   │
│ └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

## Leaderboard Screen

```
┌─────────────────────────────────────────────────────────┐
│ LEADERBOARD                                      [❌]   │
├─────────────────────────────────────────────────────────┤
│ [Global] [Friends] [Weekly] [Tier]                     │
├─────────────────────────────────────────────────────────┤
│                                                         │
│ Your Rank: #234 ↑12                                    │
│                                                         │
│ ┌─────────────────────────────────────────────────┐   │
│ │ 1.  👑 ProMiner123        1,234,567 blocks      │   │
│ │ 2.  🥈 DiamondDave         987,654 blocks      │   │
│ │ 3.  🥉 CrystalQueen        876,543 blocks      │   │
│ │ 4.     BlockBreaker        765,432 blocks      │   │
│ │ 5.     MiningMaster        654,321 blocks      │   │
│ │ ...                                             │   │
│ │ 232.   GemHunter            45,679 blocks      │   │
│ │ 233.   RockSmasher          45,678 blocks      │   │
│ │ 234. ⭐ YOU                  45,677 blocks      │   │
│ │ 235.   Noob2024             45,676 blocks      │   │
│ │ 236.   PickaxePete          45,675 blocks      │   │
│ └─────────────────────────────────────────────────┘   │
│                                                         │
│ [Refresh] [View Rewards]                               │
└─────────────────────────────────────────────────────────┘
```

## Welcome Back Screen (AFK Rewards) 🔴 NOT IMPLEMENTED

```
┌─────────────────────────────────────────────────────────┐
│              WELCOME BACK!                             │
│                                                         │
│         You were away for: 3h 24m                      │
│         Your miners collected 204 rolls!               │
│                                                         │
│    ╔═══════════════════════════════════════╗          │
│    ║     [⚡ QUICK COLLECT ALL]             ║          │
│    ╚═══════════════════════════════════════╝          │
│                                                         │
│         [👁️ View Details] [⚙️ Settings]                │
└─────────────────────────────────────────────────────────┘

When "View Details" is clicked:
┌─────────────────────────────────────────────────────────┐
│              AFK MINING REPORT                         │
├─────────────────────────────────────────────────────────┤
│ Time Away: 3h 24m (204 rolls)                          │
│                                                         │
│ Items Collected:                                       │
│ ┌─────────────────────────────────────────────────┐   │
│ │ Common (143):                                    │   │
│ │ 🪨 Stone x62  🪨 Coal x41                       │   │
│ │ 🟫 Copper x28  🟫 Tin x12                       │   │
│ └─────────────────────────────────────────────────┘   │
│ ┌─────────────────────────────────────────────────┐   │
│ │ Uncommon (48):                                   │   │
│ │ ⚪ Iron x22  ⚪ Silver x14                      │   │
│ │ 🟡 Gold x8  💎 Quartz x4                       │   │
│ └─────────────────────────────────────────────────┘   │
│ ┌─────────────────────────────────────────────────┐   │
│ │ Rare (12):                                       │   │
│ │ 💚 Emerald x6  ❤️ Ruby x4  💙 Sapphire x2      │   │
│ └─────────────────────────────────────────────────┘   │
│ ┌─────────────────────────────────────────────────┐   │
│ │ ⭐ EPIC FIND!                                   │   │
│ │ 💎 Diamond x1                                   │   │
│ └─────────────────────────────────────────────────┘   │
│                                                         │
│ Total Value: 💰 4,562                                  │
│                                                         │
│ [COLLECT ALL] [SELL COMMON] [CLOSE]                   │
└─────────────────────────────────────────────────────────┘
```

## Tier Selection Screen 🔴 NOT IMPLEMENTED

```
┌─────────────────────────────────────────────────────────┐
│              SELECT MINING TIER                        │
├─────────────────────────────────────────────────────────┤
│                                                         │
│ ┌─────────────────────────────────────────────────┐   │
│ │ T1: STARTER MINES                    [CURRENT]  │   │
│ │ Quota: 35,000                                   │   │
│ │ Difficulty: ⭐                                   │   │
│ │ Rewards: 1x                                     │   │
│ │ Recommended Power: 1-50                         │   │
│ │ Your Power: 45 ✓                                │   │
│ └─────────────────────────────────────────────────┘   │
│                                                         │
│ ┌─────────────────────────────────────────────────┐   │
│ │ T2: BRONZE DEPTHS                  [UNLOCKED]   │   │
│ │ Quota: 120,000                                  │   │
│ │ Difficulty: ⭐⭐                                 │   │
│ │ Rewards: 1.5x                                   │   │
│ │ Recommended Power: 50-200                       │   │
│ │ Your Power: 45 ⚠️                               │   │
│ │ [SELECT]                                        │   │
│ └─────────────────────────────────────────────────┘   │
│                                                         │
│ ┌─────────────────────────────────────────────────┐   │
│ │ T3: SILVER CAVERNS                   [LOCKED]   │   │
│ │ 🔒 Requires: Complete 10 T2 cubes               │   │
│ │ Progress: 3/10                                  │   │
│ └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

## Damage Feedback Visuals 🔴 NOT IMPLEMENTED

### During Mining (Real-time feedback)
```
         Click!
           ↓
    ┌─────────────┐
    │   -15 DMG   │  <- Floats up and fades
    └─────────────┘
    
    Cell being mined:
    ┌─────────────┐
    │ ▓▓▓▓▓░░░░░ │  <- HP bar appears briefly
    │  HP: 3/10   │
    └─────────────┘
    
    When cell breaks:
    ┌─────────────┐
    │   BREAK!    │  <- Green text, particles
    │   +3 EXT    │  <- Extraction points gained
    └─────────────┘
```

## Mobile-Specific Adaptations

### Touch Gestures
- **Tap**: Mine / Select item
- **Long Press**: Show details
- **Swipe Down**: Close overlay
- **Swipe Left/Right**: Change tabs
- **Pinch**: Zoom camera (gameplay)
- **Double Tap**: Quick action

### Responsive Sizing
```
Phone (< 768px):
- Bottom nav: Icons only
- Inventory: 5x8 grid
- Text: 14px base

Tablet (768-1024px):
- Bottom nav: Icons + small labels
- Inventory: 6x8 grid
- Text: 16px base

PC (> 1024px):
- Bottom nav: Full labels
- Inventory: 10x8 grid
- Text: 14px base
- Keyboard shortcuts shown
```

## Animation & Transitions

### Screen Transitions
- **Open**: 0.3s slide up + fade in
- **Close**: 0.2s slide down + fade out
- **Tab Switch**: 0.2s horizontal slide

### Feedback Animations
- **Button Press**: 0.95 scale, 0.1s
- **Item Collect**: Fly to inventory, 0.5s
- **Level Up**: Burst particles, 1.0s
- **Currency Change**: Number ticks up, 0.3s

## Notification System

### Toast Notifications (Top of screen)
```
╔═══════════════════════════════════════════╗
║ 🎉 Achievement Unlocked: Speed Demon!     ║
╚═══════════════════════════════════════════╝
```

### Floating Combat Text (In world)
```
+100 💰  (floats up from mined block)
+5 💎    (rarer, bigger text)
RARE!    (special color for rare drops)
```

## Settings Screen

```
┌─────────────────────────────────────────────────────────┐
│ SETTINGS                                         [❌]   │
├─────────────────────────────────────────────────────────┤
│ [Graphics] [Audio] [Controls] [Account]                │
├─────────────────────────────────────────────────────────┤
│                                                         │
│ GRAPHICS:                                              │
│ Quality: [Low] [Medium] [High] [Ultra]                 │
│ Particles: [✓] Enabled                                │
│ Shadows: [✓] Enabled                                  │
│ Camera Shake: [✓] Enabled                             │
│                                                         │
│ AUDIO:                                                 │
│ Master Volume: ▓▓▓▓▓▓▓▓░░ 80%                        │
│ Sound Effects: ▓▓▓▓▓▓▓▓▓▓ 100%                       │
│ Music: ▓▓▓▓▓░░░░░ 50%                                │
│                                                         │
│ CONTROLS:                                              │
│ Dig Mode: [Hold] [Toggle] [Click]                     │
│ Camera Sensitivity: ▓▓▓▓▓░░░░░ 50%                   │
│                                                         │
│ [Reset to Defaults] [Save Settings]                   │
└─────────────────────────────────────────────────────────┘
```

## Implementation Priority

### Phase 1: Core UI (Week 1)
1. Main HUD with extraction bar
2. Inventory system
3. Shop/Upgrades
4. Damage feedback visuals

### Phase 2: Features (Week 2)
5. Welcome back (AFK rewards)
6. Equipment system
7. Pet management
8. Stats & achievements

### Phase 3: Polish (Week 3)
9. Leaderboards
10. Settings
11. Tier selection
12. All animations & transitions

## Technical Notes

### UI Framework
- Use Roact or Fusion for reactive UI
- Component-based architecture
- Single source of truth for state

### Performance
- Pool all UI instances
- Lazy load tab contents
- Virtual scrolling for long lists
- Batch UI updates per frame

### Mobile Optimization
- Use UDim2.new(scale) not offset
- UIAspectRatioConstraint for consistency
- Minimum touch target: 48x48px
- Safe zone margins for notches