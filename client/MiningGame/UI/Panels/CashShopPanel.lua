--!strict
-- CashShopPanel.lua
-- Cash Shop panel with Coins (Robux products) and Cosmetics (coin purchases)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UIFolder = MiningGame:WaitForChild("UI")
-- Strict Theme typing mirrors actual Theme.lua
local _Theme = require(UIFolder:WaitForChild("Theme"))
type ThemeCSP = typeof(_Theme)
local Theme: ThemeCSP = _Theme
local GameConfig = require(MiningGame:WaitForChild("GameConfig"))
local BaseTabComponent = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("BaseTabComponent"))

local TabbedPanel = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("TabbedPanel"))
-- SimpleList no longer used here; tabs render their own UIs
local CashShopCoinsTab = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("CashShopCoinsTab"))
local CashShopCosmeticsTab =
	require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("CashShopCosmeticsTab"))

-- Manager + Panel types
type ManagerI = {
	container: Frame,
	showScene: (self: ManagerI, name: string) -> (),
	hideScene: (self: ManagerI, name: string) -> (),
}
type TabT = { refresh: (() -> ())? }
type CashShopPanelT = {
	name: string,
	frame: Frame?,
	panel: TabbedPanel.TabbedPanelT?,
	manager: ManagerI?,
	_providers: { accountDataProvider: BaseTabComponent.DataProvider? }?,
	_coinsTab: TabT?,
	_cosmeticsTab: TabT?,
	_coinsLoaded: boolean,
	_cosmeticsLoaded: boolean,
	_fallbackToastShown: boolean,
	_busy: { [string]: boolean },
	new: (providers: { accountDataProvider: BaseTabComponent.DataProvider? }?) -> CashShopPanelT,
	init: (self: CashShopPanelT, manager: ManagerI) -> (),
	show: (self: CashShopPanelT) -> (),
	hide: (self: CashShopPanelT) -> (),
	cleanup: (self: CashShopPanelT) -> (),
}

local CashShopPanel = {}
CashShopPanel.__index = CashShopPanel

local SoundManager = require(MiningGame:WaitForChild("SoundManager"))

-- No RF checks needed here; tabs perform their own requests

function CashShopPanel.new(providers): CashShopPanelT
	local self: CashShopPanelT = setmetatable({} :: any, CashShopPanel)
	self.name = "CashShopPanel"
	self.frame = nil
	self.panel = nil
	self.manager = nil
	self._providers = providers
	self._coinsTab = nil
	self._cosmeticsTab = nil
	self._coinsLoaded = false
	self._cosmeticsLoaded = false
	self._fallbackToastShown = false
	self._busy = {}
	return self
end

function CashShopPanel:init(manager)
	if self.frame then
		return
	end
	self.manager = manager

	local tabs = { { name = "Passes" } }
	local fAny: any = (GameConfig and GameConfig.Features) or nil
	local showCosmetics = (fAny and fAny.SHOW_SHOP_TAB == true) and true or false
	if showCosmetics then
		table.insert(tabs, { name = "Cosmetics" })
	end

	self.panel = TabbedPanel.new({
		parent = manager.container,
		title = "Shop",
		tintColor = Theme.colors.Background,
		transition = "scale",
		scrim = true,
		closeOnEsc = true,
		onClose = function()
			manager:hideScene("CashShopPanel")
		end,
		tabs = tabs,
		defaultTab = "Passes",
		onTabChange = function(newTab)
			if newTab == "Passes" and self._coinsTab and self._coinsTab.refresh then
				self._coinsTab:refresh()
			end
			if newTab == "Cosmetics" and self._cosmeticsTab and self._cosmeticsTab.refresh then
				self._cosmeticsTab:refresh()
			end
		end,
		onShown = function()
			local current = self.panel:getCurrentTab()
			if current == "Passes" and self._coinsTab and self._coinsTab.refresh then
				self._coinsTab:refresh()
			end
			if current == "Cosmetics" and self._cosmeticsTab and self._cosmeticsTab.refresh then
				self._cosmeticsTab:refresh()
			end
		end,
	})

	local coinsRoot = self.panel:getTabContent("Passes")
	self._coinsTab = CashShopCoinsTab.new({ parent = (coinsRoot or self.panel:getContent()) })
	if showCosmetics then
		local cosmeticsRoot = self.panel:getTabContent("Cosmetics")
		self._cosmeticsTab = CashShopCosmeticsTab.new({ parent = (cosmeticsRoot or self.panel:getContent()) })
	end

	self.frame = self.panel.container
end

function CashShopPanel:show()
	if not self.panel then
		return
	end
	SoundManager.PlayUI("openmenu")
	self.panel:show()
end

function CashShopPanel:hide()
	if not self.panel then
		return
	end
	self.panel:hide()
end

function CashShopPanel:cleanup()
	if self.panel then
		local pAny: any = self.panel
		pAny:destroy()
		self.panel = nil
	end
	self.frame = nil
	self._coinsTab = nil
	self._cosmeticsTab = nil
end

return CashShopPanel
