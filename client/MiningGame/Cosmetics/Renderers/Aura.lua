--!strict
--[[
    Aura.lua
    Handles particle-based aura cosmetics around the player.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Time = require(Shared:WaitForChild("Time"))
local RendererRegistry = require(script.Parent.Parent.RendererRegistry)

local Aura = {}
Aura.priority = 40 -- Apply after model/back/head

type CosmeticDef = RendererRegistry.CosmeticDef
type RendererCtx = RendererRegistry.RendererCtx

-- Restricted helper shapes (avoid any)
type NumSeqList = { number }
type ColSeqList = { Color3 }

function Aura.apply(character: Model, def: CosmeticDef, _ctx: RendererCtx?): RendererCtx?
	local rootInst = character:FindFirstChild("HumanoidRootPart")
	if not (rootInst and rootInst:IsA("BasePart")) then
		return nil
	end
	local rp: BasePart = rootInst

	local attachment = Instance.new("Attachment")
	attachment.Name = "AuraAttachment"
	attachment.Parent = rp

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "AuraEmitter"
	emitter.Parent = attachment

	-- Helpers to coerce optional overrides
	local function nr(
		val: NumberRange | { number } | number | nil,
		fallbackMin: number,
		fallbackMax: number
	): NumberRange
		if typeof(val) == "NumberRange" then
			return val
		end
		if type(val) == "table" and #val >= 2 then
			return NumberRange.new(tonumber(val[1]) or fallbackMin, tonumber(val[2]) or fallbackMax)
		end
		if type(val) == "number" then
			return NumberRange.new(val, val)
		end
		return NumberRange.new(fallbackMin, fallbackMax)
	end
	local function v2(val: Vector2 | { number } | nil, fx: number, fy: number): Vector2
		if typeof(val) == "Vector2" then
			return val
		end
		if type(val) == "table" and #val >= 2 then
			return Vector2.new(tonumber(val[1]) or fx, tonumber(val[2]) or fy)
		end
		return Vector2.new(fx, fy)
	end

	local function toNumberSequence(val: NumberSequence | NumberRange | NumSeqList | number): NumberSequence?
		if typeof(val) == "NumberSequence" then
			return val
		end
		if typeof(val) == "NumberRange" then
			local nrange: NumberRange = val
			return NumberSequence.new({
				NumberSequenceKeypoint.new(0, nrange.Min),
				NumberSequenceKeypoint.new(1, nrange.Max),
			})
		end
		if type(val) == "table" then
			local keys = {}
			if #val > 0 then
				local n = #val
				for i, v in ipairs(val) do
					if type(v) == "number" then
						local t = (n > 1) and ((i - 1) / (n - 1)) or 0
						table.insert(keys, NumberSequenceKeypoint.new(math.clamp(t, 0, 1), v))
					end
				end
			else
				for k, v in pairs(val) do
					if type(k) == "number" and type(v) == "number" then
						local t = k
						table.insert(keys, NumberSequenceKeypoint.new(math.clamp(t, 0, 1), v))
					end
				end
			end
			table.sort(keys, function(a, b)
				return a.Time < b.Time
			end)
			if #keys >= 2 then
				return NumberSequence.new(keys)
			end
		end
		if type(val) == "number" then
			return NumberSequence.new(val)
		end
		return nil
	end

	local function toColorSequence(val: ColorSequence | ColSeqList): ColorSequence?
		if typeof(val) == "ColorSequence" then
			return val
		end
		if type(val) == "table" then
			local keys = {}
			if #val > 0 then
				local isColorArray = true
				for _, c in ipairs(val) do
					if typeof(c) ~= "Color3" then
						isColorArray = false
						break
					end
				end
				if isColorArray then
					local n = #val
					for i, c in ipairs(val) do
						local t = (n > 1) and ((i - 1) / (n - 1)) or 0
						table.insert(keys, ColorSequenceKeypoint.new(math.clamp(t, 0, 1), c))
					end
				end
			else
				for k, c in pairs(val) do
					local t = tonumber(k)
					if t ~= nil and typeof(c) == "Color3" then
						table.insert(keys, ColorSequenceKeypoint.new(math.clamp(t, 0, 1), c))
					end
				end
			end
			table.sort(keys, function(a, b)
				return a.Time < b.Time
			end)
			if #keys >= 2 then
				return ColorSequence.new(keys)
			end
		end
		return nil
	end

	-- Base configuration (sensible defaults, overridable via def)
	emitter.Texture = def.particleTexture or "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Rate = def.emissionRate or 50
	emitter.Lifetime = nr(def.lifetime or def.lifetimeRange, 1, 2)
	emitter.Speed = nr(def.speed or def.speedRange, 2, 4)
	emitter.SpreadAngle = v2(def.spreadAngle, 360, 360)
	emitter.LightEmission = (def.lightEmission ~= nil) and def.lightEmission or 0.5
	emitter.LightInfluence = (def.lightInfluence ~= nil) and def.lightInfluence or 0.2

	-- Light host: welded, invisible part
	local existing = character:FindFirstChild("AuraLightPart")
	local lightPart: Part
	if existing and existing:IsA("Part") then
		lightPart = existing
	else
		local lp = Instance.new("Part")
		lp.Name = "AuraLightPart"
		lp.Size = Vector3.new(0.2, 0.2, 0.2)
		lp.Transparency = 1
		lp.CanCollide = false
		lp.CanQuery = false
		lp.CanTouch = false
		lp.Massless = true
		lp.Parent = character

		-- Set CFrame BEFORE creating weld to avoid position doubling with streaming
		lp.CFrame = rp.CFrame

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = rp
		weld.Part1 = lp
		weld.Parent = lp

		lightPart = lp
	end

	-- Reuse or create the light
	local light = lightPart:FindFirstChildOfClass("PointLight") or Instance.new("PointLight")
	light.Name = "AuraLight"
	light.Shadows = false
	light.Brightness = tonumber(def.lightBrightness) or 2
	light.Range = tonumber(def.lightRange) or 20
	light.Enabled = true
	light.Parent = lightPart

	-- Helper to set light properties
	local function setLight(c: Color3, b: number?, r: number?)
		light.Color = c
		if b then
			light.Brightness = b
		end
		if r then
			light.Range = r
		end
	end

	local connections: { RBXScriptConnection } = {}

	-- Handle colors and effects
	if def.effect == "rainbow" then
		-- Animated rainbow effect (10 updates/sec instead of 60)
		local last = 0
		local connection = RunService.Heartbeat:Connect(function(dt)
			last = last + dt
			if last < 0.1 then
				return
			end
			last = 0
			local hue = (Time.mono() * 0.3) % 1
			local rainbowColor = Color3.fromHSV(hue, 1, 1)
			emitter.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, rainbowColor),
				ColorSequenceKeypoint.new(0.5, Color3.fromHSV((hue + 0.5) % 1, 1, 1)),
				ColorSequenceKeypoint.new(1, rainbowColor),
			})
			-- Sync light color with rainbow if still attached
			if light:IsDescendantOf(character) then
				setLight(rainbowColor)
			end
		end)
		table.insert(connections, connection)
	elseif typeof(def.color) == "Color3" then
		emitter.Color = ColorSequence.new(def.color)
		setLight(def.color)
	end

	-- Special effect variations
	if def.effect == "void" then
		emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
		emitter.Color = ColorSequence.new(Color3.fromRGB(50, 0, 100))
		emitter.LightEmission = 0
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.1, 0.5),
			NumberSequenceKeypoint.new(0.9, 0.5),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 2),
			NumberSequenceKeypoint.new(1, 0),
		})
		-- Void: Very dim purple light
		setLight(Color3.fromRGB(50, 0, 100), 0.5, 10)
	elseif def.effect == "fire" then
		emitter.Texture = "rbxasset://textures/particles/fire_main.dds"
		emitter.LightEmission = 1
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(0.5, 1),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.Acceleration = Vector3.new(0, 5, 0)
		-- Fire: Warm orange glow
		setLight(def.color or Color3.fromRGB(255, 150, 50), 3, 25)
	elseif def.effect == "ice" then
		emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
		emitter.Speed = NumberRange.new(1, 2)
		emitter.Acceleration = Vector3.new(0, -2, 0)
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(1, 0.8),
		})
		-- Ice: Cool blue light
		setLight(def.color or Color3.fromRGB(100, 200, 255), 2, 20)
	elseif def.effect == "cosmic" then
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		emitter.LightEmission = 1
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.1, 0.5),
			NumberSequenceKeypoint.new(0.9, 0.5),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.RotSpeed = (typeof(def.rotSpeed) == "NumberRange") and def.rotSpeed
			or (type(def.rotSpeed) == "number" and NumberRange.new(-def.rotSpeed, def.rotSpeed))
			or NumberRange.new(-180, 180)
		emitter.VelocityInheritance = (type(def.velInheritance) == "number") and def.velInheritance or 0.5
		-- Cosmic: Bright white/purple starlight
		setLight(Color3.fromRGB(200, 150, 255), 4, 30)
	elseif def.effect == "energy" then
		-- Energy auras: Electric blue/yellow
		local energyColor = def.color or Color3.fromRGB(100, 200, 255)
		emitter.Color = ColorSequence.new(energyColor)
		setLight(energyColor, 2.5, 22)
	end

	-- Final explicit overrides (highest precedence)
	if
		typeof(def.lifetime) == "NumberRange"
		or type(def.lifetimeRange) == "table"
		or type(def.lifetime) == "number"
	then
		emitter.Lifetime = nr(def.lifetime or def.lifetimeRange, 1, 2)
	end
	if typeof(def.speed) == "NumberRange" or type(def.speedRange) == "table" or type(def.speed) == "number" then
		emitter.Speed = nr(def.speed or def.speedRange, 2, 4)
	end
	if def.spreadAngle then
		emitter.SpreadAngle = v2(def.spreadAngle, 360, 360)
	end
	if typeof(def.acceleration) == "Vector3" then
		emitter.Acceleration = def.acceleration
	end
	if def.rotSpeed then
		emitter.RotSpeed = (typeof(def.rotSpeed) == "NumberRange") and def.rotSpeed
			or (type(def.rotSpeed) == "number" and NumberRange.new(-def.rotSpeed, def.rotSpeed))
			or emitter.RotSpeed
	end
	if type(def.velInheritance) == "number" then
		emitter.VelocityInheritance = def.velInheritance
	end
	if typeof(def.color) == "Color3" then
		emitter.Color = ColorSequence.new(def.color)
		setLight(def.color, def.lightBrightness, def.lightRange)
	end
	if def.colorSequence then
		local cs = toColorSequence(def.colorSequence)
		if cs then
			emitter.Color = cs
		end
	end
	if def.sizeSequence then
		local ss = toNumberSequence(def.sizeSequence)
		if ss then
			emitter.Size = ss
		end
	end
	if def.transparencySequence then
		local ts = toNumberSequence(def.transparencySequence)
		if ts then
			emitter.Transparency = ts
		end
	end

	local retInstances: { Instance } = { attachment, emitter, lightPart, light }
	return { instances = retInstances, connections = connections }
end

function Aura.remove(ctx: RendererCtx)
	if not ctx then
		return
	end

	-- Disconnect connections first
	if ctx.connections then
		for _, conn in ipairs(ctx.connections) do
			if typeof(conn) == "RBXScriptConnection" then
				conn:Disconnect()
			end
		end
	end

	-- Clean up instances
	if ctx.instances then
		for _, inst in ipairs(ctx.instances) do
			if typeof(inst) == "Instance" and inst.Parent then
				-- Special handling for AuraLightPart to avoid conflicts if multiple auras share it
				if inst:IsA("Part") and inst.Name == "AuraLightPart" then
					-- Just disable the light instead of destroying the part
					-- This prevents issues if switching auras quickly
					local lightInst = inst:FindFirstChildOfClass("PointLight")
					if lightInst then
						lightInst.Enabled = false
					end
				else
					-- Destroy other instances normally (attachment, emitter, etc)
					inst:Destroy()
				end
			end
		end
	end
end

-- Register with the registry
RendererRegistry.register("aura", Aura)

return Aura
