# Unified Drop Table System Design

## Core Concept
All rewards in the game come from a single, unified drop table system. Whether you're:
- Mining blocks (1 roll per voxel)
- AFK (1 roll per minute base rate)
- Opening loot boxes
- Completing achievements

Everything uses the same drop table with different modifiers.

## Drop Table Structure

### Rarity Tiers & Base Rates
```lua
DropTable = {
    -- Common (70% combined)
    {id = "stone", weight = 3000, minDepth = 0},           -- 30%
    {id = "coal", weight = 2000, minDepth = 0},            -- 20%
    {id = "copper", weight = 1500, minDepth = 0},          -- 15%
    {id = "tin", weight = 500, minDepth = 0},              -- 5%
    
    -- Uncommon (20% combined)
    {id = "iron", weight = 1000, minDepth = 5},            -- 10%
    {id = "silver", weight = 500, minDepth = 10},          -- 5%
    {id = "gold", weight = 300, minDepth = 15},            -- 3%
    {id = "quartz", weight = 200, minDepth = 8},           -- 2%
    
    -- Rare (8% combined)
    {id = "emerald", weight = 400, minDepth = 20},         -- 4%
    {id = "ruby", weight = 200, minDepth = 25},            -- 2%
    {id = "sapphire", weight = 150, minDepth = 25},        -- 1.5%
    {id = "amethyst", weight = 50, minDepth = 30},         -- 0.5%
    
    -- Epic (1.8% combined)
    {id = "diamond", weight = 100, minDepth = 40},         -- 1%
    {id = "obsidian", weight = 50, minDepth = 35},         -- 0.5%
    {id = "mithril", weight = 25, minDepth = 50},          -- 0.25%
    {id = "adamantite", weight = 5, minDepth = 60},        -- 0.05%
    
    -- Legendary (0.19% combined)
    {id = "ancient_ore", weight = 10, minDepth = 70},      -- 0.1%
    {id = "void_stone", weight = 5, minDepth = 80},        -- 0.05%
    {id = "star_fragment", weight = 3, minDepth = 90},     -- 0.03%
    {id = "dragon_scale", weight = 1, minDepth = 100},     -- 0.01%
    
    -- Mythic (0.01% combined)
    {id = "cosmic_essence", weight = 0.5, minDepth = 150}, -- 0.005%
    {id = "god_ore", weight = 0.3, minDepth = 200},        -- 0.003%
    {id = "universe_fragment", weight = 0.2, minDepth = 250}, -- 0.002%
    
    -- Total weight: 10,000 (for easy percentage calculation)
}
```

### Roll Modifiers

#### Context Modifiers
```lua
RollContexts = {
    MINING = {
        baseRolls = 1,  -- per voxel
        luckMultiplier = 1.0,
        depthBonus = true,
    },
    AFK = {
        baseRolls = 1,  -- per minute
        luckMultiplier = 0.5,  -- Half luck when AFK
        depthBonus = false,  -- No depth bonus when AFK
        maxRarity = "Epic",  -- Cap AFK rewards
    },
    LOOT_BOX = {
        baseRolls = 5,  -- Multiple rolls per box
        luckMultiplier = 1.5,
        guaranteedRarity = "Rare",  -- At least one rare
    },
}
```

#### Player Modifiers
```lua
PlayerModifiers = {
    luck = 1.0,  -- Base, upgraded through progression
    vip = false,  -- VIP doubles rare+ chances
    boosts = {
        luckBoost = 0,  -- Temporary boost from shop
        rollBoost = 0,  -- Extra rolls per action
    },
    equipment = {
        pickaxeLuck = 0,  -- From equipped pickaxe
        petLuck = 0,  -- From active pets
    },
}
```

## AFK System Design

### Welcome Back Screen
```
┌────────────────────────────────────────┐
│ WELCOME BACK!                          │
├────────────────────────────────────────┤
│ You were away for: 3h 24m              │
│ Your auto-miners made 204 rolls!       │
│                                        │
│ [⚡ QUICK COLLECT]  [👁️ VIEW LOOT]     │
└────────────────────────────────────────┘

If VIEW LOOT is selected:
┌────────────────────────────────────────┐
│ AFK LOOT SUMMARY                       │
├────────────────────────────────────────┤
│ 204 Total Rolls:                       │
│                                        │
│ Common (143):                          │
│ 🪨 Stone x62  🪨 Coal x41             │
│ 🟫 Copper x28  🟫 Tin x12             │
│                                        │
│ Uncommon (48):                         │
│ ⚪ Iron x22  ⚪ Silver x14             │
│ 🟡 Gold x8  💎 Quartz x4              │
│                                        │
│ Rare (12):                             │
│ 💚 Emerald x6  ❤️ Ruby x4             │
│ 💙 Sapphire x2                        │
│                                        │
│ Epic (1):                              │
│ 💎 DIAMOND x1! (Lucky!)               │
│                                        │
│ Total Value: 💰 4,562                  │
│                                        │
│ [COLLECT ALL]  [SELL ALL]              │
└────────────────────────────────────────┘
```

### AFK Roll Calculation
```lua
function calculateAFKRolls(secondsAway)
    local baseRollsPerMinute = 1
    local minutes = math.floor(secondsAway / 60)
    
    -- Cap at 4 hours (240 minutes) to prevent exploitation
    local cappedMinutes = math.min(minutes, 240)
    
    -- Apply diminishing returns after 1 hour
    local rolls = 0
    if cappedMinutes <= 60 then
        rolls = cappedMinutes * baseRollsPerMinute
    else
        -- First hour: full rate
        rolls = 60 * baseRollsPerMinute
        -- After 1 hour: 75% rate
        local remainingMinutes = cappedMinutes - 60
        rolls = rolls + (remainingMinutes * baseRollsPerMinute * 0.75)
    end
    
    -- Apply player modifiers
    rolls = rolls * (1 + playerModifiers.afkBonus)
    
    return math.floor(rolls)
end
```

## Drop Rate Examples

### Mining (Active Play)
- **1 voxel mined** = 1 roll
- **3x3 dig size** = 9 rolls per dig
- **With 2x luck** = Better chances, not more rolls
- **At depth 100** = Access to all items in table

### AFK (Passive)
- **1 minute AFK** = 1 roll
- **1 hour AFK** = 60 rolls
- **4 hours AFK** = 210 rolls (with diminishing returns)
- **Capped at Epic rarity** to incentivize active play

### Actual Drop Rates (Base)
```
Per 10,000 rolls:
- Stone: 3,000 (30%)
- Coal: 2,000 (20%)
- Diamond: 100 (1%)
- Dragon Scale: 1 (0.01%)
- God Ore: 0.3 (0.003% or 1 in ~33,333)

With 4-hour AFK session (210 rolls):
- Expected diamonds: 0.21 (1 every ~5 sessions)
- Expected dragon scales: 0.0021 (1 every ~476 sessions)
- Expected god ore: 0 (capped at Epic)
```

## Implementation Structure

### DropTableService.lua
```lua
local DropTableService = {}

-- Main drop table
local DROP_TABLE = { --[[ as defined above ]] }

-- Roll on the drop table
function DropTableService:roll(context, player)
    local modifiers = self:getModifiers(context, player)
    local eligibleItems = self:filterByContext(DROP_TABLE, context)
    local weights = self:calculateWeights(eligibleItems, modifiers)
    return self:selectItem(weights)
end

-- Batch roll for efficiency
function DropTableService:batchRoll(count, context, player)
    local results = {}
    for i = 1, count do
        local item = self:roll(context, player)
        results[item] = (results[item] or 0) + 1
    end
    return results
end

-- Get total value of items
function DropTableService:calculateValue(items)
    local total = 0
    for itemId, count in pairs(items) do
        local itemData = self:getItemData(itemId)
        total = total + (itemData.value * count)
    end
    return total
end
```

## Balancing Considerations

### Economy Protection
1. **AFK Caps**: 
   - Max 4 hours accumulation
   - Diminishing returns after 1 hour
   - Rarity cap at Epic

2. **Active Play Incentive**:
   - Mining gives full drop table access
   - Depth bonus only when mining
   - Better luck multiplier when active

3. **Rare Item Scarcity**:
   - Mythic items: 1 in 33,000+ rolls
   - Even with perfect luck, still very rare
   - Creates long-term goals

### Progression Hooks
1. **Luck Upgrades**: Make every roll slightly better
2. **Dig Size**: More rolls per action
3. **AFK Efficiency**: Upgrade passive roll rate
4. **Depth Access**: Unlock deeper areas for better loot

## Monetization Tie-ins

### Direct Purchase Options
```lua
ShopItems = {
    -- Instant rolls
    {name = "Lucky Box", rolls = 100, context = "LOOT_BOX", price = "R$49"},
    {name = "Mega Box", rolls = 500, context = "LOOT_BOX", price = "R$199"},
    
    -- Roll modifiers
    {name = "2x Luck (1hr)", modifier = 2.0, duration = 3600, price = "R$25"},
    {name = "AFK Boost (24hr)", afkMultiplier = 2.0, duration = 86400, price = "R$99"},
    
    -- Permanent upgrades
    {name = "VIP", permanentLuck = 1.5, removeAfkCap = true, price = "R$399"},
}
```

## Analytics & Monitoring

### Key Metrics to Track
```lua
Analytics = {
    -- Per player per session
    totalRolls = 0,
    rollsByContext = {mining = 0, afk = 0, purchased = 0},
    
    -- Rarity distribution
    itemsRolled = {}, -- Track actual vs expected
    
    -- Economy health
    totalCurrencyGenerated = 0,
    averageSessionValue = 0,
    
    -- Engagement
    afkSessionLength = 0,
    activePlayTime = 0,
    rollsPerMinuteActive = 0,
}
```

### Admin Commands for Testing
```lua
-- Test drop rates
/simulate-rolls [count] [context] [luck]

-- View player's roll history
/player-rolls [username] [timeframe]

-- Adjust drop weights live (for events)
/modify-weight [itemId] [multiplier] [duration]

-- Emergency economy controls
/disable-drops [rarity]
/set-roll-cap [max]
```

## Future Expansion

### Event Modifiers
- Double drop weekends
- Specific item rate-ups
- Seasonal exclusive items

### New Contexts
- Boss fights (guaranteed rare+)
- Dungeons (themed drop tables)
- PvP rewards (competitive rolls)

### Player Trading
- Track item sources to prevent duping
- Separate tradeable vs bound items
- Market value based on actual rarity

This system gives you complete control over the economy while making everything feel fair and exciting for players!