--!strict
-- AnnouncementService.lua
-- Handles server-wide and global announcements using MessagingService

local Players = game:GetService("Players")
local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(Shared:WaitForChild("Logger"))
local ErrorService = require(script.Parent.ErrorService)
local log = Logger.new("AnnouncementService")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Time = require(Shared:WaitForChild("Time"))

-- Use EventBus instead of direct remotes
local EventBus = require(Shared:WaitForChild("EventBus"))
local EventNames = require(Shared:WaitForChild("EventNames"))
local Bus = EventBus.global()

local AnnouncementService = {}
type AnnouncementServiceT = {
    Init: (self: AnnouncementServiceT, container: any) -> (),
}

-- Initialize with DI container (no dependencies)
function AnnouncementService:Init(container)
    -- No dependencies needed
    log:info("Initialized")
end

-- Channel for cross-server announcements
local GLOBAL_CHANNEL = "global-announcements-v1"

-- Rate limiting for global announcements
local lastGlobalAnnounce: number = -math.huge
local MIN_GLOBAL_INTERVAL = GameConfig.Announcements and GameConfig.Announcements.MIN_GLOBAL_INTERVAL or 1

-- Subscribe to global announcements
local function subscribeToGlobalAnnouncements()
    local ok, err = ErrorService.safecall("MessagingService:SubscribeAsync", function()
        MessagingService:SubscribeAsync(GLOBAL_CHANNEL, function(message)
            local data = message.Data
            
            -- Reconstruct color if it was serialized
            local color = Color3.new(1, 0.84, 0) -- Default gold
            if data.color and data.color.r and data.color.g and data.color.b then
                color = Color3.new(data.color.r, data.color.g, data.color.b)
            end
            
            -- Send to all players in this server
            AnnouncementService.ServerBanner(data.message, color)
            
            log:info("Global announcement received: %s", data.message)
        end)
        
        log:info("Subscribed to global announcements")
    end)
    
    if not ok then
        log:warn("Failed to subscribe to global announcements: %s", tostring(err))
    end
end

-- Send banner to all players in this server
function AnnouncementService.ServerBanner(message: string, color: Color3?)
    -- Check if announcements are enabled
    if not GameConfig.Features.ANNOUNCEMENTS_ENABLED then
        return
    end
    
    color = color or Color3.new(1, 0.84, 0) -- Default gold
    
    -- Emit announcement event for all players
    Bus:emit(EventNames.ANNOUNCEMENT_BROADCAST, {
        to = { kind = "all" },
        payload = {
            message = message,
            type = "banner",
            duration = nil,
            color = color,
        }
    })
    
    log:debug("Server banner sent: %s", message)
end

-- Send banner to all servers (use sparingly!)
function AnnouncementService.GlobalBanner(message: string, color: Color3?)
    -- Check if global announcements are enabled
    if not GameConfig.Features.ANNOUNCEMENTS_ENABLED or not GameConfig.Features.MYTHIC_GLOBAL_ANNOUNCE then
        AnnouncementService.ServerBanner(message, color) -- Fall back to server-only
        return
    end
    
    color = color or Color3.new(1, 0.84, 0) -- Default gold
    
    -- Rate limit to prevent MessagingService abuse
    local now = Time.mono()
    if now - lastGlobalAnnounce < MIN_GLOBAL_INTERVAL then
        log:debug("Global announcement rate limited, falling back to server-only")
        AnnouncementService.ServerBanner(message, color)
        return
    end
    lastGlobalAnnounce = now
    
    -- Serialize color for MessagingService
    local colorData = {
        r = color.R,
        g = color.G,
        b = color.B,
    }
    
    local ok, err = ErrorService.safecall("MessagingService:PublishAsync", function()
        MessagingService:PublishAsync(GLOBAL_CHANNEL, {
            message = message,
            color = colorData,
        })
    end)
    
    if ok then
        log:info("Global announcement published: %s", message)
    else
        log:warn("Failed to publish global announcement: %s", tostring(err))
        -- Fall back to server-only
        AnnouncementService.ServerBanner(message, color)
    end
end

-- Announce rare finds to server
function AnnouncementService.AnnounceRareDrop(playerName: string, itemName: string, rarity: string)
    -- Check if any announcements are enabled
    if not GameConfig.Features.ANNOUNCEMENTS_ENABLED then
        return
    end
    
    -- Check if we should announce this rarity
    if rarity ~= "MYTHIC" and not GameConfig.Features.EPIC_SERVER_ANNOUNCE then
        return -- Skip non-mythic if epic announcements disabled
    end
    
    local message = string.format("%s just found %s %s", playerName, itemName, rarity)
    
    local color = Color3.new(1, 0.84, 0) -- Default gold
    if rarity == "MYTHIC" then
        color = Color3.fromRGB(255, 50, 50)
    elseif rarity == "LEGENDARY" then
        color = Color3.fromRGB(255, 200, 0)
    elseif rarity == "EPIC" then
        color = Color3.fromRGB(150, 50, 200)
    end
    
    -- Mythic items get global announcement (if enabled), others are server-only
    if rarity == "MYTHIC" and GameConfig.Features.MYTHIC_GLOBAL_ANNOUNCE then
        AnnouncementService.GlobalBanner(message, color)
    else
        AnnouncementService.ServerBanner(message, color)
    end
end

-- Alias for compatibility (ItemService expects AnnounceRareFind)
AnnouncementService.AnnounceRareFind = AnnouncementService.AnnounceRareDrop

-- Initialize service
subscribeToGlobalAnnouncements()

log:info("AnnouncementService initialized")

return AnnouncementService
