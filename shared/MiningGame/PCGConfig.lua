--!strict
-- PCGConfig.lua
-- Configuration for deterministic seeds and asset processing
-- Used by WorldGenerationService, SpawnStrategies, FloatingIslandService, and AssetRegistry

local PCGConfig = {}

-- Deterministic seeds used by various systems
PCGConfig.Seeds = {
    DECORATION_SPAWN = 67890,   -- Used by WorldGenerationService for trees/rocks/fireflies
    CUBE_SPAWN = 1337,          -- Used by SpawnStrategies for player cube positioning
    ISLAND_SPAWN = 54321,       -- Used by FloatingIslandService and WorldGenerationService
    SIM_AGENTS = 12345,         -- Used by SimAgents for test cube materials
}

-- Asset normalization settings
PCGConfig.AssetRegistry = {
    -- Normalize tree/foliage materials even if they have textures
    -- (fixes Neon/Fabric leaves that look wrong with textures)
    AGGRESSIVE_TREE_NORMALIZE = true,
}

return PCGConfig