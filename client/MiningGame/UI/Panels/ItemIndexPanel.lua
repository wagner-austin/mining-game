--!strict
-- ItemIndexPanel.lua â€” thin shell that mounts ItemIndexTab inside a TabbedPanel

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TabbedPanel = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("TabbedPanel"))
local ItemIndexTab = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("ItemIndexTab"))
local BaseTabComponent = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("BaseTabComponent"))

local ItemIndexPanel = {}
ItemIndexPanel.__index = ItemIndexPanel

-- Types
type ManagerI = {
	container: Frame,
	showScene: (self: ManagerI, name: string) -> (),
	hideScene: (self: ManagerI, name: string) -> (),
}
type ProviderT = { accountDataProvider: BaseTabComponent.DataProvider? }
type ItemIndexTabT = ItemIndexTab.ItemIndexTabT
export type ItemIndexPanelT = {
	name: string,
	frame: Frame?,
	panel: TabbedPanel.TabbedPanelT?,
	manager: ManagerI?,
	_provider: BaseTabComponent.DataProvider?,
	_tab: ItemIndexTabT?,
	new: (providers: ProviderT?) -> ItemIndexPanelT,
	init: (self: ItemIndexPanelT, manager: ManagerI) -> (),
	show: (self: ItemIndexPanelT) -> (),
	hide: (self: ItemIndexPanelT) -> (),
	cleanup: (self: ItemIndexPanelT) -> (),
}

function ItemIndexPanel.new(providers: ProviderT?): ItemIndexPanelT
	local self: ItemIndexPanelT = setmetatable({} :: any, ItemIndexPanel)
	self.name = "ItemIndexPanel"
	self.frame = nil
	self.panel = nil
	self.manager = nil
	self._provider = providers and providers.accountDataProvider or nil
	self._tab = nil
	return self
end

function ItemIndexPanel:init(manager)
	if self.frame then
		return
	end
	self.manager = manager

	local panel = TabbedPanel.new({
		parent = manager.container,
		title = "Item Index",
		transition = "scale",
		scrim = true,
		closeOnEsc = true,
		onClose = function()
			manager:hideScene(self.name)
		end,
		tabs = { { name = "Index" } },
		defaultTab = "Index",
		onShown = function()
			if self._tab and self._tab.setActive then
				self._tab:setActive(true)
			end
		end,
		onHidden = function()
			if self._tab and self._tab.setActive then
				self._tab:setActive(false)
			end
		end,
	})
	self.panel = panel
	self.frame = panel.container

	local content = panel:getTabContent("Index") :: Frame
	self._tab = ItemIndexTab.new({
		parent = content,
		portalParent = panel.popoverLayer,
		dataProvider = self._provider,
	})
end

function ItemIndexPanel:show()
	if not self.panel then
		return
	end
	local SoundManager = require(ReplicatedStorage.MiningGame:WaitForChild("SoundManager"))
	SoundManager.PlayUI("openmenu")
	self.panel:show()
end

function ItemIndexPanel:hide()
	if not self.panel then
		return
	end
	self.panel:hide()
end

function ItemIndexPanel:cleanup()
	-- Destroy child tab first
	do
		local tabAny: any = self._tab
		if tabAny then
			tabAny:destroy()
		end
	end
	self._tab = nil

	-- Destroy the tabbed panel
	do
		local pAny: any = self.panel
		if pAny then
			pAny:destroy()
		end
	end
	self.panel = nil
	self.frame = nil
end

return ItemIndexPanel
