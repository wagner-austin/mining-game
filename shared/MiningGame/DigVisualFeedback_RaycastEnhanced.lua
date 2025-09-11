--!strict
--[[
    Note: Time module import added at top for consistency
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Time = require(MiningGame:WaitForChild("Time"))
local MathUtils = require(MiningGame:WaitForChild("MathUtils"))

--[[
    DigVisualFeedback_RaycastEnhanced.lua
    
    Complete implementation with raycast-based terrain projection.
    Copy the methods below into DigVisualFeedback.lua for accurate terrain-hugging indicators.
]]

-- ==========================================
-- 1. FIX CACHE SCHEMA TYPO (line 83)
-- ==========================================
-- REPLACE:
-- self._terrainSurfaceCache = {} :: {[string]: {hasTerrrain: boolean, timestamp: number}}
-- WITH:
-- self._terrainSurfaceCache = {} :: {[string]: {hasTerrain: boolean, position: Vector3?, normal: Vector3?, timestamp: number}}
-- self._terrainCacheLifetime = 0.2 -- 200ms cache
-- self._rayBudget = 24 -- Max rays per frame for scalability
-- self._raysRemaining = 0 -- Track rays used this frame

-- ==========================================
-- 2. ENHANCED TERRAIN DETECTOR
-- ==========================================
-- Returns: hasTerrain, position, normal, didRaycast
function DigVisualFeedback:_cellHasVisibleTerrain(cx: number, cy: number, cz: number, surfaceNormal: Vector3?): (boolean, Vector3?, Vector3?, boolean)
    if not self.playerCubeOrigin then return false, nil, nil, false end
    local CELL = GameConfig.Grid.CELL_SIZE_STUDS
    local center = GridMath.cellToWorld(cx, cy, cz, self.playerCubeOrigin, CELL)
    
    -- Quick bounds check
    if not self:IsInsideCube(center) then return false, nil, nil, false end
    
    -- Check cache first
    local cacheKey = string.format("%d,%d,%d", cx, cy, cz)
    local now = Time.mono()
    local cached = self._terrainSurfaceCache[cacheKey]
    if cached and (now - cached.timestamp) < self._terrainCacheLifetime then
        return cached.hasTerrain, cached.position, cached.normal, false -- No raycast needed
    end
    
    local hasTerrain, position, normal, didRaycast = false, nil, nil, false
    
    -- If we have a surface normal and ray budget, use raycast for accurate detection
    if surfaceNormal and (self._raysRemaining or 0) > 0 then
        local rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Include
        rayParams.FilterDescendantsInstances = {workspace.Terrain}
        
        -- Cast ray from above the surface toward the cell
        local rayStart = center + (surfaceNormal * (CELL * 3))
        local rayDir = -surfaceNormal * (CELL * 6)
        
        local hit = workspace:Raycast(rayStart, rayDir, rayParams)
        didRaycast = true
        self._raysRemaining = MathUtils.saturatingSub(self._raysRemaining or 0, 1)
        
        if hit then
            -- Check if hit is within reasonable distance of cell center
            local distance = (hit.Position - center).Magnitude
            if distance <= (CELL * 1.5) then -- Allow for terrain mesh extension
                hasTerrain = true
                position = hit.Position
                normal = hit.Normal
            end
        end
    end
    
    -- Fallback to voxel check if no raycast hit or out of budget
    if not hasTerrain and not didRaycast then
        local half = CELL * 0.5
        local region = Region3.new(
            center - Vector3.new(half, half, half),
            center + Vector3.new(half, half, half)
        )
        region = region:ExpandToGrid(CELL)
        
        local materials = workspace.Terrain:ReadVoxels(region, CELL)
        if materials.Size.X > 0 and materials.Size.Y > 0 and materials.Size.Z > 0 then
            local mat = materials[1][1][1]
            if mat ~= Enum.Material.Air then
                hasTerrain = true
                position = center
                normal = surfaceNormal or Vector3.new(0, 1, 0)
            end
        end
    end
    
    -- Cache the result
    self._terrainSurfaceCache[cacheKey] = {
        hasTerrain = hasTerrain,
        position = position,
        normal = normal,
        timestamp = now
    }
    
    return hasTerrain, position, normal, didRaycast
end

-- ==========================================
-- 3. UPDATE _isCellSolid TO USE NEW METHOD
-- ==========================================
function DigVisualFeedback:_isCellSolid(cx: number, cy: number, cz: number): boolean
    -- Allow custom probe function to override
    if self._probe then
        return self._probe(cx, cy, cz)
    end
    
    -- Use enhanced terrain detection (just need the boolean)
    local hasTerrain = self:_cellHasVisibleTerrain(cx, cy, cz, self._lastHitNormal)
    return hasTerrain
end

-- ==========================================
-- 4. COMPUTE ONCE WITH SURFACE DATA
-- ==========================================
-- Returns enriched data with position and normal for each visible cell
function DigVisualFeedback:_computeAoEVisibleOffsets2D(cx: number, cy: number, cz: number, uAxis: string, vAxis: string, radius: number): {{du: number, dv: number, pos: Vector3?, normal: Vector3?}}
    local now = Time.mono()
    local key = string.format("%d,%d,%d|%s%s|%d", cx, cy, cz, uAxis, vAxis, (radius*2)+1)
    
    -- Use cached result if available and not expired
    if self._lastAoEKey == key and now < self._nextAoEProbeAt then
        return self._aoeVisibleOffsets
    end
    
    self._lastAoEKey = key
    self._nextAoEProbeAt = now + 0.10 -- ~10 Hz throttle
    local out = {}
    
    -- Set ray budget for this pass (scale with radius)
    self._raysRemaining = math.min(48, (2*radius+1)^2)
    
    -- LOD: Use larger steps for bigger radii
    local step = (radius >= 3) and 2 or 1
    
    -- Check each cell in the 2D footprint
    for du = -radius, radius, step do
        for dv = -radius, radius, step do
            local ox, oy, oz = cx, cy, cz
            
            if uAxis == "x" then
                ox = ox + du
            elseif uAxis == "y" then
                oy = oy + du
            else
                oz = oz + du
            end
            
            if vAxis == "x" then
                ox = ox + dv
            elseif vAxis == "y" then
                oy = oy + dv
            else
                oz = oz + dv
            end
            
            -- Get terrain surface data (position and normal)
            local hasTerrain, pos, normal = self:_cellHasVisibleTerrain(ox, oy, oz, self._lastHitNormal)
            if hasTerrain then
                table.insert(out, {
                    du = du, 
                    dv = dv,
                    pos = pos,
                    normal = normal
                })
            end
        end
    end
    
    self._aoeVisibleOffsets = out
    return out
end

-- ==========================================
-- 5. RENDER WITH TERRAIN PROJECTION
-- ==========================================
function DigVisualFeedback:_updateHoverIndicators(worldPos: Vector3, state: DigState)
    if not self.playerCubeOrigin then
        self:_resetPool()
        return
    end
    
    -- Reset pool for new configuration
    self:_resetPool()
    
    -- Calculate center cell
    local cx, cy, cz = GridMath.worldToCell(worldPos, self.playerCubeOrigin, GameConfig.Grid.CELL_SIZE_STUDS)
    
    -- Calculate radius for preview (size 1 = 3x3, size 2 = 5x5, etc)
    local radius = MathUtils.nonNegative(tonumber(self.previewSize) or 0)
    
    -- Determine which plane to show preview on based on surface normal
    local normalAxis, uAxis, vAxis = self:_planeAxesFromNormal(self._lastHitNormal)
    
    -- Get visible cells WITH surface data (compute once!)
    local visible = self:_computeAoEVisibleOffsets2D(cx, cy, cz, uAxis, vAxis, radius)
    
    -- Hide preview if no solid cells found (hole/ghost area)
    if #visible == 0 then
        self:_resetPool()
        if self.stateLabel then
            self.stateLabel.Visible = false
        end
        if self.customCursor then
            self.customCursor.ImageTransparency = 0.6
        end
        self.currentState = state
        return
    end
    
    -- Ensure we have enough boxes for visible cells
    self:_ensurePoolCapacity(#visible)
    
    -- Helper to orient a CFrame to surface normal
    local function orientToSurface(pos: Vector3, normal: Vector3): CFrame
        normal = (normal and normal.Magnitude > 0) and normal.Unit or Vector3.new(0, 1, 0)
        -- Use different fallback based on normal direction to avoid gimbal lock
        local fallback = (math.abs(normal.Y) > 0.9) and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
        local right = fallback:Cross(normal).Unit
        local forward = normal:Cross(right).Unit
        return CFrame.fromMatrix(pos, right, normal, forward)
    end
    
    -- Brighter, more visible transparency
    local transparency = 0.3
    local color = HOVER_COLOR
    
    if state == "ready" then
        color = READY_COLOR
        transparency = 0.15
    elseif state == "cooldown" then
        color = COOLDOWN_COLOR
        transparency = 0.45
    end
    
    local CELL = GameConfig.Grid.CELL_SIZE_STUDS
    
    -- Show solid cells projected to terrain surface
    for i = 1, #visible do
        local v = visible[i]
        local box = self:_getBox()
        
        if box and v.pos then
            -- Make the indicator a thin slab that hugs the terrain
            box.part.Size = Vector3.new(CELL, 0.2, CELL)
            box.part.CFrame = orientToSurface(v.pos, v.normal or self._lastHitNormal)
            box.part.Parent = workspace
            
            box.box.Color3 = color
            box.box.SurfaceColor3 = color
            box.box.LineThickness = 0.4  -- Reset to base thickness
            box.box.Transparency = transparency
            
            -- Make center cell slightly more prominent
            if v.du == 0 and v.dv == 0 then
                box.box.Transparency = math.max(0.02, transparency - 0.1)
                box.box.LineThickness = 0.6  -- Much thicker center
            end
        end
    end
end

-- ==========================================
-- 6. SIMPLIFIED CURSOR MODE (Optional)
-- ==========================================
-- To avoid cursor flicker, make OS cursor toggles a no-op
function DigVisualFeedback:_setCursorMode(mode: string)
    -- Centralized cursor mode switching for consistency
    if mode == self._cursorMode then return end
    
    local isTouch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
    
    if mode == "custom" and not isTouch then
        -- Just show our custom cursor, don't touch OS cursor
        if self.customCursor then 
            self.customCursor.Visible = true 
        end
    else
        -- Hide our custom cursor
        if self.customCursor then 
            self.customCursor.Visible = false 
        end
    end
    
    self._cursorMode = mode
end