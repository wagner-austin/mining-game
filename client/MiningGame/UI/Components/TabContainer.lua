--!strict
-- TabContainer.lua
-- Reusable tab navigation component

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UIFolder = MiningGame:WaitForChild("UI")
-- Strict Theme typing mirroring actual Theme
local _Theme = require(UIFolder:WaitForChild("Theme"))
type ThemeTC = typeof(_Theme)
local Theme: ThemeTC = _Theme
local ThemeRefresher = require(UIFolder:WaitForChild("ThemeRefresher"))
local UIx = require(UIFolder:WaitForChild("UIConstants"))

local TabContainer = {}
TabContainer.__index = TabContainer

export type TabDefinition = {
	name: string,
	displayName: string?,
	content: Instance?,
	onSelect: ((name: string) -> ())?,
	onDeselect: ((name: string) -> ())?,
}

export type Props = {
	parent: Instance,
	tabs: { TabDefinition },
	defaultTab: string?,
	position: UDim2?,
	size: UDim2?,
	tabHeight: number?,
	onTabChange: ((newTab: string, oldTab: string?) -> ())?,
	barParent: Instance?,
	contentParent: Instance?,
}

export type TabContainerT = {
	tabs: { TabDefinition },
	onTabChange: ((newTab: string, oldTab: string?) -> ())?,
	currentTab: string?,
	_connections: { RBXScriptConnection },
	container: Frame?,
	tabBar: Frame?,
	contentContainer: Frame?,
	tabButtons: { [string]: TextButton },
	tabContents: { [string]: Frame },
	_tabsCfg: typeof(Theme.tabs)?,
	new: (props: Props) -> TabContainerT,
	switchTab: (self: TabContainerT, tabName: string) -> (),
	getCurrentTab: (self: TabContainerT) -> string?,
	getTabContent: (self: TabContainerT, tabName: string) -> Frame?,
	setTabEnabled: (self: TabContainerT, tabName: string, enabled: boolean) -> (),
	destroy: (self: TabContainerT) -> (),
}

function TabContainer.new(props: Props): TabContainerT
	local self: TabContainerT = setmetatable({} :: any, TabContainer)

	local colors = Theme.colors

	-- Store props
	self.tabs = props.tabs
	self.onTabChange = props.onTabChange
	self.currentTab = props.defaultTab or (props.tabs[1] and props.tabs[1].name)
	self._connections = {}

	-- Main container
	local container = Instance.new("Frame")
	container.Name = "TabContainer"
	container.Size = props.size or UDim2.new(1, 0, 1, 0)
	container.Position = props.position or UIx.Common.ORIGIN
	container.BackgroundTransparency = 1
	container.Parent = props.parent
	self.container = container

	local tabsCfg: typeof(Theme.tabs) = Theme.tabs
	-- Normalize tab height to a definite number
	local hAny = tabsCfg.height
	local computedHeight: number = if typeof(hAny) == "number" then hAny :: number else UIx.Size.ROW_STANDARD
	local propTabHeight = props.tabHeight
	local tabHeight: number
	if typeof(propTabHeight) == "number" then
		tabHeight = propTabHeight
	else
		tabHeight = computedHeight
	end
	local singleTab = (type(props.tabs) == "table" and #props.tabs <= 1)

	-- Tab bar
	local tabBar = Instance.new("Frame")
	tabBar.Name = "TabBar"
	tabBar.Size = UDim2.new(1, 0, 0, singleTab and 0 or tabHeight)
	tabBar.BackgroundTransparency = 1
	tabBar.Parent = (props.barParent or container)
	self.tabBar = tabBar

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	local spacing = tonumber((tabsCfg :: any).spacing) or 0
	tabLayout.Padding = UDim.new(0, spacing)
	tabLayout.Parent = tabBar

	-- Content container
	local contentContainer = Instance.new("Frame")
	contentContainer.Name = "ContentContainer"
	if singleTab then
		contentContainer.Size = UDim2.new(1, 0, 1, 0)
		contentContainer.Position = UDim2.new(0, 0, 0, 0)
		tabBar.Visible = false
	else
		contentContainer.Size = UDim2.new(1, 0, 1, -(tabHeight + spacing))
		contentContainer.Position = UDim2.new(0, 0, 0, tabHeight + spacing)
		tabBar.Visible = true
	end
	contentContainer.BackgroundTransparency = 1
	contentContainer.Parent = (props.contentParent or container)
	self.contentContainer = contentContainer

	-- Persist tabs config for later methods
	self._tabsCfg = tabsCfg

	-- Create tab buttons and content frames
	self.tabButtons = {}
	self.tabContents = {}

	for i, tab in ipairs(props.tabs) do
		-- Tab button
		local tabButton = Instance.new("TextButton")
		tabButton.Name = tab.name .. "Tab"
		tabButton.LayoutOrder = i -- Set order based on array position
		tabButton.Size = UDim2.new(0, UIx.Size.GRID_CELL_PX, 1, 0)
		tabButton.BackgroundColor3 = colors.Surface
		local btnCfgAny: any = (tabsCfg.button or {})
		local inactiveT = btnCfgAny.inactiveTransparency or 0
		tabButton.BackgroundTransparency = inactiveT
		tabButton.Text = tab.displayName or tab.name
		tabButton.TextColor3 = colors.Text
		tabButton.TextScaled = true
		tabButton.Font = Theme.fonts.Primary
		tabButton.AutoButtonColor = false
		tabButton.Selectable = false
		tabButton.Parent = tabBar
		if singleTab then
			tabButton.Visible = false
			tabButton.Active = false
		end

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, Theme.sizes.CornerRadius)
		corner.Parent = tabButton

		local textConstraint = Instance.new("UITextSizeConstraint")
		textConstraint.MinTextSize = Theme.textSizes.Small.Min
		textConstraint.MaxTextSize = Theme.textSizes.Medium.Max
		textConstraint.Parent = tabButton

		-- Bind tab button to theme refresher
		ThemeRefresher.Bind(tabButton, { BackgroundColor3 = "Surface", TextColor3 = "Text" })

		self.tabButtons[tab.name] = tabButton

		-- Tab content frame
		local tabContent = Instance.new("Frame")
		tabContent.Name = tab.name .. "Content"
		tabContent.Size = UDim2.new(1, 0, 1, 0)
		tabContent.BackgroundTransparency = 1
		tabContent.Visible = tab.name == self.currentTab
		tabContent.Parent = contentContainer

		-- Add provided content if any
		if tab.content then
			tab.content.Parent = tabContent
		end

		self.tabContents[tab.name] = tabContent

		-- Tab button interaction
		local conn = tabButton.Activated:Connect(function()
			local SoundManager = require(ReplicatedStorage.MiningGame:WaitForChild("SoundManager"))
			SoundManager.PlayUI("buttonclick")
			self:switchTab(tab.name)
		end)
		table.insert(self._connections, conn)

		-- Hover effects
		local hoverIn = tabButton.MouseEnter:Connect(function()
			if tab.name ~= self.currentTab then
				local b = (tabsCfg.button or {}) :: any
				local hoverT = b.hoverTransparency or 0
				TweenService:Create(tabButton, TweenInfo.new(UIx.Anim.QUICK), {
					BackgroundTransparency = hoverT,
				}):Play()
			end
		end)
		table.insert(self._connections, hoverIn)

		local hoverOut = tabButton.MouseLeave:Connect(function()
			if tab.name ~= self.currentTab then
				local b = (tabsCfg.button or {}) :: any
				local inactiveT2 = b.inactiveTransparency or 0
				TweenService:Create(tabButton, TweenInfo.new(UIx.Anim.QUICK), {
					BackgroundTransparency = inactiveT2,
				}):Play()
			end
		end)
		table.insert(self._connections, hoverOut)
	end

	-- Set initial active tab
	if self.currentTab then
		self:switchTab(self.currentTab)
	end

	return self
end

function TabContainer:switchTab(tabName: string)
	-- Validate tab exists
	if not self.tabButtons[tabName] then
		warn("Tab '" .. tabName .. "' does not exist")
		return
	end

	local oldTab = self.currentTab

	-- Find tab definition
	local newTabDef = nil
	local oldTabDef = nil
	for _, tab in ipairs(self.tabs) do
		if tab.name == tabName then
			newTabDef = tab
		end
		if tab.name == oldTab then
			oldTabDef = tab
		end
	end

	-- Call deselect callback for old tab
	if oldTab and oldTabDef and oldTabDef.onDeselect then
		oldTabDef.onDeselect(oldTab)
	end

	-- Update tab buttons
	for name, button in pairs(self.tabButtons) do
		local tabsAny: any = (self._tabsCfg or Theme.tabs)
		local b = (tabsAny.button or {})
		local activeT = b.activeTransparency or 0
		local inactiveT = b.inactiveTransparency or 0
		TweenService:Create(button, TweenInfo.new(UIx.Anim.MEDIUM), {
			BackgroundTransparency = if name == tabName then activeT else inactiveT,
		}):Play()
	end

	-- Update tab contents
	for name, content in pairs(self.tabContents) do
		content.Visible = name == tabName
	end

	self.currentTab = tabName

	-- Call select callback for new tab
	if newTabDef and newTabDef.onSelect then
		newTabDef.onSelect(tabName)
	end

	-- Call general change callback
	if self.onTabChange then
		self.onTabChange(tabName, oldTab)
	end
end

function TabContainer:getCurrentTab(): string?
	return self.currentTab
end

function TabContainer:getTabContent(tabName: string): Frame?
	return self.tabContents[tabName]
end

function TabContainer:setTabEnabled(tabName: string, enabled: boolean)
	local button = self.tabButtons[tabName]
	if button then
		button.Active = enabled
		button.AutoButtonColor = enabled
		button.Selectable = enabled
		local tabsAny2: any = (self._tabsCfg or Theme.tabs)
		local b = (tabsAny2.button or {})
		local disabledTextT = b.disabledTextTransparency or 0.5
		local disabledT = b.disabledTransparency or 0.5
		local activeT = b.activeTransparency or 0
		local inactiveT = b.inactiveTransparency or 0
		button.TextTransparency = if enabled then 0 else disabledTextT
		button.BackgroundTransparency = if enabled
			then (if tabName == self.currentTab then activeT else inactiveT)
			else disabledT
	end
end

function TabContainer:destroy()
	-- Disconnect all connections
	for _, conn in ipairs(self._connections) do
		if conn then
			conn:Disconnect()
		end
	end
	self._connections = {}

	-- Destroy container
	if self.container then
		self.container:Destroy()
		self.container = nil :: any
	end
end

return TabContainer
