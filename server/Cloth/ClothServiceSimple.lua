-- ClothServiceSimple.lua
-- Cloth simulation service with bone-based deformation

local RS = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local InsertService = game:GetService("InsertService")
local HttpService = game:GetService("HttpService")

local MiningGame = RS:WaitForChild("MiningGame")
local GameConfig = require(MiningGame:WaitForChild("GameConfig"))
local Logger = require(MiningGame:WaitForChild("Logger"))
local log = Logger.new("ClothSimple")

local EventBus = require(MiningGame:WaitForChild("EventBus"))
local EventNames = require(MiningGame:WaitForChild("EventNames"))
local Bus = EventBus.global()

local Service = {}
Service.__index = Service

type BoneMeta = { col: number, row: number, rowsInCol: number }
type ClothInstance = {
    id: string,
    model: Model,
    mesh: MeshPart,
    bones: { Bone },
    columns: { { Bone } },
    meta: { [Bone]: BoneMeta },
    numCols: number,
    maxRows: number,
    player: Player,
    debugParts: { Instance },
}
type ServiceT = {
    _cloths: { [Player]: ClothInstance },
    _time: number,
    _frameCount: number?,
    _hbConn: RBXScriptConnection?,
    new: () -> ServiceT,
    spawnFor: (self: ServiceT, player: Player, opts: any?) -> boolean,
    destroyFor: (self: ServiceT, player: Player) -> (),
    step: (self: ServiceT, dt: number) -> (),
    Start: (self: ServiceT, container: any?) -> (),
    Stop: (self: ServiceT) -> (),
}

-- Natural name sort to keep columns stable (e.g. "Col2" before "Col10")
local function nameLess(a: Instance, b: Instance): boolean
    local an = string.match(a.Name, "%d+")
    local bn = string.match(b.Name, "%d+")
    if an and bn and tonumber(an) ~= tonumber(bn) then
        return tonumber(an) < tonumber(bn)
    end
    return a.Name < b.Name
end

-- Build a column-row grid by walking root bones down their child chains
local function buildGrid(mesh: MeshPart, bones: {Bone}): ({ { Bone } }, { [Bone]: BoneMeta }, number, number)
    local isBone = {}
    for _, b in ipairs(bones) do isBone[b] = true end

    local roots = {}
    for _, b in ipairs(bones) do
        local p = b.Parent
        if not (p and p:IsA("Bone")) then
            table.insert(roots, b)
        end
    end
    
    -- Sort columns by X position (more reliable than names)
    table.sort(roots, function(a, b)
        local ax = mesh.CFrame:PointToObjectSpace(a.WorldPosition).X
        local bx = mesh.CFrame:PointToObjectSpace(b.WorldPosition).X
        if math.abs(ax - bx) > 0.01 then return ax < bx end
        return nameLess(a, b) -- tie-breaker
    end)

    local columns = {} :: { { Bone } }
    local meta = {} :: { [Bone]: { col: number, row: number, rowsInCol: number } }
    local maxRows = 0

    for ci, root in ipairs(roots) do
        -- Follow the bone chain down, preferring first child by name
        local col = {}
        local node: Bone? = root
        local r = 1
        while node and isBone[node] do
            table.insert(col, node)
            meta[node] = { col = ci, row = r, rowsInCol = 0 }
            maxRows = math.max(maxRows, r)
            -- Pick next child bone (smallest name) if any
            local nextNode: Bone? = nil
            for _, child in ipairs(node:GetChildren()) do
                if child:IsA("Bone") then
                    if not nextNode or nameLess(child, nextNode) then nextNode = child end
                end
            end
            node = nextNode
            r += 1
        end
        columns[ci] = col
    end

    -- Store total row count for each bone's column
    for ci, col in ipairs(columns) do
        local n = #col
        for _, b in ipairs(col) do
            meta[b].rowsInCol = n
        end
    end

    return columns, meta, #roots, maxRows
end

function Service.new(): ServiceT
    local self = setmetatable({}, Service) :: ServiceT
    self._cloths = {}  -- Active cloth instances
    self._time = 0
    return self
end

-- Cache a template under ReplicatedStorage.MiningGame.Assets for reuse
local BLANKET_ASSET_ID = 116193032143091
local function ensureAssetsFolder(): Folder
    local assets = MiningGame:FindFirstChild("Assets")
    if not assets then
        assets = Instance.new("Folder")
        assets.Name = "Assets"
        assets.Parent = MiningGame
    end
    return assets
end

local function getOrLoadBlanketTemplate(): Instance?
    local Assets = ensureAssetsFolder()
    local existing = Assets:FindFirstChild("BlanketPlane")
    if existing then return existing end

    -- Attempt to load from Roblox if not present locally
    local ok, modelOrErr = pcall(function()
        return InsertService:LoadAsset(BLANKET_ASSET_ID)
    end)
    if not ok or not modelOrErr or not modelOrErr:IsA("Model") then
        log:warn("Failed to LoadAsset(%d): %s", BLANKET_ASSET_ID, tostring(modelOrErr))
        return nil
    end

    -- Find the first MeshPart (or model containing it)
    local mesh: MeshPart? = modelOrErr:FindFirstChildWhichIsA("MeshPart", true)
    local toStore: Instance = mesh or modelOrErr
    toStore.Name = "BlanketPlane"
    toStore.Parent = Assets
    
    -- Skin safety check
    local skin = mesh and mesh:FindFirstChildOfClass("Skin")
    if skin then
        (skin :: any).Enabled = true
    else
        log:warn("BlanketPlane template has no Skin; deformation may be rigid")
    end

    log:info("Cached BlanketPlane under ReplicatedStorage.MiningGame.Assets")
    return toStore
end

function Service:spawnFor(player: Player, opts: any?): boolean
    -- Remove existing
    self:destroyFor(player)
    
    -- Get or load the template (per Blanket docs)
    local template = (function()
        local Assets = ensureAssetsFolder()
        return Assets:FindFirstChild("BlanketPlane") or getOrLoadBlanketTemplate()
    end)()
    if not template then return false end
    
    -- Clone it
    local model = template:Clone()
    model.Name = "SimpleCloth_" .. player.Name
    model.Parent = workspace
    
    -- Find the mesh
    local mesh = model:IsA("MeshPart") and model or model:FindFirstChildWhichIsA("MeshPart")
    if not mesh then
        log:warn("No MeshPart found in template")
        model:Destroy()
        return false
    end

    -- Ensure we operate with a Model container so scaling works reliably
    if not model:IsA("Model") then
        local container = Instance.new("Model")
        container.Name = model.Name
        container.Parent = workspace
        model.Parent = container
        model = container
    end
    
    -- Position it like a hanging curtain (12 up, 10 in front)
    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if hrp then
        local look = (hrp :: any).CFrame.LookVector
        local pos = hrp.Position + look * 10 + Vector3.new(0, 12, 0)
        -- Rotate -90 degrees to hang vertically, then 180 around Y to flip
        mesh.CFrame = CFrame.new(pos) * CFrame.Angles(math.rad(-90), math.rad(180), 0)
    end
    
    -- Make sure it's anchored and has collision
    mesh.Anchored = true
    mesh.CanCollide = true  -- Enable collision so player can stand on it
    mesh.CanQuery = true    -- Enable raycasting
    mesh.CanTouch = true    -- Enable touch detection
    
    -- Visuals per request: deep blue Glass (no Highlight)
    -- Remove any PBR SurfaceAppearance that could override Glass visuals
    local sa = mesh:FindFirstChildOfClass("SurfaceAppearance")
    if sa then sa:Destroy() end
    -- Also ensure no stray Highlight on the model
    for _, child in ipairs(model:GetChildren()) do
        if child:IsA("Highlight") then child:Destroy() end
    end

    mesh.Material = Enum.Material.Glass
    mesh.Color = Color3.fromRGB(10, 30, 170)
    mesh.Transparency = 0.6
    mesh.Reflectance = 0.08
    mesh.CastShadow = false
    if (mesh :: any).MaterialVariant ~= nil then
        (mesh :: any).MaterialVariant = "" -- clear variant to let Glass render normally
    end

    -- Scale down the cloth uniformly (50%)
    do
        local scale = 0.5
        if model:IsA("Model") then
            local ok, err = pcall(function()
                (model :: Model):ScaleTo(scale)
            end)
            if not ok then
                -- Fallback to direct MeshPart size scaling
                local s = mesh.Size
                mesh.Size = Vector3.new(s.X * scale, s.Y * scale, s.Z * scale)
            end
        else
            local s = mesh.Size
            mesh.Size = Vector3.new(s.X * scale, s.Y * scale, s.Z * scale)
        end
    end

    -- Make it a tiny bit wider while maintaining height
    do
        local s = mesh.Size
        local widen = 1.1 -- 10% wider
        mesh.Size = Vector3.new(s.X * widen, s.Y, s.Z)
    end

    -- (Removed uplight pad per request)

    -- No Highlight per user preference
    
    -- Collect all bones
    local bones = {}
    for _, desc in ipairs(mesh:GetDescendants()) do
        if desc:IsA("Bone") then
            table.insert(bones, desc)
        end
    end
    
    -- Build the grid structure
    local columns, meta, numCols, maxRows = buildGrid(mesh, bones)
    
    log:info("Spawned simple cloth for %s: %d bones, %d cols x %d max rows", 
        player.Name, #bones, numCols, maxRows)
    
    -- Create debug visualizers for each bone
    local debugParts = {}
    for i, bone in ipairs(bones) do
        bone:SetAttribute("ClothIdx", i)
        
        -- Create a small sphere at each bone position
        local sphere = Instance.new("Part")
        sphere.Name = "BoneDebug_" .. i
        sphere.Shape = Enum.PartType.Ball
        sphere.Material = Enum.Material.Neon
        sphere.Size = Vector3.new(0.3, 0.3, 0.3)
        sphere.Anchored = true
        sphere.CanCollide = false
        sphere.CanQuery = false
        sphere.CanTouch = false
        
        -- Start all debug spheres as white; size up root bones slightly
        local m = meta[bone]
        sphere.Color = Color3.fromRGB(255, 255, 255)
        if m and m.row == 1 then
            sphere.Size = Vector3.new(0.5, 0.5, 0.5)
        end
        -- Add a point light to emphasize emission separate from color darkness
        local light = Instance.new("PointLight")
        light.Brightness = 5.0
        light.Range = 0.0
        light.Color = sphere.Color
        light.Shadows = false
        light.Parent = sphere
        
        sphere.CFrame = bone.WorldCFrame
        sphere.Transparency = 1.0  -- Fully hidden by default; animated brighter in :step
        sphere.Parent = model
        debugParts[i] = sphere
    end
    
    -- Generate ID for client sync
    local clothId = HttpService:GenerateGUID(false)
    model:SetAttribute("ClothId", clothId)

    -- Create a single GlowBar at the top edge of the cloth, pointing down
    do
        local VIS = GameConfig.Visuals
        -- Make the glow bar thinner than defaults
        local thickness = 0.2 -- thin profile
        local width = 1.0     -- narrow bar
        local extraLen = VIS and VIS.BAR_EXTRA_LENGTH or 2

        local right = mesh.CFrame.RightVector
        local baseWidth = (mesh.Size.X or 12)
        local shortenFactor = 0.9 -- make the glow bar a little less long (~10% shorter)
        local barLength = (baseWidth + extraLen) * shortenFactor

        -- Compute top row using bone metadata for precise placement
        local topBones = {}
        for _, bone in ipairs(bones) do
            local m = meta[bone]
            if m and m.row == 1 then
                table.insert(topBones, bone)
            end
        end

        local barCenter
        if #topBones > 0 then
            local sum = Vector3.new(0,0,0)
            local minProj, maxProj = math.huge, -math.huge
            for _, b in ipairs(topBones) do
                local p = b.WorldPosition
                sum += p
                local t = p:Dot(right)
                if t < minProj then minProj = t end
                if t > maxProj then maxProj = t end
            end
            local avg = sum / #topBones
            barCenter = Vector3.new(avg.X, avg.Y + (thickness * 0.5), avg.Z)
            local span = (maxProj - minProj) + extraLen
            barLength = math.max(2, span * shortenFactor)
        else
            -- Fallback to mesh center and width if no bones found
            local topApprox = mesh.Position + Vector3.new(0, mesh.Size.Y * 0.5, 0)
            barCenter = Vector3.new(topApprox.X, topApprox.Y + (thickness * 0.5), topApprox.Z)
            barLength = math.max(2, (baseWidth + extraLen) * shortenFactor)
        end

        local bar = Instance.new("Part")
        bar.Name = "ClothGlowBar"
        bar.Anchored = true
        bar.CanCollide = false
        bar.CanTouch = false
        bar.CanQuery = false
        bar.CastShadow = false
        bar.Size = Vector3.new(barLength, thickness, width)
        -- Keep bar horizontal; X across cloth width; Bottom face points downward
        local x = right.Unit
        local y = Vector3.new(0, 1, 0)
        local z = x:Cross(y).Unit
        y = z:Cross(x).Unit
        bar.CFrame = CFrame.fromMatrix(barCenter, x, y, z)
        bar.Parent = model
        -- Tag so MaterialManager themes it as a GlowBar (Neon + lights)
        CollectionService:AddTag(bar, "GlowBar")
    end

    -- Store the instance
    self._cloths[player] = {
        id = clothId,
        model = model,
        mesh = mesh,
        bones = bones,
        columns = columns,
        meta = meta,
        numCols = numCols,
        maxRows = maxRows,
        player = player,
        debugParts = debugParts,
    }
    
    return true
end

function Service:destroyFor(player: Player)
    local cloth = self._cloths[player]
    if cloth and cloth.model then
        cloth.model:Destroy()
    end
    self._cloths[player] = nil
end

function Service:step(dt: number)
    self._time = self._time + dt
    local t = self._time
    
    -- Frame counter for debug
    self._frameCount = (self._frameCount or 0) + 1

    -- Wave parameters for curtain movement
    local waveSpeed = 2.0      -- Wave speed
    local waveLength = 3.0     -- Wave length  
    local zAmplitude = 2.0     -- Z movement amplitude
    local stretchAmount = 0.15  -- Vertical stretch between bones

    for player, cloth in pairs(self._cloths) do
        local offsets = table.create(#cloth.bones)
        
        for i, bone in ipairs(cloth.bones) do
            local m = cloth.meta[bone]
            if m then
                -- Calculate base wave for this column
                local u = (m.col - 1) / math.max(cloth.numCols - 1, 1)
                local v = (m.row - 1) / math.max(m.rowsInCol - 1, 1)
                
                -- Root bones (row 1) stay anchored at top
                if m.row == 1 then
                    -- Top row doesn't move - it's the curtain rod
                    bone.Transform = CFrame.new()
                    offsets[i] = {0, 0, 0}  -- Match table format for consistency
                else
                    -- Gravity droop - controlled by stretchAmount
                    local gravityDroop = (m.row - 1) * stretchAmount
                    
                    -- More visible wave motion
                    local waveStrength = v * v  -- Much stronger at bottom
                    local forwardWave = math.sin(waveSpeed * t + u * waveLength * math.pi) * zAmplitude * waveStrength
                    
                    -- Minimal side sway
                    local xSway = math.sin(waveSpeed * t * 0.7 + u * math.pi * 2) * 0.2 * waveStrength
                    
                    -- Y is down, Z is forward/back in rotated bone space
                    bone.Transform = CFrame.new(xSway, gravityDroop, forwardWave * 0.5)
                    -- Send all transform components to client
                    offsets[i] = {xSway, gravityDroop, forwardWave * 0.5}
                end
                
                -- Update debug sphere position and apply "icicle rain" effect with white lights
                local sphere = cloth.debugParts and cloth.debugParts[i]
                if sphere then
                    sphere.CFrame = bone.WorldCFrame
                    sphere.Color = Color3.fromRGB(255, 255, 255)

                    -- Sequential spotlight: brighten one orb at a time (global sweep)
                    local total = #cloth.bones
                    local cycle = 6.0 -- seconds for a full sweep across all orbs
                    local slot = (total > 0) and (cycle / total) or cycle
                    local tCycle = t % cycle
                    local activeIdx = math.clamp(math.floor(tCycle / slot) + 1, 1, math.max(total, 1))
                    local tInSlot = (tCycle % slot) / slot -- 0..1 within current orb's slot
                    local ramp = 1 - math.abs(2 * tInSlot - 1) -- 0->1->0 triangular

                    -- Multiple evenly-spaced active orbs (6 heads) with a short trailing tail behind each head
                    local total = #cloth.bones
                    local cycle = 12.0 -- slower full sweep (base)
                    local N = 6       -- number of simultaneous bright orbs
                    local trail = 2.2 -- trail length in orb indices behind the head
                    local baseRate = 1 / cycle
                    local peak = 0
                    local peakBF = 1.0 -- brightness factor of the contributing head
                    -- Deterministic pseudo-random helper for variation
                    local function h01(x: number): number
                        local s = math.sin(x * 12.9898) * 43758.5453
                        return s - math.floor(s)
                    end
                    for j = 0, N - 1 do
                        -- Slower overall, still varied (~0.2..1.1x base)
                        local speedFactor = 0.2 + 0.9 * h01(j + 1)
                        -- Slight brightness variation per head (~0.8..1.2x)
                        local brightnessFactor = 0.8 + 0.4 * h01(101 + j)
                        local rate = baseRate * speedFactor
                        local phase = (t * rate + j / N) % 1
                        local pos = phase * total -- head position in [0,total)
                        -- distance behind head to this orb index (wrap-safe)
                        local i0 = i - 1
                        local d = pos - i0
                        d = (d % total + total) % total -- wrap into [0,total)
                        if d >= 0 and d <= trail then
                            local x = 1 - (d / trail) -- 1 at head, 0 at end of trail
                            local contrib = x * x      -- sharper near head
                            if contrib > peak then 
                                peak = contrib 
                                peakBF = brightnessFactor
                            end
                        end
                    end

                    if peak > 0 then
                        -- Brighten this orb dramatically using transparency and light
                        sphere.Transparency = math.clamp(1.0 - 0.98 * peak, 0.0, 1.0)
                        local pl = sphere:FindFirstChildOfClass("PointLight")
                        if pl then
                            pl.Color = Color3.fromRGB(255, 255, 255)
                            pl.Range = 0.0
                            pl.Brightness = (2.0 + 28.0 * peak) * peakBF
                        end
                    else
                        -- Fully dim others
                        sphere.Transparency = 1.0
                        local pl = sphere:FindFirstChildOfClass("PointLight")
                        if pl then
                            pl.Range = 0.0
                            pl.Brightness = 0.0
                        end
                    end

                    -- Stable size
                    local s = (m and m.row == 1) and 0.5 or 0.3
                    sphere.Size = Vector3.new(s, s, s)
                end
            else
                offsets[i] = {0, 0, 0}  -- Use table format consistently
            end
        end

        -- Debug log periodically
        if self._frameCount % 60 == 0 then
            local sample = offsets[1]
            local firstValue = type(sample) == "table" and sample[1] or sample or 0
            log:debug("Frame %d: Sending %d offsets to %s, first=%.2f", 
                self._frameCount, #offsets, player.Name, firstValue)
        end
        
        -- Convert {x,y,z} triples to Vector3 for strict typing
        local v3 = table.create(#offsets)
        for i, t in ipairs(offsets) do
            if typeof(t) == "Vector3" then
                v3[i] = t
            elseif type(t) == "table" then
                v3[i] = Vector3.new(t[1] or 0, t[2] or 0, t[3] or 0)
            else
                v3[i] = Vector3.new(0, 0, 0)
            end
        end
        
        -- Send to client (EventBus)
        Bus:emit(EventNames.CLOTH_UPDATE, {
            to = { kind = "player", player = player },
            payload = { id = cloth.id, offsets = v3 }
        })
    end
end

function Service:Start(_container: any?)
    if self._hbConn then return end
    self._hbConn = RunService.Heartbeat:Connect(function(dt)
        -- Protect step from hard errors
        local ok, err = pcall(function()
            self:step(dt)
        end)
        if not ok then
            log:error("ClothServiceSimple step error: %s", tostring(err))
        end
    end)
    log:info("ClothServiceSimple started (Heartbeat connected)")
end

function Service:Stop()
    if self._hbConn then
        self._hbConn:Disconnect()
        self._hbConn = nil
    end
    -- Clean up any remaining cloths
    for player, _ in pairs(self._cloths) do
        self:destroyFor(player)
    end
end

return Service.new()
