--!strict
-- Cosmetics/Hand.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MG = ReplicatedStorage:WaitForChild("MiningGame")
local Materials = require(MG:WaitForChild("CosmeticMaterials"))

local Hand: { [string]: any } = {}

Hand["hand_pickaxe_base"] = {
	id = "hand_pickaxe_base",
	name = "Pickaxe",
	type = "cosmetic",
	slot = "hand",
	rarity = "COMMON",
	value = 10,
	handleMaterial = Materials.Neon,
	handleTint = Color3.fromRGB(255, 255, 255),
	headMaterial = Materials.Neon,
	headTint = Color3.fromRGB(30, 60, 200),
	headHighlight = true,
	headPulse = true,
	headPulseSpeed = 1.8,
	headPulseColor2 = Color3.fromRGB(120, 255, 255),
	handleLength = 5.5,
	handleRadius = 0.22,
	headLength = 4.2,
	headWidth = 0.5,
	headHeight = 1.2,
	procedural = { kind = "pickaxe" },
	enhanced = false,
}

Hand["hand_sword_base"] = {
	id = "hand_sword_base",
	name = "Sword",
	type = "cosmetic",
	slot = "hand",
	rarity = "COMMON",
	value = 10,
	material = Materials.Neon,
	tint = Color3.fromRGB(255, 255, 255),
	bladeTint = Color3.fromRGB(0, 200, 80),
	bladeHighlight = true,
	pulse = true,
	pulseSpeed = 1.8,
	pulseColor2 = Color3.fromRGB(120, 220, 255),
	bladeLength = 6.0,
	bladeWidth = 1.3,
	bladeThickness = 0.26,
	procedural = { kind = "sword" },
	enhanced = false,
}

Hand["hand_warhammer_base"] = {
	id = "hand_warhammer_base",
	name = "Warhammer",
	type = "cosmetic",
	slot = "hand",
	rarity = "UNCOMMON",
	value = 40,
	handleMaterial = Materials.Neon,
	handleTint = Color3.fromRGB(255, 255, 255),
	headMaterial = Materials.Neon,
	headTint = Color3.fromRGB(180, 0, 0),
	handleLength = 6.0,
	headLength = 2.3,
	headWidth = 2.0,
	headHeight = 1.65,
	headPulse = true,
	headPulseSpeed = 1.8,
	headPulseColor2 = Color3.fromRGB(255, 40, 40),
	headHighlight = true,
	gripHandOffsetY = -0.15,
	procedural = { kind = "warhammer" },
	enhanced = false,
}

return Hand
