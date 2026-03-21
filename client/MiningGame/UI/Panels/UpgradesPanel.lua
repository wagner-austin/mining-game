--!strict
-- UpgradesPanel.lua
-- Dedicated panel that reuses the existing UpgradeTab component (no reimplementation)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UIFolder = MiningGame:WaitForChild("UI")
-- Strict Theme typing mirrors actual Theme.lua
local _Theme = require(UIFolder:WaitForChild("Theme"))
type ThemeUP = typeof(_Theme)
local Theme: ThemeUP = _Theme
local TabbedPanel = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("TabbedPanel"))
local UpgradeTab = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("UpgradeTab"))
local BaseTabComponent = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("BaseTabComponent"))

-- Panel types are internal; keep runtime fields untyped here for simplicity

local UpgradesPanel = {}
UpgradesPanel.__index = UpgradesPanel

type ManagerI = {
	container: Frame,
	showScene: (self: ManagerI, name: string) -> (),
	hideScene: (self: ManagerI, name: string) -> (),
}
type Providers = { accountDataProvider: BaseTabComponent.DataProvider? }
type Destroyable = { destroy: (self: Destroyable) -> () }

type UpgradeTabT = BaseTabComponent.BaseTab
export type UpgradesPanelT = {
	name: string,
	frame: Frame?,
	panel: TabbedPanel.TabbedPanelT?,
	manager: ManagerI?,
	_providers: Providers,
	_widgets: { Instance | Destroyable },
	_upTab: UpgradeTabT?,
}

function UpgradesPanel.new(providers: Providers?)
	local self = setmetatable({
		name = "UpgradesPanel",
		frame = nil,
		panel = nil,
		manager = nil,
		_providers = providers or {},
		_widgets = {},
		_upTab = nil,
	}, UpgradesPanel)
	return self
end

function UpgradesPanel.init(self: UpgradesPanelT, manager: ManagerI)
	if self.frame then
		return
	end
	self.manager = manager

	-- Single-tab TabbedPanel to mount the existing UpgradeTab
	local tabs = { { name = "Upgrades" } }
	local panel = TabbedPanel.new({
		parent = manager.container,
		title = "Upgrades",
		tintColor = Theme.colors.Background,
		transition = "scale",
		scrim = true,
		closeOnEsc = true,
		onClose = function()
			manager:hideScene(self.name)
		end,
		tabs = tabs,
		defaultTab = "Upgrades",
		onShown = function()
			local up = self._upTab
			if up and up.refresh then
				up:refresh()
			end
		end,
	})
	self.panel = panel
	self.frame = panel.container

	-- Mount the existing UpgradeTab component as-is
	local content = panel:getTabContent("Upgrades")
	local parent: GuiObject = (content or panel:getContent()) :: GuiObject
	self._upTab = UpgradeTab.new({
		parent = parent,
		dataProvider = self._providers and self._providers.accountDataProvider,
	})
	-- No need to track in _widgets; destroy explicitly in cleanup

	-- Footer actions removed: Respawn Cube button (moved out of Upgrades panel)
end

function UpgradesPanel.show(self: UpgradesPanelT): ()
	if not self.panel then
		return
	end
	self.panel:show()
end

function UpgradesPanel.hide(self: UpgradesPanelT): ()
	if not self.panel then
		return
	end
	self.panel:hide()
end

function UpgradesPanel.cleanup(self: UpgradesPanelT): ()
	self._widgets = {}
	if self._upTab then
		self._upTab:destroy()
		self._upTab = nil
	end
	if self.panel then
		self.panel:destroy()
		self.panel = nil
	end
	self.frame = nil
end

return UpgradesPanel
