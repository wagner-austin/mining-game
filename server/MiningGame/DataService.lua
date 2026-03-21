--!strict
-- DataService.server.lua
-- Handles data persistence with DataStore v2 and session locking

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Time = require(Shared:WaitForChild("Time"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Timeout = require(Shared:WaitForChild("Timeout"))
local LoadCfg = require(Shared:WaitForChild("LoadingConstants"))
local Types = require(Shared:WaitForChild("Types"))
local Logger = require(Shared:WaitForChild("Logger"))
local MathUtils = require(Shared:WaitForChild("MathUtils"))
local ErrorService = require(script.Parent.ErrorService)
local DigPerformance = require(script.Parent.DigPerformance)
local log = Logger.new("DataService")

-- Centralized helpers for DataStore/MemoryStore ops with timeout + retry
local function _dsGet(store, key, sectionName: string?)
	local _ = sectionName
	local t = (LoadCfg.TIMEOUTS and LoadCfg.TIMEOUTS.DataStoreOp) or 8.0
	local r = (LoadCfg.RETRY and LoadCfg.RETRY.DataStore) or { attempts = 3, backoff = 0.5 }
	local okTimeout, resultOrErr = Timeout.runWithRetry(function()
		local ok, res = ErrorService.safecall("DataService:DS_GetAsync", function()
			return store:GetAsync(key)
		end)
		if not ok then
			error(res)
		end
		return res
	end, t, r.attempts, r.backoff)
	if not okTimeout then
		return false, resultOrErr
	end
	return true, resultOrErr
end

local function _dsSet(store, key, value, sectionName: string?)
	local t = (LoadCfg.TIMEOUTS and LoadCfg.TIMEOUTS.DataStoreOp) or 8.0
	local r = (LoadCfg.RETRY and LoadCfg.RETRY.DataStore) or { attempts = 3, backoff = 0.5 }
	local okTimeout, resOrErr = Timeout.runWithRetry(function()
		local ok, err = ErrorService.safecall("DataService:DS_SetAsync", function()
			DigPerformance.measureSection(sectionName or "DS_Set_Unknown", function()
				store:SetAsync(key, value)
			end)
			return true
		end)
		if not ok then
			error(err)
		end
		return true
	end, t, r.attempts, r.backoff)
	if not okTimeout then
		return false, resOrErr
	end
	return true
end

local function _dsUpdate(store, key, transform, sectionName: string?)
	local t = (LoadCfg.TIMEOUTS and LoadCfg.TIMEOUTS.DataStoreOp) or 8.0
	local r = (LoadCfg.RETRY and LoadCfg.RETRY.DataStore) or { attempts = 3, backoff = 0.5 }
	local okTimeout, resOrErr = Timeout.runWithRetry(function()
		local ok, err = ErrorService.safecall("DataService:DS_UpdateAsync", function()
			DigPerformance.measureSection(sectionName or "DS_Update_Unknown", function()
				store:UpdateAsync(key, transform)
			end)
			return true
		end)
		if not ok then
			error(err)
		end
		return true
	end, t, r.attempts, r.backoff)
	if not okTimeout then
		return false, resOrErr
	end
	return true
end

local function _msCall(opName: string, fn)
	local _ = opName
	local t = (LoadCfg.TIMEOUTS and LoadCfg.TIMEOUTS.MemoryStoreOp) or 4.0
	local r = (LoadCfg.RETRY and LoadCfg.RETRY.MemoryStore) or { attempts = 2, backoff = 0.25 }
	local okTimeout, resOrErr = Timeout.runWithRetry(function()
		local ok, res = ErrorService.safecall("DataService:MS_Call", fn)
		if not ok then
			error(res)
		end
		return res
	end, t, r.attempts, r.backoff)
	if not okTimeout then
		return false, resOrErr
	end
	return true, resOrErr
end

-- Event Bus for decoupled communication
-- EventBus wiring removed (unused)

-- UserMetricsService will be resolved via container

-- DataStore setup (4MB per key limit)
local PlayerDataStore, CubeDataStore

-- Check if we can use DataStore (not in Studio or API access enabled)
local canUseDataStore = false
local okDS, errDS = ErrorService.safecall("DataService:GetDataStores", function()
	-- Try to access DataStore
	PlayerDataStore = DataStoreService:GetDataStore(GameConfig.DataStore.PLAYER_DATA_KEY)
	CubeDataStore = DataStoreService:GetDataStore(GameConfig.DataStore.CUBE_DATA_KEY)
	canUseDataStore = true
	return true
end)

if not okDS then
	log:warn("DataStore access disabled (Studio mode). Using mock data.")
	log:warn("Error: %s", tostring(errDS))
	-- Create mock stores for testing
	local mockData = {}
	PlayerDataStore = {
		GetAsync = function(_, key)
			return mockData[key]
		end,
		SetAsync = function(_, key, value)
			mockData[key] = value
			return true
		end,
	}
	CubeDataStore = PlayerDataStore
else
	log:info("DataStore access ENABLED - data will persist!")
end

-- Session locking with MemoryStore
local SessionLocks
local LOCK_TTL = GameConfig.DataStore.SESSION_LOCK_TTL

-- Try to use MemoryStore (may not be available in Studio)
ErrorService.safecall("MemoryStore:GetSortedMap(SessionLocks)", function()
	SessionLocks = MemoryStoreService:GetSortedMap("SessionLocks")
	return true
end)

-- Mock session locks if not available
if not SessionLocks then
	local mockLocks = {}
	SessionLocks = {
		SetAsync = function(_, key, value)
			mockLocks[key] = value
		end,
		GetAsync = function(_, key)
			return mockLocks[key]
		end,
		RemoveAsync = function(_, key)
			mockLocks[key] = nil
		end,
	}
end

-- Player data cache
local playerData: { [Player]: Types.PlayerStats } = {}
local playerCubes: { [Player]: Types.CubeState } = {}
local saveQueue: { [Player]: boolean } = {}

local DataService = {}

-- Container reference for dependency injection
local _container

-- Lazy-loaded cache for AchievementService to avoid circular dependency
-- Removed unused AchievementServiceCached

-- Forward declare functions used in Start
local onPlayerAdded: (Player) -> ()
local setupWipeCommand: (Player) -> ()
local releaseSessionLock: (number) -> ()

-- Initialize with container for dependency injection
function DataService:Init(container)
	_container = container
	log:info("Initialized with container")
end

-- Start method to connect events after all services are initialized
function DataService:Start(_container)
	-- Connect player events now that service is ready
	Players.PlayerAdded:Connect(onPlayerAdded)

	-- Handle player leaving
	Players.PlayerRemoving:Connect(function(player)
		log:event("player_leaving", {
			uid = player.UserId,
			name = player.Name,
			timestamp = math.floor(Time.unix()),
		})

		-- Save data
		if playerData[player] then
			DataService:SaveAllAsync(player)
		end

		-- Clean up
		playerData[player] = nil
		playerCubes[player] = nil
		saveQueue[player] = nil

		-- Release session lock
		releaseSessionLock(player.UserId)

		-- Session cleanup handled by SessionService
	end)

	-- Handle players already in game (Studio test player)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end

	-- Setup wipe command in Studio
	if RunService:IsStudio() then
		game.Players.PlayerAdded:Connect(setupWipeCommand)
		for _, plr in ipairs(game.Players:GetPlayers()) do
			setupWipeCommand(plr)
		end
	end

	log:info("Started with player connections")
end

-- Generate default player profile
local function createDefaultProfile(userId: number): Types.PlayerStats
	return {
		coins = 0,
		highestCoins = 0,
		gems = 0,
		materialId = "tier1", -- Use tier ID from GameConfig.CubeMaterials
		cubeSeed = userId % 1000000, -- Deterministic seed based on user ID
		upgrades = {
			speed = 0,
			size = 0, -- Level 0 gives size 1 from config
		},
		boosts = {}, -- boost type -> expiry timestamp
		pets = {}, -- pet instance id -> pet data
		inventory = {}, -- item id -> count
		equipped = {
			pickaxe = nil, -- equipment pickaxe (non-cosmetic)
			hand = nil, -- right-hand cosmetic (sword/pickaxe/warhammer)
			head = nil,
			back = nil,
			aura = nil,
			trail = nil,
			terrainTheme = nil, -- palette key
		},
		materialPreferences = {
			palette = "default",
			cubeMaterial = "rock", -- Legacy, not used anymore
			floorMaterial = "concrete",
			-- Composition system (always enabled now)
			mode = "composition",
			activeThemeId = "underwater_cave",
			compositionSeed = Random.new():NextInteger(1, 1000000),
			variationMode = "PER_REGEN",
		},
		themeSettings = {
			uiTheme = "default",
			soundPack = "default",
		},
		totalBlocksDug = 0,
		playtime = 0,
		achievements = {}, -- unlocked achievement IDs
		statCounters = { -- tracking for achievement triggers (numeric only!)
			rares_found = 0,
			epics_found = 0,
			legendaries_found = 0,
			mythics_found = 0,
			cosmetics_equipped = 0,
			pickaxes_found = 0,
		},
		-- New/returning player tracking
		firstPlayTime = DateTime.now().UnixTimestamp,
		firstDigTime = nil,
		lastSaveTime = DateTime.now().UnixTimestamp,
	}
end

-- Normalize ownedGamePasses keys to numeric gamepassIds
-- No backward-compat key normalization; profiles must use numeric gamepassId keys

-- Generate default cube state
local function createDefaultCube(userId: number, materialId: string): Types.CubeState
	return {
		ownerId = userId,
		materialId = materialId,
		cellSize = GameConfig.Grid.CELL_SIZE_STUDS,
		chunkSize = GameConfig.Grid.CHUNK_CELLS,
		chunks = {}, -- Will be populated lazily as player digs
		totalDug = 0,
		createdAt = DateTime.now().UnixTimestamp,
	}
end

-- Attempt to acquire session lock
local function acquireSessionLock(userId: number): boolean
	local key = tostring(userId)
	local now = DateTime.now().UnixTimestamp
	local ok = _msCall("SessionLocks:SetAsync", function()
		return SessionLocks:SetAsync(key, now, LOCK_TTL)
	end)
	return ok and true or false
end

-- Release session lock
releaseSessionLock = function(userId: number)
	local key = tostring(userId)
	_msCall("SessionLocks:RemoveAsync", function()
		return SessionLocks:RemoveAsync(key)
	end)
end

-- Check if session is locked
local function isSessionLocked(userId: number): boolean
	local key = tostring(userId)
	local ok, value = _msCall("SessionLocks:GetAsync", function()
		return SessionLocks:GetAsync(key)
	end)

	if ok and value then
		local lockTime: number
		if type(value) == "number" then
			lockTime = value
		else
			return false
		end
		local elapsed = DateTime.now().UnixTimestamp - lockTime
		-- If lock is older than TTL, it's expired
		return elapsed < LOCK_TTL
	end

	return false
end

-- Load player data from DataStore
function DataService:LoadPlayerAsync(player: Player): Types.PlayerStats?
	local userId = player.UserId

	-- Check for existing session
	if isSessionLocked(userId) then
		log:warn("Player %s has active session elsewhere", player.Name)
		return nil
	end

	-- Acquire lock
	if not acquireSessionLock(userId) then
		log:warn("Failed to acquire lock for %s", player.Name)
		return nil
	end

	-- Load from DataStore
	local key = "Player_" .. tostring(userId)
	log:debug("Loading data for %s with key: %s", player.Name, key)

	local okLoad, result = _dsGet(PlayerDataStore, key, "DS_Get_Player")

	if not okLoad then
		log:error("Failed to load data for %s: %s", player.Name, tostring(result))
		releaseSessionLock(userId)
		return nil
	end

	log:info("Load result for %s - Has existing data: %s", player.Name, tostring(result ~= nil))

	local profile: Types.PlayerStats
	if result then
		local res = result
		local tmpProfile: Types.PlayerStats = res
		profile = tmpProfile
		log:info("Loaded existing profile - Coins: %d Blocks dug: %d", profile.coins, profile.totalBlocksDug)
		-- Migrate old data if needed
		if not profile.gems then
			profile.gems = 0
		end
		if not profile.equipped then
			profile.equipped = {}
		end
		if not profile.pets then
			profile.pets = {}
		end
		-- Add migration defaults for metrics fields
		profile.totalCoinsEarned = profile.totalCoinsEarned or (profile.coins or 0)
		profile.totalCoinsSpent = profile.totalCoinsSpent or 0
		profile.totalGemsEarned = profile.totalGemsEarned or (profile.gems or 0)
		profile.totalGemsSpent = profile.totalGemsSpent or 0
		profile.lastLoginTime = profile.lastLoginTime or DateTime.now().UnixTimestamp
		-- Donations backfill: initialize donations from dev products (safe today; only DONATE exists)
		profile.robuxSpentDonations = profile.robuxSpentDonations or profile.robuxSpentDevProducts or 0
		-- Update session fields

		-- Ensure session baseline reflects the just-loaded lifetime blocks
		local currentTotalBlocks = profile.totalBlocksDug or 0
		if profile.sessionStartBlocks == nil or profile.sessionStartBlocks < currentTotalBlocks then
			profile.sessionStartBlocks = currentTotalBlocks
		end

		-- Increment session count synchronously for THIS join
		-- IMPORTANT: Use (profile.totalSessions or 0) to handle nil, not (profile.totalSessions or 1)
		profile.totalSessions = (profile.totalSessions or 0) + 1
		profile.lastLoginTime = DateTime.now().UnixTimestamp

		-- Invalidate cached metrics so UI sees the new value immediately
		local UMS = _container and _container:tryGet("UserMetricsService")
		if UMS then
			ErrorService.safecall("UserMetricsService.InvalidateOnLoad", function()
				UMS:Invalidate(player)
				return true
			end)
		end
	else
		log:info("Creating NEW profile for %s", player.Name)
		profile = createDefaultProfile(userId)
		-- New profiles start with 1 session
		profile.totalSessions = 1
		profile.lastLoginTime = DateTime.now().UnixTimestamp
		profile.sessionStartBlocks = profile.totalBlocksDug or 0
	end

	-- Profiles are expected to be current; no legacy cleanup/migrations

	-- Cache the data
	playerData[player] = profile

	log:info("Loaded data for %s", player.Name)
	return profile
end

-- Load cube data from DataStore
function DataService:LoadCubeAsync(player: Player): Types.CubeState?
	local userId = player.UserId
	local profile = playerData[player]

	if not profile then
		log:warn("No profile loaded for %s", player.Name)
		return nil
	end

	-- Load from DataStore
	local key = "Cube_" .. tostring(userId) .. "_" .. profile.materialId
	local okCube, result = _dsGet(CubeDataStore, key, "DS_Get_Cube")

	if not okCube then
		log:error("Failed to load cube for %s: %s", player.Name, tostring(result))
		return nil
	end

	local cube: Types.CubeState
	if result then
		local res2 = result
		local tmpCube: Types.CubeState = res2
		cube = tmpCube
	else
		cube = createDefaultCube(userId, profile.materialId)
	end

	-- Cache the data
	playerCubes[player] = cube

	log:debug("Loaded cube for %s", player.Name)
	return cube
end

-- Save player data to DataStore
function DataService:SavePlayerAsync(player: Player): boolean
	local profile = playerData[player]
	if not profile then
		return false
	end

	profile.lastSaveTime = DateTime.now().UnixTimestamp

	local userId = player.UserId
	local key = "Player_" .. tostring(userId)

	local okSave, err = _dsSet(PlayerDataStore, key, profile, "DS_Set_Player")

	if not okSave then
		log:error("Failed to save data for %s: %s", player.Name, tostring(err))
		return false
	end

	log:info("Saved data for %s", player.Name)
	return true
end

-- Save cube data to DataStore
function DataService:SaveCubeAsync(player: Player): boolean
	local cube = playerCubes[player]
	local profile = playerData[player]

	if not cube or not profile then
		return false
	end

	local userId = player.UserId
	local key = "Cube_" .. tostring(userId) .. "_" .. profile.materialId

	-- Only save dirty chunks to optimize storage
	local compactCube = {
		ownerId = cube.ownerId,
		materialId = cube.materialId,
		cellSize = cube.cellSize,
		chunkSize = cube.chunkSize,
		chunks = {},
		totalDug = cube.totalDug,
		createdAt = cube.createdAt,
	}

	-- Copy only non-empty chunks
	for chunkKey, chunk in pairs(cube.chunks) do
		if chunk.dugBits ~= "" and chunk.dugBits ~= "0x4096" then
			compactCube.chunks[chunkKey] = chunk
		end
	end

	local okSave, err = _dsSet(CubeDataStore, key, compactCube, "DS_Set_Cube")

	if not okSave then
		log:error("Failed to save cube for %s: %s", player.Name, tostring(err))
		return false
	end

	log:debug("Saved cube for %s", player.Name)
	return true
end

-- Save all data for a player
function DataService:SaveAllAsync(player: Player): boolean
	return DigPerformance.measureSection("DS_SaveAll", function()
		local success1 = self:SavePlayerAsync(player)
		local success2 = self:SaveCubeAsync(player)
		return success1 and success2
	end)
end

-- Queue a save for later
function DataService:QueueSave(player: Player)
	saveQueue[player] = true
end

-- Get player data
function DataService:GetPlayerData(player: Player): Types.PlayerStats?
	return playerData[player]
end

-- Get cube data
function DataService:GetCubeData(player: Player): Types.CubeState?
	return playerCubes[player]
end

-- Update player data (partial update)
function DataService:UpdatePlayerData(
	player: Player,
	updates: { coins: number?, gems: number?, totalBlocksDug: number?, playtime: number? }
)
	local profile = playerData[player]
	if not profile then
		return
	end

	if updates.coins ~= nil then
		profile.coins = updates.coins
	end
	if updates.gems ~= nil then
		profile.gems = updates.gems
	end
	if updates.totalBlocksDug ~= nil then
		profile.totalBlocksDug = updates.totalBlocksDug
	end
	if updates.playtime ~= nil then
		profile.playtime = updates.playtime
	end

	self:QueueSave(player)
end

-- Reset profile to defaults (used by debug commands)
function DataService:ResetProfileToDefaults(
	player: Player,
	opts: {
		upgrades: boolean?,
		currencies: boolean?,
		boosts: boolean?,
		inventory: boolean?,
	}?
)
	local options: { upgrades: boolean?, currencies: boolean?, boosts: boolean?, inventory: boolean? } = opts or {}
	local profile = playerData[player]
	if not profile then
		return false
	end

	local defaults = createDefaultProfile(player.UserId)

	if options.currencies ~= false then
		profile.coins = defaults.coins
		profile.gems = defaults.gems
	end
	if options.upgrades ~= false then
		profile.upgrades = {
			speed = defaults.upgrades.speed,
			size = defaults.upgrades.size,
		}
	end
	if options.boosts ~= false then
		profile.boosts = {}
	end
	if options.inventory == true then -- Only reset inventory if explicitly requested
		profile.inventory = {}
		profile.equipped = defaults.equipped
		if profile.pets then
			profile.pets = {}
		end
	end

	self:QueueSave(player)
	return true
end

-- Add currency (DEPRECATED: Use CurrencyService.add directly)
function DataService:AddCurrency(player: Player, currencyType: string, amount: number): boolean
	-- Delegate to CurrencyService via container
	local CS = _container:Get("CurrencyService") -- hard dep; fail fast if wiring regresses
	return CS.add(player, currencyType, amount)
end

-- Get material preferences for a player
function DataService:GetMaterialPrefs(player: Player): Types.MaterialPreferences?
	local profile = playerData[player]
	if not profile then
		return nil
	end
	return profile.materialPreferences
end

-- Update material preferences
function DataService:UpdateMaterialPrefs(
	player: Player,
	patch: {
		palette: string?,
		cubeMaterial: string?,
		floorMaterial: string?,
		mode: string?,
		activeThemeId: string?,
		compositionSeed: number?,
		variationMode: string?,
	}
): boolean
	local profile = playerData[player]
	if not profile then
		return false
	end

	-- Apply typed patch
	local mp = profile.materialPreferences
	if patch.palette ~= nil then
		mp.palette = patch.palette
	end
	if patch.cubeMaterial ~= nil then
		mp.cubeMaterial = patch.cubeMaterial
	end
	if patch.floorMaterial ~= nil then
		mp.floorMaterial = patch.floorMaterial
	end
	if patch.mode ~= nil then
		mp.mode = patch.mode
	end
	if patch.activeThemeId ~= nil then
		mp.activeThemeId = patch.activeThemeId
	end
	if patch.compositionSeed ~= nil then
		mp.compositionSeed = patch.compositionSeed
	end
	if patch.variationMode ~= nil then
		mp.variationMode = patch.variationMode
	end

	-- Queue save
	self:QueueSave(player)
	profile.lastSaveTime = DateTime.now().UnixTimestamp

	return true
end

-- Get theme settings for a player
function DataService:GetThemeSettings(player: Player): Types.ThemeSettings?
	local profile = playerData[player]
	if not profile then
		return nil
	end

	-- Ensure theme settings exist with defaults
	if not profile.themeSettings then
		local ts: Types.ThemeSettings = {
			uiTheme = "Default", -- Use proper case to match ThemePacks
			soundPack = "default",
			musicVolume = GameConfig.Audio.DEFAULT_MUSIC_VOLUME,
			sfxVolume = GameConfig.Audio.DEFAULT_SFX_VOLUME,
		}
		profile.themeSettings = ts
	end

	-- Add volume defaults if missing (for backward compat)
	if profile.themeSettings.musicVolume == nil then
		profile.themeSettings.musicVolume = GameConfig.Audio.DEFAULT_MUSIC_VOLUME
	end
	if profile.themeSettings.sfxVolume == nil then
		profile.themeSettings.sfxVolume = GameConfig.Audio.DEFAULT_SFX_VOLUME
	end

	return profile.themeSettings
end

-- Update theme settings
function DataService:SetThemeSettings(
	player: Player,
	patch: {
		uiTheme: string?,
		soundPack: string?,
		musicVolume: number?,
		sfxVolume: number?,
	}
): boolean
	local profile = playerData[player]
	if not profile then
		return false
	end

	-- Ensure theme settings exist with defaults
	if not profile.themeSettings then
		local ts: Types.ThemeSettings = {
			uiTheme = "Default", -- Use proper case to match ThemePacks
			soundPack = "default",
			musicVolume = GameConfig.Audio.DEFAULT_MUSIC_VOLUME,
			sfxVolume = GameConfig.Audio.DEFAULT_SFX_VOLUME,
		}
		profile.themeSettings = ts
	end

	-- Apply the patch
	if patch.uiTheme then
		local ts = profile.themeSettings
		ts.uiTheme = patch.uiTheme
	end
	if patch.soundPack then
		local ts = profile.themeSettings
		ts.soundPack = patch.soundPack
	end
	if patch.musicVolume ~= nil then
		local ts = profile.themeSettings
		ts.musicVolume = patch.musicVolume
	end
	if patch.sfxVolume ~= nil then
		local ts = profile.themeSettings
		ts.sfxVolume = patch.sfxVolume
	end

	-- Queue save
	self:QueueSave(player)
	profile.lastSaveTime = DateTime.now().UnixTimestamp

	return true
end

-- Ensure player data is loaded (for on-demand initialization)
function DataService:EnsureLoaded(player: Player): boolean
	-- Already loaded?
	if playerData[player] and playerCubes[player] then
		if not player:GetAttribute("DataLoaded") then
			player:SetAttribute("DataLoaded", true)
		end
		return true
	end

	-- Studio: Wait longer for async load, then synthesize if needed
	if RunService:IsStudio() then
		-- Give the async load a fair chance (up to 2 seconds)
		local deadline = Time.mono() + 2.0
		while Time.mono() < deadline do
			if playerData[player] and playerCubes[player] then
				if not player:GetAttribute("DataLoaded") then
					player:SetAttribute("DataLoaded", true)
				end
				return true
			end
			task.wait(GameConfig.Timing.DATA_LOAD_RETRY_DELAY)
		end

		-- Still no data after timeout? Synthesize defaults as fallback
		log:warn("EnsureLoaded: synthesizing default data for %s", player.Name)
		local profile = createDefaultProfile(player.UserId)
		playerData[player] = profile
		local cube = createDefaultCube(player.UserId, profile.materialId)
		playerCubes[player] = cube
		player:SetAttribute("DataLoaded", true)
		return true
	end

	-- Production: attempt synchronous load (last resort path)
	local ok, _ = ErrorService.safecall("EnsureLoaded.SyncFallback", function()
		local profile = DataService:LoadPlayerAsync(player)
		if not profile then
			return false
		end
		local cube = DataService:LoadCubeAsync(player)
		if not cube then
			return false
		end
		player:SetAttribute("DataLoaded", true)
		return true
	end)
	return ok and player:GetAttribute("DataLoaded") == true
end

-- Get active boosts for character state system
function DataService:GetActiveBoosts(player: Player): { [string]: number }
	local profile = playerData[player]
	return (profile and profile.boosts) or {}
end

-- Can afford check
-- Check if player can afford (DEPRECATED: Use CurrencyService.canAfford directly)
function DataService:CanAfford(player: Player, currencyType: string, amount: number): boolean
	-- Delegate to CurrencyService via container
	local CS = _container:Get("CurrencyService")
	return CS.canAfford(player, currencyType, amount)
end

-- Add playtime to player's lifetime total
function DataService:AddPlaytime(player: Player, seconds: number)
	local profile = playerData[player]
	if not profile then
		return
	end

	seconds = MathUtils.nonNegative(seconds or 0)
	profile.playtime = (profile.playtime or 0) + seconds
	profile.lastSaveTime = DateTime.now().UnixTimestamp

	self:QueueSave(player)
	log:debug("Added %d seconds playtime for %s - Total: %d", seconds, player.Name, profile.playtime)
end

-- ===== DURABLE RECEIPT QUEUE FOR MONETIZATION =====
-- Critical for not losing purchases if server crashes

local ReceiptQueueStore
if canUseDataStore then
	ErrorService.safecall("GetDataStore(ReceiptQueue)", function()
		ReceiptQueueStore = DataStoreService:GetDataStore(GameConfig.DataStore.RECEIPT_QUEUE_KEY)
		return true
	end)
end

-- Increment lifetime blocks-dug counter (profile-level, independent of cube/material)
function DataService:AddBlocksDug(player: Player, count: number?): boolean
	local profile = playerData[player]
	if not profile then
		return false
	end
	local add = MathUtils.nonNegative(count or 1)
	profile.totalBlocksDug = MathUtils.nonNegative((profile.totalBlocksDug or 0) + add)
	if profile.firstDigTime == nil then
		profile.firstDigTime = Time.unix()
	end
	self:QueueSave(player)
	return true
end

-- Update player preferences (whitelisted keys only)
-- Removed legacy SetPreferences; preferences are not part of the current schema

-- Increment lifetime blocks-dug counter in a single, consistent place
-- (deprecated) IncrementBlocksDug removed; cube state already tracks dug count consistently

if not ReceiptQueueStore then
	-- Mock for testing (with proper atomic semantics)
	local mockQueue = {}
	ReceiptQueueStore = {
		GetAsync = function(_, key)
			return mockQueue[key]
		end,
		SetAsync = function(_, key, value)
			mockQueue[key] = value
			return true
		end,
		UpdateAsync = function(_, key, transform)
			mockQueue[key] = transform(mockQueue[key])
			return mockQueue[key]
		end,
	}
end

-- Helper to normalize queue structure with deduplication
type ReceiptQueueState = Types.ReceiptQueueState

local function _normalizeQueue(state: ReceiptQueueState?): ReceiptQueueState
	if type(state) ~= "table" then
		return { order = {}, items = {} }
	end
	state.order = state.order or {}
	state.items = state.items or {}
	return state
end

-- Validate grant payload for safety

local function _validGrant(grant: Types.ReceiptGrant): boolean
	if grant.kind ~= "DevProduct" and grant.kind ~= "GamePass" then
		return false
	end
	if grant.id < 0 then
		return false
	end
	if grant.price < 0 then
		return false
	end
	if grant.receiptId == "" then
		return false
	end
	return true
end

-- Enqueue a receipt grant durably with deduplication (MUST succeed before returning PurchaseGranted)
function DataService:EnqueueReceiptGrant(userId: number, grant: Types.ReceiptGrant): boolean
	local key = "PendingGrants_" .. tostring(userId)

	-- Validate grant payload
	if not _validGrant(grant) then
		log:error(
			"Invalid grant payload for user {},",
			userId,
			"- kind:",
			tostring(grant.kind),
			"id:",
			tostring(grant.id),
			"price:",
			tostring(grant.price),
			"receiptId:",
			tostring(grant.receiptId)
		)
		return false
	end

	type StoreGrant = Types.ReceiptGrant & { enqueuedAt: number, userId: number }
	local grantForStore: StoreGrant = {
		kind = grant.kind,
		id = grant.id,
		price = grant.price,
		receiptId = grant.receiptId,
		timestamp = grant.timestamp,
		source = grant.source,
		enqueuedAt = DateTime.now().UnixTimestamp,
		userId = userId,
	}

	local okQ, err = _dsUpdate(ReceiptQueueStore, key, function(old)
		local q = _normalizeQueue(old)
		-- Deduplicate by receiptId
		if not q.items[grant.receiptId] then
			q.items[grant.receiptId] = grantForStore
			table.insert(q.order, grant.receiptId)
			-- Cap to last 300 grants (for whales/bursts)
			while #q.order > 300 do
				local evict = table.remove(q.order, 1)
				if evict then
					q.items[evict] = nil
				end
			end
		end
		return q
	end, "DS_Update_ReceiptQueue_Enqueue")

	if not okQ then
		log:error("Failed to enqueue receipt grant for user %d, err: %s", userId, tostring(err))
		return false
	end

	log:debug(
		"Enqueued (or deduped) grant %s for user %d (kind: %s, id: %s, price: %s)",
		grant.receiptId,
		userId,
		grant.kind or "?",
		tostring(grant.id),
		tostring(grant.price)
	)
	return true
end

-- Consume pending grants atomically (read and clear)
function DataService:ConsumePendingGrants(userId: number): { any }
	local key = "PendingGrants_" .. tostring(userId)
	local consumed: { any } = {}

	local okC, err = _dsUpdate(ReceiptQueueStore, key, function(old)
		local q = _normalizeQueue(old)
		-- Flatten grants in FIFO order
		for _, rid in ipairs(q.order) do
			local g = q.items[rid]
			if g then
				table.insert(consumed, g)
			end
		end
		-- Clear the queue atomically
		return nil
	end, "DS_Update_ReceiptQueue_Consume")

	if not okC then
		log:error("Failed to consume pending grants for %d, err: %s", userId, tostring(err))
		return {}
	end

	if #consumed > 0 then
		log:info("Consumed %d pending grants for user %d", #consumed, userId)
	end

	return consumed
end

-- Auto-save loop
local function autoSaveLoop()
	while true do
		wait(GameConfig.DataStore.AUTO_SAVE_INTERVAL)

		for player, needsSave in pairs(saveQueue) do
			if needsSave and player.Parent then
				spawn(function()
					DigPerformance.measureSection("DS_SaveAllSpawn", function()
						DataService:SaveAllAsync(player)
					end)
				end)
				saveQueue[player] = false
			end
		end
	end
end

-- Function to initialize player data
onPlayerAdded = function(player: Player)
	log:info("Player joined: %s", player.Name)
	log:event("player_joined", {
		uid = player.UserId,
		name = player.Name,
		timestamp = math.floor(Time.unix()),
	})

	-- Load data asynchronously
	spawn(function()
		-- Try to load from DataStore (works in Studio if API Services enabled)
		local profile = DataService:LoadPlayerAsync(player)
		if profile then
			local cube = DataService:LoadCubeAsync(player)
			if cube then
				-- Notify other services that data is loaded
				player:SetAttribute("DataLoaded", true)
				log:info("Data loaded for %s", player.Name)
				log:event("data_loaded", {
					uid = player.UserId,
					hasProfile = profile ~= nil,
					hasCube = cube ~= nil,
				})
			else
				-- Create default cube if loading failed
				log:warn("Failed to load cube, creating default")
				local defaultCube = createDefaultCube(player.UserId, profile.materialId)
				playerCubes[player] = defaultCube
				player:SetAttribute("DataLoaded", true)
			end
		else
			-- In Studio with no DataStore access, create default data
			if not canUseDataStore then
				log:info("No DataStore access - creating default data for %s", player.Name)
				local defaultProfile = createDefaultProfile(player.UserId)
				playerData[player] = defaultProfile
				local cube = createDefaultCube(player.UserId, defaultProfile.materialId)
				playerCubes[player] = cube
				player:SetAttribute("DataLoaded", true)
			else
				-- Production failure - should not happen
				log:error("Failed to load profile in production for %s", player.Name)
				player:Kick("Failed to load profile data. Please try again.")
			end
		end
	end)
end

-- Player events moved to Start method

-- Player leaving handler moved to Start method

-- Handle server shutdown
game:BindToClose(function()
	-- Save all player data
	local players = Players:GetPlayers()
	for _, player in ipairs(players) do
		if playerData[player] then
			DataService:SaveAllAsync(player)
			releaseSessionLock(player.UserId)
		end
	end

	-- Wait for saves to complete (max 30 seconds)
	wait(2)
end)

-- Start auto-save loop
spawn(autoSaveLoop)

-- Admin command to wipe a player's data (for testing)
setupWipeCommand = function(player: Player)
	player.Chatted:Connect(function(message)
		if message == "/wipedata" then
			log:info("Wipe command received from %s", player.Name)

			-- Wipe the player's data
			local profile = playerData[player]
			if profile then
				-- Create fresh profile
				local freshProfile = createDefaultProfile(player.UserId)

				-- Replace with fresh data
				playerData[player] = freshProfile

				-- Reset cube state too
				local freshCube = createDefaultCube(player.UserId, freshProfile.materialId)
				playerCubes[player] = freshCube

				-- Force save using the actual save method
				DataService:SaveAllAsync(player)

				log:info("Wiped data for %s", player.Name)
				log:event("data_wiped", {
					uid = player.UserId,
					timestamp = math.floor(Time.unix()),
				})

				-- Kick player to force reload
				player:Kick("Data wiped! Please rejoin.")
			else
				log:warn("No profile found for %s", player.Name)
			end
		end
	end)
end

-- Set up for already connected players
for _, player in ipairs(game.Players:GetPlayers()) do
	setupWipeCommand(player)
end

-- Wipe command setup moved to Start method

log:info("Initialized")

return DataService
