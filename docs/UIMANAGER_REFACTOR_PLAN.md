# UIManager Refactoring Plan

## Current State
- **File**: `client/MiningGame/UI/UIManager.lua`
- **Size**: 1,189 lines (too large)
- **Methods**: 29 total
- **External Callers**: Only 2 files
  - `ClientUI.client.lua` - calls showServerAnnouncement, showNotification
  - `SoundReplication.client.lua` - calls showNotificationWithRarity

## Problem Areas
1. **File too large** - 1,189 lines makes it hard to maintain
2. **Mixed responsibilities** - Toast system, scene management, UI creation, recovery system all in one file
3. **Toast system alone is ~400 lines** - Could be its own module

## Refactoring Goals
1. **Keep everything working** - No breaking changes
2. **Maintain backward compatibility** - External callers unchanged
3. **Make it testable** - Can roll back at each step
4. **Improve maintainability** - Smaller, focused modules

## Phase 1: Debug Cleanup ✅ COMPLETED
- [x] Remove debug print statements
- [x] Save debug code as comments for future use
- [x] Test that toasts still work

## Phase 2: Extract ToastManager (SAFE Delegation Pattern)

### Step 2.1: Create ToastManager Module
Create `client/MiningGame/UI/ToastManager.lua` with:

```lua
-- ToastManager handles all toast notification logic
-- Called by UIManager (maintains backward compatibility)
local ToastManager = {}
ToastManager.__index = ToastManager

function ToastManager.new(screenGui, container, theme)
    local self = setmetatable({}, ToastManager)
    -- Initialize toast-specific properties
    return self
end
```

### Step 2.2: Move Internal Toast Methods
Move these INTERNAL methods to ToastManager:
- `_spawnToastBase` (the big one - 220 lines)
- `_queueOrSpawn` 
- `_pumpToastQueue`
- `_durationFor`
- `getRarityColor`
- Helper function `color3ToHex`

### Step 2.3: UIManager Delegates to ToastManager
UIManager keeps ALL public methods but delegates:

```lua
-- UIManager.lua (keeps these for compatibility)
function UIManager:showNotification(message, type)
    self.toastManager:showNotification(message, type)
end

function UIManager:showServerAnnouncement(message, color)
    self.toastManager:showServerAnnouncement(message, color)
end
-- etc...
```

### Step 2.4: Testing Points
After each step, test:
1. Regular notifications work
2. Server announcements display
3. Rarity notifications show correctly
4. Queue system works (spam multiple notifications)

## Phase 3: Extract UIFactory Module

### Step 3.1: Create UIFactory Module
Create `shared/MiningGame/UI/UIFactory.lua` with:
- `createButton`
- `createPanel`
- `animateIn`
- `animateOut`
- `pulse`
- `formatNumber` (or move to UIUtils)

### Step 3.2: UIManager Uses UIFactory
```lua
-- UIManager.lua
local UIFactory = require(UIFolder:WaitForChild("UIFactory"))

function UIManager:createButton(...)
    return UIFactory.createButton(...)
end
```

## Phase 4: Clean Up UIManager Core

After extraction, UIManager will focus on:
- **Scene Management** (showScene, hideScene, registerScene)
- **Initialization** (init, screen GUI setup)
- **Recovery System** (_anyUIVisible, _showMainHUDNow)
- **Theme Management** (refreshTheme, refreshLayout)

Final structure:
```
UIManager (600 lines)
├── Delegates toast methods to → ToastManager (400 lines)
├── Delegates UI creation to → UIFactory (150 lines)
└── Focuses on scene management & recovery
```

## Rollback Plan

At ANY point if something breaks:
1. **Phase 2 Rollback**: Delete ToastManager.lua, revert UIManager changes (git)
2. **Phase 3 Rollback**: Delete UIFactory.lua, revert UIManager changes
3. **Emergency**: Full git revert to working commit

## Testing Checklist

### After Phase 2 (ToastManager):
- [ ] Regular info/success/error toasts appear
- [ ] Server announcements show with correct colors
- [ ] Rarity notifications display with colored rarity word
- [ ] Multiple notifications queue properly
- [ ] Toast animations work (fade in/out)
- [ ] Toast dismissal on click works
- [ ] No console errors

### After Phase 3 (UIFactory):
- [ ] Settings panel opens
- [ ] Buttons work and have hover effects
- [ ] Panels render correctly
- [ ] Animations play smoothly

## Implementation Order

1. **Test current state** - Ensure everything works before starting
2. **Implement Phase 2.1-2.2** - Create ToastManager with internal methods
3. **Test**
4. **Implement Phase 2.3** - Add delegation
5. **Test thoroughly**
6. **Implement Phase 3** - Extract UIFactory (lower risk)
7. **Test**
8. **Clean up and optimize**

## Risk Assessment

- **Phase 2**: Medium risk - Core functionality, but safe with delegation pattern
- **Phase 3**: Low risk - Just UI helper methods
- **Phase 4**: Low risk - Just organizing remaining code

## Success Metrics

1. **No breaking changes** - External callers work unchanged
2. **File sizes**: UIManager <700 lines, ToastManager ~400 lines
3. **All tests pass** - Full functionality maintained
4. **Code is more maintainable** - Clear separation of concerns