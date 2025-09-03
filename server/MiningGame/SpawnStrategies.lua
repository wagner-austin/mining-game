--!strict
-- SpawnStrategies.lua
-- Pluggable spawn strategies for cube positioning

local Workspace = game:GetService("Workspace")

local Strategies = {}

-- Helpers
local function halfCube(gc) 
    return gc.Grid.CUBE_SIZE_STUDS * 0.5 
end

local function snapToTerrainY(x: number, z: number, yFallback: number, excludes: {Instance}?): number
    -- Filter out nil entries to avoid raycast errors
    local filtered = {}
    if excludes then
        for _, inst in ipairs(excludes) do
            if inst then table.insert(filtered, inst) end
        end
    end
    
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = filtered
    params.IgnoreWater = true
    local castY = 2048
    local hit = Workspace:Raycast(Vector3.new(x, castY, z), Vector3.new(0, -castY*2, 0), params)
    return hit and hit.Position.Y or yFallback
end

-- DEFAULT: grid in XZ, fixed Y (today's behavior)
function Strategies.grid(ord: number, GameConfig)
    local spacing = (GameConfig.Multiplayer and GameConfig.Multiplayer.CUBE_SPACING) or 96
    local cols = (GameConfig.Multiplayer and GameConfig.Multiplayer.GRID_COLS) or 3
    local gx = (ord-1) % cols
    local gz = math.floor((ord-1)/cols)
    local y = halfCube(GameConfig) -- sits on base level
    return CFrame.new(gx*spacing, y, gz*spacing)
end

-- GRID + altitude noise (quick vertical variety; deterministic per ord)
function Strategies.grid_altitude_noise(ord: number, GameConfig)
    local cf = Strategies.grid(ord, GameConfig)
    local p = cf.Position
    local noise = math.noise(ord*0.37, 0, 0) -- -1..1
    local amp = (GameConfig.Multiplayer and GameConfig.Multiplayer.ALTITUDE_AMPLITUDE) or 24
    local y = p.Y + noise * amp
    return CFrame.new(p.X, y, p.Z)
end

-- GRID + terrain snap (raycast to ground, then center = ground + halfCube)
function Strategies.grid_terrain_snap(ord: number, GameConfig)
    local cf = Strategies.grid(ord, GameConfig)
    local p = cf.Position
    local groundY = snapToTerrainY(p.X, p.Z, p.Y, {
        Workspace:FindFirstChild("SimAgents"),
        Workspace:FindFirstChild("PCG_Deco"),
        Workspace:FindFirstChild("PCG_Resources"),
        Workspace:FindFirstChild("ItemDrops"),
    })
    return CFrame.new(p.X, groundY + halfCube(GameConfig), p.Z)
end

-- Hook for your PCG system (ask it for a spawn spot; fallback to grid)
function Strategies.pcg_probe(ord: number, GameConfig)
    local ok, Procedural = pcall(function()
        return require(script.Parent.pcg and script.Parent.pcg.ProceduralGenerationService)
    end)
    if ok and Procedural and Procedural.GetSpawnPositionForOrdinal then
        local pos, yaw = Procedural:GetSpawnPositionForOrdinal(ord, "cube")
        if pos then
            return CFrame.new(pos) * CFrame.Angles(0, yaw or 0, 0)
        end
    end
    -- Fallback to terrain snap if PCG unavailable
    return Strategies.grid_terrain_snap(ord, GameConfig)
end

return Strategies