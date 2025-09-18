--!strict
-- IconEffects.lua
-- Pluggable, data-driven icon effects for item tiles (Index/Inventory/Shop)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UIx = require(MiningGame:WaitForChild("UI"):WaitForChild("UIConstants"))
local Time = require(MiningGame:WaitForChild("Time"))

export type EffectParams = {[string]: any}

local IconEffects = {}
local _registry: {[string]: (GuiObject, any, EffectParams?) -> boolean} = {}

function IconEffects.register(name: string, applyFn: (GuiObject, any, EffectParams?) -> boolean)
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
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 255))
    })
end

-- Built-in: Rainbow shimmer gradient sweeping horizontally
local function cosmicShimmer(target: GuiObject, item: any, params: EffectParams?): boolean
    if not target or not target.Parent then return false end
    if target:FindFirstChild("MythicShimmer") then return true end

    local shimmer = Instance.new("UIGradient")
    shimmer.Name = "MythicShimmer"
    shimmer.Color = (params and params.gradient) or _rainbowSequence()
    shimmer.Rotation = tonumber(params and params.rotation) or 0
    shimmer.Offset = Vector2.new(0.5, 0)
    shimmer.Parent = target

    local speedHz = tonumber(params and (params.speedHz or params.speed)) or 0.1
    local amp = tonumber(params and (params.amplitude or params.amp)) or 0.48

    task.spawn(function()
        while target.Parent and shimmer.Parent do
            local now = (Time and Time.mono and Time.mono()) or os.clock()
            local sx = math.clamp(0.5 + math.sin(now * 2*math.pi * speedHz) * amp, 0, 1)
            shimmer.Offset = Vector2.new(sx, 0)
            task.wait(UIx.Anim.TINY)
        end
    end)
    return true
end

-- Built-in: Hue oscillation for TextLabel icons
local function hueOscillate(target: GuiObject, _item: any, params: EffectParams?): boolean
    local lbl = target:IsA("TextLabel") and target :: any
    if not lbl then return false end
    local speedHz = tonumber(params and (params.speedHz or params.speed)) or 0.25
    task.spawn(function()
        while lbl.Parent do
            local now = (Time and Time.mono and Time.mono()) or os.clock()
            local h = 0.5 + 0.5 * math.sin(now * 2*math.pi * speedHz)
            lbl.TextColor3 = Color3.fromHSV(h, 1, 1)
            task.wait(UIx.Anim.TINY)
        end
    end)
    return true
end

-- Built-in: Breathing transparency pulse for any GuiObject
local function pulseBreath(target: GuiObject, _item: any, params: EffectParams?): boolean
    local key
    if target:IsA("ImageLabel") then key = "ImageTransparency"
    elseif target:IsA("TextLabel") then key = "TextTransparency"
    else key = "BackgroundTransparency" end
    local minT = tonumber(params and params.min) or 0
    local maxT = tonumber(params and params.max) or 0.3
    local period = tonumber(params and params.periodSec) or UIx.Anim.EXTRA_SLOW
    task.spawn(function()
        while target.Parent do
            game:GetService("TweenService"):Create(target, TweenInfo.new(period, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {[key] = maxT}):Play()
            task.wait(period)
            game:GetService("TweenService"):Create(target, TweenInfo.new(period, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {[key] = minT}):Play()
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
function IconEffects.apply(target: GuiObject, item: any): boolean
    if not (target and item) then return false end
    local meta = (item.meta or item)
    local effName = meta and meta.uiIconEffect
    local effParams = meta and meta.uiIconParams
    if type(effName) == "string" then
        local fn = _registry[string.lower(effName)]
        if fn then return fn(target, item, effParams) end
    end
    -- Default inference: cosmic aura gets shimmer
    local typ = tostring(item.type or meta.type or "")
    local id = tostring(item.id or meta.id or "")
    local effect = meta.effect
    if typ == "cosmetic" then
        local isCosmic = (effect == "cosmic") or (string.find(string.lower(id), "cosmic") ~= nil)
        if isCosmic then return cosmicShimmer(target, item, effParams) end
    end
    return false
end

return IconEffects
