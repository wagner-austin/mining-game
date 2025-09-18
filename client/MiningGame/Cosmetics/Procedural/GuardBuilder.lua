--!strict
-- GuardBuilder.lua
-- Build segmented neon guards/rings around a chosen axis

local GuardBuilder = {}

export type RingOpts = {
    segments: number?,
    name: string?,
    axis: string?, -- "X" (default) | "Y" | "Z" (ring axis)
}

-- Creates a segmented ring parented to model, returns the list of parts
function GuardBuilder.makeGuard(model: Instance, centerCF: CFrame, radius: number, thickness: number, color: Color3, opts: RingOpts?): {BasePart}
    local segs = math.max(3, math.floor(opts and opts.segments or 12))
    local axis = (opts and opts.axis) or "X"
    local namePrefix = (opts and opts.name) or "RingSeg"

    local function chordLen(r: number, n: number): number
        return 2 * r * math.sin(math.pi / n)
    end
    local segLen = chordLen(radius, segs) * 0.98

    local parts: {BasePart} = {}
    for i = 0, segs - 1 do
        local a0 = i * (2 * math.pi / segs)
        local a1 = (i + 1) * (2 * math.pi / segs)
        local amid = 0.5 * (a0 + a1)

        local localPos: Vector3
        local tang: Vector3
        local normal: Vector3
        if axis == "Y" then
            -- Axis up: ring lies in XZ plane
            localPos = Vector3.new(radius * math.cos(amid), 0, radius * math.sin(amid))
            tang = Vector3.new(-math.sin(amid), 0, math.cos(amid)).Unit
            normal = Vector3.new(0, 1, 0)
        elseif axis == "Z" then
            -- Axis forward: ring lies in XY plane
            localPos = Vector3.new(radius * math.cos(amid), radius * math.sin(amid), 0)
            tang = Vector3.new(-math.sin(amid), math.cos(amid), 0).Unit
            normal = Vector3.new(0, 0, 1)
        else
            -- Axis right (default): ring lies in YZ plane
            localPos = Vector3.new(0, radius * math.cos(amid), radius * math.sin(amid))
            tang = Vector3.new(0, -math.sin(amid), math.cos(amid)).Unit
            normal = Vector3.new(1, 0, 0)
        end
        local bin = tang:Cross(normal).Unit

        local worldPos = centerCF:PointToWorldSpace(localPos)
        local xW = centerCF:VectorToWorldSpace(tang)
        local yW = centerCF:VectorToWorldSpace(normal)
        local zW = centerCF:VectorToWorldSpace(bin)

        local seg = Instance.new("Part")
        seg.Name = namePrefix
        seg.Size = Vector3.new(segLen, thickness, thickness)
        seg.CanCollide = false
        seg.CanQuery = false
        seg.CanTouch = false
        seg.Massless = true
        seg.Anchored = false
        seg.Material = Enum.Material.Neon
        seg.Color = color
        seg.Parent = model
        seg.CFrame = CFrame.fromMatrix(worldPos, xW, yW, zW)
        table.insert(parts, seg)
    end

    return parts
end

return GuardBuilder
