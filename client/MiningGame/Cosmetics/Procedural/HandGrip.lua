--!strict
-- HandGrip.lua
-- Helper utilities to attach hand-held items with consistent grip/orientation

local HandGrip = {}

export type AttachOptions = {
	gripOffset: number?, -- along handle local +X (before rotation)
	gripHandOffsetY: number?, -- hand-space offset along local Y (away from palm)
	gripTiltDeg: number?, -- forward/back tilt (radians derived internally)
	gripYawDeg: number?, -- outward yaw (right hand)
	gripRollDeg: number?, -- roll twist
}

-- Attaches a Motor6D from hand -> handle assuming the handle's long axis is local +X.
-- Rotates local +X to world +Y via -90° about Z, after translating to the grip point.
function HandGrip.attachXToUp(hand: BasePart, handle: BasePart, handleLen: number, opts: AttachOptions?): Motor6D
	local halfLen = handleLen * 0.5
	local gripAlong = -halfLen + (opts and opts.gripOffset or 0.25)
	local gripHandOffsetY = (opts and opts.gripHandOffsetY) or -0.15
	local tilt = math.rad((opts and opts.gripTiltDeg) or 0)
	local yaw = math.rad((opts and opts.gripYawDeg) or 0)
	local roll = math.rad((opts and opts.gripRollDeg) or 0)

	local motor = Instance.new("Motor6D")
	motor.Name = "HandItemMotor"
	motor.Part0 = hand
	motor.Part1 = handle
	-- Translate to grip point along handle axis, then rotate X->Y (-90° about Z)
	motor.C1 = CFrame.new(gripAlong, 0, 0) * CFrame.Angles(0, 0, math.rad(-90))
	-- Hand-space offset and orientation
	motor.C0 = CFrame.new(0, gripHandOffsetY, 0) * CFrame.Angles(tilt, yaw, roll)
	motor.Parent = hand
	return motor
end

return HandGrip
