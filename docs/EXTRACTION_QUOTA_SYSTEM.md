# Extraction Quota System - Implementation Guide

## Overview
Replace "mine 100% of cube" with an **Extraction Quota** system that normalizes completion times across all player levels while maintaining progression rewards.

## Core Formula
```
Time to complete = ExtractionQuota / (DigSize × Power / DigDelay)
```

Where:
- **ExtractionQuota**: Points needed to complete the cube (tier-based)
- **DigSize**: Cells per dig (27, 125, 343)
- **Power**: Damage per cell (new stat from pickaxe/upgrades)
- **DigDelay**: Seconds between digs
- **Cell HP**: Health points per cell (depth-based)

## System Components

### 1. Cube Tiers
Players progress through tiers that maintain consistent completion times:

| Tier | Quota | Target Time | Player Stage |
|------|-------|-------------|--------------|
| T1 | 35,000 | 15-20 min | New players |
| T2 | 120,000 | 8-12 min | Mid players |
| T3 | 300,000 | 3-6 min | Max players |
| T4 | 600,000 | 3-5 min | Endgame |

### 2. Cell HP by Depth
Cells have HP based on their Y position in the cube:

```lua
-- Depth quartiles (0-25%, 25-50%, 50-75%, 75-100%)
T1_HP = {1, 2, 2, 3}  -- Easy start
T2_HP = {1, 2, 3, 4}  -- Moderate
T3_HP = {2, 3, 5, 7}  -- Challenging
T4_HP = {3, 5, 7, 10} -- Hardcore
```

### 3. Damage & Destruction
- Each dig applies **Power** damage to cells
- Cells track accumulated damage (sparse storage)
- When damage ≥ HP, cell breaks → 1 roll → extraction points

### 4. Power Stat (New)
Base power starts at 1.0 and scales with:
- Pickaxe tier (1.0 → 1.5 → 2.0 → 3.0)
- Upgrades (similar to current dig speed)
- Pets/boosts (multiplicative)

## Implementation Steps

### Step 1: Update GameConfig
```lua
GameConfig.CubeTiers = {
    T1 = {
        id = "starter",
        name = "Starter Mines",
        quota = 35000,
        hpByDepth = {1, 2, 2, 3},
        lootMultiplier = 1.0,
        unlockCost = 0,
        recommendedPower = 1,
    },
    T2 = {
        id = "bronze",
        name = "Bronze Depths",
        quota = 120000,
        hpByDepth = {1, 2, 3, 4},
        lootMultiplier = 1.5,
        unlockCost = 10000,
        recommendedPower = 50,
    },
    T3 = {
        id = "silver",
        name = "Silver Caverns",
        quota = 300000,
        hpByDepth = {2, 3, 5, 7},
        lootMultiplier = 2.0,
        unlockCost = 100000,
        recommendedPower = 200,
    },
    T4 = {
        id = "gold",
        name = "Golden Core",
        quota = 600000,
        hpByDepth = {3, 5, 7, 10},
        lootMultiplier = 3.0,
        unlockCost = 1000000,
        recommendedPower = 500,
    },
}

-- Add Power upgrade levels
GameConfig.Upgrades.POWER_LEVELS = {
    {level = 0, cost = 0, multiplier = 1.0},
    {level = 1, cost = 100, multiplier = 1.1},
    {level = 2, cost = 500, multiplier = 1.25},
    {level = 3, cost = 1500, multiplier = 1.4},
    {level = 4, cost = 5000, multiplier = 1.6},
    {level = 5, cost = 15000, multiplier = 1.8},
    {level = 6, cost = 50000, multiplier = 2.0},
    -- ... continue progression
}
```

### Step 2: Modify GridService
```lua
-- Add to chunk state
type Chunk = {
    occupancy: buffer,
    damage: {[number]: number}, -- Sparse damage tracking
    material: string,
}

-- Calculate HP for a cell
function GridService:GetCellHP(cellY: number, tier: string): number
    local tierData = GameConfig.CubeTiers[tier]
    local cubeHeight = GameConfig.Grid.CUBE_SIZE_STUDS / GameConfig.Grid.CELL_SIZE_STUDS
    local depthPercent = (cellY + cubeHeight/2) / cubeHeight
    local quartile = math.min(4, math.floor(depthPercent * 4) + 1)
    return tierData.hpByDepth[quartile]
end

-- Apply damage and return destroyed cells
function GridService:ApplyDamage(
    player: Player,
    origin: CFrame,
    state: CubeState,
    cellX: number,
    cellY: number,
    cellZ: number,
    size: number,
    power: number
): {CellInfo}
    local destroyedCells = {}
    local tier = state.tier or "T1"
    
    -- For each cell in dig area
    for dx = -size, size do
        for dy = -size, size do
            for dz = -size, size do
                local x, y, z = cellX + dx, cellY + dy, cellZ + dz
                
                if self:IsCellFilled(state, x, y, z) then
                    local cellKey = GridMath.cellKey(x, y, z)
                    local chunk = self:GetChunk(state, x, y, z)
                    
                    -- Apply damage
                    chunk.damage[cellKey] = (chunk.damage[cellKey] or 0) + power
                    
                    -- Check if destroyed
                    local hp = self:GetCellHP(y, tier)
                    if chunk.damage[cellKey] >= hp then
                        -- Mark as empty
                        self:SetCell(state, x, y, z, false)
                        chunk.damage[cellKey] = nil -- Clear damage
                        
                        -- Add to destroyed list for rolls
                        table.insert(destroyedCells, {
                            x = x, y = y, z = z,
                            hp = hp,
                            depth = y,
                        })
                    end
                end
            end
        end
    end
    
    return destroyedCells
end
```

### Step 3: Create CubeProgress Module
```lua
-- server/MiningGame/CubeProgress.lua
local CubeProgress = {}

function CubeProgress:AddExtraction(player: Player, points: number)
    local state = DataService:GetCubeData(player)
    local profile = DataService:GetPlayerData(player)
    
    state.extraction = (state.extraction or 0) + points
    local tier = state.tier or "T1"
    local tierData = GameConfig.CubeTiers[tier]
    
    -- Check completion
    if state.extraction >= tierData.quota then
        self:CompleteCube(player)
    end
    
    -- Update UI
    Remotes.RE.OnExtractionUpdate:FireClient(player, {
        current = state.extraction,
        quota = tierData.quota,
        percent = state.extraction / tierData.quota,
    })
end

function CubeProgress:CompleteCube(player: Player)
    local state = DataService:GetCubeData(player)
    local profile = DataService:GetPlayerData(player)
    local tier = state.tier or "T1"
    
    -- Grant completion rewards
    local rewards = self:CalculateCompletionRewards(tier, profile.completions)
    InventoryService:GrantRewards(player, rewards)
    
    -- Increment completions
    profile.completions = (profile.completions or 0) + 1
    
    -- Reset cube
    state.extraction = 0
    GridService:ResetCube(player)
    
    -- Show completion screen
    Remotes.RE.OnCubeComplete:FireClient(player, {
        tier = tier,
        rewards = rewards,
        completions = profile.completions,
        nextTier = self:GetRecommendedTier(player),
    })
end

function CubeProgress:GetRecommendedTier(player: Player): string
    local profile = DataService:GetPlayerData(player)
    local effectiveStats = UpgradeService:ComputeEffectiveStats(profile)
    
    -- Calculate player's extraction rate
    local digSize = (effectiveStats.size * 2 + 1)^3
    local power = effectiveStats.power or 1.0
    local delay = effectiveStats.delay
    local extractionRate = (digSize * power) / delay
    
    -- Recommend tier based on rate
    if extractionRate < 100 then
        return "T1"
    elseif extractionRate < 400 then
        return "T2"
    elseif extractionRate < 1000 then
        return "T3"
    else
        return "T4"
    end
end

return CubeProgress
```

### Step 4: Update DigService
```lua
-- In ProcessDigRequest, replace ApplyDig with ApplyDamage
local destroyedCells = GridService:ApplyDamage(
    player,
    cubeData.origin,
    cubeState,
    cellX,
    cellY,
    cellZ,
    effectiveStats.size,
    effectiveStats.power -- New stat
)

if #destroyedCells == 0 then
    return {
        ok = false,
        reason = "No cells destroyed",
    }
end

-- Roll for loot (only destroyed cells)
local lootDrops = LootService:RollCells(
    profile.materialId,
    destroyedCells,
    profile.cubeSeed,
    effectiveStats.luck
)

-- Add extraction points
local extractionGained = 0
for _, cell in ipairs(destroyedCells) do
    extractionGained = extractionGained + cell.hp
end
CubeProgress:AddExtraction(player, extractionGained)
```

### Step 5: Update UI
Replace "% Mined" with extraction bar:

```lua
-- client/UI/ExtractionBar.lua
local function updateExtractionBar(data)
    local percent = data.current / data.quota
    progressBar.Size = UDim2.new(percent, 0, 1, 0)
    
    -- Format display
    local display = string.format(
        "EXTRACTION: %d / %d (%.1f%%)",
        data.current,
        data.quota,
        percent * 100
    )
    progressLabel.Text = display
    
    -- Pulse when near completion
    if percent > 0.9 then
        -- Add pulsing animation
    end
end
```

## Benefits

1. **Consistent completion times** - No more 1-minute speedruns or 40-minute slogs
2. **Clear progression** - Players see their extraction rate improve
3. **Strategic depth** - Target high-HP cells for more extraction
4. **Better pacing** - Natural tier progression keeps game fresh
5. **Economy stability** - Predictable completion times = predictable rewards

## Migration Path

1. Add extraction/quota to existing cubes (set extraction = cells_mined * 2)
2. Default all existing players to T1
3. Calculate recommended tier based on their upgrades
4. Show one-time tutorial explaining the new system

## Future Extensions

- **Bonus extraction** events (2x extraction weekends)
- **Special cells** with bonus extraction points
- **Extraction multiplier** upgrades/boosts
- **Prestige system** - Complete T4 X times to unlock T5
- **Extraction leaderboards** - Fastest to quota