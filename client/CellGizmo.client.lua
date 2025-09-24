--!strict
-- CellGizmo.client.lua
-- Visual indicator for dig cells

local RS = game:GetService("ReplicatedStorage")
local MiningGame = RS:WaitForChild("MiningGame")
local EventBus = require(MiningGame:WaitForChild("EventBus"))
local EventNames = require(MiningGame:WaitForChild("EventNames"))
local Logger = require(MiningGame:WaitForChild("Logger"))
local log = Logger.new("CellGizmo")
local Bus = EventBus.global()

-- Store connections for cleanup
local connections = {} :: {{ Disconnect: () -> () }}

local function flash(pos: Vector3)
    local p = Instance.new("Part")
    p.Size = Vector3.new(3.8, 3.8, 3.8)   -- slightly smaller than 4 to see edges
    p.CFrame = CFrame.new(pos)
    p.Color = Color3.fromRGB(255, 210, 80)
    p.Material = Enum.Material.Neon
    p.Anchored = true
    p.CanCollide = false
    p.CanTouch = false
    p.CanQuery = false
    p.CastShadow = false
    p.Transparency = 0.4
    p.Parent = workspace

    task.delay(0.2, function() 
        if p then 
            p:Destroy() 
        end 
    end)
end

-- Listen for terrain poke events via EventBus
local off = Bus:on(EventNames.TERRAIN_POKE, function(payload)
    if payload and payload.pos then
        flash(payload.pos)
    end
end)
table.insert(connections, { Disconnect = off })

-- Cleanup on script destroy (for hot-reloads)
script.Destroying:Connect(function()
    for _, c in ipairs(connections) do
        if c and c.Disconnect then c.Disconnect() end
    end
end)

log:info("Visual feedback enabled")
