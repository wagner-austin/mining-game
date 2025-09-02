--!strict
-- TestClient.client.lua
-- Minimal test client to verify dig mechanics

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

-- Wait for character
local character = player.Character or player.CharacterAdded:Wait()
local humanoidRootPart = character:WaitForChild("HumanoidRootPart")

-- Wait for MiningGame to load
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame", 30)
assert(MiningGame, "MiningGame not found in ReplicatedStorage")

-- Get Logger
local Logger = require(MiningGame:WaitForChild("Logger"))
local log = Logger.new("TestClient")

log:info("Starting...")
log:debug("Found MiningGame")

-- Get config
local GameConfig = require(MiningGame:WaitForChild("GameConfig"))
local CELL_SIZE = GameConfig.Grid.CELL_SIZE_STUDS

-- Get remotes using the Remotes accessor module
local Remotes = require(MiningGame:WaitForChild("Remotes"))
log:debug("Remotes loaded")

-- Get SoundManager for local sound playback
local SoundManager = require(MiningGame:WaitForChild("SoundManager"))

-- Track last dig time for visual feedback
local lastDigTime = 0
local digCooldown = 1 -- Start with 1 second cooldown

-- Store player's cube origin when profile loads
local playerCubeOrigin = nil

-- Get material at position for local sound playback
local function getMaterialAtPosition(position: Vector3): string
    -- Sample the terrain to determine what material we're hitting
    local region = Region3.new(position - Vector3.new(2, 2, 2), position + Vector3.new(2, 2, 2))
    region = region:ExpandToGrid(4)
    
    local materials, _ = workspace.Terrain:ReadVoxels(region, 4)
    local size = materials.Size
    
    -- Find the most common non-air material in the region
    local materialCounts = {}
    for x = 1, size.X do
        for y = 1, size.Y do
            for z = 1, size.Z do
                local mat = materials[x][y][z]
                if mat ~= Enum.Material.Air then
                    materialCounts[mat] = (materialCounts[mat] or 0) + 1
                end
            end
        end
    end
    
    -- Find dominant material
    local dominantMaterial = Enum.Material.Rock
    local maxCount = 0
    for mat, count in pairs(materialCounts) do
        if count > maxCount then
            dominantMaterial = mat
            maxCount = count
        end
    end
    
    -- Map to material key using MaterialKeys module for consistency with server
    local MaterialKeys = require(MiningGame:WaitForChild("MaterialKeys"))
    return MaterialKeys.KeyFromEnum[dominantMaterial] or "rock"
end

-- Quick client-side bounds check with tolerance for terrain texture overflow
local function insideCube(worldPos: Vector3, origin: CFrame): boolean
    if not origin then return false end
    local localPos = origin:PointToObjectSpace(worldPos)
    local half = GameConfig.Grid.CUBE_SIZE_STUDS / 2
    -- Add 2 stud tolerance for terrain texture that extends beyond voxel boundaries
    local tolerance = 2
    return math.abs(localPos.X) <= (half + tolerance) and 
           math.abs(localPos.Y) <= (half + tolerance) and 
           math.abs(localPos.Z) <= (half + tolerance)
end

-- Function to request a dig at specific position
local function requestDigAt(position: Vector3)
    local now = tick()  -- ✅ ensure 'now' exists
    
    -- Client-side bounds check for better UX
    if not insideCube(position, playerCubeOrigin) then
        log:debug("Click outside cube bounds - ignoring")
        return
    end
    
    -- ✅ local cooldown guard (mirrors server; prevents fails/no-sound cases)
    if (now - lastDigTime) < (digCooldown - 1/60) then
        log:debug("On cooldown (%.2fs left)",
            math.max(0, digCooldown - (now - lastDigTime)))
        return
    end
    
    log:debug("Requesting dig at: %s", tostring(position))
    
    -- ✅ ask the server FIRST
    local result = Remotes.RF.RequestDig:InvokeServer(position)
    
    if result and result.ok then
        log:info("Dig successful! Dug %d cells", result.cellsDug)
        
        -- ✅ play sound ONLY on success
        -- Prefer the server's material if provided; fallback to local probe
        local matKey = (result.soundMaterialKey :: string?) or getMaterialAtPosition(position) or "rock"
        local sfxPos = result.soundWorldPos or position
        log:debug("Playing local sound for material: %s at position: %s", matKey, tostring(sfxPos))
        SoundManager.PlayMining(matKey, "hit", sfxPos)
        
        if result.effectiveStats then
            digCooldown = result.effectiveStats.delay
        end
        lastDigTime = now
        
        if result.lootGranted and #result.lootGranted > 0 then
            log:info("Loot received: %s", table.concat(result.lootGranted, ", "))
        end
        if result.nextAllowedAt then
            log:debug("Next dig allowed at %.2f", result.nextAllowedAt)
        end
    else
        log:warn("Dig failed: %s", (result and result.reason) or "Unknown reason")
        -- No sound on failures ✅
        if result and result.nextAllowedAt then
            local timeLeft = result.nextAllowedAt - now
            log:debug("Can dig again in %.2fs", timeLeft)
        end
    end
end

-- Function to get profile
local function getProfile()
    log:debug("Requesting profile...")
    local profile = Remotes.RF.GetProfile:InvokeServer()
    
    if profile then
        log:info("Profile loaded:")
        print("  Coins:", profile.profile.coins)
        print("  Gems:", profile.profile.gems)
        print("  Total blocks dug:", profile.profile.totalBlocksDug)
        print("  Effective stats:")
        print("    Delay:", profile.effectiveStats.delay)
        print("    Size:", profile.effectiveStats.size or 0)
        print("    Luck:", profile.effectiveStats.luck)
        
        -- Store cube origin for bounds checking
        if profile.cubeOrigin then
            -- Accept CFrame directly (or handle legacy formats)
            if typeof(profile.cubeOrigin) == "CFrame" then
                playerCubeOrigin = profile.cubeOrigin
            elseif typeof(profile.cubeOrigin) == "Vector3" then
                playerCubeOrigin = CFrame.new(profile.cubeOrigin)
            elseif typeof(profile.cubeOrigin) == "table" then
                -- Legacy table format
                playerCubeOrigin = CFrame.new(profile.cubeOrigin.x, profile.cubeOrigin.y, profile.cubeOrigin.z)
            end
        else
            -- Fallback (shouldn't happen with updated server)
            warn("[TestClient] No cube origin in profile, using fallback")
            local cubeY = GameConfig.Grid.CUBE_SIZE_STUDS / 2
            playerCubeOrigin = CFrame.new(0, cubeY, 0)
        end
        log:debug("Cube origin set to: %s", tostring(playerCubeOrigin.Position))
    else
        log:error("Failed to get profile")
    end
end

-- Listen for feedback events
Remotes.RE.OnDigFeedback.OnClientEvent:Connect(function(feedback)
    log:debug("Dig feedback received:")
    print("  Cells dug:", feedback.cellCount or "unknown")
    print("  Size:", feedback.size or "unknown")
    print("  Shake:", feedback.shake)
    print("  Particles:", feedback.particles)
end)

Remotes.RE.OnLootDropped.OnClientEvent:Connect(function(data)
    log:debug("Loot dropped!")
    if data.schema == 2 and data.counts then
        -- New batched format
        log:debug("  Items received (batched):")
        for itemId, count in pairs(data.counts) do
            log:debug("    - %s x%d", itemId, count)
        end
    elseif data.item then
        -- Legacy single item format
        print("  Item:", data.item.id)
        print("  Rarity:", data.item.rarity)
    end
    print("  Position:", data.worldPos)
end)

Remotes.RE.OnInventoryChanged.OnClientEvent:Connect(function(change)
    log:debug("Inventory changed:")
    print("  Action:", change.action)
    print("  Item:", change.itemId)
    print("  Count:", change.count)
    print("  Total:", change.total)
end)

Remotes.RE.OnNotification.OnClientEvent:Connect(function(notification)
    log:info("Notification: %s", notification.message)
end)

-- Controls
log:debug("Controls:")
print("  Press E to dig below player")
print("  Press P to view profile")
print("  Click to dig at mouse position")

-- Keyboard input
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    
    if input.KeyCode == Enum.KeyCode.E then
        -- Dig below player
        requestDigAt(humanoidRootPart.Position + Vector3.new(0, -10, 0))
    elseif input.KeyCode == Enum.KeyCode.P then
        getProfile()
    end
end)

-- Mouse click to dig
mouse.Button1Down:Connect(function()
    local cam = workspace.CurrentCamera
    if not cam then return end
    
    -- Build a ray from the screen point
    local ray = cam:ScreenPointToRay(mouse.X, mouse.Y)
    
    -- ONLY hit Terrain (avoid Bounds/Origin parts)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = {workspace.Terrain}
    
    local hit = workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
    
    if hit then
        -- Use 1 stud offset to ensure we're inside the surface cell
        -- but not so deep that we skip to the next cell (cells are 4 studs)
        local digPos = hit.Position - (hit.Normal * 1.0)
        print(string.format("[Click] Hit terrain at %.1f, %.1f, %.1f", hit.Position.X, hit.Position.Y, hit.Position.Z))
        print(string.format("[Click] Digging at %.1f, %.1f, %.1f (offset by normal)", digPos.X, digPos.Y, digPos.Z))
        requestDigAt(digPos)
    else
        print("[Click] No terrain hit")
    end
end)

-- Get initial profile
wait(2) -- Wait for data to load
getProfile()

log:info("Test client ready! Press E to dig, P for profile")