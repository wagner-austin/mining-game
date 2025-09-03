--!strict
--[[
    TestClient.client.lua
    Test client for mining game mechanics including dig requests, visual feedback, and sound playback.
    
    Features:
    - Click-to-dig with terrain raycasting
    - Cell snapping for server alignment
    - Visual feedback system integration
    - Local sound playback based on material
    - Profile fetching and display
    - Cooldown tracking
    
    Controls:
    - Click: Dig at mouse position
    - E: Dig below player
    - P: View profile
]]

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

-- Get utilities
local Utils = MiningGame:WaitForChild("Utils")
local GridMath = require(Utils:WaitForChild("GridMath"))

-- Get remotes using the Remotes accessor module
local Remotes = require(MiningGame:WaitForChild("Remotes"))
log:debug("Remotes loaded")

-- Get SoundManager for local sound playback
local SoundManager = require(MiningGame:WaitForChild("SoundManager"))

-- Get DigVisualFeedback for visual indicators
local DigVisualFeedback = require(MiningGame:WaitForChild("DigVisualFeedback"))
local visualFeedback = nil

-- Pre-create raycast params for terrain detection
local terrainRayParams = RaycastParams.new()
terrainRayParams.FilterType = Enum.RaycastFilterType.Include
terrainRayParams.FilterDescendantsInstances = {workspace.Terrain}

-- Track dig cooldown
local digCooldown = 1 -- Start with 1 second cooldown (will be updated from server)
local cooldownEndsAt = 0 -- Track when next dig is allowed
local lastDigTime = 0 -- Track when we last attempted a dig

-- Store player's cube origin when profile loads
local playerCubeOrigin = nil

-- Listen for cube origin changes (e.g., after reset)
Remotes.RE.OnCubeOriginChanged.OnClientEvent:Connect(function(newOrigin)
    playerCubeOrigin = newOrigin
    log:info("Cube origin updated to: {}", tostring(newOrigin.Position))
    
    -- Update visual feedback system if it exists
    if visualFeedback then
        visualFeedback:SetCubeOrigin(newOrigin)
    end
end)

--[[
    Get the terrain material at a given position for accurate sound playback.
    Samples a 4x4x4 voxel region and returns the dominant material.
    
    @param position: Vector3 - The world position to sample
    @return string - Material key for sound system (e.g., "rock", "sand")
]]
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

--[[
    Check if a world position is inside the player's cube with tolerance.
    Accounts for terrain texture that extends ~2 studs beyond voxel boundaries.
    
    @param worldPos: Vector3 - The world position to check
    @param origin: CFrame - The cube's origin CFrame
    @return boolean - True if position is inside or near cube boundary
]]
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

--[[
    Request a dig operation at the specified world position.
    Handles client-side validation, server communication, and feedback.
    
    @param position: Vector3 - The world position to dig at
]]
local function requestDigAt(position: Vector3)
    local now = tick()  -- ✅ ensure 'now' exists
    
    -- Client-side bounds check for better UX
    if not insideCube(position, playerCubeOrigin) then
        log:debug("Click outside cube bounds - ignoring")
        return
    end
    
    -- ✅ local cooldown guard (mirrors server; prevents fails/no-sound cases)
    if now < cooldownEndsAt then
        log:debug("On cooldown (%.2fs left)", math.max(0, cooldownEndsAt - now))
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
            if visualFeedback then
                visualFeedback:SetCooldown(digCooldown)
                visualFeedback:SetPreviewSize(result.effectiveStats.size or 1)
            end
        end
        
        -- Update cooldown tracking
        cooldownEndsAt = result.nextAllowedAt or (now + digCooldown)
        
        -- Update visual feedback
        if visualFeedback then
            visualFeedback:SetCooldownEndsAt(cooldownEndsAt)
            visualFeedback:OnDig()
            visualFeedback:ShowDigResult(true, result.soundWorldPos or position)
        end
        
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
            cooldownEndsAt = result.nextAllowedAt
            local timeLeft = result.nextAllowedAt - now
            log:debug("Can dig again in %.2fs", timeLeft)
            if visualFeedback then
                visualFeedback:SetCooldownEndsAt(cooldownEndsAt)
                visualFeedback:OnDig()  -- Show cooldown bar even on failures
            end
        end
        
        -- Show failure feedback
        if visualFeedback then
            visualFeedback:ShowDigResult(false, position)
        end
    end
end

--[[
    Fetch and display the player's profile data from the server.
    Updates local state including cube origin and dig cooldown.
]]
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
        
        -- Update visual feedback with profile data
        if visualFeedback then
            visualFeedback:SetCubeOrigin(playerCubeOrigin)
            visualFeedback:SetCooldown(profile.effectiveStats.delay)
            visualFeedback:SetPreviewSize(profile.effectiveStats.size or 1)
        end
        
        -- Update cooldown tracking
        digCooldown = profile.effectiveStats.delay
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
    
    -- Update visual feedback for continuous digs
    if visualFeedback then
        -- We don't get nextAllowedAt here; approximate with last known delay
        local approxEnds = tick() + (digCooldown or 0.2)
        visualFeedback:SetCooldownEndsAt(approxEnds)
        visualFeedback:OnDig()
        visualFeedback:ShowDigResult(true, feedback.centerPos or feedback.worldPos)
    end
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

-- Track continuous dig state
local isMouseDown = false
local continuousDigLoop = nil

-- Helper function to get dig position from mouse
local function getDigPositionFromMouse(): Vector3?
    if not playerCubeOrigin then return nil end -- Guard against missing cube origin
    
    local cam = workspace.CurrentCamera
    if not cam then return nil end
    
    -- Build a ray from the screen point
    local ray = cam:ScreenPointToRay(mouse.X, mouse.Y)
    
    -- Use pre-created params for efficiency
    local hit = workspace:Raycast(ray.Origin, ray.Direction * 2000, terrainRayParams)
    
    if not hit then return nil end
    
    -- Tiny nudge onto the surface, then snap to the exact cell center the server uses
    local aim = hit.Position - (hit.Normal * 0.01)
    
    -- Snap to cell center for perfect alignment with server
    local cx, cy, cz = GridMath.worldToCell(aim, playerCubeOrigin, CELL_SIZE)
    return GridMath.cellToWorld(cx, cy, cz, playerCubeOrigin, CELL_SIZE)
end

-- Mouse down: start continuous digging at cursor position
mouse.Button1Down:Connect(function()
    isMouseDown = true
    
    -- Start a loop that digs wherever the mouse is pointing
    continuousDigLoop = task.spawn(function()
        while isMouseDown do
            local now = tick()
            
            -- Only dig if we're past the cooldown
            if now >= cooldownEndsAt then
                local pos = getDigPositionFromMouse()
                if pos then
                    requestDigAt(pos)
                    lastDigTime = now
                end
            end
            
            -- Wait a short time before checking again
            -- Use a small interval to be responsive when cooldown ends
            task.wait(0.05)
        end
    end)
end)

-- Mouse up: stop continuous digging
mouse.Button1Up:Connect(function()
    isMouseDown = false
    
    -- Cancel the continuous dig loop
    if continuousDigLoop then
        task.cancel(continuousDigLoop)
        continuousDigLoop = nil
    end
end)

-- Get initial profile first (before starting visual feedback)
wait(2) -- Wait for data to load
getProfile()

-- Initialize visual feedback system AFTER profile is loaded
task.spawn(function()
    -- Small delay to ensure profile data is set
    wait(0.1)
    
    visualFeedback = DigVisualFeedback.new()
    visualFeedback:Init()
    
    -- Set initial data if available
    if playerCubeOrigin then
        visualFeedback:SetCubeOrigin(playerCubeOrigin)
    end
    
    visualFeedback:Start()
    
    -- Store globally for UIManager access
    _G.MiningGameVisualFeedback = visualFeedback
    
    log:info("Visual feedback system started with origin: {}", 
        playerCubeOrigin and tostring(playerCubeOrigin.Position) or "nil")
end)

log:info("Test client ready! Press E to dig, P for profile")