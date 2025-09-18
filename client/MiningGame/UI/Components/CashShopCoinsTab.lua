-- CashShopCoinsTab.lua — Products tab (Robux) styled like Cosmetics: tile + price button row

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

type Props = { parent: Instance }

local CashShopCoinsTab = {}
CashShopCoinsTab.__index = CashShopCoinsTab
setmetatable(CashShopCoinsTab, { __index = BaseTabComponent })

local function hasRF(name: string): boolean
    return Remotes.RF[name] ~= nil
end

function CashShopCoinsTab.new(props: Props)
    local self: any = setmetatable(BaseTabComponent.new({ parent = props.parent, stacked = true, name = "CashShopCoinsTab" }), CashShopCoinsTab)

    -- Card container (match Cosmetics sizing: full-height card with scrollable grid inside)
    local card = self:createSectionCard(self.container, { name = "ProductsCard", size = UDim2.new(1, 0, 1, -UIx.Size.ROW_LARGE), autoSize = false })
    self:createSectionTitle(card, "Products")

    local gridScroll = Instance.new("ScrollingFrame")
    gridScroll.Name = "Grid"
    gridScroll.Size = UDim2.new(1, 0, 1, -UIx.Size.BUTTON_SMALL_HEIGHT)
    gridScroll.Position = UDim2.new(0, 0, 0, UIx.Size.ROW_LARGE)
    gridScroll.BackgroundTransparency = 1
    gridScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    gridScroll.ScrollingDirection = Enum.ScrollingDirection.Y
    gridScroll.CanvasSize = UIx.Common.ORIGIN
    gridScroll.Parent = card

    local layout = Instance.new("UIGridLayout")
    -- Match Cosmetics: add extra height to fit price row below tile
    layout.CellSize = UDim2.new(0, UIx.Size.INVENTORY_CELL_WIDTH, 0, UIx.Size.INVENTORY_CELL_HEIGHT + UIx.Size.ROW_STANDARD + UIx.Spacing.SM + 2)
    layout.CellPadding = UDim2.new(0, UIx.Spacing.SM, 0, UIx.Spacing.SM)
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = gridScroll

    self._grid = gridScroll

    return self
end
function CashShopCoinsTab:refresh()
    local gridScroll: ScrollingFrame = self._grid
    if not gridScroll then return end
    for _, ch in ipairs(gridScroll:GetChildren()) do if ch:IsA("GuiObject") then ch:Destroy() end end

    if not hasRF("GetPrices") then
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -UIx.Spacing.SM, 0, UIx.Size.ROW_SECTION)
        lbl.Position = UDim2.new(0, UIx.Spacing.TINY, 0, UIx.Spacing.TINY)
        lbl.BackgroundTransparency = 1
        lbl.Text = "Coins shop unavailable"
        lbl.TextScaled = true
        lbl.Font = Theme.fonts.Secondary
        lbl.TextColor3 = Theme.colors.Text
        lbl.Parent = gridScroll
        return
    end

    local products = ClientCashShop.getRobuxProducts()
    if #products == 0 then
        local retry = Instance.new("TextButton")
        retry.Size = UDim2.new(1, -UIx.Spacing.SM, 0, UIx.Size.ROW_SECTION)
        retry.Position = UDim2.new(0, UIx.Spacing.TINY, 0, UIx.Spacing.TINY)
        retry.BackgroundColor3 = Theme.colors.Surface
        retry.BackgroundTransparency = Theme.button and Theme.button.surfaceTransparency or 0.1
        retry.Text = "Unable to load prices — RETRY"
        retry.TextScaled = true
        retry.Font = Theme.fonts.Primary
        retry.TextColor3 = Theme.colors.Text
        retry.Parent = gridScroll
        retry.Activated:Connect(function()
            self:refresh()
        end)
        return
    end

    for _, prod in ipairs(products) do
        local priceRobux = ClientCashShop.getRobuxPrice(prod.price or prod)
        local item = {
            id = "product_" .. tostring(prod.id),
            name = prod.name or tostring(prod.id),
            type = "product",
            slot = "coins",
            rarity = nil,
            icon = prod.icon or "",
        }

        -- Cell container (tile + price row)
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

        -- Tile area (fixed height)
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
            rarityEffects = false,
        })
        local btnTile = tile.button
        tile.helpers.addSymbol(item)
        tile.helpers.addNameLabel(item.name, { useRarityColor = false })
        -- No purchase on tile click for products (keep purchase on price button only)
        btnTile.Active = true

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
        priceBtn.BackgroundTransparency = 0.1
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

        -- Left icon label (use Robux currency mark)
        local icon = Instance.new("TextLabel")
        icon.BackgroundTransparency = 1
        icon.Text = "R$"
        icon.Font = Theme.fonts.Secondary
        icon.TextScaled = true
        icon.TextColor3 = Theme.colors.Text
        icon.Size = UDim2.new(0, UIx.Size.ROW_STANDARD - 2, 0, UIx.Size.ROW_STANDARD - 2)
        icon.Parent = priceBtn

        local lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency = 1
        lbl.Text = UIUtils.formatNumber(priceRobux)
        lbl.Font = Theme.fonts.Secondary
        lbl.TextScaled = true
        lbl.TextColor3 = Theme.colors.Text
        lbl.Size = UDim2.new(1, -UIx.Size.ROW_STANDARD, 1, 0)
        lbl.Parent = priceBtn

        local ThemeRefresher = require(ReplicatedStorage:WaitForChild("MiningGame"):WaitForChild("UI"):WaitForChild("ThemeRefresher"))
        ThemeRefresher.Bind(priceBtn, { BackgroundColor3 = "Background" })
        ThemeRefresher.Bind(icon, { TextColor3 = "Text" })
        ThemeRefresher.Bind(lbl, { TextColor3 = "Text" })

        -- Enablement and click wiring
        local configured = ClientCashShop.isProductConfigured(tostring(prod.id))
        local canBuyRF = hasRF("PurchaseProduct")
        local canBuy = configured and canBuyRF
        priceBtn.Active = canBuy
        priceBtn.AutoButtonColor = canBuy
        if not canBuy then
            priceBtn.BackgroundTransparency = 0.3
            if not configured then
                lbl.Text = "Configure"
            elseif not canBuyRF then
                lbl.Text = "Unavailable"
            end
        else
            priceBtn.Activated:Connect(function()
                local SoundManager = require(MiningGame:WaitForChild("SoundManager"))
                SoundManager.PlayUI("buttonclick")
                local r, e = ClientRF.call("PurchaseProduct", prod.id)
                if _G.UIManager then
                    if r and r.success then _G.UIManager:showNotification("Purchase prompt opened", "info")
                    else _G.UIManager:showNotification(e or "Purchase failed", "error") end
                end
            end)
        end
    end
end

return CashShopCoinsTab
