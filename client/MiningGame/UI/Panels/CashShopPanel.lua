--!strict
-- CashShopPanel.lua
-- Cash Shop panel with Coins (Robux products) and Cosmetics (coin purchases)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UIFolder = MiningGame:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))
local UIx = require(UIFolder:WaitForChild("UIConstants"))
local GameConfig = require(MiningGame:WaitForChild("GameConfig"))

local TabbedPanel = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("TabbedPanel"))
-- SimpleList no longer used here; tabs render their own UIs
local CashShopCoinsTab = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("CashShopCoinsTab"))
local CashShopCosmeticsTab = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("CashShopCosmeticsTab"))

type Providers = { accountDataProvider: any? }

type CashShopPanelT = {
    name: string,
    frame: Frame?,
    panel: any?,
    manager: any?,
    _providers: Providers?,
    _coinsTab: any?,
    _cosmeticsTab: any?,
    _coinsLoaded: boolean,
    _cosmeticsLoaded: boolean,
    _fallbackToastShown: boolean,
    _busy: {[string]: boolean},
    new: (providers: Providers?) -> CashShopPanelT,
    init: (self: CashShopPanelT, manager: any) -> (),
    show: (self: CashShopPanelT) -> (),
    hide: (self: CashShopPanelT) -> (),
    cleanup: (self: CashShopPanelT) -> (),
}

local CashShopPanel = {}
CashShopPanel.__index = CashShopPanel

local SoundManager = require(MiningGame:WaitForChild("SoundManager"))

-- No RF checks needed here; tabs perform their own requests

function CashShopPanel.new(providers: Providers?): CashShopPanelT
    local self = setmetatable({
        name = "CashShopPanel",
        frame = nil,
        panel = nil,
        manager = nil,
        _providers = providers,
        _coinsTab = nil,
        _cosmeticsTab = nil,
        _coinsLoaded = false,
        _cosmeticsLoaded = false,
        _fallbackToastShown = false,
        _busy = {},
    }, CashShopPanel)
    return self :: any
end

function CashShopPanel:init(manager)
    if self.frame then return end
    self.manager = manager

    local features = GameConfig.Features or {}
    local tabs = { { name = "Passes" } }
    local showCosmetics = features.SHOW_SHOP_TAB == true
    if showCosmetics then table.insert(tabs, { name = "Cosmetics" }) end

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
            if newTab == "Passes" and self._coinsTab and self._coinsTab.refresh then self._coinsTab:refresh() end
            if newTab == "Cosmetics" and self._cosmeticsTab and self._cosmeticsTab.refresh then self._cosmeticsTab:refresh() end
        end,
        onShown = function()
            local current = self.panel:getCurrentTab()
            if current == "Passes" and self._coinsTab and self._coinsTab.refresh then self._coinsTab:refresh() end
            if current == "Cosmetics" and self._cosmeticsTab and self._cosmeticsTab.refresh then self._cosmeticsTab:refresh() end
        end,
    })

    local coinsRoot = self.panel:getTabContent("Passes")
    self._coinsTab = CashShopCoinsTab.new({ parent = coinsRoot })
    if showCosmetics then
        local cosmeticsRoot = self.panel:getTabContent("Cosmetics")
        self._cosmeticsTab = CashShopCosmeticsTab.new({ parent = cosmeticsRoot })
    end

    self.frame = self.panel.container
end

function CashShopPanel:show()
    if not self.panel then return end
    SoundManager.PlayUI("openmenu")
    self.panel:show()
end

function CashShopPanel:hide()
    if not self.panel then return end
    self.panel:hide()
end

function CashShopPanel:cleanup()
    if self.panel then
        self.panel:destroy()
        self.panel = nil
    end
    self.frame = nil
    self._coinsTab = nil
    self._cosmeticsTab = nil
end

return CashShopPanel


