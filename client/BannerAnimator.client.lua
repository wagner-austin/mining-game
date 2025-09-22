--!strict
-- BannerAnimator.client.lua
-- Client-side cloth animation for base banners (replaces server per-frame updates)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local EventBus = require(MiningGame:WaitForChild("EventBus"))
local EventNames = require(MiningGame:WaitForChild("EventNames"))
local Time = require(MiningGame:WaitForChild("Time"))

-- Cloth helpers
local ClothFolder = MiningGame:WaitForChild("Cloth")
local ClothBase = require(ClothFolder:WaitForChild("ClothBase"))

local Bus = EventBus.global()

-- Track animated banners by cloth id
type Entry = {
    id: string,
    model: Model,
    mesh: MeshPart,
    bones: { Bone },
    meta: { [Bone]: any },
    numCols: number,
    maxRows: number,
    debugParts: { Instance }?,
    _ancConn: RBXScriptConnection?,
}

local tracked: { [string]: Entry } = {}

local function detach(id: string)
    local e = tracked[id]
    if not e then return end
    -- cleanup local debug parts
    if e.debugParts then
        for _, p in ipairs(e.debugParts) do
            if p and p.Parent then p:Destroy() end
        end
        e.debugParts = nil
    end
    if e._ancConn then pcall(function() e._ancConn:Disconnect() end) end
    tracked[id] = nil
end

local function normalizeBones(mesh: MeshPart): { Bone }
    -- Prefer ClothIdx ordering if present; else collect in discovery order
    local byIdx: { [number]: Bone } = {}
    local maxIdx = 0
    for _, d in ipairs(mesh:GetDescendants()) do
        if d:IsA("Bone") then
            local idx = d:GetAttribute("ClothIdx")
            if typeof(idx) == "number" and idx >= 1 then
                byIdx[idx] = d
                if idx > maxIdx then maxIdx = idx end
            end
        end
    end
    local bones: { Bone } = {}
    if maxIdx > 0 then
        for i = 1, maxIdx do
            local b = byIdx[i]
            if b then table.insert(bones, b) end
        end
    else
        for _, d in ipairs(mesh:GetDescendants()) do
            if d:IsA("Bone") then table.insert(bones, d) end
        end
    end
    return bones
end

local function mountBanner(model: Model, id: string)
    if tracked[id] and tracked[id].model == model then return end
    local mesh = (model:IsA("MeshPart") and model) or model:FindFirstChildWhichIsA("MeshPart")
    if not mesh then return end

    local bones = normalizeBones(mesh)
    if #bones == 0 then return end

    -- Build grid metadata for computeOffsets
    local columns, meta, numCols, maxRows = ClothBase.buildGrid(mesh, bones)

    local ancConn = model.AncestryChanged:Connect(function(_, parent)
        if not parent then detach(id) end
    end)

    tracked[id] = {
        id = id,
        model = model,
        mesh = mesh,
        bones = bones,
        meta = meta,
        numCols = numCols,
        maxRows = maxRows,
        debugParts = nil,
        _ancConn = ancConn,
    }
end

-- Listen for server banner readiness (explicit models provided)
Bus:on(EventNames.BANNER_READY, function(evt)
    local banners = evt and evt.banners
    if type(banners) ~= "table" then return end
    for _, b in ipairs(banners) do
        if typeof(b) == "Instance" then
            local m: Instance = b
            if m:IsA("Model") then
                local cid = (m:GetAttribute("ClothId"))
                if type(cid) == "string" then mountBanner(m, cid) end
            end
        elseif type(b) == "table" then
            local m = b.model
            local cid = b.id
            if typeof(m) == "Instance" and m:IsA("Model") and type(cid) == "string" then
                mountBanner(m, cid)
            end
        end
    end
end)

-- Lightweight animator: 30 FPS target, distance-culling
local ACCUM = 0
local STEP = 1/30 -- ~33ms
local MAX_DIST = 300 -- studs

-- Simple deterministic phase from cloth id
local function idPhase(id: string): number
    local h = 0
    for i = 1, #id do h = (h * 257 + string.byte(id, i)) % 100000 end
    return (h % 628) / 100 -- [0, 6.28)
end

-- Optional bone lighting orbs (client-local; no network replication)
local function ensureDebugParts(e: Entry)
    if e.debugParts then return end
    -- If server (Studio) already made debug parts, adopt them
    local adopt = e.model:FindFirstChild("BoneDebug_1")
    local parts = table.create(#e.bones)
    if adopt then
        for i = 1, #e.bones do
            local p = e.model:FindFirstChild("BoneDebug_" .. i)
            if p and p:IsA("BasePart") then
                parts[i] = p
            end
        end
        e.debugParts = parts
        return
    end

    for i, bone in ipairs(e.bones) do
        local sphere = Instance.new("Part")
        sphere.Name = "BoneDebug_" .. i
        sphere.Shape = Enum.PartType.Ball
        sphere.Material = Enum.Material.Neon
        sphere.Size = Vector3.new(0.3, 0.3, 0.3)
        sphere.Anchored = true
        sphere.CanCollide = false
        sphere.CanQuery = false
        sphere.CanTouch = false
        sphere.CastShadow = false
        sphere.Color = Color3.fromRGB(255, 255, 255)
        sphere.Transparency = 1.0 -- hidden until lit
        local pl = Instance.new("PointLight")
        pl.Brightness = 0
        pl.Range = 0
        pl.Shadows = false
        pl.Color = sphere.Color
        pl.Parent = sphere
        sphere.CFrame = bone.WorldCFrame
        sphere.Parent = e.model
        parts[i] = sphere
    end
    e.debugParts = parts
end

local function cleanupDebugParts(e: Entry)
    if not e.debugParts then return end
    for _, p in ipairs(e.debugParts) do
        if p and p.Parent then p:Destroy() end
    end
    e.debugParts = nil
end

RunService.RenderStepped:Connect(function(dt)
    ACCUM += dt
    if ACCUM < STEP then return end
    ACCUM -= STEP

    local cam = Workspace.CurrentCamera
    local camPos = cam and cam.CFrame.Position
    local t = Time.unix() -- server-synced clock on client

    for id, e in pairs(tracked) do
        if not e.model.Parent or not e.mesh.Parent then
            cleanupDebugParts(e)
            detach(id)
        else
            local visible = true
            if camPos then
                local dist = (e.mesh.Position - camPos).Magnitude
                visible = dist <= MAX_DIST
            end
            if visible then
                local inst = {
                    id = e.id,
                    model = e.model,
                    mesh = e.mesh,
                    bones = e.bones,
                    columns = nil,
                    meta = e.meta,
                    numCols = e.numCols,
                    maxRows = e.maxRows,
                    debugParts = e.debugParts,
                } :: any

                local offsets = ClothBase.computeOffsets(inst, t + idPhase(id), {
                    waveSpeed = 2.0,
                    waveLength = 3.0,
                    zAmplitude = 1.0,
                    stretchAmount = 0.12,
                })
                for i, bone in ipairs(e.bones) do
                    local v = offsets[i]
                    if typeof(v) == "Vector3" then
                        bone.Transform = CFrame.new(v.X, v.Y, v.Z)
                    else
                        bone.Transform = CFrame.new()
                    end
                end

                -- Update client-local bone lighting orbs
                ensureDebugParts(e)
                inst.debugParts = e.debugParts
                ClothBase.updateDebug(inst, t)
            end
        end
    end
end)
