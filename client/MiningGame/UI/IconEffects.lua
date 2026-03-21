--!strict
-- IconEffects.lua
-- Pluggable, data-driven icon effects for item tiles (Index/Inventory/Shop)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UIx = require(MiningGame:WaitForChild("UI"):WaitForChild("UIConstants"))
local Time = require(MiningGame:WaitForChild("Time"))
local Types = require(MiningGame:WaitForChild("Types"))

export type EffectParams = { [string]: Types.JsonValue }

local IconEffects = {}
local _registry: { [string]: (GuiObject, { [string]: Types.JsonValue }?, EffectParams?) -> boolean } = {}

function IconEffects.register(
	name: string,
	applyFn: (GuiObject, { [string]: Types.JsonValue }?, EffectParams?) -> boolean
)
	_registry[string.lower(name)] = applyFn
end

local function _rainbowSequence(): ColorSequence
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
		ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 165, 0)),
		ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 255, 0)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 255, 0)),
		ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 100, 255)),
		ColorSequenceKeypoint.new(0.83, Color3.fromRGB(150, 0, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 255)),
	})
end

-- Built-in: Rainbow shimmer gradient sweeping horizontally
local function cosmicShimmer(target: GuiObject, _item: { [string]: Types.JsonValue }?, params: EffectParams?): boolean
	if not target or not target.Parent then
		return false
	end
	if target:FindFirstChild("MythicShimmer") then
		return true
	end

	local shimmer = Instance.new("UIGradient")
	shimmer.Name = "MythicShimmer"
	do
		local g = params and params.gradient
		if typeof(g) == "ColorSequence" then
			shimmer.Color = g
		else
			shimmer.Color = _rainbowSequence()
		end
	end
	local rot = params and params.rotation
	shimmer.Rotation = (typeof(rot) == "number") and (rot :: number) or 0
	shimmer.Offset = Vector2.new(0.5, 0)
	shimmer.Parent = target

	local sp = params and (params.speedHz or params.speed)
	local speedHz = (typeof(sp) == "number") and (sp :: number) or 0.1
	local ap = params and (params.amplitude or params.amp)
	local amp = (typeof(ap) == "number") and (ap :: number) or 0.48

	task.spawn(function()
		while target.Parent and shimmer.Parent do
			local now = (Time and Time.mono and Time.mono()) or os.clock()
			local sx = math.clamp(0.5 + math.sin(now * 2 * math.pi * speedHz) * amp, 0, 1)
			shimmer.Offset = Vector2.new(sx, 0)
			task.wait(UIx.Anim.TINY)
		end
	end)
	return true
end

-- Built-in: Hue oscillation for TextLabel icons
local function hueOscillate(target: GuiObject, _item: { [string]: Types.JsonValue }?, params: EffectParams?): boolean
	if not target:IsA("TextLabel") then
		return false
	end
	local lbl: TextLabel = target
	local sp = params and (params.speedHz or params.speed)
	local speedHz = (typeof(sp) == "number") and (sp :: number) or 0.25
	task.spawn(function()
		while lbl.Parent do
			local now = (Time and Time.mono and Time.mono()) or os.clock()
			local h = 0.5 + 0.5 * math.sin(now * 2 * math.pi * speedHz)
			lbl.TextColor3 = Color3.fromHSV(h, 1, 1)
			task.wait(UIx.Anim.TINY)
		end
	end)
	return true
end

-- Built-in: Breathing transparency pulse for any GuiObject
local function pulseBreath(target: GuiObject, _item: { [string]: Types.JsonValue }?, params: EffectParams?): boolean
	local key
	if target:IsA("ImageLabel") then
		key = "ImageTransparency"
	elseif target:IsA("TextLabel") then
		key = "TextTransparency"
	else
		key = "BackgroundTransparency"
	end
	local minT = (params and typeof(params.min) == "number") and (params.min :: number) or 0
	local maxT = (params and typeof(params.max) == "number") and (params.max :: number) or 0.3
	local period = (params and typeof(params.periodSec) == "number") and (params.periodSec :: number)
		or UIx.Anim.EXTRA_SLOW
	task.spawn(function()
		while target.Parent do
			game:GetService("TweenService")
				:Create(
					target,
					TweenInfo.new(period, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{ [key] = maxT }
				)
				:Play()
			task.wait(period)
			game:GetService("TweenService")
				:Create(
					target,
					TweenInfo.new(period, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{ [key] = minT }
				)
				:Play()
			task.wait(period)
		end
	end)
	return true
end

-- Register built-ins
IconEffects.register("cosmicShimmer", cosmicShimmer)
IconEffects.register("hueOscillate", hueOscillate)
IconEffects.register("pulseBreath", pulseBreath)

-- Apply effect based on item/meta or explicit meta.uiIconEffect
function IconEffects.apply(target: GuiObject, item: { [string]: Types.JsonValue }): boolean
	if not (target and item) then
		return false
	end
	local metaRaw: Types.JsonValue? = item.meta or item
	local effName: string? = nil
	local effParams: EffectParams? = nil
	if typeof(metaRaw) == "table" then
		local mt = metaRaw :: { [string]: Types.JsonValue }
		if typeof(mt.uiIconEffect) == "string" then
			effName = mt.uiIconEffect :: string
		end
		if typeof(mt.uiIconParams) == "table" then
			effParams = mt.uiIconParams :: EffectParams
		end
	end
	if effName then
		local fn = _registry[string.lower(effName)]
		if fn then
			return fn(target, item, effParams)
		end
	end
	-- Default inference: cosmic aura gets shimmer
	local typV: Types.JsonValue? = item.type
	local idV: Types.JsonValue? = item.id
	if typeof(metaRaw) == "table" then
		local mt = metaRaw :: { [string]: Types.JsonValue }
		typV = typV or mt.type
		idV = idV or mt.id
	end
	local typ = (typeof(typV) == "string") and (typV :: string) or ""
	local id = (typeof(idV) == "string") and (idV :: string) or ""
	local effect: Types.JsonValue? = (typeof(metaRaw) == "table") and (metaRaw :: { [string]: Types.JsonValue }).effect
		or nil
	if typ == "cosmetic" then
		local isCosmic = (effect == "cosmic") or (string.find(string.lower(id), "cosmic") ~= nil)
		if isCosmic then
			return cosmicShimmer(target, item, effParams)
		end
	end
	return false
end

return IconEffects
