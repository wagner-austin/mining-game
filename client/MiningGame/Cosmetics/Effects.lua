--!strict
-- Effects.lua
-- Small helpers for cosmetic visual effects (outline + neon pulsing)

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Time = require(Shared:WaitForChild("Time"))

local Effects = {}

export type OutlineOpts = {
    color: Color3?,
    name: string?,
    occluded: boolean?,
}

function Effects.outline(adorn: Instance, opts: OutlineOpts?): Highlight
    local color = (opts and opts.color) or Color3.new(0, 0, 0)
    local name = (opts and opts.name) or "Outline"
    local occluded = (opts and opts.occluded) ~= false

    local hl = Instance.new("Highlight")
    hl.Name = name
    hl.Adornee = adorn
    hl.FillTransparency = 1
    hl.OutlineTransparency = 0
    hl.OutlineColor = color
    hl.DepthMode = occluded and Enum.HighlightDepthMode.Occluded or Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent = adorn
    return hl
end

-- Pulse a set of baseparts between two colors at a fixed speed; returns connection
function Effects.pulseNeon(parts: {BasePart}, base: Color3, peak: Color3, speed: number): RBXScriptConnection
    local conn = RunService.Heartbeat:Connect(function()
        local t = math.sin(Time.mono() * speed) * 0.5 + 0.5
        local c = base:Lerp(peak, t)
        for _, p in ipairs(parts) do
            if p and p.Parent then
                p.Material = Enum.Material.Neon
                p.Color = c
            end
        end
    end)
    return conn
end

return Effects

