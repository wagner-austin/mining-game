--!strict
-- ClothServiceSimple.lua
-- Cloth simulation service with bone-based deformation

local RS = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local MiningGame = RS:WaitForChild("MiningGame")
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
    new: () -> ServiceT,
    spawnFor: (self: ServiceT, player: Player) -> boolean,
    destroyFor: (self: ServiceT, player: Player) -> (),
    step: (self: ServiceT, dt: number) -> (),
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

function Service:spawnFor(player: Player): boolean
    -- Remove existing
    self:destroyFor(player)
    
    -- Get the template
    local Assets = MiningGame:FindFirstChild("Assets")
    if not Assets then 
        log:warn("No Assets folder found")
        return false
    end
    
    local template = Assets:FindFirstChild("BlanketPlane")
    if not template then
        log:warn("No BlanketPlane template found")
        return false
    end
    
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
    
    -- Position it higher up like a hanging curtain
    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if hrp then
        -- Rotate -90 degrees to hang vertically, then 180 around Y to flip
        mesh.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 15, -10)) * CFrame.Angles(math.rad(-90), math.rad(180), 0)
    end
    
    -- Make sure it's anchored and has collision
    mesh.Anchored = true
    mesh.CanCollide = true  -- Enable collision so player can stand on it
    mesh.CanQuery = true     -- Enable raycasting
    mesh.CanTouch = true     -- Enable touch detection
    
    -- Make it wood
    mesh.Material = Enum.Material.Wood
    mesh.Color = Color3.fromRGB(139, 90, 43)  -- Brown wood color
    
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
        
        -- Color code by column
        local m = meta[bone]
        if m then
            -- Different color for each column
            local hue = (m.col - 1) / math.max(numCols - 1, 1)
            sphere.Color = Color3.fromHSV(hue, 1, 1)
            -- Make root bones bigger
            if m.row == 1 then
                sphere.Size = Vector3.new(0.5, 0.5, 0.5)
            end
        else
            sphere.Color = Color3.new(1, 1, 1)
        end
        
        sphere.CFrame = bone.WorldCFrame
        sphere.Transparency = 0  -- Show the debug spheres
        sphere.Parent = model
        debugParts[i] = sphere
    end
    
    -- Generate ID for client sync
    local clothId = HttpService:GenerateGUID(false)
    model:SetAttribute("ClothId", clothId)
    
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
                
                -- Update debug sphere position
                if cloth.debugParts and cloth.debugParts[i] then
                    cloth.debugParts[i].CFrame = bone.WorldCFrame
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

return Service.new()
