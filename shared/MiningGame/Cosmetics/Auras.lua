--!strict
-- Cosmetics/Auras.lua

-- no ReplicatedStorage access needed here
-- local MG = ReplicatedStorage:WaitForChild("MiningGame")

local AURAS: { [string]: any } = {}

local Colors = {
	Orange = Color3.fromRGB(255, 150, 0),
	Ice = Color3.fromRGB(100, 200, 255),
	Void = Color3.fromRGB(50, 0, 100),
	Cosmic = Color3.fromRGB(100, 50, 150),
	Yellow = Color3.fromRGB(255, 255, 0),
}

AURAS["aura_fire"] = {
	id = "aura_fire",
	name = "Fire Aura",
	type = "cosmetic",
	slot = "aura",
	rarity = "RARE",
	value = 100,
	particleTexture = "rbxasset://textures/particles/fire_main.dds",
	emissionRate = 50,
	lightEmission = 1,
	effect = "fire",
	color = Colors.Orange,
	enhanced = false,
}

AURAS["aura_ice"] = {
	id = "aura_ice",
	name = "Ice Aura",
	type = "cosmetic",
	slot = "aura",
	rarity = "EPIC",
	value = 500,
	particleTexture = "rbxasset://textures/particles/smoke_main.dds",
	emissionRate = 40,
	lightEmission = 0.5,
	effect = "ice",
	color = Colors.Ice,
	enhanced = false,
}

AURAS["aura_rainbow"] = {
	id = "aura_rainbow",
	name = "Rainbow Aura",
	type = "cosmetic",
	slot = "aura",
	rarity = "LEGENDARY",
	value = 2500,
	effect = "rainbow",
	particleTexture = "rbxasset://textures/particles/sparkles_main.dds",
	emissionRate = 60,
	enhanced = true,
	perks = { luckMult = 1.12 },
}

AURAS["aura_void"] = {
	id = "aura_void",
	name = "Void Aura",
	type = "cosmetic",
	slot = "aura",
	rarity = "MYTHIC",
	value = 10000,
	color = Colors.Void,
	effect = "void",
	particleTexture = "rbxasset://textures/particles/smoke_main.dds",
	emissionRate = 100,
	enhanced = false,
}

AURAS["aura_cosmic"] = {
	id = "aura_cosmic",
	name = "Cosmic Aura",
	type = "cosmetic",
	slot = "aura",
	rarity = "MYTHIC",
	value = 10000,
	uiIconEffect = "cosmicShimmer",
	uiIconParams = { speedHz = 0.1, amplitude = 0.48 },
	color = Colors.Cosmic,
	effect = "cosmic",
	particleTexture = "rbxasset://textures/particles/sparkles_main.dds",
	emissionRate = 80,
	enhanced = false,
}

AURAS["aura_energy"] = {
	id = "aura_energy",
	name = "Energy Aura",
	type = "cosmetic",
	slot = "aura",
	rarity = "RARE",
	value = 100,
	particleTexture = "rbxasset://textures/particles/sparkles_main.dds",
	emissionRate = 45,
	lightEmission = 0.8,
	effect = "energy",
	color = Colors.Yellow,
	enhanced = false,
}

return AURAS
