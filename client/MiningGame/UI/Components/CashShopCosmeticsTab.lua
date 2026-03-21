--!strict
-- CashShopCosmeticsTab.lua — Grid of cosmetics rendered via shared ItemTileRenderer

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UIFolder = MiningGame:WaitForChild("UI")
-- Strict Theme typing mirrors actual Theme.lua
local _Theme = require(UIFolder:WaitForChild("Theme"))
type ThemeCCT = typeof(_Theme)
local Theme: ThemeCCT = _Theme
local UIx = require(UIFolder:WaitForChild("UIConstants"))
local BaseTabComponent = require(script.Parent:WaitForChild("BaseTabComponent"))
local ShopGridHelpers = require(script.Parent:WaitForChild("ShopGridHelpers"))
local ClientRF = require(MiningGame:WaitForChild("ClientRF"))
local Remotes = require(MiningGame:WaitForChild("Remotes"))
local ClientCashShop = require(MiningGame:WaitForChild("ClientCashShop"))
local ItemDetailsPopup = require(script.Parent:WaitForChild("ItemDetailsPopup"))
local ClientEconomy = require(MiningGame:WaitForChild("ClientEconomy"))
local ClientRegistry = require(MiningGame:WaitForChild("ClientRegistry"))

type Props = { parent: Instance }
type ShopItem = ClientCashShop.ShopItem

local CashShopCosmeticsTab = {}
CashShopCosmeticsTab.__index = CashShopCosmeticsTab
setmetatable(CashShopCosmeticsTab, { __index = BaseTabComponent })

local function hasRF(name: string): boolean
	return rawget(Remotes.RF, name) ~= nil
end

function CashShopCosmeticsTab.new(props: Props)
	local baseAny: any = BaseTabComponent.new({ parent = props.parent, stacked = true, name = "CashShopCosmeticsTab" })
	local self = setmetatable(baseAny, CashShopCosmeticsTab)

	-- Scrollable card section consistent with other panels
	local _, gridScroll, grid = self:createScrollableSection("Cosmetics", UIx.Size.INVENTORY_MIN_HEIGHT)
	-- Override grid layout to match shop cell sizing
	grid.CellSize = UDim2.new(
		0,
		UIx.Size.INVENTORY_CELL_WIDTH,
		0,
		UIx.Size.INVENTORY_CELL_HEIGHT + UIx.Size.ROW_STANDARD + UIx.Spacing.SM + 2
	)
	grid.CellPadding = UDim2.new(0, UIx.Spacing.SM, 0, UIx.Spacing.SM)
	self._grid = gridScroll
	self._confirm = {}

	return self
end

function CashShopCosmeticsTab:refresh()
	local gridScroll: ScrollingFrame = self._grid
	if not gridScroll then
		return
	end
	for _, ch in ipairs(gridScroll:GetChildren()) do
		if ch:IsA("GuiObject") then
			ch:Destroy()
		end
	end

	local items: { ShopItem } = ClientCashShop.getCosmeticCatalog()
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
		local ownedCount = 0
		if it.ownedCount ~= nil and type(it.ownedCount) == "number" then
			ownedCount = it.ownedCount
		elseif it.meta and it.meta.ownedCount ~= nil and type(it.meta.ownedCount) == "number" then
			ownedCount = it.meta.ownedCount
		end

		ShopGridHelpers.renderItemCell({
			parent = gridScroll,
			item = it,
			rarityEffects = true,
			nameAlign = "center",
			useRarityColorForName = true,
			ownedCount = ownedCount,
			onTileClick = function()
				local mgr = ClientRegistry.getUIManager()
				local parentGui = (mgr and mgr.overlayGui) or self.container
				ItemDetailsPopup.new({ parent = parentGui, itemId = it.itemId or it.id })
			end,
			price = price,
			canBuy = (canBuyRF and affordable) == true,
			onPurchase = function()
				if not (canBuyRF and affordable) then
					return
				end
				local id = it.itemId or it.id
				local r, e = ClientRF.call("PurchaseItem", id)
				if e or (r and (r.ok == false or r.success == false)) then
					local mgr = ClientRegistry.getUIManager()
					if mgr then
						mgr:showNotification(e or (r and r.err) or "Purchase failed", "error")
					end
				end
				self:refresh()
			end,
		})
	end
end

return CashShopCosmeticsTab
