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

    -- Footer action row (non-intrusive): Respawn Cube button
    local footer = Instance.new("Frame")
    footer.Name = "FooterActions"
    footer.BackgroundTransparency = 1
    footer.Size = UDim2.new(1, 0, 0, UIx.Size.BUTTON_MEDIUM_HEIGHT)
    footer.LayoutOrder = 999
    footer.Parent = content
    local fl = Instance.new("UIListLayout")
    fl.FillDirection = Enum.FillDirection.Horizontal
    fl.HorizontalAlignment = Enum.HorizontalAlignment.Center
    fl.VerticalAlignment = Enum.VerticalAlignment.Center
    fl.Padding = UDim.new(0, UIx.Spacing.SM)
    fl.Parent = footer

    local respawn = Instance.new("TextButton")
    respawn.Name = "RespawnCubeButton"
    respawn.Size = UDim2.new(0, UIx.Size.BUTTON_WIDTH, 0, UIx.Size.BUTTON_MEDIUM_HEIGHT - 6)
    respawn.BackgroundColor3 = Theme.colors.Surface
    respawn.TextColor3 = Theme.colors.Text
    respawn.TextScaled = true
    respawn.Font = Theme.fonts.Primary
    respawn.Text = "Respawn Cube"
    respawn.AutoButtonColor = false
    respawn.Parent = footer
    ThemeRefresher.Bind(respawn, { BackgroundColor3 = "Surface", TextColor3 = "Text" })
    local rc = Instance.new("UICorner")
    rc.CornerRadius = UIx.corner()
    rc.Parent = respawn
    respawn.Activated:Connect(function()
        local res, err = ClientRF.call("RespawnCubeModel")
        if _G.UIManager then
            if err or not (res and res.success) then
                _G.UIManager:showNotification(err or (res and res.reason) or "Respawn failed", "error")
            else
                _G.UIManager:showNotification("Cube respawned", "success")
            end
        end
    end)
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
