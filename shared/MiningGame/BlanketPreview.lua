--!strict
-- BlanketPreview.lua — smooth "blanket" dig preview using a SkinnedMeshPart
-- API:
--  local bp = BlanketPreview.new(cellSize)
--  bp:setEnabled(true/false)
--  bp:update(centerPos, centerNormal, cubeOrigin, radius, color, style)

local BlanketPreview = {}
BlanketPreview.__index = BlanketPreview

local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MiningGame = RS:WaitForChild("MiningGame")
local Logger = require(MiningGame:WaitForChild("Logger"))
local MathUtils = require(MiningGame:WaitForChild("MathUtils"))
local log = Logger.new("BlanketPreview")

type Style = {
    transparency: number,         -- 0 (opaque) .. 1 (invisible)
    material: Enum.Material,      -- ForceField/Neon/Plastic
    updateHz: number,             -- sampling rate (e.g. 10)
    maxRays: number,              -- per update budget
    pixelsPerStud: number,        -- optional: SurfaceGui overlay if you add one later
}

local DEFAULT_STYLE: Style = {
    transparency = 0.25,
    material = Enum.Material.ForceField,
    updateHz = 10,
    maxRays = 81, -- 9x9
    pixelsPerStud = 0,
}

-- Try to find the asset, but don't block if it doesn't exist
local MiningGame = RS:WaitForChild("MiningGame")
local Assets = MiningGame:FindFirstChild("Assets")
local BlanketTemplate = Assets and Assets:FindFirstChild("BlanketPlane") :: Instance?

local function clamp(n, a, b) return math.max(a, math.min(n, b)) end

function BlanketPreview.new(cellSize: number)
    local self = setmetatable({}, BlanketPreview)
    self._enabled = false
    self._cell = cellSize
    self._style = DEFAULT_STYLE
    self._accum = 0
    self._period = 1 / self._style.updateHz
    self._span = cellSize -- will be resized per radius

    -- Instance
    if not BlanketTemplate then
        log:warn("Missing Skinned mesh asset at ReplicatedStorage.MiningGame.Assets.BlanketPlane")
        self._mesh = nil
        self._bones = {}
        return self
    end

    -- Handle both Model (with MeshPart child) and direct SkinnedMeshPart
    local mesh
    if BlanketTemplate:IsA("Model") then
        -- It's a Model, find the MeshPart child (which has the bones)
        local meshPart = BlanketTemplate:FindFirstChildWhichIsA("MeshPart")
        if meshPart then
            mesh = BlanketTemplate:Clone()
            self._actualMesh = mesh:FindFirstChildWhichIsA("MeshPart")
        else
            log:warn("BlanketPlane Model has no MeshPart child")
            self._mesh = nil
            self._bones = {}
            return self
        end
    else
        -- It's a direct MeshPart/SkinnedMeshPart
        mesh = BlanketTemplate:Clone()
        self._actualMesh = mesh
    end
    
    mesh.Name = "DigBlanket"
    mesh.Parent = workspace
    
    -- Apply properties to the actual mesh part
    if self._actualMesh then
        self._actualMesh.Anchored = true
        self._actualMesh.CanCollide = false
        self._actualMesh.CanQuery = false
        self._actualMesh.CanTouch = false
        self._actualMesh.CastShadow = false
        self._actualMesh.Transparency = self._style.transparency
        self._actualMesh.Material = self._style.material
    end
    
    self._mesh = self._actualMesh or mesh
    self._isSkinned = true  -- If it has bones, treat it as skinned

    -- Map bones by name for quick lookup
    local bones: {[string]: Bone} = {}
    local boneList = {}
    
    -- Look for bones in the actual mesh part
    local searchTarget = self._actualMesh or mesh
    for _, d in ipairs(searchTarget:GetDescendants()) do
        if d:IsA("Bone") then
            bones[d.Name] = d
            table.insert(boneList, d)
        end
    end
    self._bones = bones

    -- Build grid from bone positions (generic approach)
    self._grid = {} :: {{name:string, r:number, c:number}}
    
    -- Calibration fields
    self._calibrated = false
    self._uSign = 1
    self._vSign = 1
    self._swapUV = false
    
    log:debug("Building grid from " .. tostring(#boneList) .. " bones")
    
    if #boneList > 0 then
        -- Sort bones by position to create a grid
        table.sort(boneList, function(a, b)
            -- Sort by Z first (rows), then X (columns)
            if math.abs(a.Position.Z - b.Position.Z) > 0.1 then
                return a.Position.Z < b.Position.Z
            end
            return a.Position.X < b.Position.X
        end)
        
        -- Create grid indices based on sorted positions
        local gridSize = math.ceil(math.sqrt(#boneList))
        local minR, maxR, minC, maxC =  1e9, -1e9, 1e9, -1e9
        
        for i, bone in ipairs(boneList) do
            local r = math.floor((i - 1) / gridSize) - math.floor(gridSize / 2)
            local c = ((i - 1) % gridSize) - math.floor(gridSize / 2)
            table.insert(self._grid, {name=bone.Name, r=r, c=c})
            minR = math.min(minR, r); maxR = math.max(maxR, r)
            minC = math.min(minC, c); maxC = math.max(maxC, c)
        end
        
        self._halfR = math.max(math.abs(minR), math.abs(maxR))
        self._halfC = math.max(math.abs(minC), math.abs(maxC))
        
        log:debug("Grid size: " .. gridSize .. "x" .. gridSize)
        log:debug("Grid bounds: r=[" .. minR .. "," .. maxR .. "] c=[" .. minC .. "," .. maxC .. "]")
    end
    
    if #self._grid == 0 then
        if self._isSkinned then
            log:warn("No bones found in mesh!")
        else
            log:info("Initialized MeshPart blanket (no bones)")
        end
    else
        log:info("Initialized with " .. #self._grid .. " bones in grid")
    end
    
    -- Normalize bone layout to UV in [-0.5..0.5] using the mesh's object space (skinned only)
    if #boneList > 0 then
        local cf = (self._actualMesh or mesh).CFrame
        local uMin, uMax = math.huge, -math.huge
        local vMin, vMax = math.huge, -math.huge

        -- 1) project each bone into mesh object space
        for _, g in ipairs(self._grid) do
            local b = bones[g.name]
            if b then
                -- world -> object space (handles any root/parent transforms + the 2048 offset)
                local lp = cf:PointToObjectSpace(b.WorldPosition)
                g._u = lp.X         -- X = U
                g._v = lp.Z         -- Z = V (Y is up)
                if g._u < uMin then uMin = g._u end
                if g._u > uMax then uMax = g._u end
                if g._v < vMin then vMin = g._v end
                if g._v > vMax then vMax = g._v end
            end
        end

        log:debug(("Raw UV bounds (obj space): u=[%s,%s] v=[%s,%s]"):format(uMin, uMax, vMin, vMax))

        -- 2) normalize to [-0.5 .. 0.5]
        local uSpan = math.max(1e-6, uMax - uMin)
        local vSpan = math.max(1e-6, vMax - vMin)
        
        -- Store object-space spans for scaling calculations
        self._objUSpan = uSpan           -- object-space width across bones (X)
        self._objVSpan = vSpan           -- object-space length across bones (Z)
        
        log:info(("Object spans stored: uSpan=%f vSpan=%f"):format(uSpan, vSpan))
        
        for _, g in ipairs(self._grid) do
            g.u = ((g._u - uMin)/uSpan) - 0.5
            g.v = ((g._v - vMin)/vSpan) - 0.5
            g._u, g._v = nil, nil
        end

        -- Build helpers for calibration (center, extremes)
        local nearest, nearestDist = nil, math.huge
        local maxU, minU, maxV, minV = nil, nil, nil, nil
        for _, it in ipairs(self._grid) do
            local d = math.abs(it.u) + math.abs(it.v)
            if d < nearestDist then nearest, nearestDist = it, d end
            if (not maxU) or it.u > maxU.u then maxU = it end
            if (not minU) or it.u < minU.u then minU = it end
            if (not maxV) or it.v > maxV.v then maxV = it end
            if (not minV) or it.v < minV.v then minV = it end
        end
        self._calib = { center = nearest, maxU = maxU, minU = minU, maxV = maxV, minV = minV }
    end

    -- Raycast setup
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Include
    rp.FilterDescendantsInstances = {workspace.Terrain}
    self._rp = rp

    -- Update loop
    self._conn = RunService.Heartbeat:Connect(function(dt)
        if not self._enabled or not self._mesh then return end
        self._accum += dt
        if self._accum >= self._period then
            self._accum -= self._period
            self:_sampleAndDeform()
        end
    end)

    return self
end

function BlanketPreview:destroy()
    if self._conn then self._conn:Disconnect(); self._conn = nil end
    if self._mesh then self._mesh:Destroy(); self._mesh = nil end
end

function BlanketPreview:setEnabled(on: boolean)
    self._enabled = on
    if self._mesh then
        self._mesh.Parent = on and workspace or nil
        if not on then
            -- reset bones back toward rest
            if self._isSkinned then
                for _, b in pairs(self._bones) do
                    b.Transform = CFrame.new()
                end
            end
        end
    end
end

function BlanketPreview:setStyle(style: any)
    for k, v in pairs(style) do
        (self._style :: any)[k] = v
    end
    self._period = 1 / self._style.updateHz
    if self._mesh then
        self._mesh.Transparency = self._style.transparency
        self._mesh.Material = self._style.material
    end
end

-- Call each frame/tick with latest target pose
function BlanketPreview:update(centerPos: Vector3, centerNormal: Vector3, cubeOrigin: CFrame, radius: number, color: Color3?)
    self._targetPos = centerPos
    self._targetUp  = (centerNormal.Magnitude > 0) and centerNormal.Unit or Vector3.new(0,1,0)
    self._cubeCF    = cubeOrigin
    self._radius    = MathUtils.nonNegative(radius)
    self._span      = (2*self._radius + 1) * self._cell
    self._color     = color
    
    -- Log update parameters for debugging (only first few calls)
    self._updateCount = (self._updateCount or 0) + 1
    if self._updateCount <= 5 then
        log:debug("Update #" .. self._updateCount .. ": pos=" .. tostring(centerPos) .. ", normal=" .. tostring(centerNormal) .. ", radius=" .. radius .. ", span=" .. self._span)
    end
    
    if self._mesh and color then
        -- optional color tint via VertexColor; if your asset supports it
        self._mesh.Color = color
    end
end

function BlanketPreview:_autoCalibrateAxes(cf: CFrame)
    if self._calibrated or not self._calib then return end

    local right = cf.RightVector
    local back  = -cf.LookVector
    local center = self._calib.center
    if not center then self._calibrated = true; return end

    local function wp(name: string)
        local b = self._bones[name]
        return b and b.WorldPosition or cf.Position
    end

    local cPos = wp(center.name)
    local uRef = self._calib.maxU or center
    local vRef = self._calib.maxV or center

    local uVec = (wp(uRef.name) - cPos).Unit
    local vVec = (wp(vRef.name) - cPos).Unit

    local dotUright = math.abs(uVec:Dot(right))
    local dotUback  = math.abs(uVec:Dot(back))
    self._swapUV = (dotUback > dotUright)

    if self._swapUV then
        self._uSign = (uVec:Dot(back)  >= 0) and 1 or -1
        self._vSign = (vVec:Dot(right) >= 0) and 1 or -1
    else
        self._uSign = (uVec:Dot(right) >= 0) and 1 or -1
        self._vSign = (vVec:Dot(back)  >= 0) and 1 or -1
    end

    -- Measure current world span across U and V to derive world-per-object scale
    if self._objUSpan and self._objVSpan then
        local uA, uB = self._calib.minU or center, self._calib.maxU or center
        local vA, vB = self._calib.minV or center, self._calib.maxV or center
        local uWorld = math.abs((wp((uB :: any).name) - wp((uA :: any).name)):Dot(right))
        local vWorld = math.abs((wp((vB :: any).name) - wp((vA :: any).name)):Dot(back))
        self._worldPerObjU = (self._objUSpan > 0) and (uWorld / self._objUSpan) or 1
        self._worldPerObjV = (self._objVSpan > 0) and (vWorld / self._objVSpan) or 1
        self._worldToObj   = 2 / ((self._worldPerObjU or 1) + (self._worldPerObjV or 1))
        log:info(("Calibration: swapUV=%s uSign=%d vSign=%d  (U·R=%.3f U·B=%.3f)  scales U=%.6f V=%.6f")
            :format(tostring(self._swapUV), self._uSign, self._vSign, dotUright, dotUback, self._worldPerObjU, self._worldPerObjV))
    end

    self._calibrated = true
end

-- Internal: sample terrain and bend bones
function BlanketPreview:_sampleAndDeform()
    if not (self._mesh and self._targetPos and self._targetUp and self._cubeCF) then 
        log:warn("Missing required data for deform")
        return 
    end

    local up = self._targetUp
    -- keep visuals aligned to cube axes for a consistent grid look
    local cubeRight, cubeUp, cubeFwd = self._cubeCF.RightVector, self._cubeCF.UpVector, self._cubeCF.LookVector
    local right, forward
    do
        local dY = math.abs(up:Dot(cubeUp))
        local dZ = math.abs(up:Dot(cubeFwd))
        local dX = math.abs(up:Dot(cubeRight))
        if dY >= dZ and dY >= dX then right, forward = cubeRight, cubeFwd
        elseif dZ >= dX then            right, forward = cubeRight, cubeUp
        else                             right, forward = cubeFwd,  cubeUp end
        right   = (right - right:Dot(up)*up).Unit
        forward = (up:Cross(right)).Unit
    end

    local lift = 0.03
    local cf = CFrame.fromMatrix(self._targetPos + up*lift, right, up, -forward)
    self._mesh.CFrame = cf
    
    -- If not skinned, simply size and place the plane; skip bone work
    if not self._isSkinned then
        local msAny = (self._mesh :: any)
        if msAny:IsA("BasePart") then
            msAny.Size = Vector3.new(self._span, 0.05, self._span)
        end
        return
    end

    -- Compute uniform scale from object-space span -> desired dig span (skinned)
    local objSpan = math.max(self._objUSpan or 1, self._objVSpan or 1)
    local s = self._span / objSpan             -- world studs per 1 object-space unit
    self._meshScale = s                        -- remember for bone transforms

    -- Debug: Log all scaling values
    log:debug(("Scale calc: objUSpan=%f objVSpan=%f objSpan=%f span=%f s=%f"):format(
        self._objUSpan or -1, self._objVSpan or -1, objSpan, self._span, s))

    -- Scale the skinned mesh (visual) to exactly match self._span
    local ms = self._mesh.MeshSize             -- native mesh size (read-only reference)
    
    -- The issue: MeshSize is the VISUAL size of the mesh asset (275000 studs)
    -- But the bones only span 2048 units in that space
    -- We need to scale based on the ratio: bone_span / mesh_size
    local meshToObjRatio = objSpan / math.max(ms.X, ms.Z)  -- 2048 / 275000 ≈ 0.00745
    local targetScale = self._span / objSpan               -- 12 / 2048 ≈ 0.00586
    
    -- Apply the scale directly to match span
    local targetX = self._span  -- Direct assignment to span
    local targetZ = self._span  -- Direct assignment to span
    local targetY = math.max(ms.Y * s, 0.05)   -- keep a small thickness relative to native Y
    
    log:debug(("Mesh scaling: MeshSize=%s meshToObjRatio=%f targetScale=%f"):format(
        tostring(ms), meshToObjRatio, targetScale))
    log:debug(("Target size: X=%f Y=%f Z=%f (should match span=%f)"):format(
        targetX, targetY, targetZ, self._span))
    
    self._mesh.Size = Vector3.new(targetX, targetY, targetZ)
    
    -- Precompute world->object scale for bone transforms (prefer measured; fallback to 1/s)
    local worldToObj = (self._worldToObj and self._worldToObj > 0) and self._worldToObj or ((s ~= 0) and (1 / s) or 1)

    -- Log scaling info once
    if not self._sizeLogged then
        self._sizeLogged = true
        log:info(("FINAL: objSpan=%.3f span=%.3f s=%.6f  MeshSize=%s  ActualSize=%s"):format(
            objSpan, self._span, s, tostring(ms), tostring(self._mesh.Size)))
        
        -- Verify the actual size
        local actualSize = self._mesh.Size
        if math.abs(actualSize.X - self._span) > 0.1 or math.abs(actualSize.Z - self._span) > 0.1 then
            log:warn(("SIZE MISMATCH! Expected %f, got X=%f Z=%f"):format(
                self._span, actualSize.X, actualSize.Z))
        else
            log:info(("Size correct: mesh is %fx%f, span is %f"):format(
                actualSize.X, actualSize.Z, self._span))
        end
    end

    -- Log a couple frames to confirm positioning
    if not self._logCount then self._logCount = 0 end
    if self._logCount < 3 then
        self._logCount = self._logCount + 1
        log:debug(("Blanket frame %d | cf=%s span=%.2f"):format(
            self._logCount, tostring(cf.Position), self._span))
    end

    -- Auto-calibrate on first frame
    self:_autoCalibrateAxes(cf)

    -- LOD step: sample fewer anchors for large spans
    local step = (self._radius >= 4) and 2 or 1
    local rays = 0
    local maxRays = self._style.maxRays

    local back = -forward  -- Define once outside loop
    
    for _, a in ipairs(self._grid) do
        -- stride sampling for perf (lod)
        if (a.r % step == 0) and (a.c % step == 0) then
            local bone = self._bones[a.name]
            if bone then
                -- Use normalized UV from the grid (computed from actual bone positions)
                local u = a.u or 0  -- normalized [-0.5..0.5], from local bone X
                local v = a.v or 0  -- normalized [-0.5..0.5], from local bone Z
                
                -- Apply auto-calibrated mapping
                if self._swapUV then u, v = v, u end
                u = u * self._uSign
                v = v * self._vSign
                
                -- Sample position for this bone on the current blanket plane
                local sampleWorld =
                    cf.Position + right*(u * self._span) + back*(v * self._span)

                if rays < maxRays then
                    -- Raycast straight down from bone position to find ground
                    local rayStart = sampleWorld + up * 10  -- Start high above
                    local rayDir = -up * 20  -- Cast down
                    local hit = workspace:Raycast(rayStart, rayDir, self._rp)
                    rays += 1

                    -- Initialize bone physics attributes
                    if not bone:GetAttribute("velocity") then
                        bone:SetAttribute("velocity", 0)
                        bone:SetAttribute("currentY", 0)
                    end
                    
                    local velocity = bone:GetAttribute("velocity") or 0
                    local currentY = bone:GetAttribute("currentY") or 0
                    
                    -- Find the ground height at this position
                    local groundHeight = 0
                    if hit then
                        -- Get exact height where ray hit, relative to the blanket center
                        groundHeight = (hit.Position - sampleWorld):Dot(up)
                        -- Add small offset so cloth sits ON terrain, not in it
                        groundHeight = groundHeight + 0.05
                    else
                        -- No ground found, use a default low position
                        groundHeight = -3
                    end
                    
                    -- Simple cloth physics
                    local gravity = -0.08  -- Gentle fall
                    local damping = 0.85   -- Air resistance
                    local groundRepulsion = 0.4  -- How hard ground pushes back
                    
                    -- Apply gravity
                    velocity = velocity + gravity
                    
                    -- Check if we're at or below ground
                    if currentY <= groundHeight then
                        -- We're touching/below ground - push back up
                        if velocity < 0 then
                            -- Bounce off ground with energy loss
                            velocity = -velocity * 0.2  
                        end
                        -- Force position to ground level
                        currentY = groundHeight
                        -- Add upward force if we're below ground
                        if currentY < groundHeight then
                            velocity = velocity + (groundHeight - currentY) * groundRepulsion
                        end
                    end
                    
                    -- Apply damping
                    velocity = velocity * damping
                    
                    -- Update position
                    currentY = currentY + velocity
                    
                    -- HARD CONSTRAINT: Never go below ground
                    if currentY < groundHeight then
                        currentY = groundHeight
                        velocity = 0  -- Stop movement
                    end
                    
                    -- Limit maximum height above ground
                    local maxHeight = groundHeight + 2
                    if currentY > maxHeight then
                        currentY = maxHeight
                        velocity = 0
                    end
                    
                    -- Store for next frame
                    bone:SetAttribute("velocity", velocity)
                    bone:SetAttribute("currentY", currentY)
                    
                    -- Apply the transform - no wobble, just clean draping
                    bone.Transform = CFrame.new(0, currentY, 0)
                end
            end
        end
    end
end

return BlanketPreview
