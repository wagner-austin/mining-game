--!strict
--[[
    Back.lua
    Handles back cosmetics like wings, capes, and jetpacks.
]]

local RunService = game:GetService("RunService")
local Registry = require(script.Parent.Parent.RendererRegistry)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Time = require(Shared:WaitForChild("Time"))
local CosmeticMaterials = require(Shared:WaitForChild("CosmeticMaterials"))

local Back = {}
Back.priority = 50 -- Apply after model swap

type CosmeticDef = Registry.CosmeticDef
type RendererCtx = Registry.RendererCtx

type BackDef = CosmeticDef & {
	spanStuds: number?,
	wingHeight: number?,
	wingThickness: number?,
	mountX: number?,
	mountY: number?,
	mountZ: number?,
	highlight: boolean?,
	highlightColor: Color3?,
	highlightFillT: number?,
	highlightOutlineT: number?,
	animates: boolean?,
	animSpec: { speedHz: number?, freqHz: number?, amplitudeDeg: number?, axis: string? }?,
	effect: string?,
	color: Color3?,
	colorMode: string?,
	hueSpeedHz: number?,
	colorSpeedHz: number?,
	lightBrightness: number?,
	lightRange: number?,
	lightColor: Color3?,
}

function Back.apply(character: Model, def: CosmeticDef): RendererCtx?
	local torsoInst = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	local torso: BasePart? = (torsoInst and torsoInst:IsA("BasePart")) and torsoInst or nil
	if not torso then
		return
	end

	-- Fallback simple wings (procedural)
	local model = Instance.new("Model")
	model.Name = "CosmeticBack"
	model.Parent = character

	local left = Instance.new("Part")
	left.Name = "LeftWing"
	local span = def.spanStuds or 3
	local height = def.wingHeight or 4
	local thick = def.wingThickness or 0.5
	left.Size = Vector3.new(span, height, thick)
	left.CanCollide = false
	left.CanQuery = false
	left.CanTouch = false
	left.Massless = true
	left.Anchored = false
	left.Material = CosmeticMaterials.pick(def)
	if typeof(def.color) == "Color3" then
		left.Color = def.color
	else
		left.BrickColor = BrickColor.new("White")
	end
	if type(def.transparency) == "number" then
		left.Transparency = math.clamp(def.transparency, 0, 1)
	end
	left.Parent = model

	local right = left:Clone()
	right.Name = "RightWing"
	right.Anchored = false
	if type(def.transparency) == "number" then
		right.Transparency = math.clamp(def.transparency, 0, 1)
	end
	right.Parent = model

	-- Apply style based on ID (only when no explicit presets provided)
	local hasExplicit = (def.material ~= nil) or (def.materialPreset ~= nil) or (typeof(def.color) == "Color3")
	if (not hasExplicit) and def.id and string.find(def.id, "fire") then
		left.BrickColor = BrickColor.new("Bright orange")
		right.BrickColor = BrickColor.new("Bright orange")
		left.Material = Enum.Material.Neon
		right.Material = Enum.Material.Neon
	elseif (not hasExplicit) and def.id and string.find(def.id, "ice") then
		left.BrickColor = BrickColor.new("Cyan")
		right.BrickColor = BrickColor.new("Cyan")
		left.Material = Enum.Material.Ice
		right.Material = Enum.Material.Ice
	elseif (not hasExplicit) and def.id and string.find(def.id, "void") then
		left.BrickColor = BrickColor.new("Dark indigo")
		right.BrickColor = BrickColor.new("Dark indigo")
		left.Material = Enum.Material.ForceField
		right.Material = Enum.Material.ForceField
	end

	-- Optional lighting for fallback parts
	do
		local lb = tonumber(def.lightBrightness)
		if lb and lb > 0 then
			local function addLight(p: BasePart)
				local light = Instance.new("PointLight")
				light.Name = "BackLight"
				light.Brightness = lb
				light.Range = tonumber(def.lightRange) or 8
				if typeof(def.lightColor) == "Color3" then
					light.Color = def.lightColor
				elseif typeof(def.color) == "Color3" then
					light.Color = def.color
				end
				light.Parent = p
			end
			addLight(left)
			addLight(right)
		end
	end

	-- Use Motor6Ds for animatable wings
	local leftMotor = Instance.new("Motor6D")
	leftMotor.Name = "LeftWingMotor"
	leftMotor.Part0 = torso
	leftMotor.Part1 = left
	leftMotor.Parent = torso
	local mountX = tonumber(def.mountX) or 2
	local mountY = tonumber(def.mountY) or 0
	local mountZ = tonumber(def.mountZ) or 1
	leftMotor.C0 = CFrame.new(-mountX, mountY, mountZ)

	local rightMotor = Instance.new("Motor6D")
	rightMotor.Name = "RightWingMotor"
	rightMotor.Part0 = torso
	rightMotor.Part1 = right
	rightMotor.Parent = torso
	rightMotor.C0 = CFrame.new(mountX, mountY, mountZ)

	local conns: { RBXScriptConnection } = {}
	-- Optional highlight outline for semi-transparent/glass wings
	if def.highlight or def.highlightColor then
		local hl = Instance.new("Highlight")
		hl.Name = "BackHighlight"
		hl.Adornee = model
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.FillTransparency = math.clamp(tonumber(def.highlightFillT) or 0.85, 0, 1)
		hl.OutlineTransparency = math.clamp(tonumber(def.highlightOutlineT) or 0.25, 0, 1)
		local hc = (typeof(def.highlightColor) == "Color3") and def.highlightColor or left.Color
		if hc then
			hl.OutlineColor = hc
		end
		hl.Parent = model
	end

	-- Optional tiny base particle emitters removed (dead code)
	if tostring(def.effect or def.colorMode or ""):lower() == "rainbow" then
		local hueHz = tonumber(def.hueSpeedHz or def.colorSpeedHz) or 0.25
		local lights = {}
		for _, d in ipairs({ left, right }) do
			local l = d:FindFirstChild("BackLight")
			if l and l:IsA("PointLight") then
				table.insert(lights, l)
			end
		end
		table.insert(
			conns,
			RunService.Heartbeat:Connect(function()
				local h = (Time.mono() * hueHz) % 1
				local c = Color3.fromHSV(h, 1, 1)
				left.Color = c
				right.Color = c
				for _, l in ipairs(lights) do
					l.Color = c
				end
			end)
		)
	end

	if def.animates ~= false then -- Default to animated
		local freq = (def.animSpec and (def.animSpec.speedHz or def.animSpec.freqHz)) or 2.5
		local ampDeg = (def.animSpec and def.animSpec.amplitudeDeg) or 22
		if ampDeg < 5 then
			ampDeg = 22
		end -- ensure visible motion
		local axis = (def.animSpec and def.animSpec.axis) or "yaw"
		local conn = RunService.Heartbeat:Connect(function()
			local flap = math.sin(Time.mono() * freq) * math.rad(ampDeg)
			if axis == "pitch" then
				leftMotor.Transform = CFrame.Angles(flap, 0, 0)
				rightMotor.Transform = CFrame.Angles(flap, 0, 0)
			elseif axis == "roll" then
				leftMotor.Transform = CFrame.Angles(0, 0, flap)
				rightMotor.Transform = CFrame.Angles(0, 0, flap)
			else
				leftMotor.Transform = CFrame.Angles(0, -flap, 0)
				rightMotor.Transform = CFrame.Angles(0, flap, 0)
			end
		end)
		table.insert(conns, conn)
	end

	model.PrimaryPart = left
	local instances: { Instance } = { model, leftMotor, rightMotor }
	return { instances = instances, connections = conns }
end

function Back.remove(ctx: RendererCtx)
	if ctx and ctx.connections then
		for _, c in ipairs(ctx.connections) do
			if typeof(c) == "RBXScriptConnection" then
				c:Disconnect()
			end
		end
	end
	if ctx and ctx.instances then
		for _, i in ipairs(ctx.instances) do
			if typeof(i) == "Instance" then
				i:Destroy()
			end
		end
	end
end

Registry.register("back", Back)
return Back
