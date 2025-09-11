-- StarterCharacterScripts/Movement/DoubleJump.client.lua
-- Robust double jump, tuned by shared/Movement/Config.lua

local RS         = game:GetService("ReplicatedStorage")
local UIS        = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local MiningGame = RS:WaitForChild("MiningGame")
local MathUtils = require(MiningGame:WaitForChild("MathUtils"))
local Time = require(MiningGame:WaitForChild("Time"))

local movementFolder = script.Parent          -- "Movement"
local character      = movementFolder.Parent
local humanoid       = character:WaitForChild("Humanoid")
local root           = character:WaitForChild("HumanoidRootPart")

local Movement = RS:WaitForChild("Movement")
local Config   = require(Movement:WaitForChild("Config"))
local DJ       = Config.DOUBLE_JUMP or {}

-- Check if double jump is enabled
if DJ.enabled == false then
    return -- feature disabled
end

-- Removed unused DoubleJumpFired BindableEvent
-- If server authority is needed, use EventBus/RemoteEventBridge instead

local MAX_JUMPS     = DJ.maxJumps or 2
local DOUBLE_SCALE  = DJ.scale or 1.0
local IMPULSE_SCALE = DJ.impulseScale or 0.7
local COYOTE_TIME   = DJ.coyoteTime or 0.12
local JUMP_COOLDOWN = DJ.jumpCooldown or 0.10

local charges        = MathUtils.saturatingSub(MAX_JUMPS, 1)
local isGrounded     = true
local lastGroundedT  = 0
local lastJumpPressT = 0
local function setCharges(n) character:SetAttribute("DoubleJumpCharges", n) end
setCharges(charges)

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = { character }
rayParams.IgnoreWater = false

local function stateLooksGrounded(state)
    return state == Enum.HumanoidStateType.Running
        or state == Enum.HumanoidStateType.RunningNoPhysics
        or state == Enum.HumanoidStateType.Landed
        or state == Enum.HumanoidStateType.PlatformStanding
        or state == Enum.HumanoidStateType.Climbing
        or state == Enum.HumanoidStateType.Swimming
        or state == Enum.HumanoidStateType.Seated
end

local function groundedNow()
    if stateLooksGrounded(humanoid:GetState()) then return true end
    local length = humanoid.HipHeight + 3.0
    if workspace:Raycast(root.Position, Vector3.new(0, -length, 0), rayParams) then return true end
    return humanoid.FloorMaterial ~= Enum.Material.Air
end

RunService.Heartbeat:Connect(function()
    local g = groundedNow()
    if g then lastGroundedT = Time.mono() end
    if not isGrounded and g then
        charges = MathUtils.saturatingSub(MAX_JUMPS, 1)
        setCharges(charges)
    end
    isGrounded = g
end)

UIS.JumpRequest:Connect(function()
    -- Skip if character is dead
    if humanoid.Health <= 0 or humanoid:GetState() == Enum.HumanoidStateType.Dead then return end
    
    local now = Time.mono()
    if now - lastJumpPressT < JUMP_COOLDOWN then return end
    lastJumpPressT = now

    local groundedish = isGrounded or (now - lastGroundedT) <= COYOTE_TIME
    if groundedish then
        charges = MathUtils.saturatingSub(MAX_JUMPS, 1)
        setCharges(charges)
        return
    end

    if charges > 0 then
        charges -= 1
        setCharges(charges)

        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)

        local g = workspace.Gravity
        local desiredHeight = (humanoid.JumpHeight or Config.BASE_JUMP_HEIGHT) * DOUBLE_SCALE
        local jumpVelocity = math.sqrt(math.max(0, 2 * g * desiredHeight))
        
        -- Consistent double jump: add a scaled impulse
        -- We use IMPULSE_SCALE because we're adding to existing velocity, not setting it
        -- This makes the double jump feel similar in strength to the initial jump
        local impulseStrength = jumpVelocity * IMPULSE_SCALE
        root:ApplyImpulse(Vector3.new(0, root.AssemblyMass * impulseStrength, 0))

        -- Double jump executed successfully
        -- Add EventBus emit here if needed for telemetry/effects
    end
end)