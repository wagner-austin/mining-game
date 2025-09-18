--!strict
-- SettingsPanel.lua
-- Settings panel using modular TabbedPanel and tab components

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UIFolder = MiningGame:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))
local UIx = require(UIFolder:WaitForChild("UIConstants"))
local GameConfig = require(MiningGame:WaitForChild("GameConfig"))
local TabbedPanel = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("TabbedPanel"))
local MaterialsTab = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("MaterialsTab"))
local AccountTab = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("AccountTab"))
local ThemeTab = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("ThemeTab"))

-- Only load MetricsTab and DebugTab in Studio for testing
local MetricsTab, DebugTab
if RunService:IsStudio() then
    MetricsTab = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("MetricsTab"))
    DebugTab = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("DebugTab"))
end

local SettingsPanel = {}
SettingsPanel.__index = SettingsPanel

type Providers = { accountDataProvider: any? }

type SettingsPanelT = typeof(setmetatable({} :: any, SettingsPanel)) & {
    name: string,
    _widgets: {any},
    panel: any?,
    frame: Frame?,
    lastTab: string,
    _providers: Providers,
    materialsTab: any?,
    themeTab: any?,
    upgradesTab: any?,
    inventoryTab: any?,
    accountTab: any?,
    metricsTab: any?,
    debugTab: any?,
    manager: any?,
    new: (providers: Providers?) -> SettingsPanelT,
    init: (self: SettingsPanelT, manager: any) -> (),
    switchTab: (self: SettingsPanelT, tabName: string) -> (),
    show: (self: SettingsPanelT) -> (),
    hide: (self: SettingsPanelT) -> (),
    cleanup: (self: SettingsPanelT) -> (),
}

function SettingsPanel.new(providers: Providers?): SettingsPanelT
    local self = setmetatable({
        name = "SettingsPanel",
        _widgets = {},   -- Track tab widgets for cleanup
        panel = nil,     -- cache TabbedPanel instance
        frame = nil,     -- UIManager uses this to know it's initialized
        lastTab = "Materials",  -- Remember last opened tab
        _providers = providers or {},
    }, SettingsPanel)
    
    return self :: any
end

function SettingsPanel:init(manager)
    if self.frame then return end  -- already initialized
    
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
    
    -- Debug: Print the tabs array
    print("[SettingsPanel] Tabs array:")
    for i, tab in ipairs(tabs) do
        print(string.format("  [%d] %s", i, tab.name))
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
    table.insert(self._widgets, self.themeTab)
    
    -- Upgrades and Inventory tabs removed from Settings
    
    -- Mount Account tab
    local accountRoot = self.panel:getTabContent("Account") :: Frame
    self.accountTab = AccountTab.new({
        parent = accountRoot,
        -- Let the tab auto-size based on content
        dataProvider = self._providers.accountDataProvider,
    })
    table.insert(self._widgets, self.accountTab)
    
    -- Mount Metrics tab (Studio only)
    if RunService:IsStudio() and MetricsTab then
        local metricsRoot = self.panel:getTabContent("Metrics") :: Frame
        self.metricsTab = MetricsTab.new({
            parent = metricsRoot,
            -- Let the tab auto-size based on content
            dataProvider = self._providers and self._providers.accountDataProvider,
        })
        table.insert(self._widgets, self.metricsTab)
    end
    
    -- Mount Debug tab (Studio only)
    if RunService:IsStudio() and DebugTab then
        local debugRoot = self.panel:getTabContent("Debug") :: Frame
        self.debugTab = DebugTab.new({
            parent = debugRoot,
            -- Let the tab auto-size based on content
            portalParent = self.panel.popoverLayer,
            dataProvider = self._providers and self._providers.accountDataProvider,
        })
        table.insert(self._widgets, self.debugTab)
    end
end

function SettingsPanel:switchTab(tabName: string)
    if self.panel then
        self.panel:switchTab(tabName)
    end
end

function SettingsPanel:show()
    if not self.panel then return end
    local SoundManager = require(ReplicatedStorage.MiningGame:WaitForChild("SoundManager"))
    SoundManager.PlayUI("openmenu")
    self.panel:show()
end

function SettingsPanel:hide()
    if not self.panel then return end
    self.panel:hide()
end

function SettingsPanel:cleanup()
    -- Destroy widgets (tabs)
    if self._widgets then
        for _, w in ipairs(self._widgets) do
            if w and w.destroy then
                w:destroy()
            end
        end
        self._widgets = {}
    end
    
    -- Destroy panel (handles popover layer and base panel cleanup)
    if self.panel then
        self.panel:destroy()
        self.panel = nil
    end
    self.frame = nil
end

return SettingsPanel
