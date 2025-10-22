--!strict
-- TabbedPanel.lua
-- Composes BasePanel + TabContainer (+ popover layer) and exposes a simple API

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UIFolder = MiningGame:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))

local BasePanel = require(script.Parent:WaitForChild("BasePanel"))
local TabContainer = require(script.Parent:WaitForChild("TabContainer"))

local TabbedPanel = {}
TabbedPanel.__index = TabbedPanel

export type TabSpec = TabContainer.TabDefinition

export type Props = {
    parent: GuiObject,
    title: string,
    tabs: {TabSpec},
    defaultTab: string?,
    -- Pass-through to BasePanel:
    size: UDim2?,
    position: UDim2?,
    tintColor: Color3?,
    transition: ("left" | "down" | "scale")?,
    scrim: boolean?,
    closeOnEsc: boolean?,
    onClose: (() -> ())?,
    onShown: (() -> ())?,
    onHidden: (() -> ())?,
    onTabChange: ((newTab: string, oldTab: string?) -> ())?,
}

export type TabbedPanelT = {
    _base: any,
    container: Frame?,
    popoverLayer: Frame?,
    _tabs: {TabSpec},
    _tabContainer: any,
    new: (props: Props) -> TabbedPanelT,
    getTabContent: (self: TabbedPanelT, tabName: string) -> Frame?,
    -- Expose BasePanel's content layer for overlay UI that should
    -- participate in BasePanel animations/reveals (e.g., sticky bars)
    getContentLayer: (self: TabbedPanelT) -> Frame?,
    switchTab: (self: TabbedPanelT, tabName: string) -> (),
    getCurrentTab: (self: TabbedPanelT) -> string?,
    setTabEnabled: (self: TabbedPanelT, tabName: string, enabled: boolean) -> (),
    getContent: (self: TabbedPanelT) -> Frame,
    show: (self: TabbedPanelT) -> (),
    hide: (self: TabbedPanelT) -> (),
    destroy: (self: TabbedPanelT) -> (),
}

function TabbedPanel.new(props: Props): TabbedPanelT
    local self = setmetatable({}, TabbedPanel)

    -- Base panel
    local base = BasePanel.new({
        parent = props.parent,
        title = props.title,
        size = props.size,
        position = props.position,
        tintColor = props.tintColor or Theme.colors.Background,
        transition = props.transition or "scale",
        scrim = props.scrim ~= nil and props.scrim or true,
        closeOnEsc = props.closeOnEsc ~= nil and props.closeOnEsc or true,
        onClose = props.onClose,
        onShown = props.onShown,
        onHidden = props.onHidden,
    })
    self._base = base
    self.container = base.container -- expose for callers if needed

    -- Popover layer (for dropdown portals)
    local popover = Instance.new("Frame")
    popover.Name = "PopoverLayer"
    popover.BackgroundTransparency = 1
    popover.Size = UDim2.fromScale(1, 1)
    -- Ensure dropdown popovers render above all content (and other panels)
    popover.ZIndex = Theme.z.Modal + 100
    popover.Parent = base.container
    self.popoverLayer = popover

    -- Tabs skeleton
    self._tabs = props.tabs
    self._tabContainer = TabContainer.new({
        parent = base:getContent(),
        tabs = props.tabs,
        defaultTab = props.defaultTab or (props.tabs[1] and props.tabs[1].name) or nil,
        onTabChange = props.onTabChange,
    })

    return self
end

-- Convenience passthroughs
function TabbedPanel:getTabContent(tabName: string): Frame?
    return self._tabContainer:getTabContent(tabName)
end

function TabbedPanel:getContentLayer(): Frame?
    return self._base and self._base.contentLayer or nil
end

function TabbedPanel:switchTab(tabName: string)
    self._tabContainer:switchTab(tabName)
end

function TabbedPanel:getCurrentTab(): string?
    return self._tabContainer:getCurrentTab()
end

function TabbedPanel:setTabEnabled(tabName: string, enabled: boolean)
    self._tabContainer:setTabEnabled(tabName, enabled)
end

-- BasePanel passthroughs
function TabbedPanel:getContent(): Frame
    return self._base:getContent()
end

function TabbedPanel:show()
    self._base:show()
end

function TabbedPanel:hide()
    self._base:hide()
end

function TabbedPanel:destroy()
    if self._tabContainer then
        self._tabContainer:destroy()
        self._tabContainer = nil
    end
    if self.popoverLayer then
        self.popoverLayer:Destroy()
        self.popoverLayer = nil
    end
    if self._base then
        self._base:destroy()
        self._base = nil
    end
    self.container = nil
end

return TabbedPanel
