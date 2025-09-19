-- SimpleClothService.lua
-- Cloth simulation service with bone-based deformation

local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local InsertService = game:GetService("InsertService")

local MiningGame = RS:WaitForChild("MiningGame")
local GameConfig = require(MiningGame:WaitForChild("GameConfig"))
local Logger = require(MiningGame:WaitForChild("Logger"))
local log = Logger.new("SimpleClothService")

local EventBus = require(MiningGame:WaitForChild("EventBus"))
local EventNames = require(MiningGame:WaitForChild("EventNames"))
local Bus = EventBus.global()

local ClothBase = require(MiningGame:WaitForChild("Cloth"):WaitForChild("ClothBase"))

local Service = {}
Service.__index = Service

type BoneMeta = { col: number, row: number, rowsInCol: number }
type ClothInstance = ClothBase.ClothInstance & { player: Player }
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
-- Grid building moved to ClothBase.buildGrid

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
    
    -- Compute placement cframe: hang vertically (12 up, 10 forward) facing player
    local placeCFrame: CFrame? = nil
    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if hrp then
        local look = (hrp :: any).CFrame.LookVector
        local pos = hrp.Position + look * 10 + Vector3.new(0, 12, 0)
        placeCFrame = CFrame.new(pos) * CFrame.Angles(math.rad(-90), math.rad(180), 0)
    end

    -- Spawn via reusable base with visuals and effects
    local VIS = GameConfig.Visuals
    local inst = ClothBase.spawnFromTemplate(template, {
        parent = workspace,
        name = "SimpleCloth_" .. player.Name,
        cframe = placeCFrame,
        anchored = true,
        canCollide = true,
        canQuery = true,
        canTouch = true,
        visual = {
            material = Enum.Material.Glass,
            color = Color3.fromRGB(10, 30, 170),
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
        makeDebugSpheres = true, -- keep the icicle effect
        glowBar = {
            enabled = true,
            thickness = 0.2,
            width = 1.0,
            extraLen = (VIS and VIS.BAR_EXTRA_LENGTH) or 2,
            shortenFactor = 0.9,
        },
    })

    log:info(
        "Spawned simple cloth for %s: %d bones, %d cols x %d max rows",
        player.Name,
        #inst.bones,
        inst.numCols,
        inst.maxRows
    )

    -- Store the instance
    self._cloths[player] = (table.freeze or function(t) return t end)(({
        id = inst.id,
        model = inst.model,
        mesh = inst.mesh,
        bones = inst.bones,
        columns = inst.columns,
        meta = inst.meta,
        numCols = inst.numCols,
        maxRows = inst.maxRows,
        debugParts = inst.debugParts,
        player = player,
    }) :: any)
    
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

    for player, cloth in pairs(self._cloths) do
        -- Compute motion offsets from base class
        local offsetsV3 = ClothBase.computeOffsets(
            (cloth :: any) :: ClothBase.ClothInstance,
            t,
            {
                waveSpeed = 2.0,
                waveLength = 3.0,
                zAmplitude = 2.0,
                stretchAmount = 0.15,
            }
        )

        -- Apply transforms on server for debug spheres/world attachments (does not visually deform mesh on clients)
        for i, bone in ipairs(cloth.bones) do
            local m = cloth.meta[bone]
            local off = offsetsV3[i] or Vector3.new()
            if m and m.row == 1 then
                bone.Transform = CFrame.new()
            else
                bone.Transform = CFrame.new(off.X, off.Y, off.Z)
            end
        end

        -- Optional debug visuals update
        ClothBase.updateDebug((cloth :: any) :: ClothBase.ClothInstance, t)

        -- Debug log periodically
        if self._frameCount % 60 == 0 then
            local sample = offsetsV3[1]
            local firstValue = (typeof(sample) == "Vector3") and sample.X or 0
            log:debug("Frame %d: Sending %d offsets to %s, first=%.2f", 
                self._frameCount, #offsetsV3, player.Name, firstValue)
        end
        
        -- Send to client (EventBus)
        Bus:emit(EventNames.CLOTH_UPDATE, {
            to = { kind = "player", player = player },
            payload = { id = cloth.id, offsets = offsetsV3 }
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
            log:error("SimpleClothService step error: %s", tostring(err))
        end
    end)
    log:info("SimpleClothService started (Heartbeat connected)")
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
