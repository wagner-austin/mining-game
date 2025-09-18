--!strict
-- ItemIndexTab.lua Ã¢â‚¬â€ modular item compendium tab matching Inventory styling

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UIFolder = MiningGame:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))
local UIx = require(UIFolder:WaitForChild("UIConstants"))
local GameConfig = require(MiningGame:WaitForChild("GameConfig"))
local ItemDefinitions = require(MiningGame:WaitForChild("ItemDefinitions"))
local Time = require(MiningGame:WaitForChild("Time"))
local TextUtils = require(MiningGame:WaitForChild("TextUtils"))

local BaseTabComponent = require(script.Parent:WaitForChild("BaseTabComponent"))
local ItemDetailsPopup = require(script.Parent:WaitForChild("ItemDetailsPopup"))

type Props = {
    parent: GuiObject,
    portalParent: Instance?,
    dataProvider: any?,
}

type ItemIndexTabT = typeof(setmetatable({} :: any, {})) & {
    refresh: (self: any) -> (),
    setActive: (self: any, boolean) -> (),
    destroy: (self: any) -> (),
}

local ItemIndexTab = {}
ItemIndexTab.__index = ItemIndexTab
setmetatable(ItemIndexTab, { __index = BaseTabComponent })

local function collectAll(): { any }
    -- Use unified ItemDefinitions for all items
    local out = {}
    for _, it in ipairs(ItemDefinitions.all()) do
        table.insert(out, it)
    end
    return out
end

function ItemIndexTab.new(props: Props): ItemIndexTabT
    local self: any = setmetatable(BaseTabComponent.new({
        parent = props.parent,
        portalParent = props.portalParent,
        dataProvider = props.dataProvider,
        stacked = true,
        name = "ItemIndexTab",
    }), ItemIndexTab)

    self._provider = props.dataProvider
    self._active = false
    self._filters = { type = "All", rarity = "All", enhanced = false, search = "" }
    self._animationTasks = {} -- Track animation tasks for cleanup

    -- No top filter row: match Settings > Inventory visual setup

    -- Sections matching Inventory style exactly
    local function makeSection(title: string)
        local card = self:createSectionCard(self.container, {
            size = UDim2.new(1, 0, 0, UIx.Size.INVENTORY_MIN_HEIGHT + 50),
            autoSize = false
        })
        self:createSectionTitle(card, title)

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

    local cardC, gridC = makeSection("Cosmetics")
    local cardR, gridR = makeSection("Resources")
    local cardU, gridU = makeSection("Consumables")

    -- Store references for later title updates (found/total)
    self._cards = { cosmetics = cardC, resources = cardR, consumables = cardU }
    self._titles = {
        cosmetics = cardC:FindFirstChild("Title") :: TextLabel,
        resources = cardR:FindFirstChild("Title") :: TextLabel,
        consumables = cardU:FindFirstChild("Title") :: TextLabel,
        -- No Tools section
    }

    self._grids = { cosmetics = gridC, resources = gridR, consumables = gridU }

    -- Data connection
    if self._provider and self._provider.onChanged then
        self:addConnection(self._provider:onChanged():Connect(function()
            if self._active then self:refresh() end
        end))
    end

    return self
end

-- Create an item button styled like Inventory tiles (simplified parity)
function ItemIndexTab:_createItemButton(item: any, ownedCount: number): TextButton
    local Renderer = require(script.Parent:WaitForChild("ItemTileRenderer"))
    -- Only apply rarity effects to owned items to avoid fighting with missing-state dimming
    -- Always enable rarity effects so icons are richly colored even when unowned
    local tile = Renderer.create({ item = item, sizeMode = "grid", rarityEffects = true })
    local btn = tile.button
    local symbol = tile.helpers.addSymbol(item)
    local disp = tostring(item.name or item.id)
    if disp == item.id or string.find(disp, "_") or string.find(disp, "%-") then
        disp = TextUtils.prettifyItemName(item.id, item)
    end
    local name = tile.helpers.addNameLabel(disp, { useRarityColor = true, item = item })
    tile.helpers.addOwnershipBadge(item, ownedCount)
    tile.helpers.applyOwnershipVisuals(item, ownedCount, { symbol = symbol, name = name })
    -- Open details popup on click
    btn.Activated:Connect(function()
        local parent = self.portalParent or self.container or btn.Parent
        ItemDetailsPopup.new({ parent = parent, itemId = item.id })
    end)
    return btn
end

function ItemIndexTab:refresh()
    local inv = {}
    if self._provider and self._provider.getSnapshot then
        local snap = self._provider:getSnapshot()
        inv = (snap and snap.profile and snap.profile.inventory) or {}
    end
    local all = collectAll()

    -- Tally totals and found per section
    local total = { cosmetics = 0, resources = 0, consumables = 0 }
    local found = { cosmetics = 0, resources = 0, consumables = 0 }
    for _, it in ipairs(all) do
        local section = nil
        if it.type == "cosmetic" then section = "cosmetics"
        elseif it.type == "resource" then section = "resources"
        elseif it.type == "consumable" then section = "consumables"
        end
        if section then
            total[section] += 1
            local owned = tonumber(inv[it.id] or 0) or 0
            if owned > 0 then found[section] += 1 end
        end
    end

    local function passes(_it)
        -- No filters; show all items, grouped by section below
        return true
    end

    -- Clear grids
    for _, sc in pairs(self._grids) do
        for _, ch in ipairs(sc:GetChildren()) do
            if ch:IsA("GuiObject") then ch:Destroy() end
        end
    end

    -- Update section titles with found/total
    local function setTitle(key: string, label: TextLabel?)
        if not label then return end
        local base
        if key == "cosmetics" then base = "Cosmetics"
        elseif key == "resources" then base = "Resources"
        -- No Tools section
        else base = "Consumables" end
        label.Text = string.format("%s (%d/%d)", base, found[key] or 0, total[key] or 0)
    end
    setTitle("cosmetics", self._titles.cosmetics)
    setTitle("resources", self._titles.resources)
    setTitle("consumables", self._titles.consumables)
    -- No Tools section

    -- Render using item buttons similar to InventoryTab
    for _, it in ipairs(all) do
        if passes(it) then
            local owned = tonumber(inv[it.id] or 0) or 0
            local button = self:_createItemButton(it, owned)
            if button then
                -- Parent to grid by type
                local target = nil
                if it.type == "cosmetic" then target = self._grids.cosmetics
                elseif it.type == "resource" then target = self._grids.resources
                elseif it.type == "consumable" then target = self._grids.consumables
                end
                (target or self._grids.consumables).Parent = (target or self._grids.consumables).Parent -- no-op to avoid nil warnings
                button.Parent = target or self._grids.consumables
            end
        end
    end
end

function ItemIndexTab:setActive(active: boolean)
    self._active = active and true or false
    if self._active then self:refresh() end
end

return ItemIndexTab
