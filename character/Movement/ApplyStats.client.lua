-- StarterCharacterScripts/Movement/ApplyStats.client.lua
-- Aggregates terrain + all modifiers into effective WalkSpeed / JumpHeight.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local character = script.Parent.Parent
local humanoid  = character:WaitForChild("Humanoid")

-- Config
local Movement = ReplicatedStorage:WaitForChild("Movement")
local Config   = require(Movement:WaitForChild("Config"))

humanoid.UseJumpPower = false

-- BindableEvent to centralize recalcs (create early before any references)
local recalcBE = Instance.new("BindableEvent")
recalcBE.Name = "Recalc"
recalcBE.Parent = script

-- Modifiers live under a folder so tiny scripts can drop values in/out.
local modsFolder = character:FindFirstChild("MovementModifiers")
if not modsFolder then
    modsFolder = Instance.new("Folder")
    modsFolder.Name = "MovementModifiers"
    modsFolder.Parent = character
end

local valueConns = {}
local function hookValue(v)
    if v:IsA("NumberValue") then
        valueConns[v] = v.Changed:Connect(function()
            task.defer(function()
                if script.Parent and humanoid.Parent then
                    recalcBE:Fire()
                end
            end)
        end)
    end
end
local function unhookValue(v) local c=valueConns[v]; if c then c:Disconnect() end; valueConns[v]=nil end
modsFolder.ChildAdded:Connect(function(c) hookValue(c); recalcBE:Fire() end)
modsFolder.ChildRemoved:Connect(function(c) unhookValue(c); recalcBE:Fire() end)
for _, v in ipairs(modsFolder:GetChildren()) do hookValue(v) end

local function getAggregates()
    local sMult, sAdd, jMult, jAdd = 1.0, 0.0, 1.0, 0.0
    for _, v in ipairs(modsFolder:GetChildren()) do
        if v:IsA("NumberValue") then
            local n=v.Name
            if n:match("SpeedMult$") then sMult*=v.Value
            elseif n:match("SpeedAdd$") then sAdd+=v.Value
            elseif n:match("JumpMult$")  then jMult*=v.Value
            elseif n:match("JumpAdd$")   then jAdd+=v.Value end
        end
    end
    return sMult, sAdd, jMult, jAdd
end

local function recalc()
    local speed = Config.BASE_SPEED
    local jump  = Config.BASE_JUMP_HEIGHT

    local terr = Config.TERRAIN_MULT[humanoid.FloorMaterial] or 1.0
    speed = speed * terr

    local sMult, sAdd, jMult, jAdd = getAggregates()
    speed = speed * sMult + sAdd
    jump  = jump  * jMult + jAdd

    speed = math.clamp(speed, Config.LIMITS.speedMin, Config.LIMITS.speedMax)
    jump  = math.clamp(jump,  Config.LIMITS.jumpMin,  Config.LIMITS.jumpMax)

    humanoid.WalkSpeed  = speed
    humanoid.JumpHeight = jump

    humanoid:SetAttribute("EffectiveWalkSpeed", speed)
    humanoid:SetAttribute("EffectiveJumpHeight", jump)
    humanoid:SetAttribute("TerrainMult", terr)
end

humanoid:GetPropertyChangedSignal("FloorMaterial"):Connect(recalc)
humanoid.StateChanged:Connect(function(_, new)
    if new == Enum.HumanoidStateType.Swimming
    or new == Enum.HumanoidStateType.Running
    or new == Enum.HumanoidStateType.Landed then
        recalc()
    end
end)
recalcBE.Event:Connect(recalc)
recalc()