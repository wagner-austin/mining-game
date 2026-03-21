--!strict
-- SoundDefs.lua
-- Single source of truth for all Roblox audio asset IDs

local SoundDefs = {}

-- Structured definitions with attached metadata (extend as needed)
local DEFS = {
	-- UI
	UI_BUTTON_CLICK = { id = "rbxassetid://6324790483", creator = "zachnotes" },
	UI_NOTIFICATION = { id = "rbxassetid://131136929849120", creator = "valigeorge8" },
	UI_MENU_OPEN = { id = "rbxassetid://97861038165143", creator = "AmbientSorcery" },
	UI_ERROR = { id = "rbxassetid://87519554692663", creator = "AmbientSorcery" },

	-- Mining (rock baseline)
	MINING_ROCK_HIT = { id = "rbxassetid://9125869505", creator = "ProSoundEffects" },
	MINING_ROCK_BREAK = { id = "rbxassetid://7158347304", creator = "Mythamanx" },
	MINING_ROCK_CRUMBLE = { id = "rbxassetid://9118608146", creator = "ProSoundEffects" },

	-- Mining (metal variant)
	MINING_METAL_HIT = { id = "rbxassetid://9116680684" },
	MINING_METAL_CRACK = { id = "rbxassetid://9116460378" },
	MINING_METAL_BREAK = { id = "rbxassetid://9125664705" },

	-- Mining (ice)
	MINING_ICE_HIT = { id = "rbxassetid://9114865628", creator = "ProSoundEffects" },
	MINING_ICE_BREAK = { id = "rbxassetid://9114857470", creator = "ProSoundEffects" },
	MINING_ICE_SHATTER = { id = "rbxassetid://9114856117", creator = "ProSoundEffects" },

	-- Mining (sand)
	MINING_SAND_HIT = { id = "rbxassetid://9114109951", creator = "ProSoundEffects" },
	MINING_SAND_BREAK = { id = "rbxassetid://9125964297", creator = "ProSoundEffects" },
	MINING_SAND_SCATTER = { id = "rbxassetid://84116488163645", creator = "POWER_WOLF4" },

	-- Mining (mud)
	MINING_MUD_HIT = { id = "rbxassetid://118050992847083", creator = "Sheriff_Ssb2" },
	MINING_MUD_BREAK = { id = "rbxassetid://9125813369", creator = "ProSoundEffects" },
	MINING_MUD_SQUISH = { id = "rbxassetid://125883468018106", creator = "chiu0113" },

	-- Mining (snow)
	MINING_SNOW_HIT = { id = "rbxassetid://9119310368", creator = "ProSoundEffects" },
	MINING_SNOW_BREAK = { id = "rbxassetid://9119312319", creator = "ProSoundEffects" },
	MINING_SNOW_CRUNCH = { id = "rbxassetid://133577998869206", creator = "Diman_X64" },

	-- Mining (water)
	MINING_WATER_HIT = { id = "rbxassetid://9125701669", creator = "ProSoundEffects" },
	MINING_WATER_SPLASH = { id = "rbxassetid://9117823333", creator = "ProSoundEffects" },
	MINING_WATER_FLOW = { id = "rbxassetid://91241249104052", creator = "TheAngelMGR" },

	-- Mining (grass)
	MINING_GRASS_HIT = { id = "rbxassetid://9113592947", creator = "ProSoundEffects" },
	MINING_GRASS_BREAK = { id = "rbxassetid://9114109952", creator = "ProSoundEffects" },
	MINING_GRASS_DIG = { id = "rbxassetid://9120068543", creator = "ProSoundEffects" },

	-- Mining (dirt)
	MINING_DIRT_HIT = { id = "rbxassetid://9118598288", creator = "ProSoundEffects" },
	MINING_DIRT_BREAK = { id = "rbxassetid://73077365148421", creator = "gooberaltacclolz" },
	MINING_DIRT_DIG = { id = "rbxassetid://9120068816", creator = "ProSoundEffects" },

	-- Mining (wood)
	MINING_WOOD_HIT = { id = "rbxassetid://9120807255", creator = "ProSoundEffects" },
	MINING_WOOD_BREAK = { id = "rbxassetid://74139702398034", creator = "adrian75556435" },
	MINING_WOOD_CRACK = { id = "rbxassetid://121832712632393", creator = "faizalrmp7765" },

	-- Pets
	PET_SPAWN = { id = "rbxassetid://8363346672", creator = "princeebet" },
	PET_HAPPY = { id = "rbxassetid://5153736658", creator = "XenoTheFox" },
	PET_IDLE = { id = "rbxassetid://1841144696", creator = "APMOfficial", looped = true },
	PET_WORKING = { id = "rbxassetid://119243954316450", creator = "kj26pcc" },
	PET_LEVELUP = { id = "rbxassetid://130283511889291", creator = "Madd0wg" },
	PET_EQUIP = { id = "rbxassetid://8807795651", creator = "Vamonoz" },
	PET_UNEQUIP = { id = "rbxassetid://8807795651", creator = "Vamonoz" },

	-- Ambience
	AMBIENT_WIND = { id = "rbxassetid://9056932358", creator = "Festivereinhard2" },
	AMBIENT_BIRDS_MORNING = { id = "rbxassetid://9056670230", creator = "SovereignFrost" },
	AMBIENT_TREES_RUSTLING = { id = "rbxassetid://5108956689", creator = "RealSirStrider" },
	AMBIENT_CAVE_WIND = { id = "rbxassetid://273398061", creator = "Texodus" },
	AMBIENT_CAVE_WATER = { id = "rbxassetid://9120583774", creator = "ProSoundEffects" },
	AMBIENT_CAVE_DRIPS = { id = "rbxassetid://9120505299", creator = "ProSoundEffects" },
	AMBIENT_WATERFLOW = { id = "rbxassetid://9126200384", creator = "ProSoundEffects" },
	AMBIENT_CRICKETS = { id = "rbxassetid://9112767683", creator = "ProSoundEffects" },
	AMBIENT_OCEANWAVES = { id = "rbxassetid://125442735185102", creator = "DistrokidOfficial" },
	AMBIENT_LAVAFLOW = { id = "rbxassetid://9112887644", creator = "ProSoundEffects" },
	AMBIENT_ICECRACKING = { id = "rbxassetid://9114858163", creator = "ProSoundEffects" },

	-- Movement (footsteps)
	MOVEMENT_FOOTSTEP_ROCK = { id = "rbxassetid://110574097038578", creator = "goodberaltacclolz" },
	MOVEMENT_FOOTSTEP_SAND = { id = "rbxassetid://112084382996930", creator = "diman_x64" },
	MOVEMENT_FOOTSTEP_GRASS = { id = "rbxassetid://135182192451997", creator = "TheAngelMGR" },
	MOVEMENT_FOOTSTEP_DIRT = { id = "rbxassetid://80932364310315", creator = "TheAngelMGR" },
	MOVEMENT_FOOTSTEP_WOOD = { id = "rbxassetid://7002935061", creator = "Juicy_Fruit" },
	MOVEMENT_FOOTSTEP_ICE = { id = "rbxassetid://9118686859", creator = "ProSoundEffects" },
	MOVEMENT_FOOTSTEP_MUD = { id = "rbxassetid://112281090439034", creator = "ra1nsl1_4" },
	MOVEMENT_FOOTSTEP_SNOW = { id = "rbxassetid://76389772156953", creator = "Diman_x64" },
	MOVEMENT_FOOTSTEP_WATER = { id = "rbxassetid://116195990169547", creator = "Diman_x64" },

	-- Movement (actions)
	MOVEMENT_JUMP = { id = "rbxassetid://2428506580", creator = "happysupercooldude99" },
	MOVEMENT_LAND = { id = "rbxassetid://4839280516", creator = "SSWEEEE" },

	-- Environment SFX
	ENV_THUNDER = { id = "rbxassetid://6409267922", creator = "wafflesforall", looped = false },
	ENV_RAIN = { id = "rbxassetid://9064263922", creator = "secretbankvault", looped = true },
	ENV_EXPLOSION = { id = "rbxassetid://5801257793", creator = "deadstickdoom", looped = false },
	ENV_EARTHQUAKE = { id = "rbxassetid://4870579875", creator = "Enel_Sama", looped = true },
	ENV_FIRE = { id = "rbxassetid://2787093357", creator = "Festivereinhard2", looped = true },
	ENV_ROCKFALL = { id = "rbxassetid://17806433069", creator = "Zai Studios 3", looped = false },
	ENV_STEAM = { id = "rbxassetid://5057582133", creator = "CheerfulFLAPJACK", looped = true },

	-- Rewards
	REWARD_RARE = { id = "rbxassetid://96223188229725", creator = "Agent_F4Z" },
	REWARD_EPIC = { id = "rbxassetid://9045122943", creator = "APMOfficial" },
	REWARD_LEGENDARY = { id = "rbxassetid://103629759331575", creator = "Darcksci221_v2" },
	REWARD_COIN = { id = "rbxassetid://203620899", creator = "DCavallaro" },
	REWARD_GEM = { id = "rbxassetid://3199298549", creator = "thienbao2109" },
	REWARD_ITEM = { id = "rbxassetid://105599775370376", creator = "5p_nn" },
	REWARD_LEVELUP = { id = "rbxassetid://6079105785", creator = "MarcoMonopoly" },
	REWARD_ACHIEVEMENT = { id = "rbxassetid://17894585400", creator = "searql" },
	REWARD_CHEST = { id = "rbxassetid://5153735143", creator = "XenoTheFox" },
	REWARD_MILESTONE = { id = "rbxassetid://87681552750899", creator = "NoriAndris" },

	-- Music
	MUSIC_MAIN = { id = "rbxassetid://1835878163" },
	MUSIC_MINING = { id = "rbxassetid://9048375035" },
	MUSIC_CAVE = { id = "rbxassetid://1837075763" },
	MUSIC_SHOP = { id = "rbxassetid://1844872472" },
	MUSIC_BOSS = { id = "rbxassetid://1839961091" },
	MUSIC_VICTORY = { id = "rbxassetid://9048816189" },
	MUSIC_ICE = { id = "rbxassetid://1836542585" },
	MUSIC_DESERT = { id = "rbxassetid://1843277044" },
	-- Additional background tracks (playlist-ready)
	MUSIC_BG_01 = { id = "rbxassetid://137209065211429", creator = "DistrokidOfficial" },
	MUSIC_BG_02 = { id = "rbxassetid://107093426488629", creator = "DistrokidOfficial" },
	MUSIC_BG_03 = { id = "rbxassetid://75417411747761", creator = "DistrokidOfficial" },
	MUSIC_BG_04 = { id = "rbxassetid://83293712202332", creator = "DistrokidOfficial" },
	MUSIC_BG_05 = { id = "rbxassetid://112036310618421", creator = "DistrokidOfficial" },
}

-- Freeze nested entries
for _, v in pairs(DEFS) do
	table.freeze(v)
end

-- Backward-compatible flat map: NAME -> id string
local ASSETS: { [string]: string } = {}
for k, v in pairs(DEFS) do
	ASSETS[k] = v.id
end

-- Build reverse lookup by id
local BY_ID: { [string]: any } = {}
for k, v in pairs(DEFS) do
	BY_ID[v.id] = table.freeze({ key = k, id = v.id, creator = v.creator, looped = v.looped })
end

SoundDefs.DEFS = table.freeze(DEFS)
SoundDefs.ASSETS = table.freeze(ASSETS)
SoundDefs.BY_ID = table.freeze(BY_ID)

function SoundDefs.getId(key: string): string?
	local d = DEFS[key]
	return d and d.id or nil
end

function SoundDefs.getMeta(key: string): any
	return DEFS[key]
end

function SoundDefs.getById(id: string): any
	return BY_ID[id]
end

return table.freeze(SoundDefs)
