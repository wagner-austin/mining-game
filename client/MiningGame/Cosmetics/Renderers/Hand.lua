--!strict
--[[
    Hand.lua
    Handles pickaxe/tool visual customization with full reversibility.
]]

local RunService = game:GetService("RunService")
local Registry = require(script.Parent.Parent.RendererRegistry)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Time = require(Shared:WaitForChild("Time"))

local HandItemBuilders = require(script.Parent.Parent.Procedural.HandItemBuilders)
local Effects = require(script.Parent.Parent.Effects)
local Hand = {}
Hand.priority = 30 -- Apply last (after all wearables)

-- Store original properties and apply cosmetic
-- No Tool painting; procedural pickaxe only

-- Build a procedural hand item model and attach to character hand
-- Construction lives in HandItemBuilders + HandGrip; the renderer stays thin.

function Hand.apply(character: Model, def: any, ctx: any)
    local instances = {}
    local connections = {}
    local state = { orig = {}, proc = nil }  -- Store original handle properties and procedural parts
    -- Always build a procedural pickaxe (no Tool/asset painting)
    local proc = HandItemBuilders.build(character, def)
    if proc then
        state.proc = proc
        table.insert(instances, proc.model)
        table.insert(instances, proc.motor)
    end
    -- Warhammer: no head damping (kept rigid for predictable visuals)

    -- Handle rainbow animation
    if def.effect == "rainbow" then
        local last = 0
        local rainbowConn = RunService.Heartbeat:Connect(function(dt)
            last = last + dt
            if last < 0.1 then return end
            last = 0
            
            local hue = (Time.mono() * 0.5) % 1
            local color = Color3.fromHSV(hue, 1, 1)
            
            if state.proc and state.proc.parts then
                -- Recolor procedural hand item parts
                for _, p in ipairs(state.proc.parts) do
                    if p and p.Parent then
                        p.Color = color
                        p.Material = Enum.Material.Neon
                    end
                end
            end
        end)
        table.insert(connections, rainbowConn)
    end
    -- Warhammer visual effects: black outline highlight and pulsing deep red head
    do
        local kind = def and def.procedural and def.procedural.kind or (def and def.kind)
        if kind == "warhammer" and state.proc and state.proc.parts then
            local headPart: BasePart? = nil
            for _, p in ipairs(state.proc.parts) do
                if typeof(p) == "Instance" and p:IsA("BasePart") and p.Name == "Head" then
                    headPart = p
                    break
                end
            end
            if headPart then
                -- Optional black outline highlight
                if def.headHighlight then
                    local hl = Effects.outline(headPart, { name = "WarhammerOutline", color = Color3.new(0,0,0), occluded = true })
                    table.insert(instances, hl)
                end
                -- Pulsing deep-red color
                if def.headPulse then
                    local baseColor = (def.headTint or Color3.fromRGB(180,0,0))
                    local peakColor = (def.headPulseColor2 or Color3.fromRGB(255,40,40))
                    local speed = tonumber(def.headPulseSpeed) or 2.0
                    local conn = Effects.pulseNeon({headPart}, baseColor, peakColor, speed)
                    table.insert(connections, conn)
                end
            end
        end
    end

    -- Pickaxe visual effects: neon head + outline, optional pulse
    do
        local kind = def and def.procedural and def.procedural.kind or (def and def.kind)
        if kind == "pickaxe" and state.proc and state.proc.parts then
            local heads: {BasePart} = {}
            for _, p in ipairs(state.proc.parts) do
                if typeof(p) == "Instance" and p:IsA("BasePart") then
                    if p.Name == "HeadLeft" or p.Name == "HeadRight" or p.Name == "Head" then
                        table.insert(heads, p)
                    end
                end
            end
            if #heads > 0 then
                if def.headHighlight then
                    for _, hp in ipairs(heads) do
                        local hl = Effects.outline(hp, { name = "PickaxeHeadOutline", color = Color3.new(0,0,0), occluded = true })
                        table.insert(instances, hl)
                    end
                end
                if def.headPulse then
                    local baseColor = (def.headTint or Color3.fromRGB(40, 200, 255))
                    local peakColor = (def.headPulseColor2 or Color3.fromRGB(100, 255, 255))
                    local speed = tonumber(def.headPulseSpeed) or 1.8
                    table.insert(connections, Effects.pulseNeon(heads, baseColor, peakColor, speed))
                else
                    -- Static neon head color
                    for _, hp in ipairs(heads) do
                        hp.Material = Enum.Material.Neon
                        if def.headTint then hp.Color = def.headTint end
                    end
                end
            end
        end
    end

    -- Sword visual effects: pulsing blade and guard rings (neon) + optional outline highlight
    do
        local kind = def and def.procedural and def.procedural.kind or (def and def.kind)
        if kind == "sword" and state.proc and state.proc.parts then
            local pulse = (def and (def.pulse == true)) or true
            if pulse then
                local blades: {BasePart} = {}
                local ring1: {BasePart} = {}
                local ring2: {BasePart} = {}
                for _, p in ipairs(state.proc.parts) do
                    if typeof(p) == "Instance" and p:IsA("BasePart") then
                        if p.Name == "Blade" then
                            table.insert(blades, p)
                        elseif p.Name == "GuardRingSeg1" then
                            table.insert(ring1, p)
                        elseif p.Name == "GuardRingSeg2" then
                            table.insert(ring2, p)
                        end
                    end
                end
                -- Optional black outline highlight on the blade (DepthMode Occluded)
                if def and def.bladeHighlight and #blades > 0 then
                    for _, bp in ipairs(blades) do
                        if bp and bp.Parent then
                            local hl = Effects.outline(bp, { name = "SwordBladeOutline", color = Color3.new(0,0,0), occluded = true })
                            table.insert(instances, hl)
                        end
                    end
                end
                if #blades > 0 or #ring1 > 0 or #ring2 > 0 then
                    -- Blade: neon green; if bladeTint provided, use it (static: base == peak)
                    local baseBlade = Color3.fromRGB(60, 255, 120)
                    local peakBlade = Color3.fromRGB(140, 255, 180)
                    if def and def.bladeTint then
                        baseBlade = def.bladeTint
                        peakBlade = def.bladeTint
                    end
                    local speedBlade = tonumber(def and def.pulseSpeed) or 1.8
                    -- Rings: outer ring stays black neon, inner ring pulses/static white
                    local baseR1 = Color3.fromRGB(0, 0, 0)
                    local peakR1 = Color3.fromRGB(0, 0, 0)
                    local baseR2 = Color3.fromRGB(255, 255, 255)
                    local peakR2 = Color3.fromRGB(255, 255, 255)
                    local speedR = (tonumber(def and def.pulseSpeed) or 1.8) * 0.9
                    -- Blade pulse/static
                    table.insert(connections, Effects.pulseNeon(blades, baseBlade, peakBlade, speedBlade))
                    -- Outer ring static to black
                    table.insert(connections, Effects.pulseNeon(ring1, baseR1, peakR1, speedR))
                    -- Inner ring static/pulse to white
                    table.insert(connections, Effects.pulseNeon(ring2, baseR2, peakR2, speedR))
                end
            end
        end
    end

    return {instances = instances, connections = connections, state = state}
end

function Hand.remove(ctx)
    -- Disconnect all connections
    if ctx and ctx.connections then
        for _, c in ipairs(ctx.connections) do
            if typeof(c) == "RBXScriptConnection" then
                c:Disconnect()
            end
        end
    end
    
    -- Destroy all effect instances
    if ctx and ctx.instances then
        for _, i in ipairs(ctx.instances) do
            if typeof(i) == "Instance" then
                i:Destroy()
            end
        end
    end
    -- Destroy procedural pickaxe if present
    if ctx and ctx.state and ctx.state.proc then
        local proc = ctx.state.proc
        require(script.Parent.Parent.Procedural.HandItemBuilders).destroy(proc)
        ctx.state.proc = nil
    end
    
    -- No Tool state to restore
end

Registry.register("hand", Hand)
return Hand
