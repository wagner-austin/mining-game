--!strict
-- ShopGridHelpers.lua
-- Shared helpers to render a Shop section card with a grid of item cells
-- Unifies tile, name, ownership badge, and price button logic for Shop tabs.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MG = ReplicatedStorage:WaitForChild("MiningGame")
local UI = MG:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local UIx = require(UI:WaitForChild("UIConstants"))
local ThemeRefresher = require(UI:WaitForChild("ThemeRefresher"))

local ItemTileRenderer = require(script.Parent:WaitForChild("ItemTileRenderer"))
local UIUtils = require(UI:WaitForChild("UIUtils"))

export type CreateCardOpts = { name: string?, size: UDim2?, autoSize: boolean? }
export type ItemCellOpts = {
    parent: ScrollingFrame,
    item: any,
    -- Visuals
    rarityEffects: boolean?,
    nameAlign: ("left"|"center")?,
    useRarityColorForName: boolean?,
    ownedCount: number?, -- if nil, no ownership badge is rendered
    -- Tile click details
    onTileClick: (() -> ())?,
    -- Pricing
    price: number?,
    currencyIcon: string?, -- e.g., coins icon or "R$"
    canBuy: boolean?,
    onPurchase: (() -> ())?,
}

local ShopGridHelpers = {}

-- Preferred: build using BaseTabComponent instance to leverage shared card/title styling
function ShopGridHelpers.createGridCardWithBase(base: any, title: string, opts: CreateCardOpts?)
    local card = base:createSectionCard(base.container, {
        name = (opts and opts.name) or (title .. "Card"),
        size = (opts and opts.size) or UDim2.new(1, 0, 1, -UIx.Size.ROW_LARGE),
        autoSize = (opts and opts.autoSize) or false,
    })
    base:createSectionTitle(card, title)

    local gridScroll = Instance.new("ScrollingFrame")
    gridScroll.Name = "Grid"
    gridScroll.Size = UDim2.new(1, 0, 1, -UIx.Size.BUTTON_SMALL_HEIGHT)
    gridScroll.Position = UDim2.new(0, 0, 0, UIx.Size.ROW_LARGE)
    gridScroll.BackgroundTransparency = 1
    gridScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    gridScroll.ScrollingDirection = Enum.ScrollingDirection.Y
    gridScroll.CanvasSize = UIx.Common.ORIGIN
    gridScroll.Parent = card

    local grid = Instance.new("UIGridLayout")
    grid.CellSize = UDim2.new(0, UIx.Size.INVENTORY_CELL_WIDTH, 0, UIx.Size.INVENTORY_CELL_HEIGHT + UIx.Size.ROW_STANDARD + UIx.Spacing.SM + 2)
    grid.CellPadding = UDim2.new(0, UIx.Spacing.SM, 0, UIx.Spacing.SM)
    grid.FillDirection = Enum.FillDirection.Horizontal
    grid.SortOrder = Enum.SortOrder.LayoutOrder
    grid.Parent = gridScroll

    return gridScroll
end

-- Note: No parent-only fallback. Always use createGridCardWithBase for consistent styling.

function ShopGridHelpers.renderItemCell(opts: ItemCellOpts)
    local parent = opts.parent :: ScrollingFrame
    local item = opts.item
    local ownedCountOpt = opts.ownedCount
    local ownedCount = (ownedCountOpt ~= nil) and (tonumber(ownedCountOpt) or 0) or nil
    local price = tonumber(opts.price or 0) or 0
    local canBuy = (opts.canBuy == true)
    local onPurchase = opts.onPurchase
    local onTileClick = opts.onTileClick
    local currencyIcon = opts.currencyIcon or (Theme.icons and Theme.icons.currency and Theme.icons.currency.coins) or "$"

    -- Cell container (tile + price row)
    local cell = Instance.new("Frame")
    cell.Name = "ShopCell"
    cell.BackgroundTransparency = 1
    cell.Size = UDim2.new(1, 0, 1, 0)
    cell.Parent = parent

    local vlayout = Instance.new("UIListLayout")
    vlayout.FillDirection = Enum.FillDirection.Vertical
    vlayout.Padding = UDim.new(0, UIx.Spacing.TINY)
    vlayout.SortOrder = Enum.SortOrder.LayoutOrder
    vlayout.Parent = cell

    -- Tile (fixed height)
    local tileHost = Instance.new("Frame")
    tileHost.Name = "TileHost"
    tileHost.BackgroundTransparency = 1
    tileHost.Size = UDim2.new(1, 0, 0, UIx.Size.INVENTORY_CELL_HEIGHT)
    tileHost.LayoutOrder = 1
    tileHost.Parent = cell

    local tile = ItemTileRenderer.create({
        item = item,
        parent = tileHost,
        sizeMode = "fixed",
        fixedSize = UDim2.new(1, 0, 0, UIx.Size.INVENTORY_CELL_HEIGHT),
        rarityEffects = opts.rarityEffects == true,
    })

    -- Symbol + name
    tile.helpers.addSymbol(item)
    tile.helpers.addNameLabel(item.name or item.id, {
        useRarityColor = (opts.useRarityColorForName == true),
        item = item,
        align = opts.nameAlign or "center",
    })

    -- Ownership badge (top-left). Only render if ownedCount is provided by caller.
    if ownedCount ~= nil then
        tile.helpers.addOwnershipBadgeLeft(item, ownedCount)
    end

    -- Tile click opens details when provided
    if onTileClick then
        local btn = tile.button
        btn.Active = true
        btn.Activated:Connect(function()
            onTileClick()
        end)
    end

    -- Price row
    if price and price > 0 then
        local priceRow = Instance.new("Frame")
        priceRow.Name = "PriceRow"
        priceRow.BackgroundTransparency = 1
        priceRow.Size = UDim2.new(1, 0, 0, UIx.Size.ROW_STANDARD + 2)
        priceRow.LayoutOrder = 2
        priceRow.Parent = cell

        local priceBtn = Instance.new("TextButton")
        priceBtn.Name = "PriceButton"
        priceBtn.AutoButtonColor = true
        priceBtn.AnchorPoint = Vector2.new(0.5, 0)
        priceBtn.Position = UDim2.new(0.5, 0, 0, 0)
        priceBtn.Size = UDim2.new(0, math.min(84, UIx.Size.INVENTORY_CELL_WIDTH - UIx.Spacing.SM*2), 1, 0)
        priceBtn.BackgroundColor3 = Theme.colors.Background
        priceBtn.BackgroundTransparency = canBuy and 0.1 or 0.3
        priceBtn.Text = ""
        priceBtn.Parent = priceRow
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, UIx.Spacing.MD)
        corner.Parent = priceBtn

        local h = Instance.new("UIListLayout")
        h.FillDirection = Enum.FillDirection.Horizontal
        h.VerticalAlignment = Enum.VerticalAlignment.Center
        h.HorizontalAlignment = Enum.HorizontalAlignment.Center
        h.Padding = UDim.new(0, UIx.Spacing.TINY)
        h.Parent = priceBtn

        local icon = Instance.new("TextLabel")
        icon.BackgroundTransparency = 1
        icon.Text = currencyIcon
        icon.Font = Theme.fonts.Secondary
        icon.TextScaled = true
        icon.TextColor3 = Theme.colors.Text
        icon.Size = UDim2.new(0, UIx.Size.ROW_STANDARD - 2, 0, UIx.Size.ROW_STANDARD - 2)
        icon.Parent = priceBtn

        local lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency = 1
        lbl.Text = UIUtils.formatNumber(price)
        lbl.Font = Theme.fonts.Secondary
        lbl.TextScaled = true
        lbl.TextColor3 = Theme.colors.Text
        lbl.Size = UDim2.new(1, -UIx.Size.ROW_STANDARD, 1, 0)
        lbl.Parent = priceBtn

        ThemeRefresher.Bind(priceBtn, { BackgroundColor3 = "Background" })
        ThemeRefresher.Bind(icon, { TextColor3 = "Text" })
        ThemeRefresher.Bind(lbl, { TextColor3 = "Text" })

        priceBtn.Active = canBuy and onPurchase ~= nil
        priceBtn.AutoButtonColor = canBuy and onPurchase ~= nil
        if canBuy and onPurchase then
            priceBtn.Activated:Connect(function()
                onPurchase()
            end)
        end
    end

    return cell
end

return ShopGridHelpers
