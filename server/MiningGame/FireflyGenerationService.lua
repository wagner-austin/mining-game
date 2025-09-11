--!strict
-- FireflyGenerationService.lua
-- Dedicated service for spawning ambient firefly particle clusters

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(Shared:WaitForChild("Logger"))
local Time = require(Shared:WaitForChild("Time"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local ServiceValidator = require(Shared:WaitForChild("ServiceValidator"))
local PCGConfig = require(Shared:WaitForChild("PCGConfig"))
local EventBus = require(Shared:WaitForChild("EventBus"))
local EventNames = require(Shared:WaitForChild("EventNames"))
local EventContracts = require(Shared:WaitForChild("EventContracts"))
local WorldGenUtils = require(Shared:WaitForChild("WorldGenUtils"))

local log = Logger.new("FireflyGenerationService")
local Bus = EventBus.global()

local FireflyGenerationService = {}
local _eventsRegistered = false
local _lastStats = { count = 0, seed = 0, bounds = nil :: any }

export type GenerateOpts = {
    bounds: {minX: number, maxX: number, minZ: number, maxZ: number}?,
    center: Vector3?, sizeX: number?, sizeZ: number?,
    densityPer100x100: number?, minCount: number?, maxCount: number?, count: number?,
    allowWater: boolean?, seed: number?, minSpacing: number?, playerKeepoutRadius: number?,
    parentFolder: Instance?, phase: string?, allowedPhases: {string}?,
}

local CubePositionService: any = nil

function FireflyGenerationService:Init(container)
    CubePositionService = ServiceValidator.tryGet(container, "CubePositionService")
    log:info("Initialized%s", CubePositionService and " (CubePositionService wired)" or "")

    if not _eventsRegistered then
        Bus:on(EventNames.FIREFLY_SPAWN_REQUEST, function(msg)
            local ok, payload = pcall(EventContracts.FIREFLY_SPAWN_REQUEST, msg.payload)
            if not ok then log:warn("Invalid FIREFLY_SPAWN_REQUEST payload") return end
            local positions = self:GenerateInArea(payload)
            log:info("Generated %d firefly clusters via event", positions and #positions or 0)
        end)
        Bus:on(EventNames.FIREFLY_CLEAR_REQUEST, function(msg)
            local ok = pcall(EventContracts.FIREFLY_CLEAR_REQUEST, msg.payload)
            if not ok then log:warn("Invalid FIREFLY_CLEAR_REQUEST payload") return end
            self:ClearAll()
        end)
        _eventsRegistered = true
        log:info("Event listeners registered")
    end
end

function FireflyGenerationService:Start() end

local function spawnCluster(ground: Vector3, rng: Random, parent: Instance): Instance
    local anchor = Instance.new("Part")
    anchor.Name = "FireflyAnchor"
    anchor.Size = Vector3.new(1,1,1)
    anchor.Anchored = true
    anchor.CanCollide = false
    anchor.CanQuery = false
    anchor.CanTouch = false
    anchor.Transparency = 1
    anchor.Position = ground + Vector3.new(rng:NextNumber(-10,10), rng:NextNumber(8,30), rng:NextNumber(-10,10))
    anchor.Parent = parent

    local particles = Instance.new("ParticleEmitter")
    particles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    particles.Rate = 3
    particles.Lifetime = NumberRange.new(20, 35)
    particles.Speed = NumberRange.new(0.5, 2)
    particles.VelocitySpread = 360
    particles.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(0.5, 0),
        NumberSequenceKeypoint.new(1, 0.3)
    })
    particles.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.5, 1.5),
        NumberSequenceKeypoint.new(1, 0.8)
    })
    particles.Color = ColorSequence.new(Color3.fromRGB(255,255,180))
    particles.LightEmission = 1
    particles.Parent = anchor

    local light = Instance.new("PointLight")
    light.Brightness = 1.5
    light.Range = 20
    light.Color = Color3.fromRGB(255,255,180)
    light.Parent = anchor
    return anchor
end

function FireflyGenerationService:GenerateInArea(opts: GenerateOpts): {Vector3}
    opts = opts or {}

    -- Phase filter
    if (opts :: any).phase or (opts :: any).allowedPhases then
        local phase = WorldGenUtils.getDayNightPhase()
        local allowed = false
        if (opts :: any).allowedPhases and type((opts :: any).allowedPhases) == "table" then
            for _, p in ipairs((opts :: any).allowedPhases) do if p == phase then allowed = true break end end
        elseif (opts :: any).phase and type((opts :: any).phase) == "string" then
            allowed = ((opts :: any).phase == "any") or ((opts :: any).phase == phase)
        else
            allowed = true
        end
        if not allowed then
            log:info("Phase mismatch (%s) -> skipping firefly generation", phase)
            return {}
        end
    end

    local minX, maxX, minZ, maxZ
    if opts.bounds then
        minX, maxX, minZ, maxZ = opts.bounds.minX, opts.bounds.maxX, opts.bounds.minZ, opts.bounds.maxZ
    elseif opts.center and opts.sizeX and opts.sizeZ then
        minX = opts.center.X - opts.sizeX * 0.5
        maxX = opts.center.X + opts.sizeX * 0.5
        minZ = opts.center.Z - opts.sizeZ * 0.5
        maxZ = opts.center.Z + opts.sizeZ * 0.5
    else
        error("GenerateInArea requires bounds or center+sizeX+sizeZ")
    end

    local density = opts.densityPer100x100 or (GameConfig.Decorations and GameConfig.Decorations.FIREFLIES_PER_100x100) or 0.6
    local minCount = opts.minCount or (GameConfig.Decorations and GameConfig.Decorations.MIN_FIREFLIES) or 10
    local maxCount = opts.maxCount or (GameConfig.Decorations and GameConfig.Decorations.MAX_FIREFLIES) or 120
    local allowWater = (opts.allowWater ~= nil) and opts.allowWater or (GameConfig.Decorations and GameConfig.Decorations.ALLOW_WATER_FIREFLIES) or false
    local minSpacing = opts.minSpacing or 16
    local keepout = opts.playerKeepoutRadius or WorldGenUtils.getDefaultKeepoutRadius()
    local parentFolder = (opts.parentFolder and opts.parentFolder:IsA("Instance")) and opts.parentFolder or WorldGenUtils.getDecorationFolder()

    local area = (maxX - minX) * (maxZ - minZ)
    local tiles = area / 10000
    local targetCount = opts.count or math.clamp(math.floor(tiles * density), minCount, maxCount)

    local seed = opts.seed or ((PCGConfig.Seeds and PCGConfig.Seeds.DECORATION_SPAWN) or 67890) + 303
    local rng = Random.new(seed)

    local cubes = WorldGenUtils.getPlayerCubePositions(CubePositionService)
    local positions: {Vector3} = {}
    local spawned = 0

    log:info("Firefly spawn target=%d (tiles=%.1f, density=%.2f)", targetCount, tiles, density or 0)

    local attempts, maxAttempts, lastTick = 0, targetCount * 10, Time.mono()
    while spawned < targetCount and attempts < maxAttempts do
        attempts += 1
        lastTick = WorldGenUtils.budgetYield(lastTick)
        local x = rng:NextNumber(minX, maxX)
        local z = rng:NextNumber(minZ, maxZ)
        if not WorldGenUtils.isTooCloseToPlayerCube(x, z, cubes, keepout) and not WorldGenUtils.isTooClose(x, z, positions, minSpacing) then
            local g = WorldGenUtils.findGroundPosition(x, z, { allowWater = allowWater })
            if g then
                local anchor = spawnCluster(g, rng, parentFolder)
                spawned += 1
                table.insert(positions, anchor.Position)
                if spawned <= 3 then log:info("Firefly #%d spawned at (%.1f, %.1f, %.1f)", spawned, anchor.Position.X, anchor.Position.Y, anchor.Position.Z) end
            end
        end
    end
    _lastStats = { count = spawned, seed = seed, bounds = {minX=minX,maxX=maxX,minZ=minZ,maxZ=maxZ} }
    log:info("Firefly generation complete: %d spawned (attempts=%d)", spawned, attempts)
    return positions
end

function FireflyGenerationService:ClearAll()
    local folder = WorldGenUtils.getDecorationFolder()
    for _, inst in ipairs(folder:GetChildren()) do
        if inst:IsA("BasePart") and inst.Name == "FireflyAnchor" then
            inst:Destroy()
            RunService.Heartbeat:Wait()
        end
    end
    log:info("Cleared all firefly anchors in BlockDecorations")
end

function FireflyGenerationService:GetDefaults()
    local deco = GameConfig.Decorations or {}
    return {
        densityPer100x100 = deco.FIREFLIES_PER_100x100 or 0.6,
        minCount = deco.MIN_FIREFLIES or 10,
        maxCount = deco.MAX_FIREFLIES or 120,
        allowWater = deco.ALLOW_WATER_FIREFLIES or false,
        minSpacing = 16,
        keepoutRadius = WorldGenUtils.getDefaultKeepoutRadius(),
        phase = deco.FIREFLIES_PHASE or deco.FIREFLIES_phase,
        allowedPhases = deco.FIREFLIES_ALLOWED_PHASES,
    }
end

function FireflyGenerationService:GetStats()
    return _lastStats
end

function FireflyGenerationService:SpawnAt(position: Vector3)
    local anchor = spawnCluster(position, Random.new(), WorldGenUtils.getDecorationFolder())
    return anchor
end

return FireflyGenerationService
