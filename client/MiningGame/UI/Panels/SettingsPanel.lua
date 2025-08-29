--!strict
-- SettingsPanel.lua
-- Settings panel with interactive sliders and proper Theme configuration

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Theme = require(MiningGame:WaitForChild("UI"):WaitForChild("Theme"))
local BasePanel = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("BasePanel"))
local MaterialsTab = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("MaterialsTab"))

local SettingsPanel = {}
SettingsPanel.__index = SettingsPanel

function SettingsPanel.new()
    local self = setmetatable({
        name = "SettingsPanel",
        _cons = {},
        _widgets = {},   -- Track dropdown widgets for cleanup
        panel = nil,     -- cache BasePanel instance
        frame = nil,     -- UIManager uses this to know it's initialized
    }, SettingsPanel)
    
    return self
end

function SettingsPanel:init(manager)
    if self.frame then return end  -- already initialized
    
    self.manager = manager
    local colors = Theme.colors
    
    -- Helper for connection management
    local function bind(signal, fn)
        local c = signal:Connect(fn)
        table.insert(self._cons, c)
        return c
    end
    
    -- Create base panel with dark tint (use main container for proper sizing)
    self.panel = BasePanel.new({
        parent = manager.container,  -- Use main container, not overlayGui
        title = "Settings",
        tintColor = colors.Background,
        transition = "scale",
        scrim = true,
        closeOnEsc = true,
        useAspect = false,  -- Disable aspect ratio to preserve vertical margins
        onClose = function()
            manager:hideScene("SettingsPanel")
        end
    })
    
    -- IMPORTANT: set frame so UIManager won't re-init
    self.frame = self.panel.container
    
    -- Popover layer (for dropdown portals)
    self.popoverLayer = Instance.new("Frame")
    self.popoverLayer.Name = "PopoverLayer"
    self.popoverLayer.BackgroundTransparency = 1
    self.popoverLayer.Size = UDim2.fromScale(1, 1)
    self.popoverLayer.ZIndex = Theme.z.Modal + 5 -- above everything in the panel
    self.popoverLayer.Parent = self.panel.container
    
    -- Get content area
    local content = self.panel:getContent()
    
    -- Tab container
    local tabContainer = Instance.new("Frame")
    tabContainer.Name = "TabContainer"
    tabContainer.Size = UDim2.new(1, 0, 0, 50)
    tabContainer.BackgroundTransparency = 1
    tabContainer.Parent = content
    
    local tabLayout = Instance.new("UIListLayout")
    tabLayout.FillDirection = Enum.FillDirection.Horizontal
    tabLayout.Padding = UDim.new(0, 10)
    tabLayout.Parent = tabContainer
    
    -- Create tabs
    local tabs = {"Materials", "Account"}
    self.tabButtons = {}
    self.tabContents = {}
    
    for _, tabName in ipairs(tabs) do
        -- Tab button
        local tabButton = Instance.new("TextButton")
        tabButton.Name = tabName .. "Tab"
        tabButton.Size = UDim2.new(0, 100, 1, 0)
        tabButton.BackgroundColor3 = colors.Surface
        tabButton.BackgroundTransparency = 0.5
        tabButton.Text = tabName
        tabButton.TextColor3 = colors.Text
        tabButton.TextScaled = true
        tabButton.Font = Theme.fonts.Primary
        tabButton.Parent = tabContainer
        
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, Theme.sizes.CornerRadius)
        corner.Parent = tabButton
        
        local textConstraint = Instance.new("UITextSizeConstraint")
        textConstraint.MinTextSize = Theme.textSizes.Small.Min
        textConstraint.MaxTextSize = Theme.textSizes.Medium.Max
        textConstraint.Parent = tabButton
        
        self.tabButtons[tabName] = tabButton
        
        -- Tab content (auto-sizing)
        local tabContent = Instance.new("Frame")
        tabContent.Name = tabName .. "Content"
        tabContent.Size = UDim2.new(1, 0, 0, 0)  -- Start with 0 height
        tabContent.AutomaticSize = Enum.AutomaticSize.Y  -- Auto-grow to fit children
        tabContent.Position = UDim2.new(0, 0, 0, 60)
        tabContent.BackgroundTransparency = 1
        tabContent.Visible = tabName == "Materials"
        tabContent.Parent = content
        
        self.tabContents[tabName] = tabContent
        
        -- Tab button click
        bind(tabButton.MouseButton1Click, function()
            self:switchTab(tabName)
        end)
    end
    
    -- Populate tabs
    
    -- Create Materials tab using the modular component
    self.materialsTab = MaterialsTab.new({
        parent = self.tabContents.Materials,
        position = UDim2.new(0, 0, 0, 0),
        size = UDim2.new(1, 0, 0, 0),
        portalParent = self.popoverLayer, -- NEW: pass portal for dropdowns
    })
    table.insert(self._widgets, self.materialsTab)
    
    self:createAccountTab(self.tabContents.Account)
    
    -- Set initial active tab
    self:switchTab("Materials")
end

function SettingsPanel:createAccountTab(parent)
    local colors = Theme.colors
    
    -- Account info
    local infoLabel = Instance.new("TextLabel")
    infoLabel.Size = UDim2.new(1, 0, 0, 100)
    infoLabel.Position = UDim2.new(0, 0, 0, 20)
    infoLabel.BackgroundTransparency = 1
    infoLabel.Text = "Account Settings\n\nUsername: " .. game.Players.LocalPlayer.Name .. "\nUserID: " .. game.Players.LocalPlayer.UserId
    infoLabel.TextColor3 = colors.Text
    infoLabel.TextXAlignment = Enum.TextXAlignment.Left
    infoLabel.TextYAlignment = Enum.TextYAlignment.Top
    infoLabel.Font = Theme.fonts.Primary
    infoLabel.TextSize = 18
    infoLabel.Parent = parent
    
    -- TODO: Add more account settings like data export, privacy options, etc.
end

function SettingsPanel:switchTab(tabName: string)
    local colors = Theme.colors
    
    -- Update tab buttons
    for name, button in pairs(self.tabButtons) do
        button.BackgroundTransparency = name == tabName and 0.2 or 0.5
    end
    
    -- Update tab contents
    for name, content in pairs(self.tabContents) do
        content.Visible = name == tabName
    end
end

function SettingsPanel:show()
    if not self.panel then return end
    self.panel:show()
end

function SettingsPanel:hide()
    if not self.panel then return end
    self.panel:hide()
end

function SettingsPanel:cleanup()
    -- Disconnect all connections
    for _, c in ipairs(self._cons) do
        if c and c.Disconnect then
            c:Disconnect()
        end
    end
    self._cons = {}
    
    -- Destroy widgets (dropdowns, tabs, etc.)
    if self._widgets then
        for _, w in ipairs(self._widgets) do
            if w and w.destroy then
                w:destroy()
            end
        end
        self._widgets = {}
    end
    
    -- Cleanup popover layer
    if self.popoverLayer then
        self.popoverLayer:Destroy()
        self.popoverLayer = nil
    end
    
    -- Destroy panel
    if self.panel then
        self.panel:destroy()
        self.panel = nil
    end
    self.frame = nil
end

return SettingsPanel