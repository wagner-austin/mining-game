--!strict
-- DataService.server.lua
-- Handles data persistence with DataStore v2 and session locking

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Types = require(Shared:WaitForChild("Types"))

-- DataStore setup (4MB per key limit)
local PlayerDataStore, CubeDataStore

-- Check if we can use DataStore (not in Studio or API access enabled)
local canUseDataStore = false
local success = pcall(function()
    -- Try to access DataStore
    PlayerDataStore = DataStoreService:GetDataStore(GameConfig.DataStore.PLAYER_DATA_KEY)
    CubeDataStore = DataStoreService:GetDataStore(GameConfig.DataStore.CUBE_DATA_KEY)
    canUseDataStore = true
end)

if not success then
    warn("[DataService] DataStore access disabled (Studio mode). Using mock data.")
    warn("[DataService] Error:", success)
    -- Create mock stores for testing
    local mockData = {}
    PlayerDataStore = {
        GetAsync = function(_, key) return mockData[key] end,
        SetAsync = function(_, key, value) mockData[key] = value return true end,
    }
    CubeDataStore = PlayerDataStore
else
    print("[DataService] DataStore access ENABLED - data will persist!")
end

-- Session locking with MemoryStore
local SessionLocks
local LOCK_TTL = GameConfig.DataStore.SESSION_LOCK_TTL

-- Try to use MemoryStore (may not be available in Studio)
pcall(function()
    SessionLocks = MemoryStoreService:GetSortedMap("SessionLocks")
end)

-- Mock session locks if not available
if not SessionLocks then
    local mockLocks = {}
    SessionLocks = {
        SetAsync = function(_, key, value) mockLocks[key] = value end,
        GetAsync = function(_, key) return mockLocks[key] end,
        RemoveAsync = function(_, key) mockLocks[key] = nil end,
    }
end

-- Player data cache
local playerData: {[Player]: Types.PlayerStats} = {}
local playerCubes: {[Player]: Types.CubeState} = {}
local saveQueue: {[Player]: boolean} = {}

local DataService = {}

-- Generate default player profile
local function createDefaultProfile(userId: number): Types.PlayerStats
    return {
        coins = 0,
        gems = 0,
        materialId = "tier1",  -- Use tier ID from GameConfig.CubeMaterials
        cubeSeed = userId % 1000000, -- Deterministic seed based on user ID
        upgrades = {
            speed = 0,
            size = 0,  -- Level 0 gives size 1 from config
        },
        boosts = {}, -- boost type -> expiry timestamp
        pets = {}, -- pet instance id -> pet data
        inventory = {}, -- item id -> count
        equipped = {
            pickaxe = nil,
            head = nil,
            back = nil,
            aura = nil,
            trail = nil,
        },
        totalBlocksDug = 0,
        playtime = 0,
        lastSaveTime = os.time(),
    }
end

-- Generate default cube state
local function createDefaultCube(userId: number, materialId: string): Types.CubeState
    return {
        ownerId = userId,
        materialId = materialId,
        cellSize = GameConfig.Grid.CELL_SIZE_STUDS,
        chunkSize = GameConfig.Grid.CHUNK_CELLS,
        chunks = {}, -- Will be populated lazily as player digs
        totalDug = 0,
        createdAt = os.time(),
    }
end

-- Attempt to acquire session lock
local function acquireSessionLock(userId: number): boolean
    local key = tostring(userId)
    local now = os.time()
    
    local success = pcall(function()
        SessionLocks:SetAsync(key, now, LOCK_TTL)
    end)
    
    return success
end

-- Release session lock
local function releaseSessionLock(userId: number)
    local key = tostring(userId)
    pcall(function()
        SessionLocks:RemoveAsync(key)
    end)
end

-- Check if session is locked
local function isSessionLocked(userId: number): boolean
    local key = tostring(userId)
    local success, value = pcall(function()
        return SessionLocks:GetAsync(key)
    end)
    
    if success and value then
        local lockTime = value :: number
        local elapsed = os.time() - lockTime
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
        warn("[DataService] Player", player.Name, "has active session elsewhere")
        return nil
    end
    
    -- Acquire lock
    if not acquireSessionLock(userId) then
        warn("[DataService] Failed to acquire lock for", player.Name)
        return nil
    end
    
    -- Load from DataStore
    local key = "Player_" .. tostring(userId)
    print("[DataService] Loading data for", player.Name, "with key:", key)
    
    local success, result = pcall(function()
        return PlayerDataStore:GetAsync(key)
    end)
    
    if not success then
        warn("[DataService] Failed to load data for", player.Name, ":", result)
        releaseSessionLock(userId)
        return nil
    end
    
    print("[DataService] Load result for", player.Name, "- Has existing data:", result ~= nil)
    
    local profile: Types.PlayerStats
    if result then
        profile = result :: Types.PlayerStats
        print("[DataService] Loaded existing profile - Coins:", profile.coins, "Blocks dug:", profile.totalBlocksDug)
        -- Migrate old data if needed
        if not profile.gems then profile.gems = 0 end
        if not profile.equipped then profile.equipped = {} end
        if not profile.pets then profile.pets = {} end
        -- Migrate old material IDs to tier system
        local oldToNew = {stone = "tier1", sandstone = "tier2", granite = "tier3", 
                          obsidian = "tier4", crystal = "tier5", void = "tier6"}
        if oldToNew[profile.materialId] then
            local old = profile.materialId
            profile.materialId = oldToNew[old]
            print("[DataService] Migrated material ID:", old, "->", profile.materialId)
        end
    else
        print("[DataService] Creating NEW profile for", player.Name)
        profile = createDefaultProfile(userId)
    end
    
    -- Cache the data
    playerData[player] = profile
    
    print("[DataService] Loaded data for", player.Name)
    return profile
end

-- Load cube data from DataStore
function DataService:LoadCubeAsync(player: Player): Types.CubeState?
    local userId = player.UserId
    local profile = playerData[player]
    
    if not profile then
        warn("[DataService] No profile loaded for", player.Name)
        return nil
    end
    
    -- Load from DataStore
    local key = "Cube_" .. tostring(userId) .. "_" .. profile.materialId
    local success, result = pcall(function()
        return CubeDataStore:GetAsync(key)
    end)
    
    if not success then
        warn("[DataService] Failed to load cube for", player.Name, ":", result)
        return nil
    end
    
    local cube: Types.CubeState
    if result then
        cube = result :: Types.CubeState
    else
        cube = createDefaultCube(userId, profile.materialId)
    end
    
    -- Cache the data
    playerCubes[player] = cube
    
    print("[DataService] Loaded cube for", player.Name)
    return cube
end

-- Save player data to DataStore
function DataService:SavePlayerAsync(player: Player): boolean
    local profile = playerData[player]
    if not profile then
        return false
    end
    
    profile.lastSaveTime = os.time()
    
    local userId = player.UserId
    local key = "Player_" .. tostring(userId)
    
    local success, err = pcall(function()
        PlayerDataStore:SetAsync(key, profile)
    end)
    
    if not success then
        warn("[DataService] Failed to save data for", player.Name, ":", err)
        return false
    end
    
    print("[DataService] Saved data for", player.Name)
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
    
    local success, err = pcall(function()
        CubeDataStore:SetAsync(key, compactCube)
    end)
    
    if not success then
        warn("[DataService] Failed to save cube for", player.Name, ":", err)
        return false
    end
    
    print("[DataService] Saved cube for", player.Name)
    return true
end

-- Save all data for a player
function DataService:SaveAllAsync(player: Player): boolean
    local success1 = self:SavePlayerAsync(player)
    local success2 = self:SaveCubeAsync(player)
    return success1 and success2
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
function DataService:UpdatePlayerData(player: Player, updates: {[string]: any})
    local profile = playerData[player]
    if not profile then return end
    
    for key, value in pairs(updates) do
        (profile :: any)[key] = value
    end
    
    self:QueueSave(player)
end

-- Add currency
function DataService:AddCurrency(player: Player, currencyType: string, amount: number): boolean
    local profile = playerData[player]
    if not profile then return false end
    
    if currencyType == "coins" then
        profile.coins = math.max(0, profile.coins + amount)
        -- Fire event to update UI
        Remotes.RE.OnCurrencyChanged:FireClient(player, "coins", profile.coins)
    elseif currencyType == "gems" then
        profile.gems = math.max(0, profile.gems + amount)
        -- Fire event to update UI
        Remotes.RE.OnCurrencyChanged:FireClient(player, "gems", profile.gems)
    else
        return false
    end
    
    self:QueueSave(player)
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
        local deadline = tick() + 2.0
        while tick() < deadline do
            if playerData[player] and playerCubes[player] then
                if not player:GetAttribute("DataLoaded") then
                    player:SetAttribute("DataLoaded", true)
                end
                return true
            end
            task.wait(0.1)
        end
        
        -- Still no data after timeout? Synthesize defaults as fallback
        warn("[DataService] EnsureLoaded: synthesizing default data for", player.Name)
        local profile = createDefaultProfile(player.UserId)
        playerData[player] = profile
        local cube = createDefaultCube(player.UserId, profile.materialId)
        playerCubes[player] = cube
        player:SetAttribute("DataLoaded", true)
        return true
    end
    
    -- Production: attempt synchronous load (last resort path)
    local ok = pcall(function()
        local profile = DataService:LoadPlayerAsync(player)
        if not profile then return end
        local cube = DataService:LoadCubeAsync(player)
        if not cube then return end
        player:SetAttribute("DataLoaded", true)
    end)
    return ok and player:GetAttribute("DataLoaded") == true
end

-- Can afford check
function DataService:CanAfford(player: Player, currencyType: string, amount: number): boolean
    local profile = playerData[player]
    if not profile then return false end
    
    if currencyType == "coins" then
        return profile.coins >= amount
    elseif currencyType == "gems" then
        return profile.gems >= amount
    end
    
    return false
end

-- Auto-save loop
local function autoSaveLoop()
    while true do
        wait(GameConfig.DataStore.AUTO_SAVE_INTERVAL)
        
        for player, needsSave in pairs(saveQueue) do
            if needsSave and player.Parent then
                spawn(function()
                    DataService:SaveAllAsync(player)
                end)
                saveQueue[player] = false
            end
        end
    end
end

-- Function to initialize player data
local function onPlayerAdded(player)
    print("[DataService] Player joined:", player.Name)
    
    -- Load data asynchronously
    spawn(function()
        -- Try to load from DataStore (works in Studio if API Services enabled)
        local profile = DataService:LoadPlayerAsync(player)
        if profile then
            local cube = DataService:LoadCubeAsync(player)
            if cube then
                -- Notify other services that data is loaded
                player:SetAttribute("DataLoaded", true)
                print("[DataService] Data loaded for", player.Name)
            else
                -- Create default cube if loading failed
                warn("[DataService] Failed to load cube, creating default")
                local defaultCube = createDefaultCube(player.UserId, profile.materialId)
                playerCubes[player] = defaultCube
                player:SetAttribute("DataLoaded", true)
            end
        else
            -- In Studio with no DataStore access, create default data
            if not canUseDataStore then
                print("[DataService] No DataStore access - creating default data for", player.Name)
                local profile = createDefaultProfile(player.UserId)
                playerData[player] = profile
                local cube = createDefaultCube(player.UserId, profile.materialId)
                playerCubes[player] = cube
                player:SetAttribute("DataLoaded", true)
            else
                -- Production failure - should not happen
                warn("[DataService] Failed to load profile in production for", player.Name)
                player:Kick("Failed to load profile data. Please try again.")
            end
        end
    end)
end

-- Connect player events
Players.PlayerAdded:Connect(onPlayerAdded)

-- Handle players already in game (Studio test player)
for _, player in ipairs(Players:GetPlayers()) do
    onPlayerAdded(player)
end

-- Handle player leaving
Players.PlayerRemoving:Connect(function(player)
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
end)

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
local function setupWipeCommand(player)
    player.Chatted:Connect(function(message)
        if message == "/wipedata" then
            print("[DataService] Wipe command received from", player.Name)
            
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
                
                print("[DataService] Wiped data for", player.Name)
                
                -- Kick player to force reload
                player:Kick("Data wiped! Please rejoin.")
            else
                warn("[DataService] No profile found for", player.Name)
            end
        end
    end)
end

-- Set up for already connected players
for _, player in ipairs(game.Players:GetPlayers()) do
    setupWipeCommand(player)
end

-- Set up for future players
game.Players.PlayerAdded:Connect(setupWipeCommand)

print("[DataService] Initialized")

return DataService