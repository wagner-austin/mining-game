--!strict
-- UpgradesPanel.lua
-- Dedicated panel that reuses the existing UpgradeTab component (no reimplementation)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UIFolder = MiningGame:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))
local TabbedPanel = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("TabbedPanel"))
local UpgradeTab = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("UpgradeTab"))
local UIx = require(UIFolder:WaitForChild("UIConstants"))
local ThemeRefresher = require(UIFolder:WaitForChild("ThemeRefresher"))
local ClientRF = require(MiningGame:WaitForChild("ClientRF"))

type Providers = { accountDataProvider: any? }

type UpgradesPanelT = {
    name: string,
    frame: Frame?,
    panel: any?,
    manager: any?,
    _providers: Providers,
    _widgets: {any},
    _upTab: any?,
    new: (providers: Providers?) -> UpgradesPanelT,
    init: (self: UpgradesPanelT, manager: any) -> (),
    show: (self: UpgradesPanelT) -> (),
    hide: (self: UpgradesPanelT) -> (),
    cleanup: (self: UpgradesPanelT) -> (),
}

local UpgradesPanel = {}
UpgradesPanel.__index = UpgradesPanel

function UpgradesPanel.new(providers: Providers?): UpgradesPanelT
    local self = setmetatable({
        name = "UpgradesPanel",
        frame = nil,
        panel = nil,
        manager = nil,
        _providers = providers or {},
        _widgets = {},
        _upTab = nil,
    }, UpgradesPanel)
    return self :: any
end

function UpgradesPanel:init(manager)
    if self.frame then return end
    self.manager = manager

    -- Single-tab TabbedPanel to mount the existing UpgradeTab
    local tabs = { { name = "Upgrades" } }
    self.panel = TabbedPanel.new({
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
            if self._upTab and self._upTab.refresh then
                self._upTab:refresh()
            end
        end,
    })

    self.frame = self.panel.container

    -- Mount the existing UpgradeTab component as-is
    local content = self.panel:getTabContent("Upgrades")
    self._upTab = UpgradeTab.new({
        parent = content,
        dataProvider = self._providers and self._providers.accountDataProvider,
    })
    table.insert(self._widgets, self._upTab)

    -- Footer actions removed: Respawn Cube button (moved out of Upgrades panel)
end

function UpgradesPanel:show()
    if not self.panel then return end
    self.panel:show()
end

function UpgradesPanel:hide()
    if not self.panel then return end
    self.panel:hide()
end

function UpgradesPanel:cleanup()
    if self._widgets then
        for _, w in ipairs(self._widgets) do
            if w and w.destroy then
                w:destroy()
            end
        end
        self._widgets = {}
    end
    if self.panel then
        self.panel:destroy()
        self.panel = nil
    end
    self.frame = nil
end

return UpgradesPanel
