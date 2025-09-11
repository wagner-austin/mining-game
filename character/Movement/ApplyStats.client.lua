--!strict
-- StarterCharacterScripts/Movement/ApplyStats.client.lua
-- Aggregates terrain + CharacterStateClient movement effects into WalkSpeed / JumpHeight

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Movement = ReplicatedStorage:WaitForChild("Movement")
local Config = require(Movement:WaitForChild("Config"))
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local CharacterStateClient = require(MiningGame:WaitForChild("Character"):WaitForChild("CharacterStateClient"))

local character: Model = script.Parent.Parent
local humanoid: Humanoid = character:WaitForChild("Humanoid")

humanoid.UseJumpPower = false

local function recalc(): ()
    local speed = Config.BASE_SPEED
    local jump = Config.BASE_JUMP_HEIGHT
    
    -- Terrain multiplier
    local terr = Config.TERRAIN_MULT[humanoid.FloorMaterial] or 1.0
    speed *= terr
    
    -- Character state movement effects
    local speedMult, speedAdd, jumpMult, jumpAdd = CharacterStateClient.getMovementMods()
    speed = speed * speedMult + speedAdd
    jump = jump * jumpMult + jumpAdd
    
    -- Clamp to limits
    speed = math.clamp(speed, Config.LIMITS.speedMin, Config.LIMITS.speedMax)
    jump = math.clamp(jump, Config.LIMITS.jumpMin, Config.LIMITS.jumpMax)
    
    -- Apply to humanoid
    humanoid.WalkSpeed = speed
    humanoid.JumpHeight = jump
    
    -- Set attributes for UI/debugging
    humanoid:SetAttribute("EffectiveWalkSpeed", speed)
    humanoid:SetAttribute("EffectiveJumpHeight", jump)
    humanoid:SetAttribute("TerrainMult", terr)
end

-- Recalc on terrain change
humanoid:GetPropertyChangedSignal("FloorMaterial"):Connect(recalc)

-- Recalc on certain state changes
humanoid.StateChanged:Connect(function(_, new)
    if new == Enum.HumanoidStateType.Swimming
    or new == Enum.HumanoidStateType.Running
    or new == Enum.HumanoidStateType.Landed then
        recalc()
    end
end)

-- Recalc when effects change
CharacterStateClient.changed():Connect(recalc)

-- Initial calculation
recalc()