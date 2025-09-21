--!strict
-- TreeClimbing.client.lua
-- Shows a HUD chip to climb trees when nearby

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(MiningGame:WaitForChild("Logger"))

local log = Logger.new("TreeClimbing")

local player = Players.LocalPlayer

-- Wait for character to load
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")

log:info("TreeClimbing starting for player %s", player.Name)

-- Configuration
local DETECTION_RANGE = 25 -- Studs from trunk (increased for earlier detection)
local TELEPORT_HEIGHT_OFFSET = 10 -- Extra studs above tree top (increased to avoid getting stuck)

-- Get MainHUD reference (wait for UI to initialize)
local mainHUD = nil

-- Wait for MainHUD to be available through global UIManager
task.spawn(function()
    repeat
        task.wait(0.1)
        if _G.UIManager then
            local scenes = _G.UIManager.scenes
            if scenes and scenes.MainHUD then
                mainHUD = scenes.MainHUD
                log:info("Connected to MainHUD")
                break
            end
        end
    until mainHUD
end)

-- State
local nearbyTree = nil
local isChipShown = false

-- Find the highest point of a tree model
local function getTreeTop(treeModel: Model): Vector3?
    local highestY = -math.huge
    local highestPos = nil
    
    for _, part in ipairs(treeModel:GetDescendants()) do
        if part:IsA("BasePart") and part.Name:lower():find("leaf") then
            if part.Position.Y > highestY then
                highestY = part.Position.Y
                highestPos = part.Position
            end
        end
    end
    
    -- If no leaves found, use trunk top
    if not highestPos then
        for _, part in ipairs(treeModel:GetDescendants()) do
            if part:IsA("BasePart") then
                if part.Position.Y > highestY then
                    highestY = part.Position.Y
                    highestPos = part.Position
                end
            end
        end
    end
    
    return highestPos
end

-- Check if player is near a tree trunk
local function findNearbyTree(): Model?
    local decorFolder = Workspace:FindFirstChild("BlockDecorations")
    if not decorFolder then return nil end
    
    for _, child in ipairs(decorFolder:GetChildren()) do
        if child:IsA("Model") and child.Name:find("Tree") then
            -- Check distance to any non-leaf part (trunk/branch)
            for _, part in ipairs(child:GetDescendants()) do
                if part:IsA("BasePart") and part.Material == Enum.Material.Wood then
                    local distance = (part.Position - rootPart.Position).Magnitude
                    if distance <= DETECTION_RANGE then
                        return child
                    end
                end
            end
        end
    end
    
    return nil
end

-- Teleport player to tree top
local function teleportToTreeTop(tree: Model)
    log:debug("Attempting to teleport to tree: %s", tree.Name)
    local treeTop = getTreeTop(tree)
    if treeTop then
        local targetPos = treeTop + Vector3.new(0, TELEPORT_HEIGHT_OFFSET, 0)
        log:debug("Tree top found at Y=%d, teleporting to Y=%d", treeTop.Y, targetPos.Y)
        rootPart.CFrame = CFrame.new(targetPos)
        log:info("Teleported to tree top at position (%d, %d, %d)", targetPos.X, targetPos.Y, targetPos.Z)
    else
        log:warn("Could not find tree top for %s", tree.Name)
    end
end

-- Update loop
local frameCount = 0
RunService.Heartbeat:Connect(function()
    frameCount = frameCount + 1
    
    -- Check for nearby trees
    local previousTree = nearbyTree
    nearbyTree = findNearbyTree()
    
    -- Suppress periodic heartbeat debug logging (noise)
    
    -- Only interact with HUD if it's ready
    if not mainHUD then return end
    
    -- Handle tree detection changes
    if nearbyTree and not previousTree then
        -- Near a tree - show climb option
        log:info("Near tree: %s", nearbyTree.Name)
        isChipShown = true
        mainHUD:showActionChip("Climb", "🌳", function()
            log:debug("Climb chip activated")
            -- Delay teleport to let button animation play
            task.wait(0.2)
            teleportToTreeTop(nearbyTree)
            -- Hide chip after climbing (clean UI)
            mainHUD:hideActionChip()
            isChipShown = false
        end)
        
    elseif not nearbyTree and previousTree then
        -- Left tree area
        log:info("Left tree area")
        isChipShown = false
        mainHUD:hideActionChip()
    end
end)

-- Handle character respawn
player.CharacterAdded:Connect(function(newCharacter)
    character = newCharacter
    humanoid = character:WaitForChild("Humanoid")
    rootPart = character:WaitForChild("HumanoidRootPart")
    log:info("Character respawned, updating references")
end)

-- Check for trees immediately (they spawn at server start now)
local decorFolder = Workspace:FindFirstChild("BlockDecorations")
if decorFolder then
    local treeCount = 0
    local allChildren = {}
    for _, child in ipairs(decorFolder:GetChildren()) do
        table.insert(allChildren, child.Name)
        if child:IsA("Model") and child.Name:find("Tree") then
            treeCount = treeCount + 1
            -- Check for Wood parts in the tree
            local woodParts = 0
            for _, part in ipairs(child:GetDescendants()) do
                if part:IsA("BasePart") and part.Material == Enum.Material.Wood then
                    woodParts = woodParts + 1
                end
            end
            log:debug("Tree %s has %d wood parts", child.Name, woodParts)
        end
    end
    log:info("Tree climbing initialized - Found %d trees in folder with %d total children", treeCount, #allChildren)
    if #allChildren > 0 then
        log:debug("Folder children: %s", table.concat(allChildren, ", "))
    end
else
    -- Trees might still be loading, wait a bit
    task.wait(1)
    decorFolder = Workspace:FindFirstChild("BlockDecorations")
    if decorFolder then
        local treeCount = 0
        for _, child in ipairs(decorFolder:GetChildren()) do
            if child:IsA("Model") and child.Name:find("Tree") then
                treeCount = treeCount + 1
            end
        end
        log:info("Tree climbing initialized after wait - Found %d trees", treeCount)
    else
        log:warn("BlockDecorations folder not found during initialization")
    end
end
