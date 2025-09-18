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
local Time = require(MiningGame:WaitForChild("Time"))
local Ready = require(MiningGame:WaitForChild("Ready"))
local log = Logger.new("TestClient")

-- Client error handling
local ClientError = require(script.Parent:WaitForChild("ClientErrorHandler"))

log:info("Starting...")
log:debug("Found MiningGame")

-- Get config
local GameConfig = require(MiningGame:WaitForChild("GameConfig"))
local CELL_SIZE = GameConfig.Grid.CELL_SIZE_STUDS

-- Get utilities
local GridMath = require(MiningGame:WaitForChild("Utils"):WaitForChild("GridMath"))
local MathUtils = require(MiningGame:WaitForChild("MathUtils"))

-- Get ClientRF for remote calls
local ClientRF = require(MiningGame:WaitForChild("ClientRF"))
log:debug("ClientRF loaded")

-- Get EventBus for event listening
local EventBus = require(MiningGame:WaitForChild("EventBus"))
local EventNames = require(MiningGame:WaitForChild("EventNames"))
local Bus = EventBus.global()

-- Store connections for cleanup
local connections = {} :: {{ Disconnect: () -> () }}

-- Interval-safe time source
local function now() return Time.mono() end

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
local digCooldown = GameConfig.Client.INITIAL_DIG_COOLDOWN -- Start with default cooldown (will be updated from server)
local cooldownEndsAt = 0 -- Track when next dig is allowed
local lastDigTime = 0 -- Track when we last attempted a dig

-- Store player's cube origin when profile loads
local playerCubeOrigin = nil

-- Listen for cube origin changes via EventBus
table.insert(connections, { Disconnect = Bus:on(EventNames.CUBE_ORIGIN_CHANGED, function(payload)
    ClientError.try("CUBE_ORIGIN_CHANGED", function()
        -- payload.origin may be Vector3 (per EventTypes), handle a few shapes defensively
        local originAny = payload and (payload.origin or payload.cframe or payload.CFrame)
        if not originAny then return end

        if typeof(originAny) == "CFrame" then
        playerCubeOrigin = originAny
    elseif typeof(originAny) == "Vector3" then
        playerCubeOrigin = CFrame.new(originAny)
    elseif typeof(originAny) == "table" and originAny.x then
        playerCubeOrigin = CFrame.new(originAny.x, originAny.y, originAny.z)
    end

    if playerCubeOrigin then
        log:info("Cube origin updated to: {}", tostring(playerCubeOrigin.Position))
        if visualFeedback then
            visualFeedback:SetCubeOrigin(playerCubeOrigin)
        end
    end
    end)
end) })

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
    -- IMPORTANT: Terrain cubes are axis-aligned, don't use rotation!
    local localPos = worldPos - origin.Position
    local half = GameConfig.Grid.CUBE_SIZE_STUDS / 2
    -- Add tolerance for terrain texture that extends beyond voxel boundaries
    local tolerance = GameConfig.Client.CUBE_TOLERANCE_STUDS
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
    local t = now()
    
    -- Expanded client-side check: allow island volumes too (server authoritative)
    -- Keep permissive: only block if far out of range to reduce noisy calls.
    do
        local maxRange = (GameConfig.Digging and GameConfig.Digging.MAX_RANGE_STUDS) or 0
        if maxRange and maxRange > 0 then
            local dist = (position - humanoidRootPart.Position).Magnitude
            if dist > maxRange * 1.25 then -- small grace margin vs server
                log:debug("Click way out of range - ignoring")
                return
            end
        end
    end
    
    -- ✅ local cooldown guard (mirrors server; prevents fails/no-sound cases)
    if t < cooldownEndsAt then
        log:debug("Local cooldown (%.2fs left)", MathUtils.saturatingSub(cooldownEndsAt, t))
        return
    end
    
    log:info("[DEBUG] REQUESTING DIG AT: %s", tostring(position))
    
    -- ✅ ask the server FIRST
    local result, err = ClientRF.call("RequestDig", position)
    if err then
        log:warn("Dig request failed: %s", err)
        return
    end
    
    if result and result.ok then
        log:info("Dig successful! Dug %d cells", result.cellsDug)
        
        -- ✅ play sound ONLY on success
        -- Prefer the server's material if provided; fallback to local probe
        local matKey = (result.soundMaterialKey :: string?) or getMaterialAtPosition(position) or "rock"
        local sfxPos = result.soundWorldPos or position
        log:debug("Playing local sound for material: %s subtype: %s at position: %s (2D fixed volume)", matKey, tostring(result.soundSubtype or "hit"), tostring(sfxPos))
        -- Play local dig sound as 2D (fixed volume) regardless of camera distance
        -- Use GameConfig.Digging.HIT_VOLUME for tunable loudness
        SoundManager.PlayMining(matKey, result.soundSubtype, sfxPos, { force2D = true, volume = GameConfig.Digging.HIT_VOLUME })
        
        if result.effectiveStats then
            digCooldown = result.effectiveStats.delay
            if visualFeedback then
                visualFeedback:SetCooldown(digCooldown)
                visualFeedback:SetPreviewSize(result.effectiveStats.size or 1)
            end
        end
        
        -- Update cooldown tracking
        cooldownEndsAt = result.nextAllowedAt or (t + digCooldown)
        
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
            local timeLeft = result.nextAllowedAt - t
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
    local profile, err = ClientRF.call("GetProfile")
    if err then
        log:warn("Failed to get profile: %s", err)
        return
    end
    
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

-- Listen for dig feedback via EventBus
table.insert(connections, { Disconnect = Bus:on(EventNames.DIG_FEEDBACK, function(payload)
    ClientError.try("DIG_FEEDBACK", function()
        local feedback = payload
        log:debug("Dig feedback received:")
        print("  Cells dug:", feedback.cellCount or "unknown")
        print("  Size:", feedback.size or "unknown")
        print("  Shake:", feedback.shake)
        print("  Particles:", feedback.particles)

    if visualFeedback then
        local approxEnds = now() + (digCooldown or 0.2)
        visualFeedback:SetCooldownEndsAt(approxEnds)
        visualFeedback:OnDig()
        visualFeedback:ShowDigResult(true, feedback.centerPos or feedback.worldPos)
    end
    end)
end) })

-- Listen for loot drops via EventBus
table.insert(connections, { Disconnect = Bus:on(EventNames.LOOT_DROPPED, function(p)
    ClientError.try("LOOT_DROPPED", function()
        log:debug("Loot dropped!")
        local counts = p.counts or p.items
        if counts then
            for itemId, count in pairs(counts) do
                log:debug("  - %s x%d", itemId, count)
            end
        end
        local pos = p.position or p.worldPos
        if pos then print("  Position:", pos) end
    end)
end) })

-- Listen for inventory changes via EventBus (snapshot or legacy delta)
table.insert(connections, { Disconnect = Bus:on(EventNames.INVENTORY_CHANGED, function(change)
    ClientError.try("INVENTORY_CHANGED", function()
        log:debug("Inventory changed:")
        local isSnapshot = (type(change) == "table") and (change.items ~= nil or change.action == nil)
        if isSnapshot then
            local items = change.items or change -- new format sends the inventory table directly
            local n = 0
            for _ in pairs(items or {}) do n += 1 end
            print("  Snapshot items:", n)
        else
            -- delta
            if change.action == "add" then
                print(("  + %s x%d (total %s)"):format(change.itemId, change.count or 0, tostring(change.total)))
            elseif change.action == "remove" then
                print(("  - %s x%d (total %s)"):format(change.itemId, change.count or 0, tostring(change.total)))
            elseif change.action == "equip" then
                print(("  equip %s in %s"):format(tostring(change.itemId), tostring(change.slot)))
            elseif change.action == "unequip" then
                print(("  unequip from %s"):format(tostring(change.slot)))
            end
        end
    end)
end) })

-- Listen for announcements via EventBus
table.insert(connections, { Disconnect = Bus:on(EventNames.ANNOUNCEMENT_BROADCAST, function(msg)
    ClientError.try("ANNOUNCEMENT_BROADCAST", function()
        local message = msg.message or msg.text or "(no message)"
        log:info("Notification: %s", message)
    end)
end) })

-- Controls
log:debug("Controls:")
print("  Press E to dig below player")
print("  Press P to view profile")
print("  Click to dig at mouse position")

-- Keyboard input
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    ClientError.try("InputBegan", function()
        if gameProcessed then return end
        
        if input.KeyCode == Enum.KeyCode.E then
            -- Dig below player
            requestDigAt(humanoidRootPart.Position + Vector3.new(0, -10, 0))
        elseif input.KeyCode == Enum.KeyCode.P then
            getProfile()
        end
    end)
end)

-- Track continuous dig state
local isMouseDown = false
local continuousDigLoop = nil

-- Helper function to get dig position from mouse
local function getDigPositionFromMouse(): Vector3?
    local cam = workspace.CurrentCamera
    if not cam then return nil end
    
    -- Build a ray from the screen point
    local ray = cam:ScreenPointToRay(mouse.X, mouse.Y)
    
    -- Use pre-created params for efficiency
    local hit = workspace:Raycast(ray.Origin, ray.Direction * GameConfig.Client.CONTINUOUS_DIG_RAY_LENGTH, terrainRayParams)
    
    if not hit then
        log:debug("Raycast miss (no Terrain under cursor)")
        return nil
    end
    
    -- DEBUG: Log exact hit details
    log:info("[DEBUG] CLIENT HIT:")
    log:info("  Hit Position: %s", tostring(hit.Position))
    log:info("  Hit Normal: %s", tostring(hit.Normal))
    log:info("  Hit Material: %s", tostring(hit.Material))
    
    -- Keep the actual surface position for external faces
    local surfacePos = hit.Position
    
    -- Ask server which volume we're over
    local vol, _ = ClientRF.call("QueryVolumeAt", surfacePos)
    local origin: CFrame? = nil
    if vol and vol.ok and vol.success and vol.hit then
        origin = vol.origin
        log:info("[DEBUG] VOLUME HIT:")
        log:info("  Volume ID: %s", tostring(vol.id))
        log:info("  Volume Kind: %s", tostring(vol.kind))
        log:info("  Volume Origin: %s", tostring(vol.origin.Position))
        log:info("  Volume Size: %s", tostring(vol.size))
        -- Update visual feedback with the active volume
        if _G.MiningGameVisualFeedback then
            _G.MiningGameVisualFeedback:SetActiveVolume(vol.origin, vol.size)
        end
    else
        log:debug("QueryVolumeAt: no hit at %s", tostring(surfacePos))
        origin = playerCubeOrigin -- fallback for early boot
        -- Update visual feedback to use player cube
        if _G.MiningGameVisualFeedback and playerCubeOrigin then
            local s = GameConfig.Grid.CUBE_SIZE_STUDS
            _G.MiningGameVisualFeedback:SetActiveVolume(playerCubeOrigin, Vector3.new(s, s, s))
        end
    end
    if not origin then return surfacePos end

    -- For external surfaces, use the actual hit position
    -- The server will validate if this is a valid exposed surface
    log:info("[DEBUG] SENDING TO SERVER: %s", tostring(surfacePos))
    return surfacePos
end

-- Mouse down: start continuous digging at cursor position
mouse.Button1Down:Connect(function()
    ClientError.try("MouseDown", function()
        isMouseDown = true
        log:debug("MouseDown")
        local pos = getDigPositionFromMouse()
        if pos then
            requestDigAt(pos)
        else
            log:debug("MouseDown: no dig position available")
        end
        
        -- Start a loop that digs wherever the mouse is pointing
        continuousDigLoop = task.spawn(function()
            while isMouseDown do
                ClientError.try("ContinuousDigTick", function()
                    local t = now()
                    
                    -- Only dig if we're past the cooldown
                    if t >= cooldownEndsAt then
                        local pos = getDigPositionFromMouse()
                        if pos then
                            requestDigAt(pos)
                            lastDigTime = t
                        end
                    end
                end)
                
                -- Wait a short time before checking again
                -- Use a small interval to be responsive when cooldown ends
                task.wait(GameConfig.Client.DIG_POLL_INTERVAL)
            end
        end)
    end)
end)

-- Mouse up: stop continuous digging
mouse.Button1Up:Connect(function()
    ClientError.try("MouseUp", function()
        isMouseDown = false
        
        -- Cancel the continuous dig loop
        if continuousDigLoop then
            task.cancel(continuousDigLoop)
            continuousDigLoop = nil
        end
    end)
end)

-- Wait for server to be ready
if not Ready.wait(10) then
    log:warn("Server not ready after timeout, continuing anyway")
end

-- Get initial profile first (before starting visual feedback)
wait(GameConfig.Client.PROFILE_LOAD_WAIT) -- Wait for data to load
getProfile()

-- Initialize visual feedback system AFTER profile is loaded
task.spawn(function()
    -- Small delay to ensure profile data is set
    wait(GameConfig.Client.VISUAL_STARTUP_DELAY)
    
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

-- Cleanup on script destroy
script.Destroying:Connect(function()
    for _, c in ipairs(connections) do
        if c and c.Disconnect then c.Disconnect() end
    end
end)

log:info("Test client ready! Press E to dig, P for profile")
