--!strict
-- SettingsPanel.lua
-- Settings panel using modular TabbedPanel and tab components

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Theme = require(MiningGame:WaitForChild("UI"):WaitForChild("Theme"))
local TabbedPanel = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("TabbedPanel"))
local MaterialsTab = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("MaterialsTab"))
local AccountTab = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("AccountTab"))

local SettingsPanel = {}
SettingsPanel.__index = SettingsPanel

type Providers = { accountDataProvider: any? }

function SettingsPanel.new(providers: Providers?)
    local self = setmetatable({
        name = "SettingsPanel",
        _widgets = {},   -- Track tab widgets for cleanup
        panel = nil,     -- cache TabbedPanel instance
        frame = nil,     -- UIManager uses this to know it's initialized
        lastTab = "Materials",  -- Remember last opened tab
        _providers = providers or {},
    }, SettingsPanel)
    
    return self
end

function SettingsPanel:init(manager)
    if self.frame then return end  -- already initialized
    
    self.manager = manager
    local colors = Theme.colors
    
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
        tabs = {
            { name = "Materials" },
            { name = "Account" },
        },
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
        position = UDim2.new(0, 0, 0, 0),
        size = UDim2.new(1, 0, 0, 0),
        portalParent = self.panel.popoverLayer, -- use panel's popover
    })
    table.insert(self._widgets, self.materialsTab)
    
    -- Mount Account tab
    local accountRoot = self.panel:getTabContent("Account") :: Frame
    self.accountTab = AccountTab.new({
        parent = accountRoot,
        position = UDim2.new(0, 0, 0, 0),
        size = UDim2.new(1, 0, 0, 0),
        dataProvider = self._providers.accountDataProvider,
    })
    table.insert(self._widgets, self.accountTab)
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