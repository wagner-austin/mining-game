--!strict
-- SpawnBaseBanner.server.lua
-- Spawns one or more scenic cloth banners at each player's base.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local EventBus = require(MiningGame:WaitForChild("EventBus"))
local EventNames = require(MiningGame:WaitForChild("EventNames"))
local ClothBase = require(MiningGame:WaitForChild("Cloth"):WaitForChild("ClothBase"))
local Logger = require(MiningGame:WaitForChild("Logger"))

local log = Logger.new("SpawnBaseBanner")
local Bus = EventBus.global()
local BannerConfig = require(script.Parent:WaitForChild("BannerConfig"))

local function TUNE()
    return BannerConfig.get()
end

-- Asset cache
local BLANKET_ASSET_ID = 116193032143091
local function getTemplate(): Instance?
    local assets = MiningGame:FindFirstChild("Assets")
    local t = assets and assets:FindFirstChild("BlanketPlane")
    if t then return t end
    local ok, modelOrErr = pcall(function()
        return InsertService:LoadAsset(BLANKET_ASSET_ID)
    end)
    if ok and modelOrErr and modelOrErr:IsA("Model") then
        local mesh = modelOrErr:FindFirstChildWhichIsA("MeshPart", true)
        local toStore: Instance = mesh or modelOrErr
        toStore.Name = "BlanketPlane"
        if not assets then
            assets = Instance.new("Folder")
            assets.Name = "Assets"
            assets.Parent = MiningGame
        end
        toStore.Parent = assets
        local skin = mesh and mesh:FindFirstChildOfClass("Skin")
        if skin then (skin :: any).Enabled = true end
        return toStore
    else
        log:warn("LoadAsset(%d) failed: %s", BLANKET_ASSET_ID, tostring(modelOrErr))
    end
    return nil
end

-- Track spawned cloth per-player for cleanup
local spawned: { [Player]: { ClothBase.ClothInstance } } = {}
local tAccum = 0

-- Heartbeat: animate all banners (broadcast to all clients)
RunService.Heartbeat:Connect(function(dt)
    tAccum += dt
    for _player, list in pairs(spawned) do
        for _, inst in ipairs(list) do
            local offsets = ClothBase.computeOffsets(inst, tAccum, {
                waveSpeed = 2.0,
                waveLength = 3.0,
                zAmplitude = 1.0,
                stretchAmount = 0.12,
            })
            -- Apply transforms on the server so debug spheres map to bones (client still gets offsets for visual deform)
            for i, bone in ipairs(inst.bones) do
                local v = offsets[i]
                if typeof(v) == "Vector3" then
                    bone.Transform = CFrame.new(v.X, v.Y, v.Z)
                else
                    bone.Transform = CFrame.new()
                end
            end
            Bus:emit(EventNames.CLOTH_UPDATE, {
                to = { kind = "all" },
                payload = { id = inst.id, offsets = offsets },
            })
            -- Update debug spheres
            pcall(function()
                ClothBase.updateDebug(inst, tAccum)
            end)
        end
    end
end)

local function waitForPlayerBase(player: Player): Model?
    local basesFolder = workspace:FindFirstChild("PlayerBases") or workspace:WaitForChild("PlayerBases", 30)
    if not basesFolder then return nil end
    local name = string.format("PlayerBase_%d", player.UserId)
    local deadline = time() + 30
    while time() < deadline do
        local m = basesFolder:FindFirstChild(name)
        if m and m:IsA("Model") then return m end
        task.wait(0.25)
    end
    return nil
end

local function spawnBannerFor(player: Player)
    -- Despawn previous
    local prevList = spawned[player]
    if prevList then
        for _, inst in ipairs(prevList) do
            pcall(function() inst.model:Destroy() end)
        end
    end
    spawned[player] = {}

    local baseModel = waitForPlayerBase(player)
    if not baseModel then
        log:warn("No base model for %s", player.Name)
        return
    end

    -- Anchors
    local petsAnchor = baseModel:FindFirstChild("PetsAnchor_Anchor") or baseModel:WaitForChild("PetsAnchor_Anchor", 10)
    local hsAnchor = baseModel:FindFirstChild("HighScoreAnchor_Anchor") or baseModel:WaitForChild("HighScoreAnchor_Anchor", 10)
    local shopAnchor = baseModel:FindFirstChild("ShopAnchor_Anchor") or baseModel:WaitForChild("ShopAnchor_Anchor", 10)
    if not petsAnchor or not hsAnchor or not shopAnchor then
        log:warn("Missing one or more base anchors for %s", player.Name)
        return
    end

    local template = getTemplate()
    if not template then
        log:warn("No cloth template available")
        return
    end

    local function spawnAt(alongZT: number, inwardXT: number, index: number, slot: any?)
        local slotColor: Color3 = ((slot and slot.color) and (slot.color :: any)) or (TUNE().COLOR or Color3.fromRGB(10, 30, 170))
        local inst = ClothBase.spawnFromTemplate(template, {
            parent = baseModel,
            name = "BaseBanner",
            anchored = true,
            canCollide = true,
            canQuery = true,
            canTouch = true,
            visual = {
                material = Enum.Material.Glass,
                color = slotColor,
                transparency = 0.6,
                reflectance = 0.08,
                castShadow = false,
                clearSurfaceAppearance = true,
                clearHighlights = true,
                materialVariant = "",
            },
            scale = 0.5,
            widen = 1.1,
            idAttribute = "ClothId",
            makeDebugSpheres = true,
            glowBar = {
                enabled = true,
                thickness = 0.2,
                width = 1.0,
                extraLen = 2.0,
                shortenFactor = 0.9,
                colorOverride = (TUNE().MATCH_GLOW_TO_BANNER and slotColor or nil),
            },
        })

        local clearanceY = TUNE().LIFT_Y
        local pitchDeg = TUNE().PITCH_X_DEG or 0
        local pmod = pitchDeg % 180
        local height = (math.abs(pmod - 90) < 1e-3) and inst.mesh.Size.Z or inst.mesh.Size.Y
        local leftEdgeX = math.min(hsAnchor.Position.X, petsAnchor.Position.X)
        local rightEdgeX = shopAnchor.Position.X
        local baseFloorY = math.min(hsAnchor.Position.Y, petsAnchor.Position.Y)
        local frontZ = hsAnchor.Position.Z
        local backZ = petsAnchor.Position.Z
        local t = math.clamp(alongZT or 1, 0, 1)
        local edgeZ = frontZ + (backZ - frontZ) * t
        local centerZ = edgeZ + (TUNE().INSIDE_Z or 0)
        local fx = math.clamp(inwardXT or 0, 0, 1)
        local centerX = leftEdgeX + (rightEdgeX - leftEdgeX) * fx
        local center = Vector3.new(centerX, baseFloorY + clearanceY + height * 0.5, centerZ)
        local yawDeg = TUNE().YAW_Y_DEG or 0
        local rollDeg = TUNE().ROLL_Z_DEG or 0
        inst.model:PivotTo(CFrame.new(center) * CFrame.Angles(math.rad(pitchDeg), math.rad(yawDeg), math.rad(rollDeg)))

        if inst.debugParts then
            for _, p in ipairs(inst.debugParts :: any) do
                if p and p:IsA("BasePart") then p.Transparency = 0.2 end
            end
        end

        pcall(function()
            inst.model.Name = ("BaseBanner_%s_%d"):format(string.sub(inst.id, 1, 8), index)
        end)
        table.insert(spawned[player], inst)
    end

    local slots = (BannerConfig.get().SLOTS :: any)
    if type(slots) == "table" and #slots > 0 then
        for i, s in ipairs(slots) do
            spawnAt(s.alongZT or (TUNE().ALONG_Z_T or 1.0), s.inwardXT or (TUNE().INWARD_X_T or 0.0), i, s)
        end
        log:info("Spawned %d banners for %s", #slots, player.Name)
    else
        spawnAt(TUNE().ALONG_Z_T or 1.0, TUNE().INWARD_X_T or 0.0, 1)
        log:info("Spawned banner for %s", player.Name)
    end
end

local function onPlayerAdded(player: Player)
    task.defer(function()
        spawnBannerFor(player)
        task.wait(2)
        if not spawned[player] or #spawned[player] == 0 then
            spawnBannerFor(player)
        end
    end)
end

local function onPlayerRemoving(player: Player)
    local list = spawned[player]
    if list then
        for _, inst in ipairs(list) do pcall(function() inst.model:Destroy() end) end
    end
    spawned[player] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, plr in ipairs(Players:GetPlayers()) do onPlayerAdded(plr) end
