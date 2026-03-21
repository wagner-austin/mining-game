--!strict
-- SettingsPanel.lua
-- Settings panel using modular TabbedPanel and tab components

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UIFolder = MiningGame:WaitForChild("UI")
-- Strict Theme typing mirrors actual Theme.lua
local _Theme = require(UIFolder:WaitForChild("Theme"))
type ThemeSP = typeof(_Theme)
local Theme: ThemeSP = _Theme
local TabbedPanel = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("TabbedPanel"))
local MaterialsTab = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("MaterialsTab"))
local AccountTab = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("AccountTab"))
local ThemeTab = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("ThemeTab"))
local BaseTabComponent = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("BaseTabComponent"))
local Logger = require(MiningGame:WaitForChild("Logger"))
local log = Logger.new("SettingsPanel")

-- Only load MetricsTab and DebugTab in Studio for testing
local MetricsTab, DebugTab
if RunService:IsStudio() then
	MetricsTab = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("MetricsTab"))
	DebugTab = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("DebugTab"))
end

local SettingsPanel = {}
SettingsPanel.__index = SettingsPanel

-- Types
type ManagerI = {
	container: Frame,
	showScene: (self: ManagerI, name: string) -> (),
	hideScene: (self: ManagerI, name: string) -> (),
}
type Destroyable = { destroy: (self: any) -> () }
type Providers = { accountDataProvider: BaseTabComponent.DataProvider? }

export type SettingsPanelT = {
	name: string,
	_widgets: { Instance | Destroyable },
	panel: TabbedPanel.TabbedPanelT?,
	frame: Frame?,
	lastTab: string,
	_providers: Providers,
	materialsTab: Destroyable?,
	themeTab: Destroyable?,
	accountTab: Destroyable?,
	metricsTab: Destroyable?,
	debugTab: Destroyable?,
	manager: ManagerI?,
}

function SettingsPanel.new(providers: Providers?)
	local self = setmetatable({
		name = "SettingsPanel",
		_widgets = {}, -- Track tab widgets for cleanup
		panel = nil, -- cache TabbedPanel instance
		frame = nil, -- UIManager uses this to know it's initialized
		lastTab = "Materials", -- Remember last opened tab
		_providers = providers or {},
	}, SettingsPanel)

	return self
end

function SettingsPanel:init(manager)
	if self.frame then
		return
	end -- already initialized

	self.manager = manager
	local colors = Theme.colors

	-- Build tabs list
	local tabs = {
		{ name = "Materials" },
		{ name = "Theme" },
		{ name = "Account" },
	}

	-- Add Metrics and Debug tabs in Studio only
	if RunService:IsStudio() then
		table.insert(tabs, { name = "Metrics" })
		table.insert(tabs, { name = "Debug" })
	end

	-- Debug: Log the tabs array
	log:debug("Tabs array:")
	for i, tab in ipairs(tabs) do
		log:debug("  [%d] %s", i, tab.name)
	end

	-- Create tabbed panel
	self.panel = TabbedPanel.new({
		parent = manager.container,
		title = "Settings",
		tintColor = colors.Background,
		transition = "scale",
		scrim = true,
		closeOnEsc = true,
		onClose = function()
			manager:hideScene("SettingsPanel")
		end,
		onShown = function() end,
		onHidden = function() end,
		tabs = tabs,
		defaultTab = self.lastTab or "Materials",
		onTabChange = function(newTab)
			self.lastTab = newTab
		end,
	})

	-- IMPORTANT: set frame so UIManager won't re-init
	self.frame = self.panel.container

	-- Mount Materials tab
	local materialsRoot = self.panel:getTabContent("Materials") :: Frame
	self.materialsTab = MaterialsTab.new({
		parent = materialsRoot,
		-- Let the tab auto-size based on content
		portalParent = self.panel.popoverLayer, -- use panel's popover
	})
	table.insert(self._widgets, self.materialsTab)

	-- Mount Theme tab
	local themeRoot = self.panel:getTabContent("Theme") :: Frame
	self.themeTab = ThemeTab.new({
		parent = themeRoot,
		-- Let the tab auto-size based on content
		portalParent = self.panel.popoverLayer, -- use panel's popover
	})
	-- Track tab instances directly for cleanup

	-- Upgrades and Inventory tabs removed from Settings

	-- Mount Account tab
	local accountRoot = self.panel:getTabContent("Account") :: Frame
	self.accountTab = AccountTab.new({
		parent = accountRoot,
		-- Let the tab auto-size based on content
		dataProvider = self._providers.accountDataProvider,
	})
	-- Track tab instances directly for cleanup

	-- Mount Metrics tab (Studio only)
	if RunService:IsStudio() and MetricsTab then
		local metricsRoot = self.panel:getTabContent("Metrics") :: Frame
		self.metricsTab = MetricsTab.new({
			parent = metricsRoot,
			-- Let the tab auto-size based on content
			dataProvider = self._providers.accountDataProvider,
		})
		-- Track tab instances directly for cleanup
	end

	-- Mount Debug tab (Studio only)
	if RunService:IsStudio() and DebugTab then
		local debugRoot = self.panel:getTabContent("Debug") :: Frame
		self.debugTab = DebugTab.new({
			parent = debugRoot,
			-- Let the tab auto-size based on content
			portalParent = self.panel.popoverLayer,
			dataProvider = self._providers.accountDataProvider,
		})
		-- Track tab instances directly for cleanup
	end
end

function SettingsPanel:switchTab(tabName: string)
	if self.panel then
		self.panel:switchTab(tabName)
	end
end

function SettingsPanel:show()
	if not self.panel then
		return
	end
	local SoundManager = require(ReplicatedStorage.MiningGame:WaitForChild("SoundManager"))
	SoundManager.PlayUI("openmenu")
	self.panel:show()
end

function SettingsPanel:hide()
	if not self.panel then
		return
	end
	self.panel:hide()
end

function SettingsPanel:cleanup()
	-- Destroy widgets (tabs)
	-- Explicitly destroy tab instances we manage
	if self.materialsTab then
		self.materialsTab:destroy()
	end
	if self.themeTab then
		self.themeTab:destroy()
	end
	if self.accountTab then
		self.accountTab:destroy()
	end
	if self.metricsTab then
		self.metricsTab:destroy()
	end
	if self.debugTab then
		self.debugTab:destroy()
	end
	self._widgets = {}

	-- Destroy panel (handles popover layer and base panel cleanup)
	if self.panel then
		self.panel:destroy()
		self.panel = nil :: any
	end
	self.frame = nil
end

return SettingsPanel
