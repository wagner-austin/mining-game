--!strict
-- RockGenerationService.lua
-- Dedicated service for spawning blocky rocks with configurable knobs

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

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

local log = Logger.new("RockGenerationService")
local Bus = EventBus.global()
local DigPerformance = require(script.Parent.DigPerformance)

local RockGenerationService = {}
local _eventsRegistered = false
local _lastStats = { count = 0, seed = 0, bounds = nil :: any }

-- Visual parameters (from WorldGenerationService)
local BLOCK_SIZE = 8
local ROCK_COLOR = Color3.fromRGB(150, 150, 150)
local ROCK_ACCENT_COLOR = Color3.fromRGB(180, 180, 190)
local MIN_ROCK_SIZE = 1
local MAX_ROCK_SIZE = 3

-- Light budget per batch
local DECOR_LIGHT_BUDGET = 30

local function createBlock(position: Vector3, size: Vector3, color: Color3, material: Enum.Material, parent: Instance): BasePart
    local part = Instance.new("Part")
    part.Size = size
    part.Position = position
    part.Color = color
    part.Material = material
    part.Anchored = true
    part.CanCollide = true
    part.CastShadow = false
    part.Parent = parent
    return part
end

local function generateRockModel(basePosition: Vector3, rng: Random): Model
    local model = Instance.new("Model")
    model.Name = "BlockRock"

    local rockSize = rng:NextInteger(MIN_ROCK_SIZE, MAX_ROCK_SIZE)
    local lightCount = 0

    for x = -rockSize, rockSize do
        for y = 0, rockSize do
            for z = -rockSize, rockSize do
                local dist = math.sqrt(x*x + y*y + z*z)
                local threshold = rockSize + rng:NextNumber(-0.5, 0.5)
                if dist <= threshold and rng:NextNumber() > 0.4 then
                    local blockPos = basePosition + Vector3.new(
                        x * BLOCK_SIZE * 0.8,
                        y * BLOCK_SIZE * 0.8,
                        z * BLOCK_SIZE * 0.8
                    )
                    local blockScale = rng:NextNumber(0.7, 1.0)
                    local blockSize = BLOCK_SIZE * blockScale
                    local useAccent = rng:NextNumber() > 0.7
                    local color = useAccent and ROCK_ACCENT_COLOR or ROCK_COLOR

                    local rockBlock = createBlock(
                        blockPos,
                        Vector3.new(blockSize, blockSize, blockSize),
                        color,
                        Enum.Material.Slate,
                        model
                    )
                    rockBlock.CastShadow = false

                    if lightCount < DECOR_LIGHT_BUDGET and rng:NextNumber() > 0.9 then
                        lightCount += 1
                        local glow = Instance.new("PointLight")
                        glow.Brightness = 1.5
                        glow.Range = 12
                        glow.Color = useAccent and Color3.fromRGB(150, 180, 255) or Color3.fromRGB(255, 220, 180)
                        glow.Shadows = false
                        glow.Parent = rockBlock

                        local particles = Instance.new("ParticleEmitter")
                        particles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
                        particles.Rate = 2
                        particles.Lifetime = NumberRange.new(3, 5)
                        particles.Speed = NumberRange.new(0.5, 1)
                        particles.VelocitySpread = 360
                        particles.EmissionDirection = Enum.NormalId.Top
                        particles.Transparency = NumberSequence.new(0.7)
                        particles.Size = NumberSequence.new(2)
                        particles.Color = ColorSequence.new(glow.Color)
                        particles.LightEmission = 1
                        particles.LightInfluence = 0
                        particles.Parent = rockBlock
                    end
                end
            end
        end
    end

    local primary = model:FindFirstChildWhichIsA("BasePart")
    if primary then
        model.PrimaryPart = primary
    end
    pcall(function() CollectionService:AddTag(model, "BlockRock") end)
    return model
end

export type GenerateOpts = {
    bounds: {minX: number, maxX: number, minZ: number, maxZ: number}?,
    center: Vector3?, sizeX: number?, sizeZ: number?,
    densityPer100x100: number?, minCount: number?, maxCount: number?, count: number?,
    allowWater: boolean?, seed: number?, minSpacing: number?, playerKeepoutRadius: number?,
    parentFolder: Instance?, phase: string?, allowedPhases: {string}?,
}

local CubePositionService: any = nil

function RockGenerationService:Init(container)
    CubePositionService = ServiceValidator.tryGet(container, "CubePositionService")
    log:info("Initialized%s", CubePositionService and " (CubePositionService wired)" or "")

    if not _eventsRegistered then
        Bus:on(EventNames.ROCK_SPAWN_REQUEST, function(msg)
            local ok, payload = pcall(EventContracts.ROCK_SPAWN_REQUEST, msg.payload)
            if not ok then log:warn("Invalid ROCK_SPAWN_REQUEST payload") return end
            if payload.position then
                local model = self:SpawnAt(payload.position)
                if model then log:info("Spawned rock at %s via event", tostring(payload.position)) end
            else
                local positions = self:GenerateInArea(payload)
                log:info("Generated %d rocks via event", positions and #positions or 0)
            end
        end)
        Bus:on(EventNames.ROCK_CLEAR_REQUEST, function(msg)
            local ok = pcall(EventContracts.ROCK_CLEAR_REQUEST, msg.payload)
            if not ok then log:warn("Invalid ROCK_CLEAR_REQUEST payload") return end
            self:ClearAll()
        end)
        _eventsRegistered = true
        log:info("Event listeners registered")
    end
end

function RockGenerationService:Start() end

function RockGenerationService:GenerateInArea(opts: GenerateOpts): {Vector3}
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
            log:info("Phase mismatch (%s) -> skipping rock generation", phase)
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

    local density = opts.densityPer100x100 or (GameConfig.Decorations and GameConfig.Decorations.ROCKS_PER_100x100) or 0.9
    local minCount = opts.minCount or (GameConfig.Decorations and GameConfig.Decorations.MIN_ROCKS) or 15
    local maxCount = opts.maxCount or (GameConfig.Decorations and GameConfig.Decorations.MAX_ROCKS) or 200
    local allowWater = (opts.allowWater ~= nil) and opts.allowWater or (GameConfig.Decorations and GameConfig.Decorations.ALLOW_WATER_ROCKS) or false
    local minSpacing = opts.minSpacing or 10
    local keepout = opts.playerKeepoutRadius or WorldGenUtils.getDefaultKeepoutRadius()
    local parentFolder = (opts.parentFolder and opts.parentFolder:IsA("Instance")) and opts.parentFolder or WorldGenUtils.getDecorationFolder()

    local area = (maxX - minX) * (maxZ - minZ)
    local tiles = area / 10000
    local targetCount = opts.count or math.clamp(math.floor(tiles * density), minCount, maxCount)

    local seed = opts.seed or ((PCGConfig.Seeds and PCGConfig.Seeds.DECORATION_SPAWN) or 67890) + 202
    local rng = Random.new(seed)

    local cubes = WorldGenUtils.getPlayerCubePositions(CubePositionService)
    local positions: {Vector3} = {}
    local spawned = 0

    log:info("Rock spawn target=%d (tiles=%.1f, density=%.2f)", targetCount, tiles, density or 0)

    local attempts, maxAttempts, lastTick = 0, targetCount * 15, Time.mono()
    while spawned < targetCount and attempts < maxAttempts do
        attempts += 1
        lastTick = WorldGenUtils.budgetYield(lastTick)
        local x = rng:NextNumber(minX, maxX)
        local z = rng:NextNumber(minZ, maxZ)
        if not WorldGenUtils.isTooCloseToPlayerCube(x, z, cubes, keepout) and not WorldGenUtils.isTooClose(x, z, positions, minSpacing) then
            local g = WorldGenUtils.findGroundPosition(x, z, { allowWater = allowWater })
            if g then
                DigPerformance.measureSection("PCG_Rock_Create", function()
                    local model = generateRockModel(g, rng)
                    model.Parent = parentFolder
                end)
                spawned += 1
                table.insert(positions, g)
                if spawned <= 3 then log:info("Rock #%d spawned at (%.1f, %.1f, %.1f)", spawned, g.X, g.Y, g.Z) end
            end
        end
    end
    _lastStats = { count = spawned, seed = seed, bounds = {minX=minX,maxX=maxX,minZ=minZ,maxZ=maxZ} }
    log:info("Rock generation complete: %d spawned (attempts=%d)", spawned, attempts)
    return positions
end

function RockGenerationService:SpawnAt(position: Vector3)
    local model = generateRockModel(position, Random.new())
    model.Parent = WorldGenUtils.getDecorationFolder()
    return model
end

function RockGenerationService:ClearAll()
    local folder = WorldGenUtils.getDecorationFolder()
    for _, inst in ipairs(folder:GetChildren()) do
        if inst:IsA("Model") and (CollectionService:HasTag(inst, "BlockRock") or inst.Name:find("BlockRock")) then
            inst:Destroy()
            RunService.Heartbeat:Wait()
        end
    end
    log:info("Cleared all rocks in BlockDecorations")
end

function RockGenerationService:GetDefaults()
    local deco = GameConfig.Decorations or {}
    return {
        densityPer100x100 = deco.ROCKS_PER_100x100 or 0.9,
        minCount = deco.MIN_ROCKS or 15,
        maxCount = deco.MAX_ROCKS or 200,
        allowWater = deco.ALLOW_WATER_ROCKS or false,
        minSpacing = 10,
        keepoutRadius = WorldGenUtils.getDefaultKeepoutRadius(),
        phase = deco.ROCKS_PHASE or deco.ROCKS_phase,
        allowedPhases = deco.ROCKS_ALLOWED_PHASES,
    }
end

function RockGenerationService:GetStats()
    return _lastStats
end

return RockGenerationService
