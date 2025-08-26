--!strict
-- TestClient.client.lua
-- Minimal test client to verify dig mechanics

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

print("[TestClient] Starting...")

-- Wait for character
local character = player.Character or player.CharacterAdded:Wait()
local humanoidRootPart = character:WaitForChild("HumanoidRootPart")

-- Wait for MiningGame to load
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame", 30)
assert(MiningGame, "MiningGame not found in ReplicatedStorage")
print("[TestClient] Found MiningGame")

-- Get config
local GameConfig = require(MiningGame:WaitForChild("GameConfig"))
local CELL_SIZE = GameConfig.Grid.CELL_SIZE_STUDS

-- Get remotes using the Remotes accessor module
local Remotes = require(MiningGame:WaitForChild("Remotes"))
print("[TestClient] Remotes loaded")

-- Track last dig time for visual feedback
local lastDigTime = 0
local digCooldown = 1 -- Start with 1 second cooldown

-- Store player's cube origin when profile loads
local playerCubeOrigin = nil

-- Quick client-side bounds check
local function insideCube(worldPos: Vector3, origin: CFrame): boolean
    if not origin then return false end
    local localPos = origin:PointToObjectSpace(worldPos)
    local half = GameConfig.Grid.CUBE_SIZE_STUDS / 2
    return math.abs(localPos.X) < half and math.abs(localPos.Y) < half and math.abs(localPos.Z) < half
end

-- Function to request a dig at specific position
local function requestDigAt(position: Vector3)
    local now = tick()
    if now - lastDigTime < digCooldown then
        print(string.format("[TestClient] On cooldown (%.1fs remaining)", digCooldown - (now - lastDigTime)))
        return
    end
    
    -- Client-side bounds check for better UX
    if not insideCube(position, playerCubeOrigin) then
        print("[TestClient] Click outside cube bounds - ignoring")
        return
    end
    
    print("[TestClient] Requesting dig at:", position)
    
    -- Request dig from server
    local result = Remotes.RF.RequestDig:InvokeServer(position)
    
    if result.ok then
        print(string.format("[TestClient] Dig successful! Dug %d cells", result.cellsDug))
        if result.lootGranted and #result.lootGranted > 0 then
            print("[TestClient] Loot received:", table.concat(result.lootGranted, ", "))
        end
        if result.effectiveStats then
            digCooldown = result.effectiveStats.delay
            print(string.format("[TestClient] Next dig in %.2fs", digCooldown))
        end
        lastDigTime = now
    else
        print("[TestClient] Dig failed:", result.reason or "Unknown reason")
        if result.nextAllowedAt then
            local timeLeft = result.nextAllowedAt - now
            print(string.format("[TestClient] Can dig again in %.2fs", timeLeft))
        end
    end
end

-- Function to get profile
local function getProfile()
    print("[TestClient] Requesting profile...")
    local profile = Remotes.RF.GetProfile:InvokeServer()
    
    if profile then
        print("[TestClient] Profile loaded:")
        print("  Coins:", profile.profile.coins)
        print("  Gems:", profile.profile.gems)
        print("  Total blocks dug:", profile.profile.totalBlocksDug)
        print("  Effective stats:")
        print("    Delay:", profile.effectiveStats.delay)
        print("    Depth:", profile.effectiveStats.depth)
        print("    Radius:", profile.effectiveStats.radius)
        print("    Luck:", profile.effectiveStats.luck)
        
        -- Store cube origin for bounds checking (need to calculate it)
        -- For now, use default position until we get it from server
        local playerIndex = 0
        for i, p in ipairs(Players:GetPlayers()) do
            if p == player then
                playerIndex = i - 1
                break
            end
        end
        local spacing = GameConfig.Multiplayer.CUBE_SPACING
        local gridX = playerIndex % 3
        local gridZ = math.floor(playerIndex / 3)
        local cubeY = GameConfig.Grid.CUBE_SIZE_STUDS / 2
        playerCubeOrigin = CFrame.new(gridX * spacing, cubeY, gridZ * spacing)
    else
        print("[TestClient] Failed to get profile")
    end
end

-- Listen for feedback events
Remotes.RE.OnDigFeedback.OnClientEvent:Connect(function(feedback)
    print("[TestClient] Dig feedback received:")
    print("  Cells dug:", #feedback.cells)
    print("  Shake:", feedback.shake)
    print("  Particles:", feedback.particles)
end)

Remotes.RE.OnLootDropped.OnClientEvent:Connect(function(data)
    print("[TestClient] Loot dropped!")
    print("  Item:", data.item.id)
    print("  Rarity:", data.item.rarity)
    print("  Position:", data.worldPos)
end)

Remotes.RE.OnInventoryChanged.OnClientEvent:Connect(function(change)
    print("[TestClient] Inventory changed:")
    print("  Action:", change.action)
    print("  Item:", change.itemId)
    print("  Count:", change.count)
    print("  Total:", change.total)
end)

Remotes.RE.OnNotification.OnClientEvent:Connect(function(notification)
    print(string.format("[TestClient] Notification: %s", notification.message))
end)

-- Controls
print("[TestClient] Controls:")
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
        -- Step INTO the cube so the cell is inside, not on the surface
        -- Use just over half a cell to ensure we're inside
        local digPos = hit.Position - (hit.Normal * (CELL_SIZE * 0.51))
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

print("[TestClient] Test client ready! Press E to dig, P for profile")