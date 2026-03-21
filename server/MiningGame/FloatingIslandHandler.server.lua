--!strict
-- FloatingIslandHandler.server.lua
-- Server-side handler for floating island GUI commands

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(MiningGame:WaitForChild("Logger"))
-- FloatingIslandService now accessed via DI in RemoteFns/FloatingIsland.rf.lua

local log = Logger.new("IslandHandler")

-- Rate limiting
local playerCooldowns: { [Player]: number } = {}
local playerIslandCounts: { [Player]: number } = {}

-- Helper to mark usage
-- markUse moved to RF implementation; here unused

-- Cleanup on player leave
Players.PlayerRemoving:Connect(function(player)
	playerCooldowns[player] = nil
	playerIslandCounts[player] = nil
end)

-- Get player position
-- getPlayerPosition handled in RF path; not used here

-- Remote handlers moved to RemoteFns/FloatingIsland.rf.lua via RFRegistry
--[[
    local config = GameConfig.FloatingIslands
    local isStudio = RunService:IsStudio()
    local liveFeatureOpen = config.ENABLED and not config.STUDIO_ONLY
    
    -- Check if feature is available
    if not config.ENABLED and not isStudio then
        return {success = false, error = "Floating islands are disabled"}
    end
    
    if config.STUDIO_ONLY and not isStudio then
        return {success = false, error = "Floating islands only available in Studio"}
    end
    
    -- Authorization check: allow in studio, when live feature is open, or for creator
    if not isStudio and not liveFeatureOpen and player.UserId ~= game.CreatorId then
        log:warn(("Unauthorized island spawn by %s"):format(player.Name))
        return {success = false, error = "Unauthorized"}
    end
    
    -- Rate limiting check
    local now = Time.mono()
    local lastSpawn = playerCooldowns[player] or 0
    if now - lastSpawn < config.RATE_LIMIT_SECONDS then
        local remaining = math.ceil(config.RATE_LIMIT_SECONDS - (now - lastSpawn))
        return {success = false, error = "Please wait " .. remaining .. " seconds"}
    end
    
    -- Check island count limit
    local count = playerIslandCounts[player] or 0
    if count >= config.MAX_ISLANDS_PER_SESSION then
        return {success = false, error = "Island limit reached (" .. config.MAX_ISLANDS_PER_SESSION .. ")"}
    end
    
    -- Validate request
    if type(request) ~= "table" or type(request.action) ~= "string" then
        return {success = false, error = "Invalid request"}
    end
    
    local action = request.action
    local playerPos = getPlayerPosition(player)
    
    if not playerPos and action ~= "themes" and action ~= "presets" then
        return {success = false, error = "Could not get player position"}
    end
    
    log:debug("Island request from " .. player.Name .. ": " .. action)
    
    if action == "single" then
        -- Spawn single island above player
        local preset = request.preset or "medium"
        local theme = request.theme or "earth"
        local islandPos = playerPos + Vector3.new(0, 100, 0)
        
        local success = FloatingIslandService:GenerateIsland(islandPos, preset, theme)
        
        if success then
            markUse(player)
            log:info(player.Name .. " spawned " .. preset .. " " .. theme .. " island")
            return {success = true}
        else
            return {success = false, error = "Failed to generate island"}
        end
        
    elseif action == "random" then
        -- Spawn random island near player (Random API)
        local angle = rng:NextNumber(0, math.pi * 2)
        local distance = rng:NextInteger(50, 150)
        local height = rng:NextInteger(80, 120)
        
        local islandPos = playerPos + Vector3.new(
            math.cos(angle) * distance,
            height,
            math.sin(angle) * distance
        )
        
        local themes = FloatingIslandService:GetThemes()
        local presets = FloatingIslandService:GetPresets()
        local theme = themes[rng:NextInteger(1, #themes)]
        local preset = presets[rng:NextInteger(1, #presets)]
        
        local success = FloatingIslandService:GenerateIsland(islandPos, preset, theme)
        
        if success then
            markUse(player)
            log:info(player.Name .. " spawned random island: " .. preset .. " " .. theme)
            return {success = true}
        else
            return {success = false, error = "Failed to generate island"}
        end
        
    elseif action == "archipelago" then
        -- Generate archipelago
        local count = tonumber(request.count) or 5
        local theme = request.theme or "mixed"
        count = math.clamp(count, 1, 20)
        
        local islandPos = playerPos + Vector3.new(0, 120, 0)
        
        task.spawn(function()
            local islands = FloatingIslandService:GenerateArchipelago(
                islandPos,
                count,
                150, -- spread
                "small",
                theme
            )
            log:info(player.Name .. " generated archipelago with " .. #islands .. " islands")
        end)
        
        markUse(player)
        return {success = true}
        
    elseif action == "mass" then
        -- Generate many random islands
        local count = tonumber(request.count) or 10
        count = math.clamp(count, 1, 30)
        
        task.spawn(function()
            local islands = FloatingIslandService:GenerateRandomIslands(
                playerPos,
                300, -- area radius
                count,
                80,  -- min height
                150  -- max height
            )
            log:info(player.Name .. " generated " .. #islands .. " random islands")
        end)
        
        markUse(player)
        return {success = true}
        
    elseif action == "clear" then
        -- Clear all islands
        task.spawn(function()
            FloatingIslandService:ClearAllIslands()
        end)
        return {success = true, message = "Islands cleared"}
        
    elseif action == "themes" then
        -- Return available themes
        return {
            success = true,
            themes = FloatingIslandService:GetThemes()
        }
        
    elseif action == "presets" then
        -- Return available presets
        return {
            success = true,
            presets = FloatingIslandService:GetPresets()
        }
        
    else
        return {success = false, error = "Unknown action: " .. action}
    end
--]]

log:info("Floating island handler initialized - remotes migrated to FloatingIslandHandlerRemotes.lua")
