--!strict
-- RNG.lua
-- Deterministic random number generation for loot drops

local RNG = {}

-- Prime numbers for hash mixing
local PRIMES = { 73856093, 19349663, 83492791, 2654435761 }

-- Hash function for 3D coordinates + seed
-- Returns a deterministic 31-bit positive integer
local function hash3(x: number, y: number, z: number, seed: number): number
    -- Simple 32-bit mix using bit32
    local n = bit32.bxor(
        (x * PRIMES[1]) % 2^31,
        (y * PRIMES[2]) % 2^31
    )
    n = bit32.bxor(n, (z * PRIMES[3]) % 2^31)
    n = bit32.bxor(n, seed * PRIMES[4])
    
    -- Ensure positive result
    return (n % 2147483647)
end

-- Create a Random object seeded by cell coordinates
-- This ensures the same cell always produces the same loot
function RNG.fromCell(x: number, y: number, z: number, seed: number): Random
    local hashValue = hash3(x, y, z, seed)
    return Random.new(hashValue)
end

-- Hash a cell to get a deterministic value (0-1)
function RNG.cellValue(x: number, y: number, z: number, seed: number): number
    local hashValue = hash3(x, y, z, seed)
    return hashValue / 2147483647
end

-- Check if a cell should have loot based on probability
function RNG.cellHasLoot(x: number, y: number, z: number, seed: number, probability: number): boolean
    return RNG.cellValue(x, y, z, seed) < probability
end

return RNG