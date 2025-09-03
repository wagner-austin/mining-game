--!strict
--[[
    DigVisualFeedback.lua
    Client-side visual feedback system for mining interactions.
    
    Features:
    - Cell hover highlighting with AoE preview
    - Cooldown state visualization
    - Custom cursor system with state icons
    - Particle effects for dig feedback
    - Performance-optimized pooling system
    - Bounds checking with visual indicators
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mouse = player:GetMouse()

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local GameConfig = require(MiningGame:WaitForChild("GameConfig"))
local Utils = MiningGame:WaitForChild("Utils")
local GridMath = require(Utils:WaitForChild("GridMath"))
local Logger = require(MiningGame:WaitForChild("Logger"))
local BlanketPreview = require(MiningGame:WaitForChild("BlanketPreview"))
local log = Logger.new("DigVisualFeedback")

-- Types
type DigState = "ready" | "cooldown" | "outside_bounds" | "no_terrain"

local DigVisualFeedback = {}
DigVisualFeedback.__index = DigVisualFeedback

-- Visual settings
local HOVER_COLOR = Color3.fromRGB(255, 255, 100) -- Yellow highlight
local COOLDOWN_COLOR = Color3.fromRGB(255, 100, 100) -- Red for cooldown
local READY_COLOR = Color3.fromRGB(100, 255, 100) -- Green for ready

-- Cursor icons - using visible test icons for now (replace with proper assets later)
local CURSOR_DEFAULT = "rbxasset://textures/ui/LuaChat/icons/ic-search.png"  -- Magnifying glass
local CURSOR_DIG = "rbxasset://textures/ui/LuaChat/icons/ic-search.png"  -- Same magnifying glass, colored green
local CURSOR_COOLDOWN = "rbxasset://textures/ui/LuaChat/icons/ic-search.png"  -- Same magnifying glass, will rotate during cooldown

--[[
    Create a new visual feedback system instance.
    Initializes state tracking and prepares visual components.
    
    @return DigVisualFeedback - The feedback system instance
]]
function DigVisualFeedback.new()
    local self = setmetatable({}, DigVisualFeedback)
    
    -- State tracking
    self.enabled = false
    self.currentState = "ready" :: DigState
    self.cooldownEndsAt = 0
    self.digCooldown = 1
    self.playerCubeOrigin = nil :: CFrame?
    self.previewSize = 1
    
    -- Cursor mode tracking
    self._cursorMode = nil :: string? -- "custom" | "os"
    
    -- Performance optimization
    self._lastCellKey = nil :: string?
    self._nextProbeAt = 0
    self._hasTerrain = false
    self._lastHitNormal = Vector3.new(0, 1, 0) :: Vector3
    
    
    -- Raycast terrain cache for accurate surface detection (with LRU eviction)
    self._terrainSurfaceCache = {} :: {[string]: {hasTerrain: boolean, position: Vector3?, normal: Vector3?, timestamp: number}}
    self._terrainCacheLifetime = 0.2 -- 200ms cache
    self._maxCacheSize = 100 -- Limit cache size to prevent memory leaks
    self._cacheCleanupCounter = 0 -- Track when to clean cache
    self._rayBudget = 24 -- Max rays per frame for scalability
    self._raysRemaining = 0 -- Track rays used this frame
    
    -- Visual components
    self._blanket = nil :: any
    self.stateLabel = nil :: TextLabel?
    self.cursorGui = nil :: ScreenGui?
    self.cursorParticles = nil :: ParticleEmitter?
    self.cursorAttachment = nil :: Attachment?
    
    -- Connections
    self.connections = {} :: {RBXScriptConnection}
    
    return self
end

--[[
    Initialize the visual feedback system.
    Creates selection box pool and cursor overlays.
]]
function DigVisualFeedback:Init()
    log:debug("Initializing visual feedback system")
    
    -- Create skinned mesh blanket for smooth preview
    self._blanket = BlanketPreview.new(GameConfig.Grid.CELL_SIZE_STUDS)
    
    -- Create cursor overlay and effects
    self:CreateCursorOverlay()
    self:CreateCursorEffects()
    
    self.enabled = true
    log:info("Visual feedback system initialized")
end


function DigVisualFeedback:CreateCursorEffects()
    -- Create a part that follows the mouse for particle effects
    local effectPart = Instance.new("Part")
    effectPart.Name = "CursorEffectPart"
    effectPart.Transparency = 1
    effectPart.CanCollide = false
    effectPart.CanQuery = false
    effectPart.CanTouch = false
    effectPart.Anchored = true
    effectPart.Size = Vector3.new(0.1, 0.1, 0.1)
    
    -- Create attachment for particles
    self.cursorAttachment = Instance.new("Attachment")
    self.cursorAttachment.Parent = effectPart
    
    -- Create particle emitter for visual feedback
    self.cursorParticles = Instance.new("ParticleEmitter")
    self.cursorParticles.Enabled = false
    self.cursorParticles.Lifetime = NumberRange.new(0.3, 0.5)
    self.cursorParticles.Rate = 50
    self.cursorParticles.Speed = NumberRange.new(2, 4)
    self.cursorParticles.SpreadAngle = Vector2.new(360, 360)
    self.cursorParticles.VelocityInheritance = 0
    self.cursorParticles.EmissionDirection = Enum.NormalId.Top
    self.cursorParticles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    self.cursorParticles.LightEmission = 1
    self.cursorParticles.LightInfluence = 0
    self.cursorParticles.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(0.5, 0.3),
        NumberSequenceKeypoint.new(1, 0)
    })
    self.cursorParticles.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.5),
        NumberSequenceKeypoint.new(1, 1)
    })
    self.cursorParticles.Parent = self.cursorAttachment
    
    self.cursorEffectPart = effectPart
end

function DigVisualFeedback:CreateCursorOverlay()
    -- Create a high-priority GUI for cursor overlay
    self.cursorGui = Instance.new("ScreenGui")
    self.cursorGui.Name = "DigCursorOverlay"
    self.cursorGui.ResetOnSpawn = false
    self.cursorGui.DisplayOrder = 10000  -- Above other UI
    self.cursorGui.IgnoreGuiInset = true
    self.cursorGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    self.cursorGui.Parent = playerGui
    
    -- Check if we're on a touch device
    local isTouch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
    
    -- Hide the OS cursor since we're drawing our own (desktop only)
    if not isTouch then
        UserInputService.MouseIconEnabled = false
        pcall(function()
            UserInputService.OverrideMouseIconBehavior = Enum.OverrideMouseIconBehavior.ForceHide
        end)
    end
    
    -- Create custom cursor image (using a visible test icon for now)
    self.customCursor = Instance.new("ImageLabel")
    self.customCursor.Name = "CustomCursor"
    self.customCursor.Size = UDim2.new(0, 48, 0, 48)
    self.customCursor.BackgroundTransparency = 1
    -- Use a bright, visible icon for testing (will replace with pickaxe asset later)
    self.customCursor.Image = "rbxasset://textures/ui/LuaChat/icons/ic-search.png"  -- Magnifying glass for testing
    self.customCursor.AnchorPoint = Vector2.new(0.5, 0.5)
    self.customCursor.ZIndex = 1001
    self.customCursor.ImageColor3 = Color3.new(1, 1, 1)
    self.customCursor.Visible = not isTouch  -- Hide on touch devices
    self.customCursor.Parent = self.cursorGui
    
    -- State label positioned independently from cursor (so it doesn't rotate)
    self.stateLabel = Instance.new("TextLabel")
    self.stateLabel.Name = "StateLabel"
    self.stateLabel.Size = UDim2.new(0, 80, 0, 30)
    self.stateLabel.Position = UDim2.new(0, 0, 0, 0)  -- Will be updated with cursor
    self.stateLabel.BackgroundTransparency = 1
    self.stateLabel.TextColor3 = Color3.new(1, 1, 1)
    self.stateLabel.TextStrokeTransparency = 0
    self.stateLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    self.stateLabel.TextScaled = false
    self.stateLabel.TextSize = 18
    self.stateLabel.Font = Enum.Font.SourceSansBold
    self.stateLabel.Text = ""
    self.stateLabel.ZIndex = 1000
    self.stateLabel.Visible = not isTouch  -- Hide on touch devices
    self.stateLabel.Parent = self.cursorGui  -- Parent to GUI, not cursor, to avoid rotation
end

function DigVisualFeedback:SetCubeOrigin(origin: CFrame)
    self.playerCubeOrigin = origin
    log:debug("Cube origin set to: {}", tostring(origin.Position))
end

function DigVisualFeedback:SetCooldown(cooldown: number)
    self.digCooldown = cooldown
end

function DigVisualFeedback:SetCooldownEndsAt(timestamp: number)
    self.cooldownEndsAt = timestamp
end

function DigVisualFeedback:SetPreviewSize(size: number)
    self.previewSize = size or 1
end

-- Clean old entries from terrain cache to prevent memory leaks
function DigVisualFeedback:_cleanTerrainCache(now: number)
    local count = 0
    local toRemove = {}
    
    -- Find expired entries
    for key, entry in pairs(self._terrainSurfaceCache) do
        if (now - entry.timestamp) > self._terrainCacheLifetime * 2 then -- Remove entries older than 2x lifetime
            table.insert(toRemove, key)
        end
        count = count + 1
    end
    
    -- If cache is too large, remove oldest entries
    if count > self._maxCacheSize then
        local entries = {}
        for key, entry in pairs(self._terrainSurfaceCache) do
            table.insert(entries, {key = key, timestamp = entry.timestamp})
        end
        table.sort(entries, function(a, b) return a.timestamp < b.timestamp end)
        
        -- Remove oldest entries to get back under limit
        local removeCount = count - self._maxCacheSize + 10 -- Remove 10 extra to avoid frequent cleanup
        for i = 1, math.min(removeCount, #entries) do
            table.insert(toRemove, entries[i].key)
        end
    end
    
    -- Remove marked entries
    for _, key in ipairs(toRemove) do
        self._terrainSurfaceCache[key] = nil
    end
end


function DigVisualFeedback:OnDig()
    -- Flash particles for dig feedback
    if self.cursorParticles then
        self.cursorParticles.Color = ColorSequence.new(READY_COLOR)
        self.cursorParticles:Emit(20)
    end
end

function DigVisualFeedback:_setCursorMode(mode: string)
    -- Centralized cursor mode switching for consistency
    if mode == self._cursorMode then return end
    
    local isTouch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
    
    if mode == "custom" and not isTouch then
        -- Hide OS cursor, show our custom one
        UserInputService.MouseIconEnabled = false
        pcall(function()
            UserInputService.OverrideMouseIconBehavior = Enum.OverrideMouseIconBehavior.ForceHide
        end)
        if self.customCursor then 
            self.customCursor.Visible = true 
        end
        mouse.Icon = ""
    else
        -- Show OS cursor, hide our custom one
        if self.customCursor then 
            self.customCursor.Visible = false 
        end
        mouse.Icon = ""
        UserInputService.MouseIconEnabled = true
        pcall(function()
            UserInputService.OverrideMouseIconBehavior = Enum.OverrideMouseIconBehavior.ForceShow
        end)
        mode = "os"
    end
    
    self._cursorMode = mode
end

function DigVisualFeedback:IsInsideCube(worldPos: Vector3): boolean
    if not self.playerCubeOrigin then return false end
    
    local localPos = self.playerCubeOrigin:PointToObjectSpace(worldPos)
    local half = GameConfig.Grid.CUBE_SIZE_STUDS / 2
    local tolerance = 2.5 -- Match server tolerance for terrain mesh overhang
    
    return math.abs(localPos.X) <= (half + tolerance) and 
           math.abs(localPos.Y) <= (half + tolerance) and 
           math.abs(localPos.Z) <= (half + tolerance)
end

function DigVisualFeedback:UpdateState(hit: RaycastResult?)
    if not self.enabled then return end
    
    local now = tick()
    local onCooldown = now < self.cooldownEndsAt
    
    local newState: DigState = "ready"
    local digPos = nil
    
    if hit and hit.Instance == workspace.Terrain then
        -- Calculate dig position
        digPos = hit.Position - (hit.Normal * 1.0)
        
        -- We'll check terrain later in _updateHoverIndicators via _cellHasVisibleTerrain
        -- No need to check twice
        
        -- Store hit normal for preview orientation
        self._lastHitNormal = hit.Normal
        
        -- Determine state
        if onCooldown then
            newState = "cooldown"
        elseif not self:IsInsideCube(digPos) then
            newState = "outside_bounds"
        -- Terrain check moved to _updateHoverIndicators
        else
            newState = "ready"
        end
        
        -- Handle outside bounds state
        if newState == "outside_bounds" then
            if self._blanket then self._blanket:setEnabled(false) end
            if self.stateLabel then self.stateLabel.Visible = false end
            if self.cursorParticles then self.cursorParticles.Enabled = false end
            -- Skip indicator work when outside
        else
            -- Update hover indicators only when in bounds
            self:_updateHoverIndicators(digPos, newState)
        end
    else
        -- No terrain hit
        newState = "no_terrain"
        if self._blanket then self._blanket:setEnabled(false) end
    end
    
    -- Calculate cooldown progress (0 = just started, 1 = ready)
    local cooldownProgress = 0
    if onCooldown and self.digCooldown > 0 then
        cooldownProgress = 1 - math.clamp((self.cooldownEndsAt - now) / self.digCooldown, 0, 1)
    end
    
    -- Update cursor effects based on state with refill animation
    if self.cursorParticles then
        if newState == "ready" then
            -- Visible sparkle effect when ready
            self.cursorParticles.Enabled = true
            self.cursorParticles.Rate = 35
            self.cursorParticles.Color = ColorSequence.new(READY_COLOR)
            self.cursorParticles.Size = NumberSequence.new(0.4)
        elseif newState == "cooldown" then
            -- Particles ramp up as cooldown progresses
            self.cursorParticles.Enabled = true
            self.cursorParticles.Rate = 8 + math.floor(30 * cooldownProgress)
            local refillColor = COOLDOWN_COLOR:Lerp(READY_COLOR, cooldownProgress)
            self.cursorParticles.Color = ColorSequence.new(refillColor)
            self.cursorParticles.Size = NumberSequence.new(0.2 + 0.3 * cooldownProgress)
        else
            self.cursorParticles.Enabled = false
        end
    end
    
    -- Single decision point for cursor mode
    local wantCustom = (newState == "ready" or newState == "cooldown")
    self:_setCursorMode(wantCustom and "custom" or "os")
    
    -- Update custom cursor appearance only if we're actually using it
    local isTouch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
    if self.customCursor and wantCustom and not isTouch then
        if newState == "ready" then
            self.customCursor.Image = CURSOR_DIG  -- Magnifying glass
            self.customCursor.ImageColor3 = READY_COLOR  -- Makes it green
            self.customCursor.ImageTransparency = 0
            self.customCursor.Size = UDim2.new(0, 48, 0, 48)
            self.customCursor.Rotation = -45  -- Tilt for action feel
        elseif newState == "cooldown" then
            -- Rotating refresh icon that spins during cooldown
            self.customCursor.Image = CURSOR_COOLDOWN  -- Refresh arrow
            local refillColor = COOLDOWN_COLOR:Lerp(READY_COLOR, cooldownProgress)
            self.customCursor.ImageColor3 = refillColor
            self.customCursor.ImageTransparency = 0.3 - (0.3 * cooldownProgress)  -- Less transparent as it recharges
            self.customCursor.Size = UDim2.new(0, 48, 0, 48)
            -- Rotate continuously during cooldown (2 full rotations per second)
            self.customCursor.Rotation = ((now - (self.cooldownEndsAt - self.digCooldown)) * 720) % 360
        end
    end
    
    -- Update state label
    if self.stateLabel then
        if newState == "ready" then
            self.stateLabel.Text = "DIG"
            self.stateLabel.TextColor3 = READY_COLOR
            self.stateLabel.Visible = true
        elseif newState == "cooldown" then
            local timeLeft = math.max(0, self.cooldownEndsAt - now)
            self.stateLabel.Text = string.format("%.1fs", timeLeft)
            -- Label color also transitions during cooldown
            self.stateLabel.TextColor3 = COOLDOWN_COLOR:Lerp(READY_COLOR, cooldownProgress)
            self.stateLabel.Visible = true
        else
            -- Hide label for no_terrain and outside_bounds
            self.stateLabel.Text = ""
            self.stateLabel.Visible = false
        end
    end
    
    self.currentState = newState
end


-- Enhanced terrain detection using raycasting for accurate surface detection
-- Returns: hasTerrain, position, normal, didRaycast
function DigVisualFeedback:_cellHasVisibleTerrain(cx: number, cy: number, cz: number, surfaceNormal: Vector3?): (boolean, Vector3?, Vector3?, boolean)
    if not self.playerCubeOrigin then return false, nil, nil, false end
    local CELL = GameConfig.Grid.CELL_SIZE_STUDS
    local center = GridMath.cellToWorld(cx, cy, cz, self.playerCubeOrigin, CELL)
    
    -- Quick bounds check
    if not self:IsInsideCube(center) then return false, nil, nil, false end
    
    -- Check cache first
    local cacheKey = string.format("%d,%d,%d", cx, cy, cz)
    local now = tick()
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
        self._raysRemaining = math.max(0, (self._raysRemaining or 0) - 1)
        
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
    
    -- Fallback to voxel check if no terrain found (extra forgiving)
    if not hasTerrain then
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
    
    -- Cache the result with cleanup check
    self._terrainSurfaceCache[cacheKey] = {
        hasTerrain = hasTerrain,
        position = position,
        normal = normal,
        timestamp = now
    }
    
    -- Periodically clean old cache entries to prevent memory leak
    self._cacheCleanupCounter = (self._cacheCleanupCounter or 0) + 1
    if self._cacheCleanupCounter >= 50 then -- Every 50 cache writes
        self._cacheCleanupCounter = 0
        self:_cleanTerrainCache(now)
    end
    
    return hasTerrain, position, normal, didRaycast
end




function DigVisualFeedback:_updateHoverIndicators(worldPos: Vector3, state: DigState)
    if not self.playerCubeOrigin then
        if self._blanket then self._blanket:setEnabled(false) end
        return
    end

    -- Calculate center cell
    local cx, cy, cz = GridMath.worldToCell(worldPos, self.playerCubeOrigin, GameConfig.Grid.CELL_SIZE_STUDS)
    local radius = math.max(0, tonumber(self.previewSize) or 0)

    -- Check terrain and get accurate surface position
    local hasCenter, centerPos, centerNormal = self:_cellHasVisibleTerrain(cx, cy, cz, self._lastHitNormal)
    
    -- Update our cached terrain state for UpdateState to use
    self._hasTerrain = hasCenter
    
    if not hasCenter or not centerPos then
        if self._blanket then self._blanket:setEnabled(false) end
        -- Update state to no_terrain if we couldn't find terrain
        if not hasCenter then
            self.currentState = "no_terrain"
        end
        return
    end

    -- Pick a color by state
    local color =
        (state == "ready") and READY_COLOR or
        (state == "cooldown") and COOLDOWN_COLOR or
        HOVER_COLOR

    -- Update blanket preview
    if self._blanket then
        self._blanket:setEnabled(true)
        self._blanket:update(centerPos, centerNormal or self._lastHitNormal, self.playerCubeOrigin, radius, color)
    end
end

function DigVisualFeedback:ShowDigResult(success: boolean, position: Vector3)
    -- Emit particles at cursor for feedback
    if self.cursorParticles then
        if success then
            -- Success: Green burst
            self.cursorParticles.Color = ColorSequence.new(READY_COLOR)
            self.cursorParticles:Emit(30)
        else
            -- Failure: Red burst
            self.cursorParticles.Color = ColorSequence.new(COOLDOWN_COLOR)
            self.cursorParticles:Emit(10)
        end
    end
    
    -- Optional: Create impact effect at dig position
    if success then
        local feedbackPart = Instance.new("Part")
        feedbackPart.Name = "DigImpact"
        feedbackPart.Anchored = true
        feedbackPart.CanCollide = false
        feedbackPart.CanQuery = false
        feedbackPart.CanTouch = false
        feedbackPart.Transparency = 0.8
        feedbackPart.Size = Vector3.new(
            GameConfig.Grid.CELL_SIZE_STUDS * 0.5,
            GameConfig.Grid.CELL_SIZE_STUDS * 0.5,
            GameConfig.Grid.CELL_SIZE_STUDS * 0.5
        )
        feedbackPart.Position = position
        feedbackPart.Material = Enum.Material.ForceField
        feedbackPart.Color = READY_COLOR
        feedbackPart.Parent = workspace
        
        -- Quick flash and fade
        local tween = TweenService:Create(
            feedbackPart,
            TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {
                Size = Vector3.new(
                    GameConfig.Grid.CELL_SIZE_STUDS * 1.2,
                    GameConfig.Grid.CELL_SIZE_STUDS * 1.2,
                    GameConfig.Grid.CELL_SIZE_STUDS * 1.2
                ),
                Transparency = 1
            }
        )
        tween:Play()
        Debris:AddItem(feedbackPart, 0.5)
    end
end

function DigVisualFeedback:Start()
    if #self.connections > 0 then return end -- Already started
    
    log:debug("Starting visual feedback updates")
    
    -- Update cursor and label position every frame (works in mouse-lock too)
    table.insert(self.connections, RunService.RenderStepped:Connect(function()
        local location = UserInputService:GetMouseLocation()
        -- Don't adjust for inset since IgnoreGuiInset = true
        local x = location.X
        local y = location.Y
        
        if self.customCursor then
            self.customCursor.Position = UDim2.fromOffset(x, y)
        end
        
        if self.stateLabel then
            -- Position label next to cursor, clamped to screen edges
            local cam = workspace.CurrentCamera
            if cam then
                local vp = cam.ViewportSize
                local labelX = math.clamp(x + 35, 0, vp.X - 80)
                local labelY = math.clamp(y + 35, 0, vp.Y - 30)
                self.stateLabel.Position = UDim2.fromOffset(labelX, labelY)
            else
                self.stateLabel.Position = UDim2.fromOffset(x + 35, y + 35)
            end
        end
    end))
    
    -- Main update loop for terrain detection
    table.insert(self.connections, RunService.Heartbeat:Connect(function()
        -- Cast ray to find terrain under mouse
        local cam = workspace.CurrentCamera
        if not cam then return end
        
        local ray = cam:ScreenPointToRay(mouse.X, mouse.Y)
        
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Include
        params.FilterDescendantsInstances = {workspace.Terrain}
        
        local hit = workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
        
        -- Update cursor effect position
        if self.cursorEffectPart then
            if hit then
                self.cursorEffectPart.Position = hit.Position
                self.cursorEffectPart.Parent = workspace
            else
                self.cursorEffectPart.Parent = nil
            end
        end
        
        self:UpdateState(hit)
    end))
end

function DigVisualFeedback:Pause()
    -- Temporarily hide visual feedback without disconnecting (for UI panels)
    if not self.enabled then return end
    
    log:debug("Pausing visual feedback")
    
    -- Hide blanket preview
    if self._blanket then
        self._blanket:setEnabled(false)
    end
    
    if self.stateLabel then
        self.stateLabel.Visible = false
    end
    
    if self.cursorEffectPart then
        self.cursorEffectPart.Parent = nil
    end
    
    if self.cursorParticles then
        self.cursorParticles.Enabled = false
    end
    
    -- Use centralized cursor mode helper
    self:_setCursorMode("os")
    
    self.enabled = false
end

function DigVisualFeedback:Resume()
    -- Resume visual feedback after pause
    if self.enabled then return end
    
    log:debug("Resuming visual feedback")
    
    self.enabled = true
    
    -- Force cursor mode reevaluation on next frame
    self._cursorMode = nil
end

function DigVisualFeedback:Stop()
    log:debug("Stopping visual feedback")
    
    -- Disconnect all connections
    for _, conn in ipairs(self.connections) do
        conn:Disconnect()
    end
    self.connections = {}
    
    -- Hide blanket preview
    if self._blanket then
        self._blanket:setEnabled(false)
    end
    
    if self.customCursor then
        self.customCursor.Visible = false
    end
    
    if self.stateLabel then
        self.stateLabel.Visible = false
    end
    
    if self.cursorEffectPart then
        self.cursorEffectPart.Parent = nil
    end
    
    if self.cursorParticles then
        self.cursorParticles.Enabled = false
    end
    
    -- Re-enable OS cursor
    mouse.Icon = ""
    pcall(function()
        UserInputService.OverrideMouseIconBehavior = Enum.OverrideMouseIconBehavior.None
    end)
    UserInputService.MouseIconEnabled = true
    
    self.enabled = false
end

function DigVisualFeedback:Destroy()
    self:Stop()
    
    -- Clean up blanket preview
    if self._blanket and self._blanket.destroy then
        self._blanket:destroy()
        self._blanket = nil
    end
    
    -- Clean up cursor effects
    if self.cursorEffectPart then
        self.cursorEffectPart:Destroy()
        self.cursorEffectPart = nil
    end
    
    -- Clean up GUI
    if self.cursorGui then
        self.cursorGui:Destroy()
        self.cursorGui = nil
    end
    
    -- Ensure OS cursor is restored even if Stop() wasn't called
    pcall(function()
        UserInputService.OverrideMouseIconBehavior = Enum.OverrideMouseIconBehavior.None
    end)
    UserInputService.MouseIconEnabled = true
    mouse.Icon = ""
end

return DigVisualFeedback