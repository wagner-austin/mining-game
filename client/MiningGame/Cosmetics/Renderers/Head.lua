--!strict
--[[
    Head.lua
    Handles head accessories like crowns, halos, helmets, etc.
]]

local Registry = require(script.Parent.Parent.RendererRegistry)
type CosmeticDef = Registry.CosmeticDef
type RendererCtx = Registry.RendererCtx
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(Shared:WaitForChild("Logger"))
local log = Logger.new("CosmeticHead")
local HeadBuilders = require(script.Parent.Parent.Procedural.HeadBuilders)

local Head = {}
Head.priority = 45 -- Apply after back items

function Head.apply(character: Model, def: CosmeticDef, _ctx: RendererCtx?): RendererCtx?
	log:info("Apply head cosmetic: id=%s for %s", tostring(def and def.id), character.Name)
	local headInst = character:FindFirstChild("Head")
	if not (headInst and headInst:IsA("BasePart")) then
		log:warn("No Head found on character %s", character.Name)
		return nil
	end
	local head: BasePart = headInst

	-- Explicit procedural path (bypass asset lookup when specified)
	local procKind = (def and def.procedural and def.procedural.kind) or nil
	local shape = def and def.shape or nil

	if (procKind == "horns") or (shape == "horns") then
		local ctx2 = HeadBuilders.horns(character, head, def)
		if ctx2 then
			return ctx2
		end
	elseif (procKind == "halo") or (shape == "halo") then
		local ctx2 = HeadBuilders.halo(character, head, def)
		if ctx2 then
			return ctx2
		end
	elseif (procKind == "crown") or (shape == "crown") then
		local ctx2 = HeadBuilders.crown(character, head, def)
		if ctx2 then
			return ctx2
		end
	elseif (procKind == "charm") or (shape == "charm") then
		local ctx2 = HeadBuilders.charm(character, head, def)
		if ctx2 then
			return ctx2
		end
	elseif (procKind == "sunglasses") or (shape == "sunglasses") then
		local ctx2 = HeadBuilders.sunglasses(character, head, def)
		if ctx2 then
			return ctx2
		end
	end

	-- Assets-based path removed: Head renderer is procedural-only now

	-- Fallback placeholder accessories
	log:debug("Using placeholder for head cosmetic id=%s", tostring(def and def.id))
	local headPart: BasePart = head
	local part = Instance.new("Part")
	local idStr = tostring(def and def.id or "item")
	part.Name = ("CosmeticHead_%s"):format(idStr)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.Parent = character

	-- Style based on id hints
	local idLower = string.lower(idStr)
	if string.find(idLower, "crown") then
		local ctx2 = HeadBuilders.crown(character, head, def)
		part:Destroy()
		return ctx2
	elseif string.find(idLower, "halo") then
		local ctx2 = HeadBuilders.halo(character, head, def)
		part:Destroy()
		return ctx2
	elseif string.find(idLower, "horns") then
		-- Use procedural horns builder for id-matched horns
		local ctx2 = HeadBuilders.horns(character, head, def)
		part:Destroy()
		return ctx2
	elseif string.find(idLower, "glasses") then
		local ctx2 = HeadBuilders.sunglasses(character, head, def)
		part:Destroy()
		return ctx2
	elseif string.find(idLower, "helmet") then
		part.Size = Vector3.new(1.2, 1.2, 1.2)
		part.Shape = Enum.PartType.Ball
		part.Material = Enum.Material.Metal
		part.BrickColor = BrickColor.new("Dark stone grey")
		part.CFrame = headPart.CFrame
	else
		-- Generic head accessory
		part.Size = Vector3.new(1, 0.5, 1)
		part.Material = Enum.Material.Neon
		part.CFrame = headPart.CFrame * CFrame.new(0, 1, 0)
	end

	-- Weld to head
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = headPart
	weld.Part1 = part
	weld.Parent = part
	log:debug("Placeholder welded for head cosmetic id=%s", tostring(def and def.id))

	-- Add glow if specified
	if def.glows then
		local light = Instance.new("PointLight")
		light.Brightness = 2
		light.Range = 10
		light.Parent = part
	end

	local instances: { Instance } = { part }
	return { instances = instances }
end

function Head.remove(ctx: RendererCtx)
	log:debug("Removing head cosmetic context")
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

Registry.register("head", Head)
return Head
