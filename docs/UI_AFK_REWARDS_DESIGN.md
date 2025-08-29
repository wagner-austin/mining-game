# AFK Rewards UI Design

## Welcome Back Flow

### Step 1: Initial Welcome Screen (Appears over game view)
```
┌────────────────────────────────────────┐
│          WELCOME BACK!                 │
│                                        │
│         ⏰ Time Away: 3h 24m           │
│         🎲 Rolls Earned: 204           │
│                                        │
│    ╔═══════════════════════════╗      │
│    ║   [⚡ QUICK COLLECT]       ║      │
│    ╚═══════════════════════════╝      │
│                                        │
│    [👁️ View Details] [⚙️ Settings]    │
└────────────────────────────────────────┘
```

### Step 2A: Quick Collect Animation
- Screen flashes with collected items briefly
- Items fly to inventory icon
- Currency counters tick up
- Quick summary toast: "+4,562 coins collected!"

### Step 2B: Detailed View (If player chooses)
```
┌────────────────────────────────────────┐
│         AFK MINING REPORT              │
│      ━━━━━━━━━━━━━━━━━━━━━             │
├────────────────────────────────────────┤
│ Time Away: 3h 24m (204 rolls)          │
│                                        │
│ ▼ Common (143 items)                   │
│ ┌─────────────────────────────────┐   │
│ │ 🪨×62  🪨×41  🟫×28  🟫×12     │   │
│ └─────────────────────────────────┘   │
│                                        │
│ ▼ Uncommon (48 items)                 │
│ ┌─────────────────────────────────┐   │
│ │ ⚪×22  ⚪×14  🟡×8  💎×4       │   │
│ └─────────────────────────────────┘   │
│                                        │
│ ▼ Rare (12 items) ✨                  │
│ ┌─────────────────────────────────┐   │
│ │ 💚×6  ❤️×4  💙×2                │   │
│ └─────────────────────────────────┘   │
│                                        │
│ ⭐ EPIC FIND! (1 item)                │
│ ┌─────────────────────────────────┐   │
│ │      💎 DIAMOND ×1               │   │
│ │   "Incredible luck!"              │   │
│ └─────────────────────────────────┘   │
│                                        │
│ Total Value: 💰 4,562                  │
│                                        │
│ [COLLECT ALL]  [SELL COMMON]  [CLOSE] │
└────────────────────────────────────────┘
```

## Visual Design Elements

### Roll Animation (Optional Show)
```
┌────────────────────────────────────────┐
│         ROLLING YOUR LOOT...           │
│                                        │
│         [🎲][🎲][🎲]                  │
│          ↓   ↓   ↓                    │
│         [?] [?] [?]                   │
│                                        │
│     Processing 204 rolls...            │
│     ████████████░░░░ 67%              │
│                                        │
│     [SKIP ANIMATION]                   │
└────────────────────────────────────────┘
```

### Rarity Celebration
When rare+ items are found:
- Screen border glows with rarity color
- Particles emit from the item
- Special sound effect plays
- Item does a spin animation

### Mobile Optimizations
- Swipe up to quick collect
- Swipe left/right to see different rarity sections
- Tap and hold to see item details
- Pinch to see more items at once

## Settings for AFK System
```
┌────────────────────────────────────────┐
│         AFK SETTINGS                   │
├────────────────────────────────────────┤
│ Welcome Back Screen:                   │
│ ○ Always show details                  │
│ ● Quick collect                        │
│ ○ Ask me each time                    │
│                                        │
│ Auto-Sell Commons:                    │
│ [✓] Enabled                           │
│                                        │
│ Notification for Epic+:                │
│ [✓] Show special animation            │
│                                        │
│ AFK Efficiency: Level 3/10            │
│ Current: 1 roll/minute                │
│ Next: 1.2 rolls/minute                │
│ [💰 5,000 UPGRADE]                    │
└────────────────────────────────────────┘
```

## Integration with Main HUD

### AFK Indicator (When Active)
Small indicator showing AFK accumulation in real-time:
```
┌──────────────┐
│ AFK: 12 rolls│  <- Tucked in corner
└──────────────┘
```

### Return Celebration
When player returns:
1. Character does wake-up animation
2. Pets get excited
3. Sparkles appear around player
4. AFK rewards screen appears

## Roll History Tab (In Stats Menu)
```
┌────────────────────────────────────────┐
│         ROLL HISTORY                   │
├────────────────────────────────────────┤
│ Last 24 Hours:                         │
│ • Mining: 1,234 rolls                  │
│ • AFK: 456 rolls                       │
│ • Purchased: 100 rolls                 │
│                                        │
│ Best Find Today:                       │
│ 💎 Diamond (1:1000 chance!)           │
│                                        │
│ Luck Statistics:                       │
│ • Actual Rare Rate: 8.2%              │
│ • Expected: 8.0%                       │
│ • Lucky Streak: +0.2%! 🍀             │
│                                        │
│ [VIEW DETAILED LOG]                    │
└────────────────────────────────────────┘
```

## Upgrade Paths Display
```
┌────────────────────────────────────────┐
│      PASSIVE MINING UPGRADES           │
├────────────────────────────────────────┤
│ 🎲 Roll Rate          [Lv 3/10]       │
│ Current: 1.0/min → Next: 1.2/min      │
│ ▓▓▓░░░░░░░ 30%                       │
│ [💰 5,000 UPGRADE]                    │
│                                        │
│ 🍀 AFK Luck           [Lv 2/8]        │
│ Current: 0.5x → Next: 0.6x            │
│ ▓▓░░░░░░░░ 25%                       │
│ [💰 3,000 UPGRADE]                    │
│                                        │
│ ⏰ Max AFK Time       [Lv 1/5]        │
│ Current: 4 hours → Next: 5 hours      │
│ ▓░░░░░ 20%                           │
│ [💎 50 UPGRADE]                       │
│                                        │
│ 🎁 Rarity Cap         [LOCKED]        │
│ Unlock: Remove Epic cap on AFK        │
│ Requires: VIP Status                   │
│ [R$ 399 UNLOCK VIP]                   │
└────────────────────────────────────────┘
```

## Notification Toasts

### While Playing
```
[====================================]
[ 🎲 +1 AFK roll earned!            ]
[====================================]
```

### Special Finds
```
[====================================]
[ ⭐ EPIC! Your AFK miners found    ]
[ a DIAMOND while you were away!    ]
[====================================]
```

This creates an engaging AFK system that:
- Feels rewarding without being manipulative
- Uses clear, exciting UI to show rewards
- Integrates smoothly with the main game
- Provides clear upgrade paths
- Maintains economy balance