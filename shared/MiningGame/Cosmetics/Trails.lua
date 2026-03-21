--!strict
-- Cosmetics/Trails.lua

-- Trails table populated from generated variants

local Colors = {
	Pink = Color3.fromRGB(255, 100, 200),
	Cyan = Color3.fromRGB(0, 255, 255),
	Green = Color3.fromRGB(50, 200, 50),
	Purple = Color3.fromRGB(150, 50, 200),
	White = Color3.fromRGB(255, 255, 255),
}

local function generateColorVariations(baseName: string, baseItem: { [string]: any }, colorMap: { [string]: Color3 })
	local out = {}
	for suffix, color in pairs(colorMap) do
		local id = string.format("%s_%s", baseName, suffix)
		local item = table.clone(baseItem)
		item.id = id
		item.name = baseItem.name or "Neon Trail"
		item.color = color
		out[id] = item
	end
	return out
end

local neonTrails = generateColorVariations("trail_neon", {
	slot = "trail",
	type = "cosmetic",
	rarity = "RARE",
	value = 100,
	effect = "neon",
	enhanced = false,
	-- Normalize lifetime and taper across all remaining trails
	lifetime = 1.25,
	widthScaleSequence = {
		{ t = 0.00, v = 1.00 },
		{ t = 0.80, v = 0.30 },
		{ t = 1.00, v = 0.00 },
	},
	lightEmission = 1,
	name = "Neon Trail",
}, {
	pink = Colors.Pink,
	cyan = Colors.Cyan,
	green = Colors.Green,
	purple = Colors.Purple,
})

-- Enhance per-variant properties
for id, item in pairs(neonTrails) do
	local lid = string.lower(id)
	if string.find(lid, "_pink", 1, true) then
		item.colorSequence = { Colors.Pink, Colors.Purple }
		item.bandCount = 2
		item.bandSeparation = 0.3
		item.bandAxis = "up"
		item.bandOffset = 0.2
	elseif string.find(lid, "_cyan", 1, true) then
		item.colorSequence = { Colors.Cyan, Color3.fromRGB(0, 180, 255), Colors.White }
	elseif string.find(lid, "_green", 1, true) then
		item.colorSequence = { Color3.fromRGB(140, 255, 140), Colors.Green, Color3.fromRGB(0, 200, 120) }
	elseif string.find(lid, "_purple", 1, true) then
		item.colorSequence = { Colors.Purple, Color3.fromRGB(100, 50, 180) }
		item.widthScaleSequence = {
			{ t = 0.00, v = 1.00 },
			{ t = 0.98, v = 1.00 },
			{ t = 1.00, v = 0.00 },
		}
	end
end

local Trails: { [string]: any } = table.clone(neonTrails)

Trails["trail_rainbow"] = {
	id = "trail_rainbow",
	name = "Rainbow Trail",
	type = "cosmetic",
	slot = "trail",
	rarity = "LEGENDARY",
	value = 2500,
	effect = "rainbow",
	lifetime = 1.25,
	widthScaleSequence = {
		{ t = 0.00, v = 1.00 },
		{ t = 0.80, v = 0.30 },
		{ t = 1.00, v = 0.00 },
	},
	lightEmission = 1,
	enhanced = false,
}

return Trails
