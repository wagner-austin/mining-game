--!strict
-- CashShopCosmeticsTab.lua — Grid of cosmetics rendered via shared ItemTileRenderer

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UIFolder = MiningGame:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))
local UIx = require(UIFolder:WaitForChild("UIConstants"))
local BaseTabComponent = require(script.Parent:WaitForChild("BaseTabComponent"))
local ItemTileRenderer = require(script.Parent:WaitForChild("ItemTileRenderer"))
local ClientRF = require(MiningGame:WaitForChild("ClientRF"))
local Remotes = require(MiningGame:WaitForChild("Remotes"))
local UIUtils = require(UIFolder:WaitForChild("UIUtils"))
local ClientCashShop = require(MiningGame:WaitForChild("ClientCashShop"))
local ItemDetailsPopup = require(script.Parent:WaitForChild("ItemDetailsPopup"))
local Time = require(MiningGame:WaitForChild("Time"))
local ClientEconomy = require(MiningGame:WaitForChild("ClientEconomy"))

type Props = { parent: Instance }

local CashShopCosmeticsTab = {}
CashShopCosmeticsTab.__index = CashShopCosmeticsTab
setmetatable(CashShopCosmeticsTab, { __index = BaseTabComponent })

local function hasRF(name: string): boolean
    return Remotes.RF[name] ~= nil
end

function CashShopCosmeticsTab.new(props: Props)
    local self: any = setmetatable(BaseTabComponent.new({ parent = props.parent, stacked = true, name = "CashShopCosmeticsTab" }), CashShopCosmeticsTab)

    -- Card container
    local card = self:createSectionCard(self.container, { name = "CosmeticsCard", size = UDim2.new(1, 0, 1, -UIx.Size.ROW_LARGE), autoSize = false })
    self:createSectionTitle(card, "Cosmetics")
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
    -- Increase cell height to accommodate a price row below the tile
    grid.CellSize = UDim2.new(0, UIx.Size.INVENTORY_CELL_WIDTH, 0, UIx.Size.INVENTORY_CELL_HEIGHT + UIx.Size.ROW_STANDARD + UIx.Spacing.SM + 2)
    grid.CellPadding = UDim2.new(0, UIx.Spacing.SM, 0, UIx.Spacing.SM)
    grid.FillDirection = Enum.FillDirection.Horizontal
    grid.SortOrder = Enum.SortOrder.LayoutOrder
    grid.Parent = gridScroll
    self._grid = gridScroll
    self._confirm = {}

    return self
end

function CashShopCosmeticsTab:refresh()
    local gridScroll: ScrollingFrame = self._grid
    if not gridScroll then return end
    for _, ch in ipairs(gridScroll:GetChildren()) do
        if ch:IsA("GuiObject") then ch:Destroy() end
    end

    local items = ClientCashShop.getCosmeticCatalog()
    local canBuy = hasRF("PurchaseItem")
    local coins = ClientEconomy.getCoins()

    if #items == 0 then
        local empty = Instance.new("TextLabel")
        empty.Size = UDim2.new(1, -UIx.Spacing.SM, 0, UIx.Size.ROW_SECTION)
        empty.Position = UDim2.new(0, UIx.Spacing.TINY, 0, UIx.Spacing.TINY)
        empty.BackgroundTransparency = 1
        empty.Text = "No cosmetics available"
        empty.TextScaled = true
        empty.Font = Theme.fonts.Secondary
        empty.TextColor3 = Theme.colors.Text
        empty.Parent = gridScroll
        return
    end

    for _, it in ipairs(items) do
        local price = ClientCashShop.getCoinPrice(it and (it.price or it) or 0)
        local affordable = coins >= price

        -- Container for tile + price row (fits the grid cell)
        local cell = Instance.new("Frame")
        cell.Name = "ShopCell"
        cell.BackgroundTransparency = 1
        cell.Size = UDim2.new(1, 0, 1, 0)
        cell.Parent = gridScroll

        local vlayout = Instance.new("UIListLayout")
        vlayout.FillDirection = Enum.FillDirection.Vertical
        vlayout.Padding = UDim.new(0, UIx.Spacing.TINY)
        vlayout.SortOrder = Enum.SortOrder.LayoutOrder
        vlayout.Parent = cell

        -- Tile area (fixed to INVENTORY_CELL_HEIGHT)
        local tileHost = Instance.new("Frame")
        tileHost.Name = "TileHost"
        tileHost.BackgroundTransparency = 1
        tileHost.Size = UDim2.new(1, 0, 0, UIx.Size.INVENTORY_CELL_HEIGHT)
        tileHost.LayoutOrder = 1
        tileHost.Parent = cell

        -- Render tile inside host
        local tile = ItemTileRenderer.create({
            item = it,
            parent = tileHost,
            sizeMode = "fixed",
            fixedSize = UDim2.new(1, 0, 0, UIx.Size.INVENTORY_CELL_HEIGHT),
            rarityEffects = true,
        })
        local btn = tile.button
        tile.helpers.addSymbol(it)
        tile.helpers.addNameLabel(it.name or it.id, { useRarityColor = true, item = it, align = "center" })
        -- Ownership badge (top-left) using server-provided ownedCount when available
        local ownedCount = tonumber((it :: any).ownedCount) or tonumber((it :: any).meta and (it :: any).meta.ownedCount) or 0
        tile.helpers.addOwnershipBadgeLeft(it, ownedCount)
        -- Clicking the tile opens Item Details (no purchase on tile click)
        btn.Activated:Connect(function()
            local parent = (_G and _G.UIManager and _G.UIManager.overlayGui) or self.container
            ItemDetailsPopup.new({ parent = parent, itemId = it.itemId or it.id })
        end)

        -- Price row below tile
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
        priceBtn.BackgroundTransparency = affordable and 0.1 or 0.3
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
        icon.Text = (Theme.icons and Theme.icons.currency and Theme.icons.currency.coins) or "$"
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

        -- One-click purchase on the price button (no confirm, no hover popups)
        priceBtn.Active = canBuy and affordable
        priceBtn.AutoButtonColor = canBuy and affordable
        priceBtn.Activated:Connect(function()
            if not (canBuy and affordable) then return end
            local id = it.itemId or it.id
            local r, e = ClientRF.call("PurchaseItem", id)
            if e or (r and (r.ok == false or r.success == false)) then
                if _G.UIManager then _G.UIManager:showNotification(e or (r and r.err) or "Purchase failed", "error") end
            end
            self:refresh()
        end)
    end
end

return CashShopCosmeticsTab
