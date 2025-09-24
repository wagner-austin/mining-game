--!strict
-- BannerService.lua
-- Spawns scenic cloth banners at each player's base (event-driven, service-integrated)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- local CollectionService = game:GetService("CollectionService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local EventBus = require(MiningGame:WaitForChild("EventBus"))
local EventNames = require(MiningGame:WaitForChild("EventNames"))
local ClothBase = require(MiningGame:WaitForChild("Cloth"):WaitForChild("ClothBase"))
local Logger = require(MiningGame:WaitForChild("Logger"))
local ErrorService = require(script.Parent:WaitForChild("ErrorService"))

local log = Logger.new("BannerService")
local Bus = EventBus.global()

-- Config lives under ServerScriptService/Cloth
local BannerConfig = require(ServerScriptService:WaitForChild("Cloth"):WaitForChild("BannerConfig"))

local function TUNE()
    return BannerConfig.get()
end

-- Asset cache
local BLANKET_ASSET_ID = 116193032143091
local function getTemplate(): Instance?
    local assets = MiningGame:FindFirstChild("Assets")
    local t = assets and assets:FindFirstChild("BlanketPlane")
    if t then return t end

    -- Studio-only load to avoid runtime failures
    if RunService:IsStudio() then
        local InsertService = game:GetService("InsertService")
        local ok2, modelOrErr = ErrorService.safecall("BannerService.LoadAsset", function()
            return InsertService:LoadAsset(BLANKET_ASSET_ID)
        end)
        if ok2 and modelOrErr and modelOrErr:IsA("Model") then
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
    else
        -- In live/server runs, fall back to a simple MeshPart if asset isn't preloaded
        log:warn("BlanketPlane asset missing and not in Studio; using simple MeshPart fallback")
        if not assets then
            assets = Instance.new("Folder")
            assets.Name = "Assets"
            assets.Parent = MiningGame
        end
        local mp = Instance.new("MeshPart")
        mp.Name = "BlanketPlane"
        mp.Size = Vector3.new(12, 10, 0.5)
        mp.Anchored = true
        mp.CanCollide = false
        mp.CanQuery = false
        mp.CanTouch = false
        mp.CastShadow = false
        mp.Material = Enum.Material.Plastic
        mp.Parent = assets
        return mp
    end
    return nil
end

-- Track spawned cloth per-player for cleanup
type ClothInstance = ClothBase.ClothInstance
local spawned: { [Player]: { ClothInstance } } = {}

local function spawnFor(player: Player, baseModel: Model)
    -- Despawn previous
    local prevList = spawned[player]
    if prevList then
        for _, inst in ipairs(prevList) do
            ErrorService.safecall("BannerService.DestroyPrev", function()
                inst.model:Destroy()
            end)
        end
    end
    spawned[player] = {}

    local petsAnchor = baseModel:FindFirstChild("PetsAnchor_Anchor") or baseModel:WaitForChild("PetsAnchor_Anchor", 10)
    local hsAnchor = baseModel:FindFirstChild("HighScoreAnchor_Anchor") or baseModel:WaitForChild("HighScoreAnchor_Anchor", 10)
    local shopAnchor = baseModel:FindFirstChild("ShopAnchor_Anchor") or baseModel:WaitForChild("ShopAnchor_Anchor", 10)
    if not petsAnchor or not hsAnchor or not shopAnchor then
        log:warn("Missing one or more base anchors for %s", player.Name)
        return
    end

    local template = getTemplate()
    if not template then return end

    -- Collect explicit banner info for client to avoid attribute race
    local ready: { { model: Model, feature: string, category: string, face: string, color: Color3 } } = {}

    local function spawnAt(alongZT: number, inwardXT: number, index: number, slot: any?)
        local slotColor: Color3 = ((slot and slot.color) and (slot.color :: any)) or (TUNE().COLOR or Color3.fromRGB(10, 30, 170))
        local feature: string? = (slot and slot.feature) or TUNE().FEATURE
        local category: string = (slot and slot.category) or (TUNE().CATEGORY or "")
        local faceStr: string = (slot and slot.face) or (TUNE().FACE or "Front")

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
            -- Only create debug spheres in Studio to avoid network overhead in live servers
            makeDebugSpheres = false,
            glowBar = {
                enabled = true,
                thickness = 0.2,
                width = 1.0,
                extraLen = 2.0,
                shortenFactor = 0.9,
                colorOverride = (TUNE().MATCH_GLOW_TO_BANNER and slotColor or nil),
            },
        })

        -- Annotate for client billboards
        ErrorService.safecall("BannerService.TagAttributes", function()
            if feature ~= nil then inst.model:SetAttribute("BannerFeature", feature) end
            inst.model:SetAttribute("BannerCategory", category)
            inst.model:SetAttribute("BannerSlotIndex", index)
            inst.model:SetAttribute("BannerColor", slotColor)
            inst.model:SetAttribute("BannerFace", faceStr)
        end)

        -- Ensure PrimaryPart + anchor
        ErrorService.safecall("BannerService.AnchorAndUIPanel", function()
            if inst.mesh and inst.mesh:IsA("BasePart") then
                inst.model.PrimaryPart = inst.mesh
                local anchor = inst.mesh:FindFirstChild("BillboardAnchor")
                if not anchor then
                    local a = Instance.new("Attachment")
                    a.Name = "BillboardAnchor"
                    local sz = inst.mesh.Size
                    a.Position = Vector3.new(0, (sz.Y > 0 and sz.Y or 4) * 0.55, 0)
                    a.Parent = inst.mesh
                end

                -- Create an invisible UI panel part with axes aligned so Front face's vertical is the banner's tall axis
                local panel = inst.model:FindFirstChild("UIPanel")
                if not panel then
                    local p = Instance.new("Part")
                    p.Name = "UIPanel"
                    p.Anchored = true
                    p.CanCollide = false
                    p.CanTouch = false
                    p.CanQuery = false
                    p.CastShadow = false
                    p.Transparency = 1
                    -- Determine panel size relative to cloth so UI fills a readable area
                    local s = inst.mesh.Size
                    local tallLocal = (s.Z >= s.Y) and s.Z or s.Y
                    local wideLocal = s.X
                    -- Slightly reduce width so billboards don’t feel edge-to-edge
                    local panelWidth = math.max(12, wideLocal * 0.78)
                    -- Make the UI face physically taller so text reads larger in-world
                    local panelHeight = math.max(8, tallLocal * 1.05)
                    local panelThickness = 0.05
                    p.Size = Vector3.new(panelWidth, panelHeight, panelThickness)

                    -- Determine tall axis in world space (prefer Z if longer than Y)
                    local tallWorld = (s.Z >= s.Y) and inst.mesh.CFrame.LookVector or inst.mesh.CFrame.UpVector
                    local up = tallWorld.Unit
                    -- Pick a reference that's not parallel to up
                    local ref = math.abs(up:Dot(Vector3.new(0,1,0))) < 0.99 and Vector3.new(0,1,0) or Vector3.new(1,0,0)
                    local right = up:Cross(ref).Unit
                    local look = right:Cross(up).Unit
                    -- Slight offset forward to avoid z-fighting when using Front face
                    local pos = inst.mesh.Position + look * (panelThickness * 0.5 + 0.03)
                    p.CFrame = CFrame.fromMatrix(pos, right, up, look)
                    p.Parent = inst.model
                    panel = p
                end
                if not panel then
                    log:warn("UIPanel creation failed for %s", tostring(inst.model))
                end
            end
        end)

        -- Tag will be added after all setup is complete

        -- Compute placement against anchors
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
        log:info("Banner slot %d placed: pitch=%d yaw=%d roll=%d", index, pitchDeg, yawDeg, rollDeg)

        if inst.debugParts then
            for _, p in ipairs(inst.debugParts :: any) do if p and p:IsA("BasePart") then p.Transparency = 0.2 end end
        end

        ErrorService.safecall("BannerService.NameBanner", function()
            inst.model.Name = ("BaseBanner_%s_%d"):format(string.sub(inst.id, 1, 8), index)
        end)
        table.insert(spawned[player], inst)

        -- Queue explicit banner info for client (mounts without waiting for attribute replication)
        local feat = (type(feature) == "string" and feature) or ""
        table.insert(ready, {
            id = inst.id,
            model = inst.model,
            feature = feat,
            category = category,
            face = faceStr,
            color = slotColor,
        })
        
        -- Banner setup complete - event bus will notify clients
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

    -- Announce ready (route directly to this player) and re-emit briefly to catch late listeners
    ErrorService.safecall("BannerService.EmitReady", function()
        local target = { kind = "player", player = player }
        local payload = { banners = ready }
        Bus:emit(EventNames.BANNER_READY, { to = target, payload = payload })
        task.delay(1.0, function()
            Bus:emit(EventNames.BANNER_READY, { to = target, payload = payload })
        end)
        task.delay(2.0, function()
            Bus:emit(EventNames.BANNER_READY, { to = target, payload = payload })
        end)
    end)

    -- Cloth animation is handled client-side by BannerAnimator.client.lua
end

local Service = {}
Service.__index = Service

function Service:Init(container)
    log:info("Initialized")
end

function Service:Start(container)
    -- On player leave, cleanup
    Players.PlayerRemoving:Connect(function(player)
        local list = spawned[player]
        if list then
            for _, inst in ipairs(list) do
                ErrorService.safecall("BannerService.DestroyOnLeave", function()
                    inst.model:Destroy()
                end)
            end
        end
        spawned[player] = nil
        ErrorService.safecall("BannerService.EmitRemoved", function()
            Bus:emit(EventNames.BANNER_REMOVED, { to = { kind = "player", player = player } })
        end)
    end)

    -- On player join, send current banners so late joiners see billboards
    Players.PlayerAdded:Connect(function(viewer)
        ErrorService.safecall("BannerService.EmitReadyOnJoin", function()
            local all = {}
            for _owner, list in pairs(spawned) do
                for _, inst in ipairs(list) do
                    local m = inst.model
                    if m and m:IsA("Model") then
                        table.insert(all, {
                            id = inst.id,
                            model = m,
                            feature = (m:GetAttribute("BannerFeature") or ""),
                            category = (m:GetAttribute("BannerCategory") or ""),
                            face = (m:GetAttribute("BannerFace") or "Front"),
                            color = m:GetAttribute("BannerColor"),
                        })
                    end
                end
            end
            if #all > 0 then
                Bus:emit(EventNames.BANNER_READY, { to = { kind = "player", player = viewer }, payload = { banners = all } })
            end
        end)
    end)

    -- Spawn banners when the player's base is ready
    Bus:on(EventNames.PLAYER_BASE_READY, function(evt)
        local to = evt and evt.to
        local player = to and to.player
        local payload = evt and evt.payload
        local baseModel = payload and payload.baseModel
        if player and player.Parent and baseModel and baseModel:IsA("Model") then
            spawnFor(player, baseModel)
        end
    end)

    -- Handle bases pre-existing (e.g., Studio hot reload)
    local basesFolder = workspace:FindFirstChild("PlayerBases")
    if basesFolder then
        for _, m in ipairs(basesFolder:GetChildren()) do
            if m:IsA("Model") then
                local name = m.Name
                local uid = name:match("PlayerBase_(%d+)")
                if uid then
                    local userId = tonumber(uid)
                    local player = userId and Players:GetPlayerByUserId(userId) or nil
                    if player then spawnFor(player, m) end
                end
            end
        end
    end

    log:info("Started")
end

return Service
