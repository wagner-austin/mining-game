--!strict
-- InventoryPanel.lua
-- Inventory scene with category filters and sticky Sell All for resources

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UIFolder = MiningGame:WaitForChild("UI")
-- Strict Theme typing mirrors actual Theme.lua
local _Theme = require(UIFolder:WaitForChild("Theme"))
type ThemeIP = typeof(_Theme)
local Theme: ThemeIP = _Theme
local ThemeRefresher = require(UIFolder:WaitForChild("ThemeRefresher"))
local UIx = require(UIFolder:WaitForChild("UIConstants"))
local Time = require(MiningGame:WaitForChild("Time"))
local ClientRF = require(MiningGame:WaitForChild("ClientRF"))

local TabbedPanel = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("TabbedPanel"))
local InventoryTab = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("InventoryTab"))
local BaseChip = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("BaseChip"))
local Dropdown = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("Dropdown"))
local BaseTabComponent = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("BaseTabComponent"))

local InventoryPanel = {}
InventoryPanel.__index = InventoryPanel

-- Types
type ChipFns = {
	setBackgroundColor: (c: Color3) -> (),
	setTextColor: (c: Color3) -> (),
	setText: (s: string) -> (),
	destroy: () -> (),
}
type ManagerI = {
	container: Frame,
	showScene: (self: ManagerI, name: string) -> (),
	hideScene: (self: ManagerI, name: string) -> (),
	showNotification: ((self: ManagerI, message: string, kind: string) -> ())?,
}
type Destroyable = { destroy: (self: Destroyable) -> () }
type SnapshotWithProfile = { profile: { equipped: { [string]: string? }?, inventory: { [string]: number }? } }
type AccountProviderI = {
	getSnapshot: (self: AccountProviderI) -> SnapshotWithProfile?,
	onChanged: (self: AccountProviderI) -> RBXScriptSignal,
}
type Providers = { accountDataProvider: AccountProviderI? }
type InvTabFns = {
	refresh: () -> (),
	setActive: (boolean) -> (),
	setCategory: (string) -> (),
	setFilters: (string, string) -> (),
}

export type InventoryPanelT = {
	name: string,
	frame: Frame?,
	panel: TabbedPanel.TabbedPanelT?,
	manager: ManagerI?,
	_providers: Providers,
	_widgets: { Instance | Destroyable },
	_invTab: BaseTabComponent.BaseTab?,
	_sellBar: Frame?,
	_sellChip: ChipFns?,
	_sellableCount: number?,
	_sellableValue: number?,
	_selling: boolean?,
	_activeCategory: string?,
	_rarityFilter: string?,
	_searchQuery: string?,
	_confirmSellUntil: number?,
}

function InventoryPanel.new(providers: Providers?)
	local self: InventoryPanelT = {
		name = "InventoryPanel",
		frame = nil,
		panel = nil,
		manager = nil,
		_providers = providers or {},
		_widgets = {},
		_invTab = nil,
		_sellBar = nil,
		_sellChip = nil,
		_sellableCount = 0,
		_sellableValue = 0,
		_selling = false,
		_activeCategory = "resources",
		_rarityFilter = "all",
		_searchQuery = "",
		_confirmSellUntil = 0,
	}
	setmetatable(self, InventoryPanel)
	return self
end

function InventoryPanel:init(manager: ManagerI)
	if self.frame then
		return
	end
	self.manager = manager

	-- Build a single-tab TabbedPanel for consistent spacing/behavior with Settings
	local tabs = { { name = "Inventory" } }
	self.panel = TabbedPanel.new({
		parent = manager.container,
		title = "Inventory",
		tintColor = Theme.colors.Background,
		transition = "scale",
		scrim = true,
		closeOnEsc = true,
		onClose = function()
			manager:hideScene(self.name)
		end,
		tabs = tabs,
		defaultTab = "Inventory",
		onShown = function()
			local it = self._invTab
			if it and it.refresh then
				it:refresh()
			end
			if it and it.setActive then
				it:setActive(true)
			end
		end,
		onHidden = function()
			local it = self._invTab
			if it and it.setActive then
				it:setActive(false)
			end
		end,
	})

	-- Expose frame to UIManager
	self.frame = self.panel.container

	-- Work within the tab's content root
	local content = self.panel:getTabContent("Inventory") or self.panel:getContent()
	-- Stack children vertically inside the tab content (filter row above list)
	do
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, UIx.Spacing.MD)
		layout.Parent = content
	end
	-- Ensure content leaves space for sticky Sell Bar at bottom
	do
		local pad = Instance.new("UIPadding")
		pad.PaddingBottom = UDim.new(0, UIx.Size.BUTTON_MEDIUM_HEIGHT + UIx.Spacing.SECTION * 2)
		pad.Parent = content
	end

	-- Utility: wrap a BaseChip instance into plain function calls (no self parameter)
	local function wrapChip(b: any): ChipFns
		return {
			setBackgroundColor = function(c: Color3)
				b:setBackgroundColor(c)
			end,
			setTextColor = function(c: Color3)
				b:setTextColor(c)
			end,
			setText = function(s: string)
				b:setText(s)
			end,
			destroy = function()
				b:destroy()
			end,
		}
	end

	-- Filter bar: category chips + rarity dropdown + search
	local filterRow = Instance.new("Frame")
	filterRow.Name = "FilterBar"
	filterRow.BackgroundTransparency = 1
	filterRow.Size = UDim2.new(1, 0, 0, UIx.Size.ROW_LARGE)
	filterRow.LayoutOrder = 1
	filterRow.Parent = content

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.Padding = UDim.new(0, UIx.Spacing.SM)
	rowLayout.Parent = filterRow

	local filterChips = {}
	local function styleFilter()
		for k, chip in pairs(filterChips) do
			local active = (k == (self._activeCategory or "resources"))
			if active then
				chip:setBackgroundColor(Theme.colors.Primary)
				chip:setTextColor(Theme.colors.OnPrimary)
			else
				chip:setBackgroundColor(Theme.colors.Surface)
				chip:setTextColor(Theme.colors.Text)
			end
		end
	end

	-- Forward declaration for unified category switching
	local switchCategory

	local function makeFilterChip(kind: string, label: string)
		local slot = Instance.new("Frame")
		slot.BackgroundTransparency = 1
		slot.Size = UDim2.new(0, 130, 1, 0)
		slot.Parent = filterRow
		local chip = BaseChip.new({
			parent = slot,
			size = UDim2.new(1, 0, 1, -6),
			text = label,
			onClick = function()
				if switchCategory then
					switchCategory(kind, false)
				end
			end,
		})
		filterChips[kind] = chip
	end

	makeFilterChip("resources", "Resources")
	makeFilterChip("cosmetics", "Cosmetics")
	makeFilterChip("consumables", "Consumables")
	styleFilter()

	-- Rarity dropdown
	-- Build rarity options dynamically from ItemDefinitions
	local rarityOptions = {}
	do
		local ItemDefinitions = require(MiningGame:WaitForChild("ItemDefinitions"))
		table.insert(rarityOptions, { id = "all", label = "All" })
		local rks = ItemDefinitions.rarities()
		table.sort(rks)
		local function title(s)
			s = tostring(s or ""):lower()
			return s:sub(1, 1):upper() .. s:sub(2)
		end
		for _, key in ipairs(rks) do
			local up = tostring(key):upper()
			table.insert(rarityOptions, { id = up, label = title(key) })
		end
	end
	-- Simple layout recalculation placeholder (filter updates trigger grid refresh via InventoryTab)
	-- Define forward so closures may reference safely
	local recalc: () -> ()
	local raritySlot = Instance.new("Frame")
	raritySlot.BackgroundTransparency = 1
	raritySlot.Size = UDim2.new(0, UIx.Size.GRID_CELL_PX * 2 - UIx.Spacing.SECTION * 2, 1, 0)
	raritySlot.Parent = filterRow
	Dropdown.new({
		parent = raritySlot,
		portalParent = (self.panel and self.panel.popoverLayer) or nil,
		size = UDim2.new(1, 0, 1, -6),
		options = rarityOptions,
		placeholder = "Rarity: All",
		onSelect = function(opt)
			self._rarityFilter = (opt and opt.id) or "all"
			if type(recalc) == "function" then
				recalc()
			end
			-- Also update the InventoryTab grid filters
			local it = self._invTab
			if it and it.setFilters then
				it:setFilters(self._rarityFilter, self._searchQuery)
			end
		end,
	})

	-- Search box
	local searchSlot = Instance.new("Frame")
	searchSlot.BackgroundTransparency = 1
	searchSlot.Size = UDim2.new(0, UIx.Size.GRID_CELL_PX * 2 + UIx.Spacing.SECTION * 2, 1, 0)
	searchSlot.Parent = filterRow
	local search = Instance.new("TextBox")
	search.Size = UDim2.new(1, 0, 1, -UIx.Spacing.SM)
	search.BackgroundColor3 = Theme.colors.Surface
	search.BackgroundTransparency = Theme.card.backgroundTransparency
	search.Text = ""
	search.PlaceholderText = "Search"
	search.TextColor3 = Theme.colors.Text
	search.TextScaled = true
	search.Font = Theme.fonts.Primary
	search.Parent = searchSlot
	local sCorner = Instance.new("UICorner")
	sCorner.CornerRadius = UDim.new(0, Theme.sizes.CornerRadius)
	sCorner.Parent = search
	local sPad = Instance.new("UIPadding")
	sPad.PaddingLeft = UDim.new(0, UIx.Spacing.MD)
	sPad.PaddingRight = UDim.new(0, UIx.Spacing.MD)
	sPad.Parent = search

	-- Define unified category switching now that search exists in scope
	switchCategory = function(kind: string, resetSearch: boolean?)
		self._activeCategory = kind
		if resetSearch then
			search.Text = ""
			self._searchQuery = ""
			do
				local it = self._invTab
				if it and it.setFilters then
					it:setFilters(self._rarityFilter, self._searchQuery)
				end
			end
		end
		local it = self._invTab
		if it and it.setCategory then
			it:setCategory(kind)
		end
		styleFilter()
		if type(recalc) == "function" then
			recalc()
		end
	end

	-- Equipment bar (quick overview of equipped cosmetics per slot)
	local equipBar = Instance.new("Frame")
	equipBar.Name = "EquipmentBar"
	equipBar.BackgroundTransparency = 1
	equipBar.Size = UDim2.new(1, 0, 0, UIx.Size.ROW_LARGE)
	equipBar.LayoutOrder = 2
	equipBar.Parent = content
	do
		local el = Instance.new("UIListLayout")
		el.FillDirection = Enum.FillDirection.Horizontal
		el.VerticalAlignment = Enum.VerticalAlignment.Center
		el.Padding = UDim.new(0, UIx.Spacing.SM)
		el.Parent = equipBar
	end
	local slotOrder = { "aura", "trail", "back", "head", "hand" }
	local slotLabels = { aura = "Aura", trail = "Trail", back = "Back", head = "Head", hand = "Hand" }
	local slotChips: { [string]: ChipFns } = {}
	local function renderEquipChip(slotId: string, label: string, text: string?, isEmpty: boolean)
		local holder = Instance.new("Frame")
		holder.BackgroundTransparency = 1
		holder.Size = UDim2.new(0, 160, 1, 0)
		holder.Parent = equipBar
		local chipInst = BaseChip.new({
			parent = holder,
			size = UDim2.new(1, 0, 1, -6),
			text = (label .. ": " .. (text or "Empty")),
			onClick = function()
				-- Nudge user to cosmetics tab via unified handler
				if switchCategory then
					switchCategory("cosmetics", true)
				end
			end,
		})
		local chip = wrapChip(chipInst)
		slotChips[slotId] = chip
		local c = slotChips[slotId]
		if c then
			if isEmpty then
				c.setBackgroundColor(Theme.colors.Surface)
				c.setTextColor(Theme.colors.TextDim or Theme.colors.Text)
			else
				c.setBackgroundColor(Theme.colors.Surface)
				c.setTextColor(Theme.colors.Text)
			end
		end
	end
	for _, sid in ipairs(slotOrder) do
		renderEquipChip(sid, slotLabels[sid] or sid, nil, true)
	end

	local function updateEquipBar()
		local provider = self._providers and self._providers.accountDataProvider
		local snap = provider and provider:getSnapshot()
		local equipped = (snap and snap.profile and snap.profile.equipped) or {}
		-- ItemDefinitions for names
		local ItemDefinitions = require(MiningGame:WaitForChild("ItemDefinitions"))
		for _, sid in ipairs(slotOrder) do
			local chip = slotChips[sid]
			if chip then
				local id = equipped[sid]
				if type(id) == "string" and id ~= "" then
					local def = ItemDefinitions.get(id)
					chip.setText((slotLabels[sid] or sid) .. ": " .. (def and def.name or id))
					chip.setTextColor(Theme.colors.Text)
				else
					chip.setText((slotLabels[sid] or sid) .. ": Empty")
					chip.setTextColor(Theme.colors.TextDim or Theme.colors.Text)
				end
			end
		end
	end
	search.FocusLost:Connect(function()
		self._searchQuery = string.lower(search.Text or "")
		local it = self._invTab
		if it and it.setFilters then
			it:setFilters(self._rarityFilter, self._searchQuery)
		end
	end)

	local function setFilterEnabled(enabled: boolean)
		-- Rarity dropdown and Search removed from Resources tab; keep them hidden
		raritySlot.Visible = false
		searchSlot.Visible = false
		-- Preserve Sell Bar visibility control via this toggle
		if self._sellBar then
			self._sellBar.Visible = enabled
		end
	end

	-- Inventory content (reuse InventoryTab component)
	local tabRoot = Instance.new("Frame")
	tabRoot.Name = "InventoryContent"
	tabRoot.BackgroundTransparency = 1
	tabRoot.Size = UDim2.new(1, 0, 0, 0)
	tabRoot.AutomaticSize = Enum.AutomaticSize.Y
	tabRoot.Parent = content

	local Types = require(ReplicatedStorage:WaitForChild("MiningGame"):WaitForChild("Types"))
	local rawProvider = self._providers and self._providers.accountDataProvider or nil
	local adapter
	if rawProvider then
		adapter = {
			getSnapshot = function(_self)
				local snap = rawProvider:getSnapshot()
				local out: { [string]: Types.JsonValue } = {}
				if snap then
					out.profile = snap.profile
				end
				return out
			end,
			onChanged = function(_self)
				return rawProvider:onChanged()
			end,
		}
	end
	local invTabFull = InventoryTab.new({
		parent = tabRoot,
		dataProvider = adapter,
	})
	self._invTab = invTabFull
	-- Ensure InventoryTab renders below the filter bar
	tabRoot.LayoutOrder = 2
	if switchCategory then
		switchCategory(self._activeCategory or "resources", false)
	end
	table.insert(self._widgets, invTabFull)

	-- Sticky Sell Bar (bottom)
	local sellBar = Instance.new("Frame")
	sellBar.Name = "SellBar"
	sellBar.BackgroundTransparency = Theme.card and Theme.card.backgroundTransparency or 0.1
	sellBar.BackgroundColor3 = Theme.colors.Surface
	-- Align width to BasePanel content padding
	sellBar.AnchorPoint = Vector2.new(0, 1)
	sellBar.Position = UDim2.new(0, Theme.basePanel.contentPadding, 1, -UIx.Spacing.SM)
	sellBar.Size = UDim2.new(1, -Theme.basePanel.contentPadding * 2, 0, UIx.Size.BUTTON_MEDIUM_HEIGHT)
	sellBar.ZIndex = 3
	-- Parent to BasePanel's content layer so it animates with the panel
	local contentLayer = self.panel.getContentLayer and self.panel:getContentLayer() or self.panel.container
	sellBar.Parent = contentLayer
	ThemeRefresher.Bind(sellBar, { BackgroundColor3 = "Surface" })
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UIx.corner()
	barCorner.Parent = sellBar
	local barStroke = Instance.new("UIStroke")
	barStroke.Thickness = 1
	barStroke.Transparency = 0.6
	barStroke.Color = Theme.colors.Text
	barStroke.Parent = sellBar
	self._sellBar = sellBar

	local barLayout = Instance.new("UIListLayout")
	barLayout.FillDirection = Enum.FillDirection.Horizontal
	barLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	barLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	barLayout.Padding = UDim.new(0, UIx.Spacing.MD)
	barLayout.Parent = sellBar

	local summary = Instance.new("TextLabel")
	summary.Name = "Summary"
	summary.BackgroundTransparency = 1
	summary.Text = "Resources: none"
	summary.Font = Theme.fonts.Primary
	summary.TextScaled = true
	summary.TextColor3 = Theme.colors.Text
	ThemeRefresher.Bind(summary, { TextColor3 = "Text" })
	summary.Size = UDim2.new(1, -UIx.Size.BUTTON_WIDTH - UIx.Spacing.SECTION, 1, 0)
	summary.TextXAlignment = Enum.TextXAlignment.Left
	summary.Parent = sellBar

	local chipSlot = Instance.new("Frame")
	chipSlot.BackgroundTransparency = 1
	chipSlot.Size = UDim2.new(0, UIx.Size.BUTTON_WIDTH, 1, 0)
	chipSlot.Parent = sellBar

	local sellChipWrapped
	do
		local chipInst = BaseChip.new({
			parent = chipSlot,
			size = UDim2.new(0, UIx.Size.BUTTON_WIDTH, 0, UIx.Size.BUTTON_MEDIUM_HEIGHT - 6),
			icon = (Theme.icons and Theme.icons.currency and Theme.icons.currency.coins) or "$",
			text = "Sell All",
			onClick = function()
				if self._activeCategory ~= "resources" then
					return
				end
				if self._selling then
					return
				end
				local provider = self._providers and self._providers.accountDataProvider
				local snap = provider and provider:getSnapshot()
				local inv = {}
				if type(snap) == "table" then
					local prof = rawget(snap, "profile")
					if type(prof) == "table" then
						local invVal = rawget(prof, "inventory")
						if type(invVal) == "table" then
							inv = invVal
						end
					end
				end
				local ItemDefinitions = require(MiningGame:WaitForChild("ItemDefinitions"))
				local raritySel = string.upper(self._rarityFilter or "all")
				local term = string.lower(self._searchQuery or "")
				local sellMap = {}
				local total = 0
				for id, count in pairs(inv) do
					local d = ItemDefinitions.get(id)
					if d and d.type == "resource" and d.value and d.value > 0 and count > 0 then
						local okRarity = (raritySel == "ALL") or (string.upper(d.rarity or "") == raritySel)
						local name = string.lower(d.name or id)
						local okSearch = (term == "") or (string.find(name, term, 1, true) ~= nil)
						if okRarity and okSearch then
							sellMap[id] = count
							total += (d.value * count)
						end
					end
				end
				if next(sellMap) == nil then
					return
				end
				local now = Time.mono()
				local confirmUntil = self._confirmSellUntil or 0
				if (confirmUntil <= 0) or (now > confirmUntil) then
					self._confirmSellUntil = now + 2.0
					if self._sellChip then
						self._sellChip.setText("Confirm")
						self._sellChip.setBackgroundColor(Theme.colors.Error)
						self._sellChip.setTextColor(Theme.colors.OnPrimary)
					end
					task.delay(2.0, function()
						if self and self._sellChip and not self._selling then
							self._sellChip.setText("Sell All")
							if self._sellableCount and self._sellableCount > 0 then
								self._sellChip.setBackgroundColor(Theme.colors.Primary)
								self._sellChip.setTextColor(Theme.colors.OnPrimary)
							else
								self._sellChip.setBackgroundColor(Theme.colors.Surface)
								self._sellChip.setTextColor(Theme.colors.TextDim)
							end
						end
					end)
					return
				end
				self._confirmSellUntil = 0
				self._selling = true
				if self._sellChip then
					self._sellChip.setText("Selling...")
				end
				task.spawn(function()
					local res, err = ClientRF.call("SellItems", sellMap)
					self._selling = false
					if self._sellChip then
						self._sellChip.setText("Sell All")
					end
					local mgr = self.manager
					local notify = mgr and mgr.showNotification
					if (err or not (res and res.success)) and notify and mgr then
						notify(mgr, err or (res and res.reason) or "Sell failed", "error")
					end
					recalc()
				end)
			end,
		})
		sellChipWrapped = wrapChip(chipInst)
	end
	self._sellChip = sellChipWrapped

	recalc = function()
		local provider = self._providers and self._providers.accountDataProvider
		local snap = provider and provider:getSnapshot()
		local inv = {}
		if type(snap) == "table" then
			local prof = rawget(snap, "profile")
			if type(prof) == "table" then
				local invVal = rawget(prof, "inventory")
				if type(invVal) == "table" then
					inv = invVal
				end
			end
		end
		local activeCat = (self._activeCategory or "resources")
		if activeCat ~= "resources" then
			self._sellableCount = 0
			self._sellableValue = 0
			summary.Text = "Sell not available for this category"
			if self._sellChip then
				self._sellChip.setBackgroundColor(Theme.colors.Surface)
				self._sellChip.setTextColor(Theme.colors.TextDim)
			end
			setFilterEnabled(false)
			return
		end
		setFilterEnabled(true)
		local ItemDefinitions = require(MiningGame:WaitForChild("ItemDefinitions"))
		local raritySel = string.upper(self._rarityFilter or "all")
		local term = string.lower(self._searchQuery or "")
		local cnt, val = 0, 0
		for id, count in pairs(inv) do
			local d = ItemDefinitions.get(id)
			if d and d.type == "resource" and d.value and d.value > 0 and count > 0 then
				local okRarity = (raritySel == "ALL") or (string.upper(d.rarity or "") == raritySel)
				local name = string.lower(d.name or id)
				local okSearch = (term == "") or (string.find(name, term, 1, true) ~= nil)
				if okRarity and okSearch then
					cnt += count
					val += (d.value * count)
				end
			end
		end
		self._sellableCount = cnt
		self._sellableValue = val
		if cnt > 0 then
			-- Normalize summary formatting (avoid stray control chars)
			summary.Text = string.format("Resources: %d items for %s coins", cnt, tostring(val))
			if self._sellChip then
				self._sellChip.setBackgroundColor(Theme.colors.Primary)
				self._sellChip.setTextColor(Theme.colors.OnPrimary)
			end
		else
			summary.Text = "Resources: none"
			if self._sellChip then
				self._sellChip.setBackgroundColor(Theme.colors.Surface)
				self._sellChip.setTextColor(Theme.colors.TextDim)
			end
		end
		-- Sanitize any control characters from summary (guards against stray encoding)
		summary.Text = (summary.Text or ""):gsub("%c", " ")
	end
	-- Initialize via unified category switch for consistent behavior
	if switchCategory then
		switchCategory(self._activeCategory or "resources", false)
	end

	local provider = self._providers and self._providers.accountDataProvider
	if provider and provider.onChanged then
		provider:onChanged():Connect(function()
			recalc()
			updateEquipBar()
		end)
	end
	-- Initial equipment render
	updateEquipBar()
end

function InventoryPanel:show(): ()
	if not self.panel then
		return
	end
	self.panel:show()
	-- Activation and refresh handled by TabbedPanel onShown callback
end

function InventoryPanel:hide(): ()
	if not self.panel then
		return
	end
	self.panel:hide()
end

return InventoryPanel
