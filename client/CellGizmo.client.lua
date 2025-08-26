--!strict
-- CellGizmo.client.lua
-- Visual indicator for dig cells

local RS = game:GetService("ReplicatedStorage")
local Remotes = require(RS.MiningGame.Remotes)

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

Remotes.RE.OnTerrainPoke.OnClientEvent:Connect(function(payload)
    if payload and payload.pos then
        flash(payload.pos)
    end
end)

print("[CellGizmo] Visual feedback enabled")