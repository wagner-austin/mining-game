--!strict
-- ItemService.server.lua
-- Manages physical item drops in the world with optimized performance and security

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

-- Shared modules
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Time = require(Shared:WaitForChild("Time"))
local Logger = require(Shared:WaitForChild("Logger"))
local log = Logger.new("ItemService")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Types = require(Shared:WaitForChild("Types"))
local MathUtils = require(Shared:WaitForChild("MathUtils"))
local ServiceValidator = require(Shared:WaitForChild("ServiceValidator"))
local ErrorService = require(script.Parent:WaitForChild("ErrorService"))

-- Non-service modules (not part of DI)
local SoundBroadcast = require(script.Parent.SoundBroadcast)
local ItemAnimations = require(script.Parent.ItemAnimations)

-- Services (injected via Init)
local InventoryService
local LootService
local DataService
local UpgradeService
local AchievementService
local AnnouncementService

-- Use EventBus for events
local EventBus = require(Shared:WaitForChild("EventBus"))
local EventNames = require(Shared:WaitForChild("EventNames"))
local Bus = EventBus.global()

-- Forward declare functions used in Start
local setupRemotes: () -> ()
local startUpdateLoop: () -> ()

local ItemService = {}
ItemService.__index = ItemService

-- Types
type DropData = {
    owner: Player,
    itemId: string,
    count: number,
    rarity: string,
    value: number?,
    spawnTime: number,
    claimed: boolean,
}

type ItemServiceT = {
    Init: (self: ItemServiceT, container: any) -> (),
    Start: (self: ItemServiceT, container: any) -> (),
    SpawnLootFromDig: (self: ItemServiceT, countsById: {[string]: number}, position: Vector3, owner: Player?) -> {Model},
    GetNearbyDrops: (self: ItemServiceT, position: Vector3, range: number) -> {Model},
    RemoveDrop: (self: ItemServiceT, dropModel: Model) -> (),
}

-- Active drops tracking (moved before Start method that uses it)
local activeDrops: {[Model]: DropData} = {}

-- Player tracking tables (moved before Start method to avoid forward reference)
local playerDropCounts: {[Player]: number} = {}
local playerPickupCooldowns: {[Player]: number} = {}
local lastPromptedDrop: {[Player]: Model} = {}

-- Initialize with DI container
function ItemService:Init(container)
    InventoryService = ServiceValidator.get(container, "InventoryService", {"AddItem", "AddItemsBulk"})
    LootService = ServiceValidator.get(container, "LootService", {"GetItemDefinition", "CalculateSellValue", "GetRarityColor"})
    DataService = ServiceValidator.get(container, "DataService", {"GetPlayerData", "QueueSave"})
    UpgradeService = ServiceValidator.get(container, "UpgradeService", {"ComputeEffectiveStats"})
    AchievementService = ServiceValidator.get(container, "AchievementService", {"RecordRarityFind"})
    AnnouncementService = ServiceValidator.get(container, "AnnouncementService", {"AnnounceRareFind"})
    log:info("Initialized with dependencies")
end

-- Start method to connect events after all services are initialized
function ItemService:Start(container)
    -- Handle player leaving
    Players.PlayerRemoving:Connect(function(player)
        -- Collect drops to remove (safe iteration)
        local toRemove = {}
        for dropModel, dropData in pairs(activeDrops) do
            if dropData.owner == player then
                table.insert(toRemove, dropModel)
            end
        end
        
        -- Remove drops after iteration
        for _, dropModel in ipairs(toRemove) do
            ItemService:RemoveDrop(dropModel)
        end
        
        playerDropCounts[player] = nil
        playerPickupCooldowns[player] = nil
        lastPromptedDrop[player] = nil
    end)
    
    -- Initialize
    setupRemotes()
    startUpdateLoop()
    
    log:info("Started with player connections and update loop")
end

-- Constants
local ITEM_DROP_HEIGHT = 2 -- Studs above spawn position (deprecated - calculated)
local ITEM_PICKUP_RANGE = GameConfig.Loot.PICKUP_RANGE -- Studs (increased for better feel)
local ITEM_MAGNET_RANGE = GameConfig.Loot.AUTO_COLLECT_RANGE -- Studs for auto-collection (gamepass default)
local ITEM_LIFETIME = GameConfig.Loot.ITEM_LIFETIME or 300 -- From config
local DESPAWN_RETRY_DELAY = GameConfig.Loot.DESPAWN_RETRY_DELAY or 10
local OWNER_GRACE_SECONDS = GameConfig.Loot.OWNER_GRACE_SECONDS or 5
local FINAL_DESPAWN_AFTER = 120 -- Seconds after becoming public to hard-despawn
local MAX_DROPS_PER_PLAYER = GameConfig.Loot.MAX_DROPS_PER_PLAYER -- Performance limit (reduced for stacked drops)
local MAX_DROPS_PER_DIG = GameConfig.Loot.MAX_DROPS_PER_DIG -- Maximum physical drops per dig action
local ITEM_HOVER_HEIGHT = 2
local ITEM_ROTATION_SPEED = GameConfig.Loot.ROTATION_SPEED

-- Timing for update loops
local AUTO_COLLECT_INTERVAL = 0.2 -- seconds (reduced from 0.5 for snappier walk-over pickup)
local PICKUP_PROMPT_INTERVAL = 0.1 -- seconds (unused - prompts disabled)
local USE_PICKUP_PROMPTS = false -- Disabled - all players use walk-over pickup

-- Other tracking tables (already declared at top of file)
local hoverTweens: {[Model]: Tween} = setmetatable({}, { __mode = "k" }) -- Weak table for tween storage

-- Create a folder for item drops
local function getDropsFolder(): Folder
    local folder = workspace:FindFirstChild("ItemDrops")
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = "ItemDrops"
        folder.Parent = workspace
    end
    return folder
end

-- Update drop count label
local function updateDropCountLabel(model: Model, newCount: number)
    if not model or not model.PrimaryPart then return end
    model:SetAttribute("Count", newCount)
    
    local part = model.PrimaryPart
    local bb = part:FindFirstChildOfClass("BillboardGui")
    if not bb then return end
    
    local nameLabel = bb:FindFirstChild("NameLabel") :: TextLabel?
    if not nameLabel then return end
    
    local itemId = model:GetAttribute("ItemId")
    if not itemId then return end
    
    local def = LootService:GetItemDefinition(itemId)
    if not def then return end
    
    nameLabel.Text = newCount > 1 and (def.name .. " x" .. tostring(newCount)) or def.name
end

-- Create item drop model (optimized with anchored parts)
local function createItemModel(itemDef: Types.LootDrop, position: Vector3, count: number): Model
    local model = Instance.new("Model")
    model.Name = "ItemDrop_" .. itemDef.id
    
    -- Main part (visual representation)
    local part = Instance.new("Part")
    part.Name = "ItemPart"
    part.Size = Vector3.new(1.5, 1.5, 1.5)
    -- Place at top of the dug cell with small margin
    local cellHalf = (GameConfig.Grid.CELL_SIZE_STUDS / 2)
    local margin = 0.25
    part.Position = position + Vector3.new(0, cellHalf - margin, 0)
    part.Material = Enum.Material.Neon
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    part.CanCollide = false
    part.Anchored = true -- No physics simulation needed
    
    -- Color based on rarity
    local rarityColor = LootService:GetRarityColor(itemDef.rarity)
    part.Color = rarityColor
    
    -- Add glow effect
    local pointLight = Instance.new("PointLight")
    pointLight.Brightness = 2
    pointLight.Range = 10
    pointLight.Color = rarityColor
    pointLight.Parent = part
    
    -- Add selection box for outline
    local selectionBox = Instance.new("SelectionBox")
    selectionBox.Adornee = part
    selectionBox.Color3 = rarityColor
    selectionBox.LineThickness = 0.1
    selectionBox.Transparency = 0.3
    selectionBox.Parent = part
    
    -- Add billboard GUI for item name
    local billboardGui = Instance.new("BillboardGui")
    billboardGui.Size = UDim2.new(4, 0, 1, 0)
    billboardGui.StudsOffset = Vector3.new(0, 2, 0)
    billboardGui.AlwaysOnTop = true
    billboardGui.Parent = part
    
    local textLabel = Instance.new("TextLabel")
    textLabel.Name = "NameLabel"  -- Named for unambiguous lookup
    textLabel.Size = UDim2.new(1, 0, 1, 0)
    textLabel.BackgroundTransparency = 1
    textLabel.Text = count > 1 and (itemDef.name .. " x" .. tostring(count)) or itemDef.name
    textLabel.TextColor3 = Color3.new(1, 1, 1)
    textLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    textLabel.TextStrokeTransparency = 0
    textLabel.TextScaled = true
    textLabel.Font = Enum.Font.SourceSansBold
    textLabel.Parent = billboardGui
    
    -- Add rarity indicator
    local rarityLabel = Instance.new("TextLabel")
    rarityLabel.Name = "RarityLabel"  -- Named for unambiguous lookup
    rarityLabel.Size = UDim2.new(1, 0, 0.3, 0)
    rarityLabel.Position = UDim2.new(0, 0, 1, 0)
    rarityLabel.BackgroundTransparency = 1
    rarityLabel.Text = "[" .. itemDef.rarity .. "]"
    rarityLabel.TextColor3 = rarityColor
    rarityLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    rarityLabel.TextStrokeTransparency = 0
    rarityLabel.TextScaled = true
    rarityLabel.Font = Enum.Font.SourceSans
    rarityLabel.Parent = billboardGui
    
    -- Ambient floating particles for all items (rarity-tinted, very lightweight)
    do
        local ambient = Instance.new("ParticleEmitter")
        ambient.Name = "AmbientParticles"
        ambient.Texture = "rbxasset://textures/particles/sparkles_main.dds" -- light sparkles
        ambient.Color = ColorSequence.new(rarityColor)
        ambient.LightEmission = 0.4
        ambient.Lifetime = NumberRange.new(0.6, 1.2)
        ambient.Speed = NumberRange.new(0.2, 0.8)
        ambient.EmissionDirection = Enum.NormalId.Top
        ambient.SpreadAngle = Vector2.new(12, 12)
        ambient.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0,   0.14),
            NumberSequenceKeypoint.new(0.6, 0.09),
            NumberSequenceKeypoint.new(1,   0.00),
        })
        ambient.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.15),
            NumberSequenceKeypoint.new(1, 1),
        })
        -- Gentle rarity scaling (kept low for budget)
        local rarityRate = {
            COMMON = 3, UNCOMMON = 4, RARE = 5, EPIC = 6, LEGENDARY = 7, MYTHIC = 8
        }
        ambient.Rate = rarityRate[itemDef.rarity] or 4
        ambient.Parent = part
    end
    
    -- Store count as attribute
    model:SetAttribute("Count", count)
    model:SetAttribute("ItemId", itemDef.id)
    
    part.Parent = model
    model.PrimaryPart = part
    
    -- Add special effects for rare items
    if itemDef.rarity == "EPIC" or itemDef.rarity == "LEGENDARY" or itemDef.rarity == "MYTHIC" then
        -- Add particle emitter for rare items
        local particleEmitter = Instance.new("ParticleEmitter")
        particleEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
        particleEmitter.Rate = 20
        particleEmitter.Lifetime = NumberRange.new(1, 2)
        particleEmitter.VelocityInheritance = 0
        particleEmitter.EmissionDirection = Enum.NormalId.Top
        particleEmitter.Speed = NumberRange.new(2, 4)
        particleEmitter.Color = ColorSequence.new(rarityColor)
        particleEmitter.LightEmission = 1
        particleEmitter.Parent = part
        
        -- Add beam effect for mythic items
        if itemDef.rarity == "MYTHIC" then
            local attachment1 = Instance.new("Attachment")
            attachment1.Position = Vector3.new(0, -0.75, 0)
            attachment1.Parent = part
            
            local attachment2 = Instance.new("Attachment")
            attachment2.Position = Vector3.new(0, 10, 0)
            attachment2.Parent = part
            
            local beam = Instance.new("Beam")
            beam.Attachment0 = attachment1
            beam.Attachment1 = attachment2
            beam.Color = ColorSequence.new(rarityColor)
            beam.LightEmission = 1
            beam.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.5),
                NumberSequenceKeypoint.new(0.5, 0),
                NumberSequenceKeypoint.new(1, 0.5)
            })
            beam.Width0 = 2
            beam.Width1 = 4
            beam.Parent = part
        end
    end
    
    -- Tag for easy identification
    CollectionService:AddTag(model, "ItemDrop")
    
    return model
end

-- Spawn stacked item drop
function ItemService:SpawnStackedDrop(itemId: string, count: number, position: Vector3, owner: Player?): Model?
    log:debug("SpawnStackedDrop called - itemId: %s, count: %d, position: (%.1f, %.1f, %.1f)", 
        itemId, count, position.X, position.Y, position.Z)
    
    -- Get item definition
    local itemDef = LootService:GetItemDefinition(itemId)
    if not itemDef then
        log:warn("Unknown item: {}", itemId)
        return nil
    end
    
    -- Check drop limit for owner
    if owner then
        local dropCount = playerDropCounts[owner] or 0
        log:debug("Player drop count: %d / %d", dropCount, MAX_DROPS_PER_PLAYER)
        if dropCount >= MAX_DROPS_PER_PLAYER then
            -- Remove oldest drop
            local oldestDrop, oldestTime = nil, math.huge
            for drop, data in pairs(activeDrops) do
                if data.owner == owner and not data.claimed and data.spawnTime < oldestTime then
                    oldestDrop = drop
                    oldestTime = data.spawnTime
                end
            end
            if oldestDrop then
                log:debug("Removing oldest drop to make room for new drop")
                self:AutoCollectDrop(oldestDrop, owner)
            end
        end
    end
    
    -- Create item model
    local model = createItemModel(itemDef, position, count)
    model.Parent = getDropsFolder()
    
    -- Log actual spawn position
    if model.PrimaryPart then
        log:debug("Drop spawned at actual position: (%.1f, %.1f, %.1f)", 
            model.PrimaryPart.Position.X, model.PrimaryPart.Position.Y, model.PrimaryPart.Position.Z)
    end
    
    -- Start animation
    if model.PrimaryPart then
        local hoverTween = ItemAnimations.createHoverAnimation(model.PrimaryPart)
        hoverTweens[model] = hoverTween
    end
    
    -- Register drop
    activeDrops[model] = {
        owner = owner,
        itemId = itemId,
        count = count,
        rarity = itemDef.rarity,
        value = itemDef.value,
        spawnTime = Time.mono(),
        claimed = false,
    }
    
    -- Count active drops (can't use # on dictionary)
    local activeCount = 0
    for _ in pairs(activeDrops) do
        activeCount = activeCount + 1
    end
    log:debug("Drop registered in activeDrops. Total active drops: %d", activeCount)
    
    -- Log drop event
    if owner then
        log:event("item_dropped", {
            uid = owner.UserId,
            itemId = itemId,
            count = count,
            rarity = itemDef.rarity,
            position = tostring(position)
        })
    end
    
    if owner then
        playerDropCounts[owner] = (playerDropCounts[owner] or 0) + 1
    end
    
    -- Schedule despawn with retry mechanism
    task.delay(ITEM_LIFETIME, function()
        if model and model.Parent and activeDrops[model] then
            local data = activeDrops[model]
            if not data.claimed then
                if owner and owner.Parent then
                    -- Try to auto-collect to owner
                    local ok = self:AutoCollectDrop(model, owner)
                    if not ok then
                        -- Schedule one retry; if it still fails, make public
                        task.delay(DESPAWN_RETRY_DELAY, function()
                            if activeDrops[model] and not activeDrops[model].claimed then
                                -- Fix owner cap accounting before making public
                                if data.owner then
                                    playerDropCounts[data.owner] = MathUtils.saturatingSub((playerDropCounts[data.owner] or 0), 1)
                                end
                                -- Make public so anyone can pick it up
                                data.owner = nil
                                log:debug("Drop made public after failed collection: %s", data.itemId)
                                
                                -- Schedule final hard-despawn for orphaned drops
                                local thisModel = model
                                task.delay(FINAL_DESPAWN_AFTER, function()
                                    local d = activeDrops[thisModel]
                                    if d and not d.claimed and d.owner == nil then
                                        self:RemoveDrop(thisModel)
                                        log:debug("Hard-despawned orphaned drop: %s", d.itemId)
                                    end
                                end)
                            end
                        end)
                    end
                else
                    -- Owner gone: make public immediately
                    if data.owner then
                        playerDropCounts[data.owner] = MathUtils.saturatingSub((playerDropCounts[data.owner] or 0), 1)
                    end
                    data.owner = nil
                    log:debug("Drop made public - owner disconnected: %s", data.itemId)
                    
                    -- Schedule final hard-despawn for orphaned drops
                    local thisModel = model
                    task.delay(FINAL_DESPAWN_AFTER, function()
                        local d = activeDrops[thisModel]
                        if d and not d.claimed and d.owner == nil then
                            self:RemoveDrop(thisModel)
                            log:debug("Hard-despawned orphaned drop: %s", d.itemId)
                        end
                    end)
                end
            else
                -- Already claimed, just remove
                self:RemoveDrop(model)
            end
        end
    end)
    
    log:debug("Spawned stacked drop %s x%d at (%.1f, %.1f, %.1f)", 
        itemId, count, position.X, position.Y, position.Z)
    return model
end

-- Auto-collect drop (bypasses range check)
function ItemService:AutoCollectDrop(dropModel: Model, collector: Player): boolean
    local dropData = activeDrops[dropModel]
    if not dropData or dropData.claimed then
        return false
    end
    
    -- Mark as claimed
    dropData.claimed = true
    
    -- Add to inventory
    local actuallyAdded = InventoryService:AddItemsBulk(collector, {[dropData.itemId] = dropData.count})
    local addedCount = actuallyAdded[dropData.itemId] or 0
    
    if addedCount > 0 then
        -- Send collection feedback
        Bus:emit(EventNames.ITEM_COLLECTED, {
            to = { kind = "player", player = collector },
            payload = {
                itemId = dropData.itemId,
                count = addedCount,
                rarity = dropData.rarity,
            }
        })
        
        -- Play collection sound via SoundBroadcast
        if dropModel.PrimaryPart then
            SoundBroadcast.Collect(collector, dropModel.PrimaryPart.Position, dropData.rarity)
        end
        
        -- Track achievements for rare finds
        AchievementService.RecordRarityFind(collector, dropData.rarity)
        
        -- Announce rare finds (EPIC+ get server announcements, MYTHIC goes global)
        if dropData.rarity and (dropData.rarity == "EPIC" or dropData.rarity == "LEGENDARY" or dropData.rarity == "MYTHIC") then
            local itemDef = LootService:GetItemDefinition(dropData.itemId)
            local displayName
            if itemDef and itemDef.name then
                displayName = itemDef.name
            else
                -- Fallback: title-case the id so banners still appear (prevents silent failure)
                displayName = tostring(dropData.itemId):gsub("_", " "):gsub("(%a)([%w_']*)", function(f, r)
                    return f:upper() .. r:lower()
                end)
            end
            AnnouncementService.AnnounceRareDrop(collector.DisplayName, displayName, dropData.rarity)
        end
        
        -- Log collection event
        log:event("item_auto_collected", {
            uid = collector.UserId,
            itemId = dropData.itemId,
            count = addedCount,
            rarity = dropData.rarity
        })
        
        -- Check if there's a remainder
        local remaining = dropData.count - addedCount
        if remaining > 0 then
            -- Keep the drop with reduced count
            dropData.claimed = false
            dropData.count = remaining
            updateDropCountLabel(dropModel, remaining)
            return true
        else
            -- Fully collected - animate then remove
            if dropModel.PrimaryPart then
                ItemAnimations.stopAnimations(dropModel, hoverTweens[dropModel])
                hoverTweens[dropModel] = nil
                
                ItemAnimations.flyDropToPlayer(dropModel, collector, function()
                    self:RemoveDrop(dropModel)
                end)
            else
                self:RemoveDrop(dropModel)
            end
            return true
        end
    else
        -- Failed (stack limit/full)
        -- Check if this is a single-stack item that should become public
        local def = LootService:GetItemDefinition(dropData.itemId)
        if GameConfig.Loot.ALLOW_PUBLIC_ON_STACK_CAP 
           and def and (def.type == "pickaxe" or def.type == "cosmetic") then
            -- Make public so others can pick it up
            if dropData.owner then
                playerDropCounts[dropData.owner] = MathUtils.saturatingSub((playerDropCounts[dropData.owner] or 0), 1)
            end
            dropData.owner = nil
            log:debug("Stack-capped item made public: %s", dropData.itemId)
            
            -- Schedule final hard-despawn
            local thisModel = dropModel
            task.delay(FINAL_DESPAWN_AFTER, function()
                local d = activeDrops[thisModel]
                if d and not d.claimed and d.owner == nil then
                    ItemService:RemoveDrop(thisModel)
                    log:debug("Hard-despawned orphaned drop: %s", d.itemId)
                end
            end)
        end
        
        dropData.claimed = false
        return false
    end
end

-- Collect item drop with validation
function ItemService:CollectDrop(dropModel: Model, collector: Player): boolean
    local dropData = activeDrops[dropModel]
    log:debug("CollectDrop called - dropData exists:", dropData ~= nil)
    
    if not dropData or dropData.claimed then
        log:debug("Drop not found or already claimed")
        return false
    end
    
    -- Validate ownership
    if dropData.owner and dropData.owner ~= collector then
        log:debug("Drop owned by another player")
        return false
    end
    
    -- Validate range
    local character = collector.Character
    if not character or not character.PrimaryPart then
        log:debug("No character or PrimaryPart")
        return false
    end
    
    if not dropModel.PrimaryPart then
        log:debug("Drop has no PrimaryPart")
        return false
    end
    
    local distance = (character.PrimaryPart.Position - dropModel.PrimaryPart.Position).Magnitude
    log:debug("Pickup distance:", distance, "Max range:", ITEM_PICKUP_RANGE + 1)
    
    if distance > (ITEM_PICKUP_RANGE + 1) then -- +1 for network latency tolerance
        log:debug("Player too far from drop")
        return false
    end
    
    -- Check cooldown
    local now = Time.mono()
    local lastPickup = playerPickupCooldowns[collector] or 0
    if now - lastPickup < 0.1 then -- 100ms cooldown
        return false
    end
    playerPickupCooldowns[collector] = now
    
    -- Mark as claimed to prevent double collection
    dropData.claimed = true
    
    -- Add to inventory
    local actuallyAdded = InventoryService:AddItemsBulk(collector, {[dropData.itemId] = dropData.count})
    local addedCount = actuallyAdded[dropData.itemId] or 0
    
    if addedCount > 0 then
        local remaining = dropData.count - addedCount
        
        -- Send collection feedback
        Bus:emit(EventNames.ITEM_COLLECTED, {
            to = { kind = "player", player = collector },
            payload = {
                itemId = dropData.itemId,
                count = addedCount,
                rarity = dropData.rarity,
            }
        })
        
        -- Track achievements for rare finds
        AchievementService.RecordRarityFind(collector, dropData.rarity)
        
        -- Announce rare finds (EPIC+ get server announcements, MYTHIC goes global)
        if dropData.rarity and (dropData.rarity == "EPIC" or dropData.rarity == "LEGENDARY" or dropData.rarity == "MYTHIC") then
            local itemDef = LootService:GetItemDefinition(dropData.itemId)
            local displayName
            if itemDef and itemDef.name then
                displayName = itemDef.name
            else
                -- Fallback: title-case the id so banners still appear (prevents silent failure)
                displayName = tostring(dropData.itemId):gsub("_", " "):gsub("(%a)([%w_']*)", function(f, r)
                    return f:upper() .. r:lower()
                end)
            end
            AnnouncementService.AnnounceRareDrop(collector.DisplayName, displayName, dropData.rarity)
        end
        
        -- Log collection event
        log:event("item_collected", {
            uid = collector.UserId,
            itemId = dropData.itemId,
            count = addedCount,
            rarity = dropData.rarity
        })
        
        -- Play collection sound via SoundBroadcast
        if dropModel.PrimaryPart then
            SoundBroadcast.Collect(collector, dropModel.PrimaryPart.Position, dropData.rarity)
        end
        
        if remaining > 0 then
            -- Partial pickup - keep the drop with reduced count
            dropData.count = remaining
            dropData.claimed = false
            updateDropCountLabel(dropModel, remaining)
            
            -- Pulse animation for partial pickup
            if dropModel.PrimaryPart then
                ItemAnimations.pulsePartialPickup(dropModel.PrimaryPart)
            end
            
            log:debug("Partial pickup %s: collected %d, remaining %d (by %s)", 
                dropData.itemId, addedCount, remaining, collector.Name)
            return true
        else
            -- Full pickup - fly to player animation then remove
            if dropModel.PrimaryPart then
                ItemAnimations.stopAnimations(dropModel, hoverTweens[dropModel])
                hoverTweens[dropModel] = nil
                
                ItemAnimations.flyDropToPlayer(dropModel, collector, function()
                    self:RemoveDrop(dropModel)
                end)
            else
                self:RemoveDrop(dropModel)
            end
            
            log:debug("Item fully collected: %s x%d by %s", 
                dropData.itemId, addedCount, collector.Name)
            return true
        end
    else
        -- Inventory full or at stack limit
        dropData.claimed = false -- Allow retry
        
        Bus:emit(EventNames.ANNOUNCEMENT_BROADCAST, {
            to = { kind = "player", player = collector },
            payload = {
                message = "Inventory full!",
                type = "error",
                duration = 2.5,
            }
        })
        
        return false
    end
end

-- Remove item drop
function ItemService:RemoveDrop(dropModel: Model)
    local dropData = activeDrops[dropModel]
    if dropData and dropData.owner then
        playerDropCounts[dropData.owner] = MathUtils.saturatingSub((playerDropCounts[dropData.owner] or 0), 1)
    end
    
    -- Stop hover tween if exists
    local hoverTween = hoverTweens[dropModel]
    if hoverTween then
        ErrorService.safecall("Tween:Cancel", function() hoverTween:Cancel() end)
    end
    hoverTweens[dropModel] = nil
    
    activeDrops[dropModel] = nil
    dropModel:Destroy()
end

-- Spawn loot drops from dig (aggregated)
function ItemService:SpawnLootFromDig(countsById: {[string]: number}, position: Vector3, owner: Player?): {Model}
    local drops = {}
    local dropCount = 0
    
    -- Log dig loot event
    if owner then
        local totalItems = 0
        for _, count in pairs(countsById) do
            totalItems = totalItems + count
        end
        log:event("dig_loot_spawned", {
            uid = owner.UserId,
            totalItems = totalItems,
            uniqueTypes = next(countsById) and #countsById or 0,
            position = tostring(position)
        })
    end
    
    -- Sort by rarity to prioritize rare drops if we hit the cap
    local sortedItems = {}
    for itemId, count in pairs(countsById) do
        local itemDef = LootService:GetItemDefinition(itemId)
        if itemDef then
            table.insert(sortedItems, {
                itemId = itemId,
                count = count,
                rarity = itemDef.rarity,
                rarityWeight = GameConfig.Loot.RARITIES[itemDef.rarity].weight
            })
        end
    end
    
    -- Sort by rarity weight (lower = rarer = higher priority)
    table.sort(sortedItems, function(a, b)
        return a.rarityWeight < b.rarityWeight
    end)
    
    -- Spawn drops up to the limit
    for _, item in ipairs(sortedItems) do
        if dropCount >= MAX_DROPS_PER_DIG then
            -- Auto-add remaining items directly to inventory
            if owner then
                InventoryService:AddItem(owner, item.itemId, item.count)
            end
        else
            -- No lateral jitter to avoid embedding in terrain
            local offset = Vector3.new(0, 0, 0)
            
            local dropModel = self:SpawnStackedDrop(item.itemId, item.count, position + offset, owner)
            if dropModel then
                table.insert(drops, dropModel)
                dropCount = dropCount + 1
            end
            
            -- Stagger spawning for visual effect
            if dropCount < #sortedItems and dropCount < MAX_DROPS_PER_DIG then
                task.wait(0.05)
            end
        end
    end
    
    return drops
end

-- Check for nearby drops
function ItemService:GetNearbyDrops(position: Vector3, range: number): {Model}
    local nearbyDrops = {}
    
    for dropModel, dropData in pairs(activeDrops) do
        if dropModel.PrimaryPart and not dropData.claimed then
            local distance = (dropModel.PrimaryPart.Position - position).Magnitude
            if distance <= range then
                table.insert(nearbyDrops, dropModel)
            end
        end
    end
    
    return nearbyDrops
end

-- Get auto-collect range from config
local function getAutoCollectRangeFromConfig()
    for _, pass in ipairs(GameConfig.Monetization.GAMEPASSES) do
        if pass.id == "AUTO_COLLECT" then
            return (pass.effects and pass.effects.auto_collect_range) or ITEM_MAGNET_RANGE
        end
    end
    return ITEM_MAGNET_RANGE
end

-- Check if player has auto-collect
local function hasAutoCollect(player: Player): (boolean, number?)
    local gamepasses = UpgradeService:GetPlayerGamepasses(player)
    
    -- Check for auto-collect gamepass
    if gamepasses["AUTO_COLLECT"] then
        return true, getAutoCollectRangeFromConfig()
    end
    
    -- Check for VIP (might include auto-collect)
    if gamepasses["VIP"] then
        return true, ITEM_MAGNET_RANGE
    end
    
    return false, nil
end

-- Auto-collection loop
local autoCollectAccumulator = 0
local function handleAutoCollection(dt: number)
    autoCollectAccumulator = autoCollectAccumulator + dt
    if autoCollectAccumulator < AUTO_COLLECT_INTERVAL then
        return
    end
    autoCollectAccumulator = 0

    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        if not (character and character.PrimaryPart) then continue end

        local playerPos = character.PrimaryPart.Position
        local hasAuto, magnetRange = hasAutoCollect(player)
        local range = hasAuto and (magnetRange or ITEM_MAGNET_RANGE) or ITEM_PICKUP_RANGE
        local nearby = ItemService:GetNearbyDrops(playerPos, range)

        -- Group eligible drops by itemId for this player
        local perItem: {[string]: {Model}} = {}
        for _, dropModel in ipairs(nearby) do
            local dropData = activeDrops[dropModel]
            if dropData and not dropData.claimed then
                local canPickup = (not dropData.owner)
                    or (dropData.owner == player)
                    or ((Time.mono() - dropData.spawnTime) > OWNER_GRACE_SECONDS)
                if canPickup then
                    local bucket = perItem[dropData.itemId]
                    if not bucket then
                        bucket = {}
                        perItem[dropData.itemId] = bucket
                    end
                    table.insert(bucket, dropModel)
                end
            end
        end

        if next(perItem) ~= nil then
            -- Build requested counts
            local countsById: {[string]: number} = {}
            for itemId, list in pairs(perItem) do
                countsById[itemId] = #list
            end

            -- Apply to inventory once
            local actuallyAdded = InventoryService:AddItemsBulk(player, countsById)

            -- For each item, remove exactly the number we actually added
            for itemId, added in pairs(actuallyAdded) do
                if added > 0 then
                    local bucket = perItem[itemId]
                    -- Emit collection feedback once per itemId with aggregated count
                    Bus:emit(EventNames.ITEM_COLLECTED, {
                        to = { kind = "player", player = player },
                        payload = {
                            itemId = itemId,
                            count = added,
                            rarity = (LootService:GetItemDefinition(itemId) or {}).rarity,
                        }
                    })

                    -- Announce and record achievements for rare finds
                    local def = LootService:GetItemDefinition(itemId)
                    if def and def.rarity and (def.rarity == "EPIC" or def.rarity == "LEGENDARY" or def.rarity == "MYTHIC") then
                        AchievementService.RecordRarityFind(player, def.rarity)
                        AnnouncementService.AnnounceRareDrop(player.DisplayName, def.name or itemId, def.rarity)
                    end

                    -- Remove 'added' number of drops
                    for i = 1, math.min(added, #bucket) do
                        local model = bucket[i]
                        local d = activeDrops[model]
                        if d and not d.claimed then
                            d.claimed = true
                            if model.PrimaryPart then
                                ItemAnimations.stopAnimations(model, hoverTweens[model])
                                hoverTweens[model] = nil
                                ItemAnimations.flyDropToPlayer(model, player, function()
                                    ItemService:RemoveDrop(model)
                                end)
                            else
                                ItemService:RemoveDrop(model)
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Manual pickup prompt loop (client should handle most of this)
local pickupPromptAccumulator = 0
local lastLogTime = 0
local function handleManualPickup(dt: number)
    pickupPromptAccumulator = pickupPromptAccumulator + dt
    if pickupPromptAccumulator < PICKUP_PROMPT_INTERVAL then
        return
    end
    pickupPromptAccumulator = 0
    
    -- Only send prompts for drops without auto-collect
    for _, player in ipairs(Players:GetPlayers()) do
        local hasAuto = hasAutoCollect(player)
        if not hasAuto then
            local character = player.Character
            if character and character.PrimaryPart then
                local playerPos = character.PrimaryPart.Position
                local drops = ItemService:GetNearbyDrops(playerPos, ITEM_PICKUP_RANGE)
                
                -- Log every 2 seconds for debugging
                local now = Time.mono()
                if now - lastLogTime > 2 then
                    lastLogTime = now
                    local dropCount = 0
                    for _ in pairs(activeDrops) do
                        dropCount = dropCount + 1
                    end
                    if dropCount > 0 then
                        log:debug("Player at (%.1f, %.1f, %.1f) - Active drops: %d, Nearby: %d", 
                            playerPos.X, playerPos.Y, playerPos.Z, dropCount, #drops)
                    end
                end
                
                -- Send nearest drop only to reduce spam
                local nearestDrop, nearestDist = nil, math.huge
                for _, dropModel in ipairs(drops) do
                    local dropData = activeDrops[dropModel]
                    if dropData and not dropData.claimed and (dropData.owner == player or not dropData.owner) then
                        if dropModel.PrimaryPart then
                            local dist = (dropModel.PrimaryPart.Position - playerPos).Magnitude
                            if dist < nearestDist then
                                nearestDrop = dropModel
                                nearestDist = dist
                            end
                        end
                    end
                end
                
                if nearestDrop then
                    if nearestDrop ~= lastPromptedDrop[player] then
                        local dropData = activeDrops[nearestDrop]
                        log:debug("Sending pickup prompt for %s at distance %.1f", dropData.itemId, nearestDist)
                        Bus:emit(EventNames.PICKUP_PROMPT, {
                            to = { kind = "player", player = player },
                            payload = {
                                dropModel = nearestDrop,
                                itemId = dropData.itemId,
                                count = dropData.count,
                                rarity = dropData.rarity,
                            }
                        })
                        lastPromptedDrop[player] = nearestDrop
                    end
                else
                    -- No drops in range - hide prompt if one was showing
                    if lastPromptedDrop[player] then
                        log:debug("Hiding pickup prompt - no drops in range")
                        Bus:emit(EventNames.PICKUP_PROMPT, {
                            to = { kind = "player", player = player },
                            payload = {
                                dropModel = nil,  -- Signal to hide prompt
                            }
                        })
                        lastPromptedDrop[player] = nil
                    end
                end
            end
        end
    end
end

-- Item rotation update
local function updateItemRotations(dt: number)
    for dropModel, dropData in pairs(activeDrops) do
        if dropModel.Parent and dropModel.PrimaryPart and not dropData.claimed then
            dropModel.PrimaryPart.CFrame = dropModel.PrimaryPart.CFrame * CFrame.Angles(0, ITEM_ROTATION_SPEED * dt, 0)
        end
    end
end

-- Main update loop
local updateConnection
startUpdateLoop = function()
    if updateConnection then
        updateConnection:Disconnect()
    end
    
    updateConnection = RunService.Heartbeat:Connect(function(dt)
        -- Update rotations every frame for smoothness
        updateItemRotations(dt)
        
        -- Timed updates for collection only (prompts disabled - walk-over pickup for all)
        handleAutoCollection(dt)
        -- handleManualPickup(dt)  -- DISABLED: All players use walk-over pickup now
    end)
end

-- [MIGRATED TO ItemServiceRemotes.lua]
-- All remote handlers now use centralized RemoteManager pattern
setupRemotes = function()
    -- Remote handlers have been migrated to ItemServiceRemotes.lua
end

-- Player events and initialization moved to Start method

log:info("Initialized")

return ItemService
