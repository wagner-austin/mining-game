# Mining Game - Final Implementation Plan

**Last Updated:** September 3, 2025

## Core Philosophy
- Build it right the first time
- No temporary/fake systems
- Every feature complete before moving on
- Ready to publish when done

## Current Project Status

### ✅ Completed Systems
- **Infrastructure**: Data persistence, remotes (42 RF, 26 RE), session tracking
- **UI Framework**: Component-based panels, tabs, theme system
- **Sound System**: Manager with zones and theme packs
- **Cloth Simulation**: Bone deformation with manual server-client replication
- **Material System**: 50+ materials with rarity tiers
- **Basic Mining**: Click to remove voxels (needs HP system)
- **Grid/Cube System**: 128-stud cubes with proper CFrame origins

### ⚠️ In Progress
- **Cloth System**: Working but simplified (no drag interaction)

### ❌ Not Implemented (Critical Gap)
- **HP/Damage System**: Core mechanic missing entirely
- **Extraction Quotas**: No progression goals
- **Drop Tables**: Framework exists, no implementation  
- **Visual Feedback**: No damage numbers or effects
- **AFK System**: Session tracking exists, no rewards
- **Game HUD**: Only basic panels exist

## System 1: Extraction Quota & HP System (Complete Solution)

### 1.1 Data Structure Updates

#### Types.lua - Add ALL new fields
```lua
-- Add to PlayerStats
completions: number        -- Cubes completed
power: number             -- In upgrades table

-- Add to CubeState  
tier: string              -- "T1", "T2", "T3", "T4"
extraction: number        -- Current extraction points

-- Add to Chunk
damage: {[number]: number}  -- Sparse damage tracking

-- Add to EffectiveStats
power: number             -- Damage per cell

-- New type for damage feedback
DamageSample = {
    pos: Vector3,
    dmg: number,
    hpLeft: number,
    hpMax: number,
    broke: boolean,
    mat: Enum.Material
}
```

#### GameConfig.lua - Complete tier system
```lua
CubeTiers = {
    T1 = {
        id = "starter",
        name = "Starter Mines",
        quota = 35000,
        hpByDepth = {1, 2, 2, 3},
        lootMultiplier = 1.0,
        unlockCost = 0,
    },
    T2 = {
        id = "bronze", 
        name = "Bronze Depths",
        quota = 120000,
        hpByDepth = {1, 2, 3, 4},
        lootMultiplier = 1.5,
        unlockCost = 10000,
    },
    T3 = {
        id = "silver",
        name = "Silver Caverns", 
        quota = 300000,
        hpByDepth = {2, 3, 5, 7},
        lootMultiplier = 2.0,
        unlockCost = 100000,
    },
    T4 = {
        id = "gold",
        name = "Golden Core",
        quota = 600000,
        hpByDepth = {3, 5, 7, 10},
        lootMultiplier = 3.0,
        unlockCost = 1000000,
    }
}

-- Power upgrade levels
POWER_LEVELS = {
    {level = 0, cost = 0, multiplier = 1.0},
    {level = 1, cost = 100, multiplier = 1.2},
    {level = 2, cost = 500, multiplier = 1.5},
    {level = 3, cost = 2000, multiplier = 1.8},
    {level = 4, cost = 10000, multiplier = 2.2},
    {level = 5, cost = 50000, multiplier = 2.7},
    {level = 6, cost = 200000, multiplier = 3.3},
    {level = 7, cost = 1000000, multiplier = 4.0},
}
```

### 1.2 Server Implementation

#### GridService.lua - Replace ApplyDig with ApplyDamage
```lua
-- Complete damage tracking system
function GridService:ApplyDamage(
    player: Player,
    origin: CFrame,
    state: CubeState,
    cellX: number,
    cellY: number, 
    cellZ: number,
    size: number,
    power: number
): ({CellInfo}, {DamageSample})
    
    local destroyedCells = {}
    local damageSamples = {}
    local tier = state.tier or "T1"
    local tierData = GameConfig.CubeTiers[tier]
    
    -- Process each cell in dig area
    for dx = -size, size do
        for dy = -size, size do
            for dz = -size, size do
                local x, y, z = cellX + dx, cellY + dy, cellZ + dz
                
                if self:IsCellFilled(state, x, y, z) then
                    -- Get chunk and cell key
                    local chunk = self:GetOrCreateChunk(state, x, y, z)
                    local cellKey = self:GetCellKey(x, y, z)
                    
                    -- Initialize damage if needed
                    if not chunk.damage then
                        chunk.damage = {}
                    end
                    
                    -- Apply damage
                    chunk.damage[cellKey] = (chunk.damage[cellKey] or 0) + power
                    
                    -- Calculate HP based on depth
                    local hp = self:GetCellHP(y, tierData)
                    
                    -- Create damage sample
                    local worldPos = self:CellToWorld(x, y, z, origin)
                    local broke = chunk.damage[cellKey] >= hp
                    
                    table.insert(damageSamples, {
                        pos = worldPos,
                        dmg = math.min(power, hp - (chunk.damage[cellKey] - power)),
                        hpLeft = math.max(0, hp - chunk.damage[cellKey]),
                        hpMax = hp,
                        broke = broke,
                        mat = Enum.Material.Rock
                    })
                    
                    -- If cell destroyed
                    if broke then
                        self:SetCell(state, x, y, z, false)
                        chunk.damage[cellKey] = nil
                        
                        table.insert(destroyedCells, {
                            x = x, y = y, z = z,
                            hp = hp,
                            depth = y
                        })
                    end
                end
            end
        end
    end
    
    -- Apply terrain changes for destroyed cells
    if #destroyedCells > 0 then
        self:WriteVoxels(origin, destroyedCells)
    end
    
    return destroyedCells, damageSamples
end

function GridService:GetCellHP(cellY: number, tierData: table): number
    local cubeHeight = GameConfig.Grid.CUBE_SIZE_STUDS / GameConfig.Grid.CELL_SIZE_STUDS
    local depthPercent = (cellY + cubeHeight/2) / cubeHeight
    local quartile = math.clamp(math.floor(depthPercent * 4) + 1, 1, 4)
    return tierData.hpByDepth[quartile]
end
```

#### CubeProgress.lua - New module for extraction tracking
```lua
local CubeProgress = {}

function CubeProgress:AddExtraction(player: Player, points: number)
    local state = DataService:GetCubeData(player)
    local profile = DataService:GetPlayerData(player)
    
    state.extraction = (state.extraction or 0) + points
    local tierData = GameConfig.CubeTiers[state.tier or "T1"]
    
    -- Check for completion
    if state.extraction >= tierData.quota then
        self:CompleteCube(player)
    end
    
    -- Update client UI
    Remotes.RE.OnExtractionUpdate:FireClient(player, {
        current = state.extraction,
        quota = tierData.quota,
        percent = state.extraction / tierData.quota
    })
end

function CubeProgress:CompleteCube(player: Player)
    local state = DataService:GetCubeData(player)
    local profile = DataService:GetPlayerData(player)
    
    -- Increment completions
    profile.completions = (profile.completions or 0) + 1
    
    -- Calculate rewards
    local tierData = GameConfig.CubeTiers[state.tier or "T1"]
    local baseReward = 1000 * tierData.lootMultiplier
    local completionBonus = profile.completions * 100
    
    profile.coins = profile.coins + baseReward + completionBonus
    
    -- Reset cube
    state.extraction = 0
    state.chunks = {}
    GridService:GenerateFreshCube(player, state)
    
    -- Notify client
    Remotes.RE.OnCubeComplete:FireClient(player, {
        tier = state.tier,
        rewards = {
            coins = baseReward + completionBonus,
            completions = profile.completions
        },
        nextTier = self:GetRecommendedTier(player)
    })
    
    DataService:QueueSave(player)
end

function CubeProgress:GetRecommendedTier(player: Player): string
    local profile = DataService:GetPlayerData(player)
    local stats = UpgradeService:ComputeEffectiveStats(profile)
    
    -- Calculate throughput
    local digSize = (stats.size * 2 + 1)^3
    local throughput = (digSize * stats.power) / stats.delay
    
    if throughput < 100 then return "T1"
    elseif throughput < 400 then return "T2"  
    elseif throughput < 1000 then return "T3"
    else return "T4" end
end

return CubeProgress
```

### 1.3 Client Implementation

#### DamageDisplay.lua - Complete visual feedback system
```lua
local DamageDisplay = {}
local Debris = game:GetService("Debris")

-- Pool of damage number instances
local numberPool = {}
local MAX_NUMBERS = 20

function DamageDisplay:Init()
    -- Pre-create damage number instances
    for i = 1, MAX_NUMBERS do
        local billboard = self:CreateNumberBillboard()
        billboard.Parent = nil
        table.insert(numberPool, {
            billboard = billboard,
            busy = false
        })
    end
end

function DamageDisplay:ShowDamage(worldPos: Vector3, damage: number, broke: boolean)
    local poolItem = self:GetFromPool()
    if not poolItem then return end
    
    -- Configure billboard
    local billboard = poolItem.billboard
    billboard.Adornee.Position = worldPos
    billboard.TextLabel.Text = broke and "BREAK!" or "-"..damage
    billboard.TextLabel.TextColor3 = broke and Color3.new(0,1,0) or Color3.new(1,1,0)
    billboard.Parent = workspace
    
    -- Animate
    self:AnimateNumber(billboard, poolItem)
end

function DamageDisplay:CreateNumberBillboard()
    local part = Instance.new("Part")
    part.Anchored = true
    part.CanCollide = false
    part.Transparency = 1
    part.Size = Vector3.new(0.1, 0.1, 0.1)
    
    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.new(0, 100, 0, 50)
    billboard.StudsOffset = Vector3.new(0, 2, 0)
    billboard.AlwaysOnTop = true
    billboard.Adornee = part
    
    local text = Instance.new("TextLabel")
    text.BackgroundTransparency = 1
    text.Size = UDim2.new(1, 0, 1, 0)
    text.Font = Enum.Font.SourceSansBold
    text.TextScaled = true
    text.Parent = billboard
    
    billboard.Parent = part
    return billboard
end

return DamageDisplay
```

#### CellSelection.lua - Shows targeted cell with HP indicator
```lua
local CellSelection = {}

local selection = Instance.new("SelectionBox")
local adornee = Instance.new("Part")
adornee.Anchored = true
adornee.CanCollide = false
adornee.Transparency = 1
adornee.Size = Vector3.new(4, 4, 4)
selection.Adornee = adornee
selection.LineThickness = 0.05

function CellSelection:Show(position: Vector3, hpPercent: number)
    adornee.Position = position
    adornee.Parent = workspace
    selection.Parent = workspace
    
    -- Color based on HP
    local r = 1 - hpPercent
    local g = hpPercent
    selection.Color3 = Color3.new(r, g, 0)
end

function CellSelection:Hide()
    selection.Parent = nil
    adornee.Parent = nil
end

return CellSelection
```

#### CrackOverlay.lua - Shows damage on cells
```lua
local CrackOverlay = {}

local crackPool = {}
local MAX_CRACKS = 60

local crackTextures = {
    "rbxassetid://CRACK1",  -- 75% HP
    "rbxassetid://CRACK2",  -- 50% HP  
    "rbxassetid://CRACK3",  -- 25% HP
}

function CrackOverlay:Init()
    for i = 1, MAX_CRACKS do
        local crack = self:CreateCrackPart()
        crack.Parent = nil
        table.insert(crackPool, {
            part = crack,
            busy = false,
            fadeTask = nil
        })
    end
end

function CrackOverlay:ShowCrack(position: Vector3, hpPercent: number)
    local poolItem = self:GetFromPool()
    if not poolItem then return end
    
    local stage = self:GetCrackStage(hpPercent)
    if stage == 0 then return end
    
    poolItem.part.Position = position
    poolItem.part.SurfaceGui.ImageLabel.Image = crackTextures[stage]
    poolItem.part.Parent = workspace
    
    -- Fade out after 2 seconds
    poolItem.fadeTask = task.delay(2, function()
        self:ReturnToPool(poolItem)
    end)
end

return CrackOverlay
```

### 1.4 UI Updates

#### ExtractionBar.lua - Replaces % mined display
```lua
local ExtractionBar = {}

function ExtractionBar:Create(parent)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0.3, 0, 0, 50)
    frame.Position = UDim2.new(0.35, 0, 0, 100)
    frame.BackgroundColor3 = Color3.new(0.1, 0.1, 0.1)
    
    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(0, 0, 1, 0)
    bar.BackgroundColor3 = Color3.new(0.3, 0.8, 0.3)
    bar.Parent = frame
    
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = "EXTRACTION: 0 / 0"
    label.TextScaled = true
    label.Parent = frame
    
    frame.Parent = parent
    self.bar = bar
    self.label = label
    
    return self
end

function ExtractionBar:Update(current: number, quota: number)
    local percent = current / quota
    self.bar.Size = UDim2.new(percent, 0, 1, 0)
    self.label.Text = string.format("EXTRACTION: %d / %d (%.1f%%)", 
        current, quota, percent * 100)
end

return ExtractionBar
```

## System 2: Complete Drop Table

### DropTableService.lua
```lua
local DropTable = {
    -- 40% nothing
    {id = "nothing", weight = 4000},
    
    -- 35% common
    {id = "stone", weight = 1500, value = 1},
    {id = "coal", weight = 1000, value = 5},
    {id = "copper", weight = 700, value = 10},
    {id = "iron", weight = 300, value = 15},
    
    -- 20% uncommon
    {id = "silver", weight = 1000, value = 30},
    {id = "gold", weight = 600, value = 50},
    {id = "quartz", weight = 400, value = 75},
    
    -- 4% rare
    {id = "emerald", weight = 200, value = 150},
    {id = "ruby", weight = 100, value = 200},
    {id = "sapphire", weight = 75, value = 300},
    {id = "amethyst", weight = 25, value = 500},
    
    -- 0.9% epic
    {id = "diamond", weight = 50, value = 1000},
    {id = "obsidian", weight = 25, value = 1500},
    {id = "mithril", weight = 10, value = 2500},
    {id = "adamantite", weight = 5, value = 5000},
    
    -- 0.09% legendary
    {id = "ancient_ore", weight = 5, value = 10000},
    {id = "void_stone", weight = 2, value = 25000},
    {id = "star_fragment", weight = 1.5, value = 50000},
    {id = "dragon_scale", weight = 0.5, value = 100000},
    
    -- 0.01% mythic
    {id = "cosmic_essence", weight = 0.5, value = 250000},
    {id = "god_ore", weight = 0.3, value = 500000},
    {id = "universe_fragment", weight = 0.2, value = 1000000},
}

function DropTableService:Roll(luck: number): string
    -- Implementation with luck modifier
end
```

## System 3: AFK System

### AFKService.lua
```lua
local AFKService = {}

function AFKService:CalculateRolls(secondsAway: number, upgrades: table)
    local baseRate = 1  -- 1 roll per minute
    local rate = baseRate * (upgrades.afkMultiplier or 1)
    
    local minutes = math.floor(secondsAway / 60)
    local maxMinutes = 240  -- 4 hour cap
    
    -- Diminishing returns after 1 hour
    local rolls = 0
    if minutes <= 60 then
        rolls = minutes * rate
    else
        rolls = 60 * rate
        local remaining = math.min(minutes - 60, maxMinutes - 60)
        rolls = rolls + (remaining * rate * 0.75)
    end
    
    return math.floor(rolls)
end

function AFKService:ProcessAFKRolls(player: Player, rolls: number)
    local results = {}
    
    for i = 1, rolls do
        local item = DropTableService:Roll(0.5)  -- Half luck for AFK
        if item ~= "nothing" then
            results[item] = (results[item] or 0) + 1
        end
    end
    
    return results
end

return AFKService
```

## Complete File Changes Summary

### New Files (13 total)
```
server/
├── CubeProgress.lua
├── DropTableService.lua
└── AFKService.lua

client/
├── DamageDisplay.lua
├── CellSelection.lua
├── CrackOverlay.lua
├── ExtractionBar.lua
├── LoadingModule.lua
├── MainHUD.lua
├── SoundManager.lua
├── LootVisuals.lua
├── WelcomeBack.lua
└── TierSelector.lua
```

### Modified Files (8 total)
```
shared/
├── Types.lua (add power, damage, samples)
└── GameConfig.lua (add tiers, power levels)

server/
├── GridService.lua (ApplyDig → ApplyDamage)
├── DigService.lua (use ApplyDamage, send samples)
├── UpgradeService.lua (add power calculation)
├── DataService.lua (add tier, extraction, completions)
├── LootService.lua (use DropTableService)
└── Remotes.lua (add new events)
```

## Testing Order

1. **HP & Damage System**
   - Verify damage accumulates correctly
   - Check HP calculation by depth
   - Confirm cells break at correct damage
   - Test damage samples sent to client

2. **Visual Feedback**
   - Damage numbers appear and animate
   - Selection box follows cursor
   - Crack overlays show damage state
   - Break effects trigger

3. **Extraction System**
   - Progress accumulates correctly
   - Bar updates smoothly
   - Completion triggers at quota
   - Rewards granted properly
   - Cube resets after completion

4. **Tier Progression**
   - T1 completion time ~15-20 min
   - T4 completion time ~3-5 min
   - Recommendations accurate
   - Tier switching works

5. **Drop Table**
   - Roll distribution matches expected
   - Nothing rolls work (40%)
   - Luck affects rates correctly
   - Values assigned properly

6. **AFK System**
   - Rolls calculate correctly
   - Diminishing returns apply
   - Cap at 4 hours works
   - Welcome back shows loot

## No Temporary Code Policy
✅ Every system built complete from start
✅ No fake data or placeholder values
✅ All features fully functional when implemented
✅ Ready to publish when complete
✅ No rework or code removal needed

## Implementation Timeline & Reality Check

### Estimated Time to Complete (from current state)
- **Phase 1 - HP/Damage System**: 2-3 days (complex core rewrite)
- **Phase 2 - Visual Feedback**: 2 days (particles, numbers, effects)
- **Phase 3 - Full UI**: 3 days (HUD, menus, inventory)
- **Phase 4 - Drop Tables**: 1 day (implementation + testing)
- **Phase 5 - AFK System**: 1 day (reward calculation)
- **Total**: ~9-10 days of focused development

### Critical Path to Playable Game
**Must Have** (Core Loop):
1. HP/Damage system - Without this, no progression exists
2. Extraction quotas - Gives purpose to mining
3. Basic drop table - Rewards for playing
4. Visual feedback - Players need to see impact

**Should Have** (Polish):
1. Tier system - Progression depth
2. AFK rewards - Retention mechanic
3. Full UI - Current UI is minimal

### Simplified MVP Alternative
If timeline is a concern, consider:
1. Fixed HP for all cells (5 HP)
2. Simple extraction (1000 blocks = complete)
3. Basic drops (10% chance of coins)
4. Just damage numbers (no complex effects)
5. Ship and iterate

This could be done in 2-3 days vs 9-10 days for full plan.