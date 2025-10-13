--!strict
-- CubeReset.lua
-- Centralized helpers to reset a player's cube with optional gating/reseed/save

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(Shared:WaitForChild("Logger"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Time = require(Shared:WaitForChild("Time"))

local log = Logger.new("CubeReset")

local CubeReset = {}

-- Compute dug fraction for a cube state
function CubeReset.computeDugFraction(container, state): (number, number, number)
    if not state then return 0, 1, 0 end
    local GridService = container:Get("GridService")
    local stats = GridService:GetChunkStats(state)
    local ext = state.extentsCells
    local cellSize = GameConfig.Grid.CELL_SIZE_STUDS
    local sideX, sideY, sideZ
    if ext and typeof(ext) == "Vector3" then
        sideX, sideY, sideZ = ext.X * 2, ext.Y * 2, ext.Z * 2
    else
        local perSide = math.floor(GameConfig.Grid.CUBE_SIZE_STUDS / cellSize)
        sideX, sideY, sideZ = perSide, perSide, perSide
    end
    local totalCells = math.max(1, sideX * sideY * sideZ)
    local dug = math.max(0, stats.dugCells or 0)
    return (dug / totalCells), totalCells, dug
end

-- Reset a player's cube model+state with optional gating and reseed
-- opts = { gateAtMostMinedFrac: number?, reseed: boolean?, saveAfterReset: boolean? }
function CubeReset.resetPlayerCube(container, player: Player, opts)
    opts = opts or {}
    local DataService = container:Get("DataService")
    local DigService = container:Get("DigService")

    local state = DataService:GetCubeData(player)
    local cubeInfo = DigService.playerCubes[player]
    if not state or not cubeInfo then
        return { ok = false, success = false, err = "NO_CUBE", reason = "No cube data found" }
    end

    -- Evaluate gates if provided
    do
        local frac = CubeReset.computeDugFraction(container, state)
        if opts.gateAtLeastMinedFrac ~= nil then
            if frac < opts.gateAtLeastMinedFrac then
                return {
                    ok = false,
                    success = false,
                    err = "NOT_ENOUGH_MINED",
                    reason = "Mine more to enable manual reset",
                    minedFrac = frac,
                    threshold = opts.gateAtLeastMinedFrac,
                }
            end
        end
        if opts.gateAtMostMinedFrac ~= nil then
            if frac > opts.gateAtMostMinedFrac then
                return {
                    ok = false,
                    success = false,
                    err = "TOO_DUG",
                    reason = "Gate exceeded",
                    minedFrac = frac,
                    threshold = opts.gateAtMostMinedFrac,
                }
            end
        end
    end

    -- Clear state in-place
    state.chunks = {}
    state.totalDug = 0
    state.createdAt = Time.unix()

    if opts.reseed then
        local newSeed = (Random.new() :: Random):NextInteger(1, 1000000)
        DataService:UpdateMaterialPrefs(player, { compositionSeed = newSeed, variationMode = "PER_REGEN" })
    end

    if opts.saveAfterReset then
        pcall(function() DataService:SaveCubeAsync(player) end)
    end

    -- Destroy model and re-init
    if cubeInfo.model then
        cubeInfo.model:Destroy()
        cubeInfo.model = nil
    end
    DigService:InitializePlayerCube(player, { skipEnsureBase = true })

    return { ok = true, success = true }
end

return CubeReset


