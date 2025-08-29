# Spawn Distribution & Map Decoration Implementation Plan

## Overview
This document outlines a pragmatic, immediately-implementable solution for improving player spawn distribution and adding a modular decoration system to the mining game.

## Current Issues
1. **Spawn Clustering**: Players spawn in a tight 3x3 grid (150 stud spacing) making it hard to see/mine
2. **No Decorations**: Map lacks visual interest (no trees, rocks, water features)
3. **Poor Multiplayer Experience**: With 9+ players, cubes overlap visually
4. **Not Extensible**: Hard to add new map features or layouts

## Implementation Plan

### Phase 1: Fix Spawn Crowding (Immediate Priority)

#### 1.1 Dynamic Spacing System
**File: `shared/MiningGame/GameConfig.lua`**
```lua
-- Update Multiplayer config
GameConfig.Multiplayer = {
    LAYOUT = "grid",           -- "grid" or "ring"
    CUBE_SPACING = 150,        -- base spacing, used as minimum
    MIN_GAP_STUDS = 64,        -- guaranteed edge-to-edge gap between cubes
    -- ...existing fields...
}
```

#### 1.2 Improved Position Calculation
**File: `server/MiningGame/CubePositionService.lua`**
```lua
-- Replace GetOrigin function with adaptive spacing
local function effectiveSpacing(): number
    local minSpacing = GameConfig.Grid.CUBE_SIZE_STUDS + (GameConfig.Multiplayer.MIN_GAP_STUDS or 64)
    return math.max(GameConfig.Multiplayer.CUBE_SPACING, minSpacing)
end

local function gridDims(n: number): (number, number)
    local cols = math.ceil(math.sqrt(n))
    local rows = math.ceil(n / cols)
    return cols, rows
end

local function playersSorted()
    local list = Players:GetPlayers()
    table.sort(list, function(a, b) return a.UserId < b.UserId end)
    return list
end

function CubePositionService:GetOrigin(player: Player): CFrame
    if playerOrigins[player] then return playerOrigins[player] end

    local list = playersSorted()
    local idx = table.find(list, player)
    if not idx then idx = 1 end
    idx -= 1 -- zero-based

    local layout = GameConfig.Multiplayer.LAYOUT
    local y = GameConfig.Grid.CUBE_SIZE_STUDS / 2

    if layout == "ring" then
        -- Simple ring that grows with population
        local total = #list
        local r = math.max(0, 200 + (total * 12)) -- radius grows gently
        local angle = (idx / math.max(1, total)) * math.pi * 2
        local x = math.cos(angle) * r
        local z = math.sin(angle) * r
        local pos = Vector3.new(x, y, z)
        -- Face the plaza/center
        return CFrame.lookAt(pos, Vector3.new(0, y, 0))
    else
        -- Adaptive centered grid (default)
        local cols, rows = gridDims(#list)
        local col = idx % cols
        local row = math.floor(idx / cols)

        local s = effectiveSpacing()
        local cx = (col - (cols - 1) / 2) * s
        local cz = (row - (rows - 1) / 2) * s

        -- Tiny jitter to avoid perfect alignment
        local j = 6
        cx += math.random(-j, j)
        cz += math.random(-j, j)

        local pos = Vector3.new(cx, y, cz)
        return CFrame.lookAt(pos, Vector3.new(0, y, 0))
    end
end
```

#### 1.3 Adjust Spawn Distance
**File: `server/MiningGame/SpawnService.lua`**
```lua
local FRONT_PADDING = 36 -- Increased from 20 for better visibility
```

### Phase 2: Minimal Decoration System

#### 2.1 Decoration Configuration
**File: `shared/MiningGame/GameConfig.lua`**
```lua
GameConfig.Decor = {
    Themes = {
        forest = {
            prefabs = {"Tree_Oak", "Tree_Pine", "Rock_Small", "Bush"},
            weights = {30, 20, 30, 20},
            minDistance = 20,             -- Minimum spacing between decorations
            density = 0.0015,             -- Items per stud^2
            minScale = 0.9,
            maxScale = 1.5,
            avoidRadiusFromCube = 70,     -- Keep clear around player plots
        },
        desert = {
            prefabs = {"Cactus_Tall", "Cactus_Round", "Rock_Desert", "DeadTree"},
            weights = {25, 20, 40, 15},
            minDistance = 25,
            density = 0.001,
            minScale = 0.8,
            maxScale = 1.4,
            avoidRadiusFromCube = 60,
        },
        crystal = {
            prefabs = {"Crystal_Cluster", "Crystal_Spike", "GlowingRock"},
            weights = {40, 35, 25},
            minDistance = 30,
            density = 0.0008,
            minScale = 0.5,
            maxScale = 2.0,
            avoidRadiusFromCube = 80,
        }
    }
}
```

#### 2.2 Decoration Service
**File: `server/MiningGame/DecorationService.lua`**
```lua
--!strict
local DecorationService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local GameConfig = require(MiningGame:WaitForChild("GameConfig"))
local CubePositionService = require(script.Parent:WaitForChild("CubePositionService"))

local Prefabs = ReplicatedStorage:WaitForChild("Decorations", 10)
local DecorFolder = Workspace:FindFirstChild("Decorations") or Instance.new("Folder")
DecorFolder.Name = "Decorations"
DecorFolder.Parent = Workspace

-- Weighted random selection
local function chooseWeighted(names: {string}, weights: {number}): string
    local total = 0
    for _, w in ipairs(weights) do total += w end
    local r = math.random() * total
    for i, w in ipairs(weights) do
        r -= w
        if r <= 0 then return names[i] end
    end
    return names[#names]
end

-- Find ground height at position
local function groundYAt(x: number, z: number): number
    local origin = Vector3.new(x, 500, z)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {DecorFolder}
    
    local hit = Workspace:Raycast(origin, Vector3.new(0, -1000, 0), params)
    return hit and hit.Position.Y or 5
end

-- Check if position is far enough from any cube
local function farFromAnyCube(p: Vector3, extra: number): boolean
    local half = GameConfig.Grid.CUBE_SIZE_STUDS / 2
    for _, plr in ipairs(Players:GetPlayers()) do
        local c = CubePositionService:GetOrigin(plr).Position
        local flat = Vector3.new(p.X, c.Y, p.Z)
        if (flat - c).Magnitude < (half + extra) then
            return false
        end
    end
    return true
end

-- Main scatter function
function DecorationService:ScatterRect(rect: {minX: number, maxX: number, minZ: number, maxZ: number}, themeName: string)
    local theme = GameConfig.Decor.Themes[themeName]
    if not theme then
        warn("[DecorationService] Unknown theme:", themeName)
        return
    end

    local area = (rect.maxX - rect.minX) * (rect.maxZ - rect.minZ)
    local target = math.max(0, math.floor(area * theme.density))
    local placed: {Vector3} = {}
    local tries = 0

    while #placed < target and tries < target * 12 do
        tries += 1
        local x = math.random() * (rect.maxX - rect.minX) + rect.minX
        local z = math.random() * (rect.maxZ - rect.minZ) + rect.minZ
        local p = Vector3.new(x, 0, z)

        if farFromAnyCube(p, theme.avoidRadiusFromCube) then
            local ok = true
            for _, q in ipairs(placed) do
                if (p - q).Magnitude < theme.minDistance then
                    ok = false
                    break
                end
            end
            
            if ok then
                table.insert(placed, p)
                local name = chooseWeighted(theme.prefabs, theme.weights)
                local prefab = Prefabs:FindFirstChild(name)
                
                if prefab then
                    local m = prefab:Clone()
                    local y = groundYAt(x, z)
                    m:PivotTo(CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(math.random(0, 359)), 0))
                    
                    -- Apply random scale if model supports it
                    local scale = theme.minScale + math.random() * (theme.maxScale - theme.minScale)
                    if m:IsA("Model") and m.PrimaryPart then
                        for _, part in ipairs(m:GetDescendants()) do
                            if part:IsA("BasePart") then
                                part.Size = part.Size * scale
                            end
                        end
                    end
                    
                    m.Parent = DecorFolder
                end
            end
        end
    end
    
    print(string.format("[DecorationService] Placed %d/%d decorations in %s theme", #placed, target, themeName))
end

-- Clear all decorations
function DecorationService:ClearAll()
    DecorFolder:ClearAllChildren()
end

-- Refresh decorations when players join/leave
function DecorationService:Refresh()
    self:ClearAll()
    self:ScatterRect({
        minX = -1500, maxX = 1500,
        minZ = -1500, maxZ = 1500,
    }, "forest")
end

return DecorationService
```

### Phase 3: Water Features (Using Terrain)

#### 3.1 Water Helpers Module
**File: `server/MiningGame/WaterHelpers.lua`**
```lua
--!strict
local Workspace = game:GetService("Workspace")
local Terrain = Workspace.Terrain

local WaterHelpers = {}

-- Place a pond using Terrain water
function WaterHelpers:PlacePond(center: Vector3, size: Vector3)
    -- Carve a shallow bowl
    local bowlSize = size - Vector3.new(0, 4, 0)
    Terrain:FillBlock(CFrame.new(center - Vector3.new(0, 2, 0)), bowlSize, Enum.Material.Air)
    
    -- Fill with water
    local waterSize = size - Vector3.new(4, 6, 4)
    Terrain:FillBlock(CFrame.new(center), waterSize, Enum.Material.Water)
end

-- Create a river segment
function WaterHelpers:PlaceRiverSegment(startPos: Vector3, endPos: Vector3, width: number, depth: number)
    local midpoint = (startPos + endPos) / 2
    local length = (endPos - startPos).Magnitude
    local direction = CFrame.lookAt(midpoint, endPos)
    
    -- Carve channel
    Terrain:FillBlock(direction, Vector3.new(width, depth + 2, length), Enum.Material.Air)
    
    -- Fill with water
    Terrain:FillBlock(direction, Vector3.new(width - 2, depth, length), Enum.Material.Water)
end

-- Create a waterfall
function WaterHelpers:PlaceWaterfall(topPos: Vector3, height: number, width: number)
    local cf = CFrame.new(topPos - Vector3.new(0, height/2, 0))
    Terrain:FillBlock(cf, Vector3.new(width, height, width/2), Enum.Material.Water)
end

return WaterHelpers
```

### Phase 4: Integration Points

#### 4.1 Initialize Decorations
**In `server/MiningGame/init.server.lua`:**
```lua
-- After loading services
local DecorationService = require(script:WaitForChild("DecorationService"))
local WaterHelpers = require(script:WaitForChild("WaterHelpers"))

-- Initial decoration spawn
task.wait(5) -- Let players load
DecorationService:ScatterRect({
    minX = -1500, maxX = 1500,
    minZ = -1500, maxZ = 1500,
}, "forest")

-- Add some water features
WaterHelpers:PlacePond(Vector3.new(200, 5, -300), Vector3.new(60, 12, 60))
WaterHelpers:PlacePond(Vector3.new(-350, 5, 200), Vector3.new(80, 10, 40))

-- Refresh decorations when player count changes significantly
local lastPlayerCount = 0
Players.PlayerAdded:Connect(function()
    if #Players:GetPlayers() - lastPlayerCount >= 3 then
        lastPlayerCount = #Players:GetPlayers()
        DecorationService:Refresh()
    end
end)
```

## Asset Requirements

### Decoration Models Structure
```
ReplicatedStorage/
  Decorations/
    Tree_Oak (Model)
    Tree_Pine (Model)
    Rock_Small (Model)
    Bush (Model)
    Cactus_Tall (Model)
    Cactus_Round (Model)
    Rock_Desert (Model)
    Crystal_Cluster (Model)
    Crystal_Spike (Model)
    GlowingRock (Model)
```

Each model should:
- Have all parts Anchored = true
- Have a PrimaryPart set for positioning
- Be reasonably optimized (< 50 parts)
- Have CanCollide = true for major parts
- Have CanQuery = false for small details

## Performance Considerations

### Optimization Strategies
1. **Spatial Partitioning**: Decorations only check nearby cubes
2. **Streaming Compatible**: Works with StreamingEnabled
3. **Batched Operations**: Decorations spawn in one pass
4. **LOD Ready**: Can add distance-based quality later
5. **Mobile Friendly**: Density/count can be reduced via config

### Performance Settings
```lua
GameConfig.Performance.DECORATION_SETTINGS = {
    PC = {
        maxDecorations = 500,
        renderDistance = 500,
        density_multiplier = 1.0,
    },
    MOBILE = {
        maxDecorations = 100,
        renderDistance = 200,
        density_multiplier = 0.3,
    }
}
```

## Migration Path

### From Current System
1. **No Breaking Changes**: Existing spawn system continues working
2. **Gradual Rollout**: Can test with `LAYOUT = "ring"` per server
3. **Backwards Compatible**: Manual overrides still respected

### To Future Features
1. **Biome System**: Decoration themes become biome definitions
2. **Map System**: Hardcoded rect becomes per-map zones
3. **Procedural Generation**: Scatter algorithm upgrades to noise-based
4. **Dynamic Loading**: Static decorations become streaming-aware

## Benefits

### Immediate Improvements
- **50% more space** between cubes (64 stud minimum gap)
- **Better visibility** with increased spawn padding (36 studs)
- **Visual interest** from decorations and water
- **Scalable layout** that adapts to player count

### Long-term Advantages
- **Modular system** easy to extend with new themes
- **Performance-aware** with built-in optimization points
- **Multiplayer-friendly** respects all player spaces
- **Future-proof** architecture for maps/biomes

## Testing Checklist

- [ ] Test with 1 player (centered)
- [ ] Test with 4 players (2x2 grid)
- [ ] Test with 9 players (3x3 grid)
- [ ] Test with 16 players (4x4 grid)
- [ ] Test ring layout with various counts
- [ ] Verify decorations avoid all cubes
- [ ] Check water collision/swimming works
- [ ] Measure FPS impact with decorations
- [ ] Test on mobile devices
- [ ] Verify streaming compatibility

## Rollout Plan

### Week 1
1. Implement Phase 1 (spawn improvements)
2. Test with small group
3. Create decoration assets

### Week 2
1. Implement Phase 2 (decorations)
2. Implement Phase 3 (water)
3. Performance testing

### Week 3
1. Polish and optimization
2. Full multiplayer testing
3. Ship to production

## Next Steps

1. **Review & Approve** this plan
2. **Create decoration models** in Studio
3. **Implement Phase 1** for immediate relief
4. **Iterate based on feedback**