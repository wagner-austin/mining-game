--!strict
-- InventoryTab.lua — modular inventory display with equip/unequip functionality
-- Migrated to use BaseTabComponent for consistent UI patterns

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UIFolder = MiningGame:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))
local UIx = require(UIFolder:WaitForChild("UIConstants"))
local GameConfig = require(MiningGame:WaitForChild("GameConfig"))
local CosmeticDefinitions = require(MiningGame:WaitForChild("CosmeticDefinitions"))
local Logger = require(MiningGame:WaitForChild("Logger"))
local ClientRF = require(MiningGame:WaitForChild("ClientRF"))
local PlayerProfileGuard = require(MiningGame:WaitForChild("PlayerProfileGuard"))
local Time = require(MiningGame:WaitForChild("Time"))

local BaseTabComponent = require(script.Parent:WaitForChild("BaseTabComponent"))

local log = Logger.new("InventoryTab")

local InventoryTab = {}
InventoryTab.__index = InventoryTab
setmetatable(InventoryTab, { __index = BaseTabComponent })

type Props = {
    parent: GuiObject,
    position: UDim2?,
    size: UDim2?,
    dataProvider: any?,
}

type InventoryTabT = typeof(setmetatable({} :: any, InventoryTab)) & {
    _itemButtons: {[string]: TextButton},
    _inventory: {[string]: number},
    _equipped: {[string]: string},
    _dirty: boolean,
    _updateScheduled: boolean,
    _animationTasks: {thread},
    _active: boolean,
    _pendingRefresh: boolean,
    _snapshotDebounce: thread?,
    new: (props: Props) -> InventoryTabT,
}

function InventoryTab.new(props: Props): InventoryTabT
    -- Initialize base component with stacked=true for vertical sections
    local self = setmetatable(BaseTabComponent.new({
        parent = props.parent,
        position = props.position,
        size = props.size,
        dataProvider = props.dataProvider,
        stacked = true,
        name = "InventoryTab",
    }), InventoryTab)
    
    -- Tab-specific state
    self._itemButtons = {}
    self._inventory = {}
    self._equipped = {}
    self._dirty = false
    self._updateScheduled = false
    self._animationTasks = {} -- Track animation tasks for cleanup
    self._active = false -- Only rebuild UI when tab is active/visible
    self._pendingRefresh = false -- Remember to refresh once we become active
    self._snapshotDebounce = nil -- handle for debounced snapshot applies
    
    -- Create sections
    self:_createCosmeticsSection()
    self:_createResourcesSection()
    self:_createConsumablesSection()
    
    -- Inventory changes now handled via dataProvider (see connectDataProvider below)
    
    -- Hook data provider if available (base handles initial connection)
    if props.dataProvider then
        self:connectDataProvider(props.dataProvider, function(snapshot, key, value)
            -- Prefer incremental updates for inventory deltas
            if key == "inventoryDelta" and typeof(value) == "table" then
                -- Apply delta to local cache and schedule an update
                for itemId, inc in pairs(value) do
                    local curr = self._inventory[itemId] or 0
                    local nextVal = (curr + (inc :: number))
                    if nextVal > 0 then
                        self._inventory[itemId] = nextVal
                    else
                        self._inventory[itemId] = nil
                    end
                end
                -- Batch UI rebuilds
                self:_markDirtyAndSchedule()
                return
            end

            -- Fall back to snapshot application with a short debounce to avoid churn
            if self._snapshotDebounce then
                self:clearTimeout(self._snapshotDebounce)
                self._snapshotDebounce = nil
            end
            self._snapshotDebounce = self:setTimeout(0.15, function()
                self._snapshotDebounce = nil
                self:_applySnapshot(snapshot)
            end)
        end)
    else
        log:warn("No dataProvider, using direct remote")
        -- Request initial data if no provider
        self:_refreshInventory()
    end
    
    return self :: any
end

function InventoryTab:_sectionCard(title: string, minHeight: number?): (Frame, ScrollingFrame)
    local card = self:createSectionCard(self.container, {
        size = UDim2.new(1, 0, 0, minHeight or UIx.Size.INVENTORY_MIN_HEIGHT),
        autoSize = false
    })
    
    -- Title
    self:createSectionTitle(card, title)
    
    -- Scrolling grid
    local scroll = Instance.new("ScrollingFrame")
    scroll.Name = "Grid"
    scroll.Size = UDim2.new(1, 0, 1, -UIx.Size.BUTTON_SMALL_HEIGHT)
    scroll.BackgroundTransparency = 1
    scroll.ScrollBarThickness = UIx.Spacing.TINY
    scroll.ScrollBarImageColor3 = self._theme.colors.TextSecondary or self._theme.colors.Text
    scroll.CanvasSize = UIx.Common.ORIGIN
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.Parent = card
    
    self:bindToTheme(scroll, { ScrollBarImageColor3 = "TextSecondary" })
    
    local gridLayout = Instance.new("UIGridLayout")
    gridLayout.CellSize = UDim2.new(0, UIx.Size.INVENTORY_CELL_WIDTH, 0, UIx.Size.INVENTORY_CELL_HEIGHT)
    gridLayout.CellPadding = UDim2.new(0, UIx.Spacing.SM, 0, UIx.Spacing.SM)
    gridLayout.FillDirection = Enum.FillDirection.Horizontal
    gridLayout.SortOrder = Enum.SortOrder.Name
    gridLayout.Parent = scroll
    
    return card, scroll
end

function InventoryTab:_createCosmeticsSection()
    local card, grid = self:_sectionCard("Cosmetics", UIx.Size.INVENTORY_MIN_HEIGHT + 50)
    self.cosmeticsGrid = grid
end

function InventoryTab:_createResourcesSection()
    local card, grid = self:_sectionCard("Resources", UIx.Size.INVENTORY_MIN_HEIGHT + 50)
    self.resourcesGrid = grid
end

function InventoryTab:_createConsumablesSection()
    local card, grid = self:_sectionCard("Consumables", UIx.Size.INVENTORY_MIN_HEIGHT + 50)
    self.consumablesGrid = grid
end

function InventoryTab:_createItemButton(itemId: string, count: number): TextButton?
    -- Get item definition
    local itemDef = nil
    
    -- Check GameConfig items first
    for _, item in ipairs(GameConfig.Loot.ITEMS) do
        if item.id == itemId then
            itemDef = item
            break
        end
    end
    
    -- Check cosmetic definitions
    if not itemDef then
        itemDef = CosmeticDefinitions.Get(itemId)
    end
    
    if not itemDef then
        log:warn("Unknown item: %s", itemId)
        return nil
    end
    
    local button = Instance.new("TextButton")
    button.Name = itemId
    button.Size = UDim2.new(1, 0, 1, 0)
    button.BackgroundColor3 = self._theme.colors.Surface
    button.BackgroundTransparency = 0.1
    button.Text = ""
    button.AutoButtonColor = true
    
    -- Bind button to theme
    self:bindToTheme(button, { BackgroundColor3 = "Surface" })
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UIx.corner()
    corner.Parent = button
    
    -- Rarity border
    local rarityData = GameConfig.Loot.RARITIES[itemDef.rarity]
    if rarityData then
        local stroke = Instance.new("UIStroke")
        stroke.Color = rarityData.color
        stroke.Thickness = UIx.Visual.BORDER_WIDTH
        stroke.Parent = button
        
        -- Mythic/Legendary glow
        if itemDef.rarity == "MYTHIC" or itemDef.rarity == "LEGENDARY" then
            stroke.Transparency = 0
            local gradient = Instance.new("UIGradient")
            gradient.Rotation = 90
            gradient.Parent = stroke
        end
    end
    
    -- Item display (text-based with emoji/symbol)
    local itemDisplay = Instance.new("TextLabel")
    itemDisplay.Name = "ItemDisplay"
    itemDisplay.Size = UDim2.new(1, -UIx.Spacing.SM, 1, -UIx.Size.ROW_LARGE)
    itemDisplay.Position = UDim2.new(0, UIx.Spacing.TINY, 0, UIx.Spacing.TINY)
    itemDisplay.BackgroundTransparency = 1
    itemDisplay.Parent = button
    
    -- Choose emoji/symbol based on item type
    local symbol = "💎"  -- Default gem
    
    log:debug("Creating item card for: %s, type: %s", itemDef.id, tostring(itemDef.type))
    
    if itemDef.type == "resource" then
        if itemDef.id:find("stone") then symbol = "🪨"
        elseif itemDef.id:find("coal") then symbol = "⚫"
        elseif itemDef.id:find("copper") then symbol = "🟫"
        elseif itemDef.id:find("iron") then symbol = "⚪"
        elseif itemDef.id:find("silver") then symbol = "🔘"
        elseif itemDef.id:find("gold") then symbol = "🟡"
        elseif itemDef.id:find("crystal") then symbol = "💎"
        elseif itemDef.id:find("diamond") then symbol = "💎"
        elseif itemDef.id:find("ruby") then symbol = "🔴"
        elseif itemDef.id:find("emerald") then symbol = "🟢"
        elseif itemDef.id:find("obsidian") then symbol = "⬛"
        elseif itemDef.id:find("void") then symbol = "🌀"
        elseif itemDef.id:find("glass") then symbol = "🔷"
        elseif itemDef.id:find("ice") or itemDef.id:find("frozen") then symbol = "❄️"
        elseif itemDef.id:find("prismatic") or itemDef.id:find("rainbow") then symbol = "🌈"
        elseif itemDef.id:find("chromatic") then symbol = "🎨"
        elseif itemDef.id:find("cosmic") then symbol = "✨"
        elseif itemDef.id:find("dark") then symbol = "🌑"
        end
    elseif itemDef.type == "pickaxe" then
        symbol = "⛏️"
    elseif itemDef.type == "cosmetic" then
        -- Cosmetic items use 'slot' not 'type' for their category
        if itemDef.slot == "head" then 
            symbol = "⛑️"
        elseif itemDef.slot == "chest" or itemDef.slot == "armor" then 
            symbol = "🛡️"
        elseif itemDef.slot == "feet" or itemDef.slot == "boots" then 
            symbol = "👢"
        elseif itemDef.slot == "back" or itemDef.slot == "wings" then 
            symbol = "🦋"
        elseif itemDef.slot == "aura" then 
            symbol = "✨"
        elseif itemDef.slot == "trail" then 
            symbol = "💫"
        elseif itemDef.slot == "accessory" then 
            symbol = "💍"
        else
            symbol = "🎨"  -- Generic cosmetic
        end
    elseif itemDef.type == "consumable" then
        symbol = "🧪"
    end
    
    itemDisplay.Text = symbol
    itemDisplay.TextScaled = true
    itemDisplay.Font = self._theme.fonts.Primary
    itemDisplay.TextColor3 = rarityData and rarityData.color or self._theme.colors.Text
    
    -- Add visual effects based on rarity
    if itemDef.rarity == "MYTHIC" then
        -- Mythic: Rainbow shimmer effect
        local shimmer = Instance.new("UIGradient")
        shimmer.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
            ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 165, 0)),
            ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 255, 0)),
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 255, 0)),
            ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 100, 255)),
            ColorSequenceKeypoint.new(0.83, Color3.fromRGB(150, 0, 255)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 255))
        })
        shimmer.Rotation = 0
        shimmer.Parent = itemDisplay
        
        -- Animate the gradient rotation (will auto-cleanup when button is destroyed)
        local animTask = task.spawn(function()
            while itemDisplay.Parent do
                shimmer.Rotation = (shimmer.Rotation + 2) % 360
                task.wait(UIx.Anim.MICRO)
            end
        end)
        table.insert(self._animationTasks, animTask)
        
        -- Pulsing glow effect
        local pulseTask = task.spawn(function()
            while itemDisplay.Parent do
                TweenService:Create(itemDisplay, TweenInfo.new(UIx.Anim.VERY_SLOW, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
                    TextTransparency = 0.2
                }):Play()
                task.wait(UIx.Anim.VERY_SLOW)
                TweenService:Create(itemDisplay, TweenInfo.new(UIx.Anim.VERY_SLOW, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
                    TextTransparency = 0
                }):Play()
                task.wait(UIx.Anim.VERY_SLOW)
            end
        end)
        table.insert(self._animationTasks, pulseTask)
        
    elseif itemDef.rarity == "LEGENDARY" then
        -- Legendary: Golden pulse
        local pulseTask = task.spawn(function()
            while itemDisplay.Parent do
                TweenService:Create(itemDisplay, TweenInfo.new(UIx.Anim.EXTRA_SLOW, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
                    TextTransparency = 0.3
                }):Play()
                task.wait(UIx.Anim.EXTRA_SLOW)
                TweenService:Create(itemDisplay, TweenInfo.new(UIx.Anim.EXTRA_SLOW, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
                    TextTransparency = 0
                }):Play()
                task.wait(UIx.Anim.EXTRA_SLOW)
            end
        end)
        table.insert(self._animationTasks, pulseTask)
        
    elseif itemDef.rarity == "EPIC" then
        -- Epic: Subtle shimmer
        local shimmer = Instance.new("UIGradient")
        shimmer.Color = ColorSequence.new(rarityData.color, rarityData.color:Lerp(Color3.new(1,1,1), 0.3))
        shimmer.Rotation = 45
        shimmer.Parent = itemDisplay
        
        local shimmerTask = task.spawn(function()
            while itemDisplay.Parent do
                shimmer.Rotation = 45 + math.sin(Time.mono() * 2) * 15
                task.wait(UIx.Anim.TINY)
            end
        end)
        table.insert(self._animationTasks, shimmerTask)
    end
    
    -- Item name (format it nicely)
    local displayName = itemDef.name or itemId
    -- Remove underscores and format as title case
    displayName = displayName:gsub("_", " ")
    displayName = displayName:gsub("(%a)([%w_']*)", function(first, rest)
        return first:upper() .. rest:lower()
    end)
    
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1, -UIx.Spacing.SM, 0, UIx.Size.ROW_STANDARD)
    nameLabel.Position = UDim2.new(0, UIx.Spacing.TINY, 1, -(UIx.Size.ROW_MEDIUM))
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = displayName
    nameLabel.TextColor3 = rarityData and rarityData.color or self._theme.colors.Text
    nameLabel.Font = self._theme.fonts.Primary
    nameLabel.TextSize = UIx.Visual.TEXT_SMALL
    nameLabel.TextScaled = false
    nameLabel.TextWrapped = true
    -- Only bind to theme if not using rarity color
    if not rarityData then
        self:bindToTheme(nameLabel, { TextColor3 = "Text" })
    end
    nameLabel.Parent = button
    
    -- Count badge (if stackable)
    if count > 1 then
        local countBadge = Instance.new("TextLabel")
        countBadge.Size = UDim2.new(0, UIx.Size.BADGE_WIDTH, 0, UIx.Size.BADGE_HEIGHT)
        countBadge.Position = UDim2.new(1, -(UIx.Size.BADGE_WIDTH + UIx.Spacing.TINY), 0, UIx.Spacing.TINY)
        countBadge.BackgroundColor3 = self._theme.colors.Background
        countBadge.BackgroundTransparency = 0.1
        countBadge.Text = tostring(count)
        countBadge.TextColor3 = self._theme.colors.Text
        countBadge.Font = self._theme.fonts.Primary
        countBadge.TextSize = UIx.Visual.TEXT_SMALL
        self:bindToTheme(countBadge, { 
            BackgroundColor3 = "Background",
            TextColor3 = "Text" 
        })
        countBadge.Parent = button
        
        local countCorner = Instance.new("UICorner")
        countCorner.CornerRadius = UDim.new(0, UIx.Spacing.TINY)
        countCorner.Parent = countBadge
    end
    
    -- Equipped indicator
    if itemDef.type == "cosmetic" and itemDef.slot then
        if self._equipped[itemDef.slot] == itemId then
            local equipped = Instance.new("TextLabel")
            equipped.Name = "Equipped"
            equipped.Size = UDim2.new(1, 0, 0, UIx.Size.ROW_TINY)
            equipped.Position = UDim2.new(0, 0, 0.5, -(UIx.Size.ROW_TINY / 2))
            equipped.BackgroundColor3 = self._theme.colors.Success
            equipped.BackgroundTransparency = 0.8
            equipped.Text = "EQUIPPED"
            equipped.TextColor3 = self._theme.colors.Text
            equipped.Font = self._theme.fonts.Primary
            equipped.TextSize = UIx.Visual.TEXT_TINY
            equipped.Parent = button
            
            self:bindToTheme(equipped, { BackgroundColor3 = "Success" })
            
            local equippedCorner = Instance.new("UICorner")
            equippedCorner.CornerRadius = UDim.new(0, UIx.Spacing.TINY)
            equippedCorner.Parent = equipped
        end
    end
    
    -- Click handler
    self:addConnection(button.MouseButton1Click:Connect(function()
        if itemDef.type == "cosmetic" and itemDef.slot then
            self:_toggleEquip(itemId, itemDef.slot)
        elseif itemDef.type == "consumable" then
            self:_useConsumable(itemId)
        end
        -- Resources just display, can't be used directly
    end))
    
    -- Hover effect
    self:addConnection(button.MouseEnter:Connect(function()
        TweenService:Create(button, TweenInfo.new(UIx.Anim.FAST), {
            BackgroundTransparency = 0
        }):Play()
    end))
    
    self:addConnection(button.MouseLeave:Connect(function()
        TweenService:Create(button, TweenInfo.new(UIx.Anim.FAST), {
            BackgroundTransparency = 0.1
        }):Play()
    end))
    
    return button
end

function InventoryTab:_toggleEquip(itemId: string, slot: string)
    if self._equipped[slot] == itemId then
        -- Unequip
        task.spawn(function()
            local result, err = ClientRF.call("UnequipItem", slot)
            if not err and result and result.success then
                log:info("Unequipped %s", itemId)
                PlayerProfileGuard.clearCache() -- Bust cache for immediate UI update
            else
                log:warn("Failed to unequip: %s", err or (result and result.reason) or "unknown")
            end
        end)
    else
        -- Equip
        task.spawn(function()
            local result, err = ClientRF.call("EquipItem", itemId)
            if not err and result and result.success then
                log:info("Equipped %s", itemId)
                PlayerProfileGuard.clearCache() -- Bust cache for immediate UI update
            else
                log:warn("Failed to equip: %s", err or (result and result.reason) or "unknown")
            end
        end)
    end
end

function InventoryTab:_useConsumable(itemId: string)
    task.spawn(function()
        local result, err = ClientRF.call("UseConsumable", itemId)
        if not err and result and result.success then
            log:info("Used %s", itemId)
            PlayerProfileGuard.clearCache() -- Bust cache for immediate UI update
        else
            log:warn("Failed to use: %s", err or (result and result.reason) or "unknown")
        end
    end)
end

function InventoryTab:_updateDisplay()
    -- Defer rebuilds while tab is not visible to avoid background churn
    if not self._active then
        self._pendingRefresh = true
        return
    end
    -- Cancel existing animations before clearing buttons
    for _, thread in ipairs(self._animationTasks) do
        if thread then
            task.cancel(thread)
        end
    end
    self._animationTasks = {}
    
    -- Clear existing buttons
    for _, button in pairs(self._itemButtons) do
        button:Destroy()
    end
    self._itemButtons = {}
    
    -- Create buttons for each item
    for itemId, count in pairs(self._inventory) do
        local button = self:_createItemButton(itemId, count)
        if button then
            -- Get item definition to determine type
            local itemDef = nil
            for _, item in ipairs(GameConfig.Loot.ITEMS) do
                if item.id == itemId then
                    itemDef = item
                    break
                end
            end
            if not itemDef then
                itemDef = CosmeticDefinitions.Get(itemId)
            end
            
            if itemDef then
                -- Place in appropriate grid
                if itemDef.type == "cosmetic" then
                    button.Parent = self.cosmeticsGrid
                elseif itemDef.type == "resource" then
                    button.Parent = self.resourcesGrid
                elseif itemDef.type == "consumable" then
                    button.Parent = self.consumablesGrid
                end
                
                table.insert(self._itemButtons, button)
            end
        end
    end
end

function InventoryTab:_refreshInventory()
    task.spawn(function()
        local profile, err = PlayerProfileGuard.get()
        if profile then
            self._inventory = profile.inventory or {}
            self._equipped = profile.equipped or {}
            self:_updateDisplay()
        else
            log:warn("Failed to get profile:", err)
        end
    end)
end

function InventoryTab:_applySnapshot(snapshot: any)
    if snapshot and snapshot.profile then
        self._inventory = snapshot.profile.inventory or {}
        self._equipped = snapshot.profile.equipped or {}
        
        local inventoryCount = 0
        for _ in pairs(self._inventory) do
            inventoryCount = inventoryCount + 1
        end
        
        log:debug("Applying snapshot - %d items in inventory, %d equipped", 
            inventoryCount,
            next(self._equipped) and 1 or 0
        )
        
        self:_updateDisplay()
    else
        log:warn("Invalid snapshot structure: %s", tostring(snapshot))
    end
end

function InventoryTab:_onInventoryChanged(change)
    -- Update cache based on change
    if change.action == "add" or change.action == "remove" then
        if change.total and change.total > 0 then
            self._inventory[change.itemId] = change.total
        else
            self._inventory[change.itemId] = nil
        end
    elseif change.action == "equip" then
        if change.slot then
            self._equipped[change.slot] = change.itemId
        end
    elseif change.action == "unequip" then
        if change.slot then
            self._equipped[change.slot] = nil
        end
    end
    
    -- Batch updates to avoid excessive rebuilds
    self:_markDirtyAndSchedule()
end

-- Internal: mark UI as dirty and schedule a single rebuild (debounced by one tick)
function InventoryTab:_markDirtyAndSchedule()
    self._dirty = true
    if not self._updateScheduled then
        self._updateScheduled = true
        task.defer(function()
            if self._dirty then
                -- If inactive, remember to refresh when activated
                if self._active then
                    self:_updateDisplay()
                    self._dirty = false
                else
                    self._pendingRefresh = true
                end
            end
            self._updateScheduled = false
        end)
    end
end

-- Public: toggle active state to control background rebuilds
function InventoryTab:setActive(isActive: boolean)
    self._active = isActive and true or false
    if self._active and (self._pendingRefresh or self._dirty) then
        -- Ensure UI is up to date when becoming visible
        self:_updateDisplay()
        self._pendingRefresh = false
        self._dirty = false
    end
end

function InventoryTab:refresh()
    -- Restore visibility after BasePanel hide made everything transparent
    if self._dataProvider then
        local snap = self._dataProvider:getSnapshot()
        self:_applySnapshot(snap)
    end
end

-- Override destroy for tab-specific cleanup
function InventoryTab:destroy()
    -- Cancel all animation tasks
    for _, animTask in ipairs(self._animationTasks) do
        if animTask then
            task.cancel(animTask)
        end
    end
    
    -- Clear tab-specific state
    self._itemButtons = nil
    self._inventory = nil
    self._equipped = nil
    self._animationTasks = nil
    self._dirty = nil
    self._updateScheduled = nil
    self.cosmeticsGrid = nil
    self.resourcesGrid = nil
    self.consumablesGrid = nil
    
    -- Call base destroy (handles connections, container, periodic updates)
    BaseTabComponent.destroy(self)
end

return InventoryTab
