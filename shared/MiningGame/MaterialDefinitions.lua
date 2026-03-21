--!strict
-- MaterialDefinitions.lua
-- Single source of truth for all terrain material properties
--
-- TO ADD A NEW MATERIAL:
-- 1. Add a new entry in MaterialDefinitions.Materials with:
--    - enum: one of Roblox's terrain Enum.Material values
--    - displayName: human-readable name
--    - order: (optional) controls UI/list order, lower = earlier
--    - properties: must include speedMultiplier, soundCategory, color
--    - soundCategory must be a valid category from SoundCategories
-- 2. That's it! MaterialKeys, movement speeds, sounds, and UI all pick it up automatically.

local SoundCategories = require(script.Parent.SoundCategories)

local MaterialDefinitions = {}

export type MaterialProperty = {
	speedMultiplier: number,
	soundCategory: string,
	digDifficulty: number,
	color: Color3,
	isLiquid: boolean?,
}

export type MaterialDef = {
	enum: Enum.Material,
	displayName: string,
	order: number?,
	properties: MaterialProperty,
}

-- Complete definition of all terrain materials and their properties
-- Each material MUST have a corresponding Enum.Material value from Roblox
MaterialDefinitions.Materials = {
	-- Core mining materials (ordered first)
	rock = {
		enum = Enum.Material.Rock,
		displayName = "Rock",
		order = 1,
		properties = {
			speedMultiplier = 0.95, -- Slightly slower on rock
			soundCategory = "rock",
			digDifficulty = 1.0,
			color = Color3.fromRGB(140, 140, 140),
		},
	},
	sandstone = {
		enum = Enum.Material.Sandstone,
		displayName = "Sandstone",
		order = 2,
		properties = {
			speedMultiplier = 0.95, -- Similar to rock
			soundCategory = "rock",
			digDifficulty = 0.9,
			color = Color3.fromRGB(199, 172, 120),
		},
	},
	basalt = {
		enum = Enum.Material.Basalt,
		displayName = "Basalt",
		order = 3,
		properties = {
			speedMultiplier = 0.90, -- Harder rock, more difficult
			soundCategory = "rock",
			digDifficulty = 1.3,
			color = Color3.fromRGB(75, 74, 74),
		},
	},
	slate = {
		enum = Enum.Material.Slate,
		displayName = "Slate",
		order = 4,
		properties = {
			speedMultiplier = 1.00, -- Standard mine floor
			soundCategory = "rock",
			digDifficulty = 1.1,
			color = Color3.fromRGB(88, 89, 86),
		},
	},
	limestone = {
		enum = Enum.Material.Limestone,
		displayName = "Limestone",
		order = 5,
		properties = {
			speedMultiplier = 0.95, -- Similar to rock
			soundCategory = "rock",
			digDifficulty = 0.9,
			color = Color3.fromRGB(255, 243, 192),
		},
	},

	-- Ice/Snow materials
	glacier = {
		enum = Enum.Material.Glacier,
		displayName = "Glacier",
		order = 10,
		properties = {
			speedMultiplier = 1.15, -- Slippery like ice
			soundCategory = "ice",
			digDifficulty = 1.2,
			color = Color3.fromRGB(221, 228, 229),
		},
	},
	ice = {
		enum = Enum.Material.Ice,
		displayName = "Ice",
		order = 11,
		properties = {
			speedMultiplier = 1.20, -- Ice caves are slippery but fast
			soundCategory = "ice",
			digDifficulty = 0.8,
			color = Color3.fromRGB(204, 210, 223),
		},
	},
	snow = {
		enum = Enum.Material.Snow,
		displayName = "Snow",
		order = 12,
		properties = {
			speedMultiplier = 0.85, -- Slower than normal
			soundCategory = "snow",
			digDifficulty = 0.2,
			color = Color3.fromRGB(255, 255, 255),
		},
	},

	-- Soft materials
	sand = {
		enum = Enum.Material.Sand,
		displayName = "Sand",
		order = 20,
		properties = {
			speedMultiplier = 0.75, -- Sandy areas slow you down
			soundCategory = "sand",
			digDifficulty = 0.3,
			color = Color3.fromRGB(255, 197, 139),
		},
	},
	mud = {
		enum = Enum.Material.Mud,
		displayName = "Mud",
		order = 21,
		properties = {
			speedMultiplier = 0.60, -- Very slow in muddy areas
			soundCategory = "mud",
			digDifficulty = 0.4,
			color = Color3.fromRGB(58, 46, 36),
		},
	},
	ground = {
		enum = Enum.Material.Ground,
		displayName = "Ground",
		order = 22,
		properties = {
			speedMultiplier = 1.00,
			soundCategory = "dirt",
			digDifficulty = 0.6,
			color = Color3.fromRGB(140, 130, 104),
		},
	},
	grass = {
		enum = Enum.Material.Grass,
		displayName = "Grass",
		order = 23,
		properties = {
			speedMultiplier = 1.00,
			soundCategory = "grass",
			digDifficulty = 0.5,
			color = Color3.fromRGB(86, 125, 70),
		},
	},
	leafygrass = {
		enum = Enum.Material.LeafyGrass,
		displayName = "Leafy Grass",
		order = 24,
		properties = {
			speedMultiplier = 1.00,
			soundCategory = "grass",
			digDifficulty = 0.5,
			color = Color3.fromRGB(115, 132, 74),
		},
	},

	-- Constructed materials
	concrete = {
		enum = Enum.Material.Concrete,
		displayName = "Concrete",
		order = 30,
		properties = {
			speedMultiplier = 1.10, -- Constructed paths are faster
			soundCategory = "rock",
			digDifficulty = 0.9,
			color = Color3.fromRGB(127, 142, 100),
		},
	},
	cobblestone = {
		enum = Enum.Material.Cobblestone,
		displayName = "Cobblestone",
		order = 31,
		properties = {
			speedMultiplier = 0.95, -- Slightly rough surface
			soundCategory = "rock",
			digDifficulty = 1.0,
			color = Color3.fromRGB(134, 134, 118),
		},
	},
	brick = {
		enum = Enum.Material.Brick,
		displayName = "Brick",
		order = 32,
		properties = {
			speedMultiplier = 1.00,
			soundCategory = "rock",
			digDifficulty = 0.9,
			color = Color3.fromRGB(138, 86, 62),
		},
	},
	asphalt = {
		enum = Enum.Material.Asphalt,
		displayName = "Asphalt",
		order = 33,
		properties = {
			speedMultiplier = 1.05, -- Slightly faster on smooth asphalt
			soundCategory = "rock",
			digDifficulty = 0.8,
			color = Color3.fromRGB(60, 60, 60),
		},
	},
	pavement = {
		enum = Enum.Material.Pavement,
		displayName = "Pavement",
		order = 34,
		properties = {
			speedMultiplier = 1.05, -- Slightly faster on pavement
			soundCategory = "rock",
			digDifficulty = 0.8,
			color = Color3.fromRGB(148, 148, 140),
		},
	},
	salt = {
		enum = Enum.Material.Salt,
		displayName = "Salt",
		order = 35,
		properties = {
			speedMultiplier = 0.90, -- Slightly rough
			soundCategory = "sand", -- Granular material, sounds like sand
			digDifficulty = 0.7,
			color = Color3.fromRGB(255, 255, 254),
		},
	},
	woodplanks = {
		enum = Enum.Material.WoodPlanks,
		displayName = "Wood Planks",
		order = 36,
		properties = {
			speedMultiplier = 1.00,
			soundCategory = "wood",
			digDifficulty = 0.6,
			color = Color3.fromRGB(128, 102, 64),
		},
	},

	-- Special materials
	water = {
		enum = Enum.Material.Water,
		displayName = "Water",
		order = 40,
		properties = {
			speedMultiplier = 0.70, -- Wading through underground water
			soundCategory = "water",
			digDifficulty = 0.5, -- Easy to displace water
			isLiquid = true, -- Special handling for liquid materials
			color = Color3.fromRGB(138, 167, 168),
		},
	},
	crackedlava = {
		enum = Enum.Material.CrackedLava,
		displayName = "Cracked Lava",
		order = 41,
		properties = {
			speedMultiplier = 0.70, -- Dangerous terrain, slower
			soundCategory = "rock",
			digDifficulty = 1.5,
			color = Color3.fromRGB(255, 24, 67),
		},
	},
} :: { [string]: MaterialDef }

-- Helper functions to access material data

-- Get all material keys as an array (sorted by order then alphabetically)
function MaterialDefinitions.GetAllKeys(): { string }
	local keyed: { { key: string, order: number } } = {}
	for key, def in pairs(MaterialDefinitions.Materials) do
		table.insert(keyed, { key = key, order = def.order or math.huge })
	end
	table.sort(keyed, function(a: { key: string, order: number }, b: { key: string, order: number })
		if a.order == b.order then
			return a.key < b.key
		end
		return a.order < b.order
	end)

	local keys = {}
	for _, row in ipairs(keyed) do
		table.insert(keys, row.key)
	end
	return keys
end

-- Get Enum.Material from key
function MaterialDefinitions.GetEnum(key: string): Enum.Material?
	key = string.lower(key or "")
	local def = MaterialDefinitions.Materials[key]
	return def and def.enum or nil
end

-- Get display name from key
function MaterialDefinitions.GetDisplayName(key: string): string
	key = string.lower(key or "")
	local def = MaterialDefinitions.Materials[key]
	return def and def.displayName or key
end

-- Get property from key
function MaterialDefinitions.GetProperty(key: string, propertyName: string): any
	key = string.lower(key or "")
	local def = MaterialDefinitions.Materials[key]
	if def and def.properties then
		return def.properties[propertyName]
	end
	return nil
end

-- Get all properties for a material
function MaterialDefinitions.GetProperties(key: string): MaterialProperty?
	key = string.lower(key or "")
	local def = MaterialDefinitions.Materials[key]
	return def and def.properties or nil
end

-- Build reverse lookup table (Enum -> key)
MaterialDefinitions.KeyFromEnum = {} :: { [Enum.Material]: string }
for key, def in pairs(MaterialDefinitions.Materials) do
	MaterialDefinitions.KeyFromEnum[def.enum] = key
end

-- Precomputed array of all terrain Enum.Material values (sorted by order)
MaterialDefinitions.AllTerrainEnums = (function()
	local keyed: { { key: string, order: number, enum: Enum.Material } } = {}
	for key, def in pairs(MaterialDefinitions.Materials) do
		table.insert(keyed, { key = key, order = def.order or math.huge, enum = def.enum :: Enum.Material })
	end
	table.sort(keyed, function(a: { key: string, order: number }, b: { key: string, order: number })
		if a.order == b.order then
			return a.key < b.key
		end
		return a.order < b.order
	end)

	local out = {}
	for _, row in ipairs(keyed) do
		table.insert(out, row.enum)
	end
	return out
end)()

-- Precomputed ordered keys list
MaterialDefinitions.KeysOrdered = (function()
	local t: { { key: string, order: number } } = {}
	for key, def in pairs(MaterialDefinitions.Materials) do
		table.insert(t, { key = key, order = def.order or math.huge })
	end
	table.sort(t, function(a: { key: string, order: number }, b: { key: string, order: number })
		if a.order == b.order then
			return a.key < b.key
		end
		return a.order < b.order
	end)
	local out = {}
	for _, r in ipairs(t) do
		table.insert(out, r.key)
	end
	return out
end)()

-- Helper to get speed multiplier from Enum.Material
function MaterialDefinitions.GetSpeedFromEnum(mat: Enum.Material): number
	local key = MaterialDefinitions.KeyFromEnum[mat]
	if not key then
		return 1.0
	end
	local props = MaterialDefinitions.Materials[key].properties
	return (props and props.speedMultiplier) or 1.0
end

-- Validation at startup
do
	local seen = {}
	for key, def in pairs(MaterialDefinitions.Materials) do
		-- Check for duplicate enum values
		if seen[def.enum] then
			error(
				("[MaterialDefinitions] Duplicate Enum.Material: %s used by both '%s' and '%s'"):format(
					tostring(def.enum),
					seen[def.enum],
					key
				)
			)
		end
		seen[def.enum] = key

		-- Validate required fields
		assert(def.displayName, ("[MaterialDefinitions] Missing displayName for '%s'"):format(key))
		assert(def.properties, ("[MaterialDefinitions] Missing properties for '%s'"):format(key))
		assert(def.properties.speedMultiplier, ("[MaterialDefinitions] Missing speedMultiplier for '%s'"):format(key))
		assert(def.properties.soundCategory, ("[MaterialDefinitions] Missing soundCategory for '%s'"):format(key))
		assert(def.properties.color, ("[MaterialDefinitions] Missing color for '%s'"):format(key))

		-- Validate soundCategory is valid
		assert(
			SoundCategories.IsValid(def.properties.soundCategory),
			("[MaterialDefinitions] Invalid soundCategory '%s' for material '%s'. Valid categories: %s"):format(
				def.properties.soundCategory,
				key,
				table.concat(SoundCategories.Ordered, ", ")
			)
		)
	end
end

-- Freeze all nested tables for complete immutability
MaterialDefinitions.AllTerrainEnums = table.freeze(MaterialDefinitions.AllTerrainEnums)
MaterialDefinitions.KeysOrdered = table.freeze(MaterialDefinitions.KeysOrdered)

for _, def in pairs(MaterialDefinitions.Materials) do
	def.properties = table.freeze(def.properties)
end
MaterialDefinitions.KeyFromEnum = table.freeze(MaterialDefinitions.KeyFromEnum)
MaterialDefinitions.Materials = table.freeze(MaterialDefinitions.Materials)

return table.freeze(MaterialDefinitions)
