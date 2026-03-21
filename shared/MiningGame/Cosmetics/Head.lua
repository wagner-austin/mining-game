--!strict
-- Cosmetics/Head.lua

-- local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- local MG = ReplicatedStorage:WaitForChild("MiningGame")
-- local Materials = require(MG:WaitForChild("CosmeticMaterials"))

local Head: { [string]: any } = {}

local Colors = {
	Gold = Color3.fromRGB(255, 215, 0),
	White = Color3.fromRGB(255, 255, 255),
}

-- Crown
Head["head_crown_gold"] = {
	id = "head_crown_gold",
	name = "Golden Crown",
	type = "cosmetic",
	slot = "head",
	rarity = "LEGENDARY",
	value = 2500,
	procedural = { kind = "crown" },
	color = Colors.Gold,
	materialPreset = "neon",
	glows = true,
	spikeCount = 7,
	segments = 18,
	enhanced = false,
}

-- Horns (procedural)
Head["head_horns_neon"] = {
	id = "head_horns_neon",
	name = "Neon Horns",
	type = "cosmetic",
	slot = "head",
	rarity = "UNCOMMON",
	value = 50,
	glows = true,
	color = Colors.White,
	procedural = { kind = "horns" },
	materialPreset = "neon",
	hornLength = 1.2,
	hornRadius = 0.22,
	hornSeparation = 0.55,
	hornTiltDeg = 18,
	hornHeightOffset = 0.08,
	segments = 4,
	enhanced = false,
}

-- Sunglasses (procedural)
Head["head_glasses_sunglasses"] = {
	id = "head_glasses_sunglasses",
	name = "Sunglasses",
	type = "cosmetic",
	slot = "head",
	rarity = "COMMON",
	value = 10,
	glows = false,
	procedural = { kind = "sunglasses" },
	materialPreset = "neon",
	lensTint = Color3.fromRGB(10, 10, 10),
	lensTransparency = 0.5,
	frameColor = Color3.fromRGB(20, 20, 20),
	glassesForwardOffset = 0.09,
	glassesHeightOffset = 0.12,
	enhanced = false,
}

-- Halo (procedural)
Head["head_halo_thick"] = {
	id = "head_halo_thick",
	name = "Halo",
	type = "cosmetic",
	slot = "head",
	rarity = "UNCOMMON",
	value = 25,
	glows = true,
	color = Colors.Gold,
	procedural = { kind = "halo" },
	materialPreset = "neon",
	haloThickness = 0.14,
	segments = 24,
	enhanced = false,
}

-- Speed Charm (enhanced)
Head["head_speed_charm"] = {
	id = "head_speed_charm",
	name = "Speed Charm",
	type = "cosmetic",
	slot = "head",
	rarity = "EPIC",
	value = 1500,
	enhanced = true,
	perks = { speedMult = 1.10 },
	description = "A radiant charm that increases movement speed.",
	procedural = { kind = "charm" },
	materialPreset = "neon",
	color = Color3.fromRGB(0, 255, 200),
	charmPlacement = "top",
	charmCoreRadius = 0.22,
	charmRingThickness = 0.06,
	charmRingRadius = 0.32,
	charmHeightOffset = 0.9,
	charmForwardOffset = 0.25,
	charmSpinHz = 1.2,
	charmOrbRing = true,
	charmOrbCount = 10,
	charmOrbSmallRadius = 0.12,
	charmOrbMediumRadius = 0.18,
}

return Head
