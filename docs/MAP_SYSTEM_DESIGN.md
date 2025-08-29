# Improved Map & Plot System Design

## Current System Issues
- Plot bounds are calculated separately from cube position
- Map configuration is minimal (just a base CFrame)
- Hard to visualize and configure different map layouts
- Plot/cube relationship isn't clearly defined

## Proposed Configurable System

### Enhanced Map Configuration Structure
```lua
GameConfig.Street.MAPS = {
    main = {
        base = CFrame.new(0, 0, 0),
        
        -- Plot layout configuration
        plot = {
            -- Plot dimensions (relative to cube)
            frontPadding = 20,    -- Space in front of cube (where player spawns)
            backPadding = 64,     -- Space behind cube
            sidePadding = 26,     -- Space on each side of cube
            
            -- Visual style
            borderColor = Color3.fromRGB(0, 162, 255),
            borderHeight = 0.2,
            borderThickness = 0.5,
            showCorners = true,
            showNameSign = true,
        },
        
        -- Street configuration for this map
        street = {
            width = 40,
            centerZ = 0,
            northLaneZ = 150,    -- Where north cubes are placed
            southLaneZ = -150,   -- Where south cubes are placed
        },
        
        -- Optional features
        features = {
            hasShop = true,
            hasLeaderboard = false,
            allowVisitors = true,
        }
    },
    
    vip = {
        base = CFrame.new(5000, 0, 0),
        plot = {
            frontPadding = 30,    -- Bigger plots for VIP
            backPadding = 80,
            sidePadding = 40,
            borderColor = Color3.fromRGB(255, 215, 0),  -- Gold borders
            borderHeight = 0.5,
            borderThickness = 1.0,
            showCorners = true,
            showNameSign = true,
        },
        street = {
            width = 60,           -- Wider street
            centerZ = 0,
            northLaneZ = 200,     -- More spacing
            southLaneZ = -200,
        },
        features = {
            hasShop = true,
            hasLeaderboard = true,
            allowVisitors = true,
            vipOnly = true,
        }
    }
}
```

### Unified Plot Calculation System

Instead of separate calculations, we'll have one source of truth:

```lua
function CubePositionService:GetPlotConfiguration(player: Player)
    local mapId = player:GetAttribute("MapId") or "main"
    local mapConfig = GameConfig.Street.MAPS[mapId]
    local cubeOrigin = self:GetOrigin(player)
    local cubeSize = self:GetCubeSizeStuds(player)
    
    return {
        -- Cube info
        cubeOrigin = cubeOrigin,
        cubeSize = cubeSize,
        
        -- Plot bounds (calculated from config)
        plotBounds = self:CalculatePlotBounds(
            cubeOrigin, 
            cubeSize, 
            mapConfig.plot
        ),
        
        -- Visual settings
        visual = mapConfig.plot,
        
        -- Map features
        features = mapConfig.features,
    }
end

function CubePositionService:CalculatePlotBounds(origin, cubeSize, plotConfig)
    local cubeHalf = cubeSize * 0.5
    local center = origin.Position
    
    -- Plot extends around cube based on config
    return {
        minX = center.X - cubeHalf - plotConfig.sidePadding,
        maxX = center.X + cubeHalf + plotConfig.sidePadding,
        minZ = center.Z - cubeHalf - plotConfig.backPadding,
        maxZ = center.Z + cubeHalf + plotConfig.frontPadding,
        minY = 0,  -- Ground level
        maxY = cubeSize + 10,  -- Above cube
    }
end
```

### Benefits of This System

1. **Easy Map Creation**: Just add a new entry to MAPS config
2. **Per-Map Customization**: Each map can have different plot sizes, colors, features
3. **Single Source of Truth**: Plot bounds always calculated from cube position + config
4. **Visual Consistency**: Plot outline automatically matches configuration
5. **Migration Ready**: Moving a player to a new map automatically updates everything

### Migration Process

When moving a player to a new map:
```lua
function CubePositionService:MovePlayerToMap(player: Player, newMapId: string)
    -- 1. Remove old plot outline
    self:RemovePlotOutline(player)
    
    -- 2. Release old slot
    self:ReleaseSlot(player)
    
    -- 3. Set new map attribute
    player:SetAttribute("MapId", newMapId)
    
    -- 4. Assign new slot in new map
    local slot = self:AssignSlot(player)
    
    -- 5. Create new plot outline with new map's config
    self:CreatePlotOutline(player)  -- Uses new map's visual settings
    
    -- 6. Respawn player at new location
    -- (SpawnService handles this automatically)
    
    return slot ~= nil
end
```

### Plot Boundary Validation

Simplified validation that works with any map:
```lua
function CubePositionService:IsInPlayersPlot(player: Player, worldPos: Vector3)
    local config = self:GetPlotConfiguration(player)
    if not config then return false end
    
    local bounds = config.plotBounds
    
    -- Add small tolerance for edge cases (0.5 studs)
    local tolerance = 0.5
    
    return worldPos.X >= bounds.minX - tolerance and 
           worldPos.X <= bounds.maxX + tolerance and
           worldPos.Z >= bounds.minZ - tolerance and 
           worldPos.Z <= bounds.maxZ + tolerance
end
```

## Implementation Steps

1. **Update GameConfig.lua** with enhanced MAPS structure
2. **Refactor CubePositionService** to use unified plot configuration
3. **Update plot outline creation** to use map-specific visual settings
4. **Simplify boundary checking** with tolerance
5. **Test map transitions** ensure smooth player movement between maps

This system ensures that plots and cubes always move together and are configured consistently across different maps.