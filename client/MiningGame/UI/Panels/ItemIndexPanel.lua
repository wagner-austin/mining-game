--!strict
-- ItemIndexPanel.lua â€” thin shell that mounts ItemIndexTab inside a TabbedPanel

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UIFolder = MiningGame:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))
local UIx = require(UIFolder:WaitForChild("UIConstants"))

local TabbedPanel = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("TabbedPanel"))
local ItemIndexTab = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("ItemIndexTab"))

local ItemIndexPanel = {}
ItemIndexPanel.__index = ItemIndexPanel

export type ItemIndexPanelT = typeof(setmetatable({} :: any, ItemIndexPanel)) & {
    name: string,
    frame: Frame?,
    panel: any?,
    manager: any?,
    _provider: any?,
    _tab: any?,
    new: (providers: {accountDataProvider: any}?) -> ItemIndexPanelT,
    init: (self: ItemIndexPanelT, manager: any) -> (),
    show: (self: ItemIndexPanelT) -> (),
    hide: (self: ItemIndexPanelT) -> (),
}

function ItemIndexPanel.new(providers): ItemIndexPanelT
    local self = setmetatable({
        name = "ItemIndexPanel",
        frame = nil,
        panel = nil,
        manager = nil,
        _provider = providers and providers.accountDataProvider or nil,
        _tab = nil,
    }, ItemIndexPanel)
    return self :: any
end

function ItemIndexPanel:init(manager)
    if self.frame then return end
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
            if self._tab and self._tab.setActive then self._tab:setActive(true) end
        end,
        onHidden = function()
            if self._tab and self._tab.setActive then self._tab:setActive(false) end
        end,
    })
    self.panel = panel
    self.frame = panel.container

    local content = panel:getTabContent("Index")
    self._tab = ItemIndexTab.new({
        parent = content,
        portalParent = panel.popoverLayer,
        dataProvider = self._provider,
    })
end

function ItemIndexPanel:show()
    if not self.panel then return end
    local SoundManager = require(ReplicatedStorage.MiningGame:WaitForChild("SoundManager"))
    SoundManager.PlayUI("openmenu")
    self.panel:show()
end

function ItemIndexPanel:hide()
    if not self.panel then return end
    self.panel:hide()
end

return ItemIndexPanel
