--!strict
-- Cosmetics/Wings.lua (Back items)

local Wings: { [string]: any } = {}

local Colors = {
	White = Color3.fromRGB(255, 255, 255),
	Cyan = Color3.fromRGB(0, 255, 255),
	Void = Color3.fromRGB(50, 0, 100),
}

-- Minimal curated wings
local wingTypes = {
	angel = { name = "Angel Wings", rarity = "EPIC", value = 500 },
	demon = { name = "Demon Wings", rarity = "LEGENDARY", value = 2500 },
	void = { name = "Void Wings", rarity = "MYTHIC", value = 10000 },
}

for wingType, wingData in pairs(wingTypes) do
	local id = "back_" .. wingType
	Wings[id] = {
		id = id,
		name = wingData.name,
		type = "cosmetic",
		slot = "back",
		rarity = wingData.rarity,
		value = wingData.value,
		animates = true,
		enhanced = false,
	}
end

Wings["back_rainbow_wings"] = {
	id = "back_rainbow_wings",
	name = "Rainbow Wings",
	type = "cosmetic",
	slot = "back",
	rarity = "LEGENDARY",
	value = 4000,
	-- Increase drop likelihood ~3x over default LEGENDARY cosmetic weight (2 * 0.01 = 0.02 → 0.06)
	dropWeight = 0.06,
	animates = true,
	effect = "rainbow",
	materialPreset = "neon",
	hueSpeedHz = 0.20,
	lightBrightness = 0.6,
	lightRange = 10,
	enhanced = false,
}

Wings["back_quad_wings"] = {
	id = "back_quad_wings",
	name = "Quad Wings",
	type = "cosmetic",
	slot = "back",
	rarity = "LEGENDARY",
	value = 3000,
	-- Increase drop likelihood ~3x over default LEGENDARY cosmetic weight (2 * 0.01 = 0.02 → 0.06)
	dropWeight = 0.06,
	animates = true,
	enhanced = true,
	perks = { extraJumps = 2 },
	materialPreset = "neon",
	color = Colors.Cyan,
	lightBrightness = 0.6,
	lightRange = 10,
	description = "Lightweight wings that grant two additional air jumps.",
	notes = "Enhanced-ready: add perks later.",
}

-- Tuning for curated wings
do
	local angel = Wings["back_angel"]
	if angel then
		angel.animSpec = angel.animSpec or { speedHz = 2.2, amplitudeDeg = 10, axis = "yaw" }
		angel.enhanced = false
		angel.color = Colors.White
		angel.materialPreset = "neon"
	end

	local demon = Wings["back_demon"]
	if demon then
		demon.animSpec = demon.animSpec or { speedHz = 2.0, amplitudeDeg = 12, axis = "yaw" }
		demon.enhanced = false
		demon.color = Color3.fromRGB(170, 20, 20)
		demon.materialPreset = "neon"
		demon.baseParticles = nil
	end

	local void = Wings["back_void"]
	if void then
		void.animSpec = void.animSpec or { speedHz = 1.6, amplitudeDeg = 12, axis = "yaw" }
		void.enhanced = false
		void.color = Colors.Void
		void.materialPreset = "glass"
		void.transparency = 0.35
		void.lightBrightness = 0.8
		void.lightColor = Colors.Void
		void.lightRange = 10
		void.highlight = false
		void.highlightColor = nil
		void.highlightFillT = nil
		void.highlightOutlineT = nil
	end
end

return Wings
