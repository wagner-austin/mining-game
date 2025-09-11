--!strict
-- GrassAnimation.lua (Client-side module in ReplicatedStorage)
-- Animated grass/bone chains with proper segment chaining

local RunService = game:GetService("RunService")

-- Wind field parameters
local WIND_SCALE = 0.06   -- spatial scale
local WIND_SPEED = 0.35   -- temporal speed

local GrassAnimation = {}
GrassAnimation.__index = GrassAnimation

-- Module-level RNG for consistent randomization
local rng = Random.new()

function GrassAnimation.new()
    local self = setmetatable({}, GrassAnimation)
    self.blades = {}
    self.time = 0
    self.running = false
    self.connection = nil :: RBXScriptConnection?
    self.camera = nil :: Camera?
    
    -- Single container for all grass elements
    self.root = Instance.new("Folder")
    self.root.Name = "GrassFX_Client"
    self.root.Parent = workspace
    
    -- Time-slicing for performance
    self._updateIndex = 1
    self._updateFrac = 1.0  -- fraction of blades to update each frame
    
    return self
end

-- Align cylinder between two points (Y-axis aligned to direction)
local function alignCylinder(p0: Vector3, p1: Vector3, cyl: BasePart)
    local dir = p1 - p0
    local len = dir.Magnitude
    if len < 1e-4 then return end
    
    local mid = p0 + dir * 0.5
    local y = dir.Unit
    local x = y:Cross(Vector3.zAxis)
    if x.Magnitude < 1e-4 then 
        x = y:Cross(Vector3.xAxis) 
    end
    x = x.Unit
    local z = x:Cross(y)
    
    cyl.Size = Vector3.new(cyl.Size.X, len, cyl.Size.Z) -- Y = height
    cyl.CFrame = CFrame.fromMatrix(mid, x, y, z)
end

-- Create a bone snake with proper chained movement
function GrassAnimation:createBoneSnake(position: Vector3, config: {
    segments: number?, 
    spacing: number?, 
    radius: number?,
    color: Color3?,
    swayAmount: number?,
    swaySpeed: number?
}?)
    config = config or {}
    local segments = config.segments or 12
    local spacing = config.spacing or 0.8
    local radius = config.radius or 0.3
    local baseColor = config.color or Color3.fromRGB(50, 200, 50)
    
    local snake = {
        segments = {},
        basePosition = position,
        baseCFrame = CFrame.new(position),
        phase = rng:NextNumber() * math.pi * 2,
        swaySpeed = config.swaySpeed or (2 + rng:NextNumber()),
        swayAmount = config.swayAmount or 1.5,
        spacing = spacing,
        type = "snake",
        _pos = table.create(segments) -- Pre-allocate positions array
    }
    
    local folder = Instance.new("Folder")
    folder.Name = "BoneSnake_" .. #self.blades
    folder.Parent = self.root
    
    for i = 1, segments do
        -- Create segment sphere
        local part = Instance.new("Part")
        part.Name = "Bone_" .. i
        part.Shape = Enum.PartType.Ball
        part.Size = Vector3.new(1, 1, 1) * (radius * 2 * (1 - (i-1) / segments * 0.3)) -- Taper
        part.Material = Enum.Material.SmoothPlastic
        part.Color = baseColor:Lerp(Color3.fromRGB(150, 250, 150), (i-1) / segments)
        part.Anchored = true
        part.CanCollide = false
        part.CanQuery = false
        part.Position = position + Vector3.new(0, (i - 1) * spacing, 0)
        part.Parent = folder
        
        -- Create connector cylinder
        local connector = nil :: Part?
        if i > 1 then
            connector = Instance.new("Part")
            connector.Name = "Connector_" .. i
            connector.Shape = Enum.PartType.Cylinder
            local connRadius = radius * 1.2 * (1 - (i-2) / segments * 0.3)
            connector.Size = Vector3.new(connRadius * 2, spacing, connRadius * 2) -- X and Z for diameter
            connector.Material = Enum.Material.SmoothPlastic
            connector.Color = part.Color
            connector.Anchored = true
            connector.CanCollide = false
            connector.CanQuery = false
            connector.Parent = folder
            
            -- Initial alignment
            alignCylinder(
                position + Vector3.new(0, (i - 2) * spacing, 0),
                position + Vector3.new(0, (i - 1) * spacing, 0),
                connector
            )
        end
        
        snake.segments[i] = {
            part = part,
            connector = connector,
            index = i,
            radius = radius * (1 - (i-1) / segments * 0.3)
        }
    end
    
    snake.folder = folder
    snake._visible = true -- Track visibility for culling
    table.insert(self.blades, snake)
    return snake
end

-- Create a grass blade with chained segments
function GrassAnimation:createGrassBlade(position: Vector3, config: {
    segments: number?,
    height: number?,
    width: number?,
    color: Color3?,
    swayAmount: number?,
    swaySpeed: number?
}?)
    config = config or {}
    local segments = config.segments or 8
    local height = config.height or 6
    local width = config.width or 0.3
    local color = config.color or Color3.fromRGB(50, 180, 50)
    
    local blade = {
        segments = {},
        basePosition = position,
        baseCFrame = CFrame.new(position),
        phase = rng:NextNumber() * math.pi * 2,
        swaySpeed = config.swaySpeed or (1 + rng:NextNumber() * 0.5),
        swayAmount = config.swayAmount or (0.5 + rng:NextNumber() * 0.3),
        segmentHeight = height / segments,
        type = "blade"
    }
    
    local folder = Instance.new("Folder")
    folder.Name = "GrassBlade_" .. #self.blades
    folder.Parent = self.root
    
    for i = 1, segments do
        local part = Instance.new("Part")
        part.Name = "Segment_" .. i
        local taper = 1 - (i-1) / segments * 0.5
        part.Size = Vector3.new(
            width * taper,
            blade.segmentHeight * 1.1, -- Slight overlap
            width * 0.3
        )
        part.Material = Enum.Material.Grass
        part.Color = color:Lerp(Color3.fromRGB(100, 220, 100), (i-1) / segments)
        part.TopSurface = Enum.SurfaceType.Smooth
        part.BottomSurface = Enum.SurfaceType.Smooth
        part.Anchored = true
        part.CanCollide = false
        part.CanQuery = false
        
        -- Initial pose
        local offset = CFrame.new(0, blade.segmentHeight * (i - 0.5), 0)
        part.CFrame = blade.baseCFrame * offset
        part.Parent = folder
        
        blade.segments[i] = {
            part = part,
            index = i
        }
    end
    
    blade.folder = folder
    blade._visible = true -- Track visibility for culling
    table.insert(self.blades, blade)
    return blade
end

-- Animate with proper chaining
function GrassAnimation:animate(dt: number)
    self.time = self.time + dt
    local t = self.time
    
    -- Time-slicing for performance
    local n = #self.blades
    local step = math.max(1, math.floor(1 / self._updateFrac))
    
    for i = self._updateIndex, n, step do
        local blade = self.blades[i]
        if not blade then break end
        
        -- Skip animation for culled blades
        if not blade._visible then
            continue
        end
        
        -- Wind field calculation
        local base = blade.basePosition
        local wind = math.noise(base.X * WIND_SCALE, base.Z * WIND_SCALE, self.time * WIND_SPEED)
        wind = wind * 2 -- remap [-0.5,0.5] to [-1,1]
        
        local animTime = t * blade.swaySpeed + blade.phase
        
        if blade.type == "snake" then
            -- Snake animation with proper chaining
            local positions = blade._pos
            local currentCFrame = blade.baseCFrame
            
            for i, segment in ipairs(blade.segments) do
                local v = (i - 1) / math.max(#blade.segments - 1, 1)
                
                if i == 1 then
                    -- Root stays fixed with proper CFrame
                    segment.part.CFrame = blade.baseCFrame
                    positions[i] = blade.baseCFrame.Position
                    currentCFrame = blade.baseCFrame
                else
                    -- Chain-based movement with wind influence
                    local waveDelay = v * 0.5
                    local sway = math.sin(animTime - waveDelay) * blade.swayAmount * v * v * (0.65 + 0.35 * wind)
                    local bend = math.cos(animTime * 0.7 - waveDelay) * blade.swayAmount * 0.5 * v * v * (0.65 + 0.35 * wind)
                    
                    -- Build transform relative to previous segment
                    currentCFrame = currentCFrame * CFrame.new(0, blade.spacing, 0) * 
                                   CFrame.Angles(math.rad(sway * 15), 0, math.rad(bend * 15))
                    
                    positions[i] = currentCFrame.Position
                    segment.part.CFrame = currentCFrame
                end
            end
            
            -- Update connectors between segments
            for i = 2, #blade.segments do
                local connector = blade.segments[i].connector
                if connector then
                    alignCylinder(positions[i-1], positions[i], connector)
                end
            end
            
        elseif blade.type == "blade" then
            -- Grass blade with chain-based bending
            local segCFrame = blade.baseCFrame
            
            for i, segment in ipairs(blade.segments) do
                local v = (i - 1) / math.max(#blade.segments - 1, 1)
                
                -- Progressive bending along the blade with wind influence
                local sway = math.sin(animTime + v * 0.5) * blade.swayAmount * v * v * (0.65 + 0.35 * wind)
                local bend = math.sin(animTime * 0.7) * 0.3 * v * (0.65 + 0.35 * wind)
                
                -- Chain transforms
                segCFrame = segCFrame * CFrame.new(0, blade.segmentHeight, 0) * 
                           CFrame.Angles(0, math.rad(bend * 10), math.rad(sway * 20))
                
                segment.part.CFrame = segCFrame
            end
        end
    end
    
    -- Update time-slice index
    self._updateIndex = self._updateIndex + 1
    if self._updateIndex > n then
        self._updateIndex = 1
    end
end

-- Start animation with RenderStepped for smoothness
function GrassAnimation:start()
    if self.running then return end
    self.running = true
    
    self.connection = RunService.RenderStepped:Connect(function(dt)
        self:animate(dt)
    end)
end

-- Stop animation
function GrassAnimation:stop()
    if self.connection then
        self.connection:Disconnect()
        self.connection = nil
    end
    self.running = false
end

-- Clean up all blades
function GrassAnimation:cleanup()
    self:stop()
    for _, blade in ipairs(self.blades) do
        if blade.folder then
            blade.folder:Destroy()
        end
    end
    self.blades = {}
    
    -- Clean up root folder
    if self.root then
        self.root:Destroy()
        self.root = Instance.new("Folder")
        self.root.Name = "GrassFX_Client"
        self.root.Parent = workspace
    end
end

-- Distance culling helper (optional)
function GrassAnimation:setCamera(camera: Camera)
    self.camera = camera
end

function GrassAnimation:cullDistant(maxDistance: number)
    if not self.camera then return end
    
    local camPos = self.camera.CFrame.Position
    for _, blade in ipairs(self.blades) do
        local distance = (blade.basePosition - camPos).Magnitude
        blade._visible = distance <= maxDistance
        
        -- Avoid redundant reparenting
        if blade.folder then
            local wantParent = blade._visible and self.root or nil
            if blade.folder.Parent ~= wantParent then
                blade.folder.Parent = wantParent
            end
        end
    end
end

-- Getter for root folder (for raycast exclusion updates)
function GrassAnimation:getRoot(): Instance
    return self.root
end

-- Set time-slice update fraction (0.1 to 1.0)
function GrassAnimation:setUpdateFraction(f: number)
    self._updateFrac = math.clamp(f, 0.1, 1.0)
end

return GrassAnimation