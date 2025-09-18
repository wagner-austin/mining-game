--!strict
-- MountUtils.lua
-- Small helpers for placing and welding parts relative to a handle (local +X length)

local MountUtils = {}

export type MountOpts = {
    inset: number?,        -- small gap from absolute tip along +X (default 0.02)
    axis: string?,         -- which cross axis is "top": "Y" or "Z" (default "Y")
    rollQuarter: number?,  -- 0..3 quarter turns around handle X (default 0)
}

function MountUtils.weld(part0: BasePart, part1: BasePart): WeldConstraint
    local w = Instance.new("WeldConstraint")
    w.Part0 = part0
    w.Part1 = part1
    w.Parent = part1
    return w
end

-- Attach a part to the end (+X) of the handle, aligning by TOP edge on the chosen axis.
-- Keeps the part centered on the other cross axis. Optionally rolls around X in 90° steps.
function MountUtils.mountEndTopEdge(handle: BasePart, part: BasePart, opts: MountOpts?)
    local axis = (opts and opts.axis) or "Y" -- which axis is considered "top" on cross-section
    local inset = (opts and opts.inset) or 0.02
    local rollQuarter = (opts and opts.rollQuarter) or 0

    local angle = (math.pi/2) * (rollQuarter % 4)

    local offsetX = (handle.Size.X * 0.5) + (part.Size.X * 0.5) - inset

    -- Compute top-edge offset so top faces are seamless: handle half - part half (in part local Y before roll)
    local topDelta: number
    if axis == "Z" then
        topDelta = (handle.Size.Z * 0.5) - (part.Size.Y * 0.5)
        part.CFrame = handle.CFrame * CFrame.new(offsetX, 0, topDelta) * CFrame.Angles(angle, 0, 0)
    else
        topDelta = (handle.Size.Y * 0.5) - (part.Size.Y * 0.5)
        part.CFrame = handle.CFrame * CFrame.new(offsetX, topDelta, 0) * CFrame.Angles(angle, 0, 0)
    end
end

-- Attach a part to the end (+X) of the handle, centered in cross-section (no top/bottom offset).
function MountUtils.mountEndCenter(handle: BasePart, part: BasePart, inset: number?)
    local dx = (handle.Size.X * 0.5) + (part.Size.X * 0.5) - (inset or 0.02)
    part.CFrame = handle.CFrame * CFrame.new(dx, 0, 0)
end

-- Place part so its FAR tip (+X face) sits just before the handle tip by `inset`.
-- This mimics the prior warhammer layout where the handle barely pokes through.
function MountUtils.mountEndByTip(handle: BasePart, part: BasePart, inset: number?)
    local dx = (handle.Size.X * 0.5) - (part.Size.X * 0.5) - (inset or 0.02)
    part.CFrame = handle.CFrame * CFrame.new(dx, 0, 0)
end

return MountUtils
