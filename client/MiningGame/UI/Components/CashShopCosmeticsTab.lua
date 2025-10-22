--!strict
-- CashShopCosmeticsTab.lua — Grid of cosmetics rendered via shared ItemTileRenderer

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UIFolder = MiningGame:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))
local UIx = require(UIFolder:WaitForChild("UIConstants"))
local BaseTabComponent = require(script.Parent:WaitForChild("BaseTabComponent"))
local ItemTileRenderer = require(script.Parent:WaitForChild("ItemTileRenderer"))
local ShopGridHelpers = require(script.Parent:WaitForChild("ShopGridHelpers"))
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

    -- Scrollable card section consistent with other panels
    local _, gridScroll, grid = self:createScrollableSection("Cosmetics", UIx.Size.INVENTORY_MIN_HEIGHT)
    -- Override grid layout to match shop cell sizing
    grid.CellSize = UDim2.new(0, UIx.Size.INVENTORY_CELL_WIDTH, 0, UIx.Size.INVENTORY_CELL_HEIGHT + UIx.Size.ROW_STANDARD + UIx.Spacing.SM + 2)
    grid.CellPadding = UDim2.new(0, UIx.Spacing.SM, 0, UIx.Spacing.SM)
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
    local canBuyRF = hasRF("PurchaseItem")
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
        local ownedCount = tonumber((it :: any).ownedCount) or tonumber((it :: any).meta and (it :: any).meta.ownedCount) or 0

        ShopGridHelpers.renderItemCell({
            parent = gridScroll,
            item = it,
            rarityEffects = true,
            nameAlign = "center",
            useRarityColorForName = true,
            ownedCount = ownedCount,
            onTileClick = function()
                local parentGui = (_G and _G.UIManager and _G.UIManager.overlayGui) or self.container
                ItemDetailsPopup.new({ parent = parentGui, itemId = it.itemId or it.id })
            end,
            price = price,
            canBuy = (canBuyRF and affordable) == true,
            onPurchase = function()
                if not (canBuyRF and affordable) then return end
                local id = it.itemId or it.id
                local r, e = ClientRF.call("PurchaseItem", id)
                if e or (r and (r.ok == false or r.success == false)) then
                    if _G.UIManager then _G.UIManager:showNotification(e or (r and r.err) or "Purchase failed", "error") end
                end
                self:refresh()
            end,
        })
    end
end

return CashShopCosmeticsTab
