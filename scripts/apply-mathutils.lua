--!strict
-- Script to apply MathUtils to remaining server services
-- Run with: luau scripts/apply-mathutils.lua

local files = {
    "server/MiningGame/MonetizationService.lua",
    "server/MiningGame/GridService.lua",
    "server/MiningGame/SimAgents.lua",
    "server/MiningGame/WorldGenerationService.lua",
    "server/MiningGame/SpawnStrategies.lua",
    "server/MiningGame/TimeService.lua",
    "server/MiningGame/SessionService.lua",
    "server/MiningGame/UserMetricsService.lua",
}

local replacements = {
    -- Simple patterns
    {
        pattern = "math%.max%(0,%s*([^%)]+)%)",
        replacement = "MathUtils.nonNegative(%1)",
        description = "math.max(0, x) -> MathUtils.nonNegative(x)"
    },
    -- Subtraction patterns
    {
        pattern = "math%.max%(0,%s*([^%)]+)%s*%-%s*([^%)]+)%)",
        replacement = "MathUtils.saturatingSub(%1, %2)",
        description = "math.max(0, a - b) -> MathUtils.saturatingSub(a, b)"
    },
}

print("MathUtils Migration Plan:")
print("=======================")
print()

for _, file in ipairs(files) do
    print("File: " .. file)
    print("  Add import: local MathUtils = require(Shared:WaitForChild(\"MathUtils\"))")
    print("  Replacements needed:")
    
    -- In real script, would read file and apply patterns
    -- For now, just document what needs to be done
    for _, r in ipairs(replacements) do
        print("    - " .. r.description)
    end
    print()
end

print([[
Manual steps:
1. Add MathUtils import to each file after Shared modules section
2. Apply replacements using search/replace
3. Test each service after changes
4. Run validate-client-patterns.sh to verify
]])