# Achievement Display System Plan

## Current State
- **Server**: Achievement system fully implemented with 13 achievements
- **Server**: Awards achievements and fires `OnAchievement` RemoteEvent
- **Client**: NO handler for achievement notifications
- **Players**: Can't see when they unlock achievements (happening silently)

## Goals
1. Display achievement unlock notifications prominently
2. Different visual style from regular toasts (more celebratory)
3. Show achievement tier (Bronze/Silver/Gold/Diamond/Platinum)
4. Display rewards earned
5. Possible achievement progress tracking UI

## Design Decisions

### Option 1: Special Achievement Toast (Recommended)
- Use existing toast system but with special styling
- Position: Center-top of screen (more prominent than side toasts)
- Larger size, special animation (scale + glow)
- Display for longer duration (4-5 seconds)
- Show: Icon, Name, Description, Tier badge, Rewards

### Option 2: Full-Screen Modal
- Dramatic full-screen overlay
- Blurred background
- Large achievement display with effects
- Pros: Very noticeable, celebratory
- Cons: Interrupts gameplay

### Option 3: Dedicated Achievement Panel
- Permanent UI element showing recent/next achievements
- Updates when achievements unlock
- Shows progress bars for milestone achievements
- Pros: Always visible progress
- Cons: Takes up screen space

## Implementation Plan

### Phase 1: Basic Achievement Toast

#### Step 1.1: Add Achievement Handler in ClientUI
```lua
-- ClientUI.client.lua
local onAchievement = RE.OnAchievement
if onAchievement then
    onAchievement.OnClientEvent:Connect(function(achievement)
        manager:showAchievement(achievement)
    end)
end
```

#### Step 1.2: Add showAchievement Method to UIManager
```lua
function UIManager:showAchievement(achievement: {
    id: string,
    name: string,
    desc: string,
    tier: string,
    reward: {coins: number?, gems: number?}
})
    -- Special styling for achievements
end
```

#### Step 1.3: Achievement Toast Styling
- **Size**: 1.5x larger than regular toasts
- **Position**: Center-top (not side)
- **Duration**: 5 seconds (vs 3 for regular)
- **Animation**: Scale bounce in + glow effect
- **Colors by Tier**:
  - Bronze: `#CD7F32`
  - Silver: `#C0C0C0`
  - Gold: `#FFD700`
  - Diamond: `#B9F2FF`
  - Platinum: `#E5E4E2`

#### Step 1.4: Achievement Toast Layout
```
┌─────────────────────────────────────┐
│ 🏆  ACHIEVEMENT UNLOCKED!           │
│                                     │
│     [ICON]  Master Miner            │
│             Dig 10,000 blocks       │
│                                     │
│     Rewards: 💰 2000  💎 10         │
│                                     │
│     ════════ GOLD ════════          │
└─────────────────────────────────────┘
```

### Phase 2: Achievement Progress Tracking

#### Step 2.1: Track Progress for Milestone Achievements
- Show progress bars for near-complete achievements
- "Next Achievement: 8,234/10,000 blocks"
- Update in real-time as player progresses

#### Step 2.2: Achievement Menu/Panel
- Button to open full achievement list
- Show completed vs available
- Display rewards and requirements
- Categories: First-Time, Milestones, Wealth, Rarity

### Phase 3: Enhanced Effects

#### Step 3.1: Particle Effects
- Confetti burst for Gold+ achievements
- Star particles floating up
- Tier-specific effects (bronze sparks, diamond shimmer)

#### Step 3.2: Sound Effects
- Different sounds per tier
- Fanfare for high-tier achievements
- Coin sound for reward display

#### Step 3.3: Screen Effects
- Brief screen flash (tier color)
- Optional: Slight zoom/shake for Mythic achievement

## Technical Considerations

### Reuse Toast System vs New System
**Recommendation**: Extend toast system with new `showAchievement` method
- Reuses queue management
- Reuses animation logic
- Just different styling/positioning

### Achievement Data Storage
- Cache achievement definitions client-side
- Track which achievements player has (for UI)
- Store progress for milestone achievements

### Performance
- Limit particle effects on mobile
- Queue achievements if multiple unlock at once
- Preload achievement icons/sounds

## Testing Checklist

### Phase 1 Testing
- [ ] Achievement notification appears when unlocked
- [ ] Correct tier color and styling
- [ ] Rewards display properly
- [ ] Animation plays smoothly
- [ ] Notification doesn't overlap game UI
- [ ] Multiple achievements queue properly

### Phase 2 Testing
- [ ] Progress bars update correctly
- [ ] Achievement menu opens/closes
- [ ] Completed achievements marked properly
- [ ] Categories filter correctly

### Phase 3 Testing
- [ ] Particles don't cause lag
- [ ] Sounds play at appropriate volume
- [ ] Effects scale with graphics settings
- [ ] Mobile performance acceptable

## Priority Order

1. **High Priority** (Do First)
   - Basic achievement toast display
   - Tier coloring
   - Reward display

2. **Medium Priority**
   - Achievement menu/list
   - Progress tracking
   - Better animations

3. **Low Priority** (Polish)
   - Particle effects
   - Sound effects
   - Screen effects

## Example Code Structure

```lua
-- UIManager.lua
function UIManager:showAchievement(data)
    local tierColors = {
        bronze = Color3.fromRGB(205, 127, 50),
        silver = Color3.fromRGB(192, 192, 192),
        gold = Color3.fromRGB(255, 215, 0),
        diamond = Color3.fromRGB(185, 242, 255),
        platinum = Color3.fromRGB(229, 228, 226),
    }
    
    local color = tierColors[data.tier] or tierColors.bronze
    
    -- Create special achievement toast
    self:_queueOrSpawn({
        labelText = string.format("🏆 %s\n%s", data.name, data.desc),
        iconText = "🏆",
        accentColor = color,
        textColor = color,
        richText = true,
        duration = 5,
        isAchievement = true, -- Special flag for different positioning
    })
end
```

## Success Metrics

1. Players notice and celebrate achievement unlocks
2. No missed achievement notifications
3. Clear understanding of what was achieved and rewards earned
4. Performance impact < 5ms
5. Mobile-friendly display

## Next Steps

1. Review and approve plan
2. Implement Phase 1 (basic achievement toast)
3. Test with a few achievements
4. Gather feedback
5. Implement Phase 2-3 based on feedback
# Achievement Display System Plan

## Current State (Aligned With Code)
- Server: Achievement system implemented (award, persist, rewards, milestone checks).
- Server: Emits `EventNames.ACHIEVEMENT_UNLOCKED` over the EventBus (not a dedicated RemoteEvent per achievement).
  - Emission site: `server/MiningGame/AchievementService.lua`
  - Guarded by `GameConfig.Features.ACHIEVEMENT_NOTIFICATIONS`.
  - Payload currently includes: `{ achievementId, reward, playerName }`.
- Client: No listener/UI wired up yet — unlocks are silent to players.

## Goals
1. Display achievement unlock notifications prominently
2. Different visual style from regular toasts (more celebratory)
3. Show achievement tier (Bronze/Silver/Gold/Diamond/Platinum)
4. Display rewards earned
5. Possible achievement progress tracking UI

## Design Decisions

### Option 1: Special Achievement Toast (Recommended)
- Use existing toast system but with special styling
- Position: Center-top of screen (more prominent than side toasts)
- Larger size, special animation (scale + glow)
- Display for longer duration (4-5 seconds)
- Show: Icon, Name, Description, Tier badge, Rewards

### Option 2: Full-Screen Modal
- Dramatic full-screen overlay
- Blurred background
- Large achievement display with effects
- Pros: Very noticeable, celebratory
- Cons: Interrupts gameplay

### Option 3: Dedicated Achievement Panel
- Permanent UI element showing recent/next achievements
- Updates when achievements unlock
- Shows progress bars for milestone achievements
- Pros: Always visible progress
- Cons: Takes up screen space

## Implementation Plan (Matches Current Server Emission)

### Phase 1: Basic Achievement Toast

#### Step 1.1: Subscribe to EventBus (ACHIEVEMENT_UNLOCKED)
```lua
-- Client bootstrap (e.g., ClientUI.client.lua)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local EventBus = require(MiningGame:WaitForChild("EventBus")).global()
local EventNames = require(MiningGame:WaitForChild("EventNames"))

local UIManager = require(MiningGame:WaitForChild("UIManager"))
local manager = UIManager.get()

-- Server sends: { achievementId, reward, playerName }
local function onUnlocked(evt)
    local p = evt and evt.payload or {}
    manager:showAchievement({
        id = p.achievementId,
        reward = p.reward,
    })
end

-- Subscribe
local unsubscribe = EventBus:on(EventNames.ACHIEVEMENT_UNLOCKED, onUnlocked)
```

#### Step 1.2: Add showAchievement Method to UIManager
```lua
function UIManager:showAchievement(achievement: {
    id: string,
    name: string?,
    desc: string?,
    tier: string?,
    reward: {coins: number?, gems: number?, items: {[string]: number}?}?
})
    -- Special styling for achievements (see styling below)
end
```

#### Step 1.3: Resolve Achievement Metadata on Client
- Current server payload does not include `name/desc/tier`.
- Recommended: ship a small definitions module in `ReplicatedStorage.MiningGame` (e.g., `Achievements.lua`) or include a map in UIManager.
- Minimal interim: map known IDs → names/tiers client-side; fall back to the raw `id` string if unknown.

Example resolver:
```lua
local AchDefs = MiningGame:FindFirstChild("Achievements") and require(MiningGame.Achievements)
function UIManager:_resolveAchievementMeta(id: string)
    local def = AchDefs and AchDefs[id]
    if def then
        return def.name, def.desc, string.lower(def.tier or "bronze")
    end
    return id, "", "bronze"
end
```

#### Step 1.4: Achievement Toast Styling
- Size: ~1.5x larger than regular toasts
- Position: Center-top (not side)
- Duration: 5 seconds (vs 3 for regular)
- Animation: Scale bounce in + glow effect
- Colors by Tier:
  - Bronze: `#CD7F32`
  - Silver: `#C0C0C0`
  - Gold: `#FFD700`
  - Diamond: `#B9F2FF`
  - Platinum: `#E5E4E2`

#### Step 1.5: Achievement Toast Layout (example)
```
[ ACHIEVEMENT UNLOCKED! ]

  [ICON]  Master Miner
          Dig 10,000 blocks

  Rewards:  2000 coins   10 gems
  Tier: GOLD
```

### Phase 2: Achievement Progress Tracking

#### Step 2.1: Track Progress for Milestone Achievements
- Show progress bars for near-complete achievements
- "Next Achievement: 8,234/10,000 blocks"
- Update in real-time as player progresses

#### Step 2.2: Achievement Menu/Panel
- Button to open full achievement list
- Show completed vs available
- Display rewards and requirements
- Categories: First-Time, Milestones, Wealth, Rarity

### Phase 3: Enhanced Effects

#### Step 3.1: Particle Effects
- Confetti burst for Gold+ achievements
- Star particles floating up
- Tier-specific effects (bronze sparks, diamond shimmer)

#### Step 3.2: Sound Effects
- Different sounds per tier
- Fanfare for high-tier achievements
- Coin sound for reward display

#### Step 3.3: Screen Effects
- Brief screen flash (tier color)
- Optional: Slight zoom/shake for mythic-tier unlocks

## Technical Considerations

### Transport: EventBus vs Dedicated RemoteEvent
- Current code emits achievements via EventBus (`Remotes.EventBus` + typed names) — keep this.
- No need to add a dedicated RemoteEvent; reuse the EventBus subscription on client.

### Reuse Toast System vs New System
Recommendation: Extend toast system with `showAchievement`
- Reuses queue and animation logic; change styling/positioning only

### Achievement Data Storage
- Cache achievement definitions client-side (static module or RF fetch)
- Track which achievements player has (for menu/panel)
- Store progress for milestone achievements

### Feature Flags
- Server emission is gated by `GameConfig.Features.ACHIEVEMENT_NOTIFICATIONS`.
- Client should tolerate feature-off state (no events) without errors.

### Performance
- Limit particle effects on mobile
- Queue achievements if multiple unlock at once
- Preload achievement icons/sounds

## Testing Checklist

### Phase 1 Testing
- [ ] EventBus subscription receives events when achievements unlock
- [ ] Achievement notification appears; correct tier color and styling
- [ ] Rewards display properly (coins/gems/items)
- [ ] Animation plays smoothly; no UI overlap issues
- [ ] Multiple achievements queue properly
- [ ] Works when feature flag is toggled off (no errors)
- [ ] Unsubscribe on teardown (no memory leaks)

### Phase 2 Testing
- [ ] Progress bars update correctly
- [ ] Achievement menu opens/closes
- [ ] Completed achievements marked properly
- [ ] Categories filter correctly

### Phase 3 Testing
- [ ] Particles performant on mobile/low-end
- [ ] Sounds play at appropriate volume
- [ ] Effects scale with graphics settings

## Priority Order

1. High Priority (Do First)
   - EventBus listener + basic achievement toast display
   - Tier coloring
   - Reward display

2. Medium Priority
   - Achievement menu/list
   - Progress tracking
   - Better animations

3. Low Priority (Polish)
   - Particle effects
   - Sound effects
   - Screen effects

## Example Code Structure

```lua
-- UIManager.lua
function UIManager:showAchievement(data)
    local tierColors = {
        bronze = Color3.fromRGB(205, 127, 50),
        silver = Color3.fromRGB(192, 192, 192),
        gold   = Color3.fromRGB(255, 215, 0),
        diamond= Color3.fromRGB(185, 242, 255),
        platinum=Color3.fromRGB(229, 228, 226),
    }

    local name, desc, tier = self:_resolveAchievementMeta(data.id)
    local color = tierColors[(data.tier or tier or "bronze")] or tierColors.bronze

    -- Create special achievement toast
    self:_queueOrSpawn({
        labelText = string.format("%s\n%s", name, desc),
        iconText = "★",
        accentColor = color,
        textColor = color,
        richText = true,
        duration = 5,
        isAchievement = true, -- Special positioning
        reward = data.reward,
    })
end
```

## Success Metrics

1. Players notice and celebrate achievement unlocks
2. No missed achievement notifications
3. Clear understanding of what was achieved and rewards earned
4. Performance impact < 5ms per toast
5. Mobile-friendly display

## Next Steps

1. Review and approve plan
2. Implement Phase 1 (EventBus listener + basic achievement toast)
3. Test with a few achievements
4. Gather feedback
5. Implement Phase 2-3 based on feedback
