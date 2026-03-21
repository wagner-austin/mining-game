--!strict

-- InventoryTab.lua ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â modular inventory display with equip/unequip functionality

-- Migrated to use BaseTabComponent for consistent UI patterns

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")

local UIFolder = MiningGame:WaitForChild("UI")

local UIx = require(UIFolder:WaitForChild("UIConstants"))

local ItemDefinitions = require(MiningGame:WaitForChild("ItemDefinitions"))

local Logger = require(MiningGame:WaitForChild("Logger"))

local ClientRF = require(MiningGame:WaitForChild("ClientRF"))

local PlayerProfileGuard = require(MiningGame:WaitForChild("PlayerProfileGuard"))
local ClientError = require(MiningGame:WaitForChild("ClientError"))

local BaseTabComponent = require(script.Parent:WaitForChild("BaseTabComponent"))

local log = Logger.new("InventoryTab")

local InventoryTab = {}

InventoryTab.__index = InventoryTab

setmetatable(InventoryTab, { __index = BaseTabComponent })

type Props = {

	parent: GuiObject,

	position: UDim2?,

	size: UDim2?,

	dataProvider: BaseTabComponent.DataProvider?,
}

export type InventoryTabT = BaseTabComponent.BaseTab & {

	_itemButtons: { [string]: TextButton },

	_inventory: { [string]: number },

	_equipped: { [string]: string },

	_rfBusy: { [string]: boolean },

	_dirty: boolean,

	_updateScheduled: boolean,

	_animationTasks: { thread },

	_active: boolean,

	_pendingRefresh: boolean,

	_snapshotDebounce: thread?,
	_rarityFilter: string,
	_searchQuery: string,

	-- section roots
	cosmeticsGrid: ScrollingFrame?,
	resourcesGrid: ScrollingFrame?,
	consumablesGrid: ScrollingFrame?,

	-- local method declarations for analyzer
	_sectionCard: (self: InventoryTabT, title: string, minHeight: number?) -> (Frame, ScrollingFrame),
	_createCosmeticsSection: (self: InventoryTabT) -> (),
	_createResourcesSection: (self: InventoryTabT) -> (),
	_createConsumablesSection: (self: InventoryTabT) -> (),
	_createItemButton: (self: InventoryTabT, itemId: string, count: number) -> TextButton?,
	_toggleEquip: (self: InventoryTabT, itemId: string, slot: string) -> (),
	_useConsumable: (self: InventoryTabT, itemId: string, _button: TextButton?, onDone: (() -> ())?) -> (),
	_updateDisplay: (self: InventoryTabT) -> (),
	_refreshInventory: (self: InventoryTabT) -> (),
	_applySnapshot: (self: InventoryTabT, snapshot: InvSnapshot) -> (),
	_onInventoryChanged: (self: InventoryTabT, change: any) -> (),
	_markDirtyAndSchedule: (self: InventoryTabT) -> (),
	setActive: (self: InventoryTabT, isActive: boolean) -> (),
	refresh: (self: InventoryTabT) -> (),

	new: (props: Props) -> InventoryTabT,
}

function InventoryTab.new(props: Props): InventoryTabT
	-- Initialize base component with stacked=true for vertical sections
	local baseAny: any = BaseTabComponent.new({
		parent = props.parent,
		position = props.position,
		size = props.size,
		dataProvider = props.dataProvider,
		stacked = true,
		name = "InventoryTab",
	})
	local self: InventoryTabT = setmetatable(baseAny, InventoryTab)

	-- Tab-specific state

	self._itemButtons = {}
	-- RF-in-flight flags per item to prevent double-consume from rapid/double clicks
	self._rfBusy = {}

	self._inventory = {}

	self._equipped = {}

	self._dirty = false

	self._updateScheduled = false

	self._animationTasks = {} -- Track animation tasks for cleanup

	self._active = false -- Only rebuild UI when tab is active/visible

	self._pendingRefresh = false -- Remember to refresh once we become active

	self._snapshotDebounce = nil -- handle for debounced snapshot applies

	self._rarityFilter = "ALL"

	self._searchQuery = ""

	-- Create sections

	self:_createCosmeticsSection()

	self:_createResourcesSection()

	self:_createConsumablesSection()

	-- Inventory changes now handled via dataProvider (see connectDataProvider below)

	-- Hook data provider if available (base handles initial connection)

	if props.dataProvider then
		self:connectDataProvider(props.dataProvider, function(snapshot, key, value)
			-- Prefer incremental updates for inventory deltas

			if key == "inventoryDelta" and typeof(value) == "table" then
				-- Apply delta to local cache and schedule an update

				for itemId, inc in pairs(value) do
					local curr = self._inventory[itemId] or 0

					local nextVal = (curr + (inc :: number))

					if nextVal > 0 then
						self._inventory[itemId] = nextVal
					else
						self._inventory[itemId] = nil
						-- If this was a consumable reaching zero, remove any lingering tile immediately
						if self.consumablesGrid then
							local stale = self.consumablesGrid:FindFirstChild(itemId)
							if stale and stale:IsA("TextButton") then
								ClientError.try("InventoryTab.DestroyStaleTile", function()
									stale:Destroy()
								end)
							end
						end
					end
				end

				-- Batch UI rebuilds

				self:_markDirtyAndSchedule()

				return
			end

			-- Fall back to snapshot application with a short debounce to avoid churn

			if self._snapshotDebounce then
				self:clearTimeout(self._snapshotDebounce)

				self._snapshotDebounce = nil
			end

			self._snapshotDebounce = self:setTimeout(0.15, function()
				self._snapshotDebounce = nil
				local prof: any = snapshot and (snapshot :: any).profile or nil
				self:_applySnapshot({ profile = prof })
			end)
		end)
	else
		log:warn("No dataProvider, using direct remote")

		-- Request initial data if no provider

		self:_refreshInventory()
	end

	return self
end

function InventoryTab:_sectionCard(title: string, minHeight: number?): (Frame, ScrollingFrame)
	local card = self:createSectionCard(self.container, {

		size = UDim2.new(1, 0, 0, minHeight or UIx.Size.INVENTORY_MIN_HEIGHT),

		autoSize = false,
	})

	-- Title

	self:createSectionTitle(card, title)

	-- Scrolling grid

	local scroll = Instance.new("ScrollingFrame")

	scroll.Name = "Grid"

	scroll.Size = UDim2.new(1, 0, 1, -UIx.Size.BUTTON_SMALL_HEIGHT)

	scroll.BackgroundTransparency = 1

	scroll.ScrollBarThickness = UIx.Spacing.TINY

	scroll.ScrollBarImageColor3 = self._theme.colors.TextSecondary or self._theme.colors.Text

	scroll.CanvasSize = UIx.Common.ORIGIN

	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y

	scroll.Parent = card

	self:bindToTheme(scroll, { ScrollBarImageColor3 = "TextSecondary" })

	local gridLayout = Instance.new("UIGridLayout")

	gridLayout.CellSize = UDim2.new(0, UIx.Size.INVENTORY_CELL_WIDTH, 0, UIx.Size.INVENTORY_CELL_HEIGHT)

	gridLayout.CellPadding = UDim2.new(0, UIx.Spacing.SM, 0, UIx.Spacing.SM)

	gridLayout.FillDirection = Enum.FillDirection.Horizontal

	gridLayout.SortOrder = Enum.SortOrder.Name

	gridLayout.Parent = scroll

	return (card :: any) :: Frame, scroll
end

function InventoryTab:_createCosmeticsSection()
	local _card, grid = self:_sectionCard("Cosmetics", UIx.Size.INVENTORY_MIN_HEIGHT + 50)

	self.cosmeticsGrid = grid
end

function InventoryTab:_createResourcesSection()
	local _card, grid = self:_sectionCard("Resources", UIx.Size.INVENTORY_MIN_HEIGHT + 50)

	self.resourcesGrid = grid
end

function InventoryTab:_createConsumablesSection()
	local _card, grid = self:_sectionCard("Consumables", UIx.Size.INVENTORY_MIN_HEIGHT + 50)

	self.consumablesGrid = grid
end

function InventoryTab:_createItemButton(itemId: string, count: number): TextButton?
	-- Get item definition via unified ItemDefinitions

	local itemDef = ItemDefinitions.get(itemId)

	if not itemDef then
		log:warn("Unknown item: %s", itemId)
		return nil
	end

	local ItemTileRenderer = require(script.Parent:WaitForChild("ItemTileRenderer"))

	-- Adapt ItemDefinitions.Item into ItemTileRenderer.ItemData shape
	local it: any = itemDef
	local data = {
		id = it and it.id or itemId,
		type = it and it.type or nil,
		slot = it and it.slot or nil,
		rarity = it and tostring(it.rarity or "") or "",
		icon = (it and it.meta and it.meta.icon) or nil,
		meta = it and it.meta or nil,
	}

	local tile = ItemTileRenderer.create({
		item = data,
		sizeMode = "grid",
		backgroundTransparency = 0.1,
		rarityEffects = true,
	})

	local button = tile.button

	-- Cache rarity data for later label effects (may be nil)

	-- Item display via shared renderer

	local itemDisplay = tile.helpers.addSymbol(data)

	-- Rarity effects already applied automatically by renderer when enabled
	-- Item name via shared renderer

	local displayName = (itemDef.name or itemId):gsub("_", " ")

	displayName = displayName:sub(1, 1):upper() .. displayName:sub(2):lower()

	local nameLabel = tile.helpers.addNameLabel(displayName, { useRarityColor = true, item = data })

	-- Count badge via shared renderer

	tile.helpers.addCountBadge(count)
	tile.helpers.applyOwnershipVisuals(data, count, { symbol = itemDisplay, name = nameLabel })

	-- Equipped indicator via shared renderer

	if itemDef.type == "cosmetic" and itemDef.slot and self._equipped[itemDef.slot] == itemId then
		tile.helpers.showEquippedOverlay()
	end

	-- Click handler

	self:addConnection(button.MouseButton1Click:Connect(function()
		if itemDef.type == "cosmetic" and itemDef.slot then
			self:_toggleEquip(itemId, itemDef.slot)
		elseif itemDef.type == "consumable" then
			-- Client-side debounce: prevent rapid double-activation
			if self._rfBusy[itemId] then
				return
			end
			self._rfBusy[itemId] = true
			-- Temporarily disable the button to avoid repeated clicks
			local prevAuto = button.AutoButtonColor
			local prevActive = button.Active
			button.AutoButtonColor = false
			button.Active = false
			self:_useConsumable(itemId, button, function()
				if button and button.Parent then
					button.AutoButtonColor = prevAuto
					button.Active = prevActive
				end
				self._rfBusy[itemId] = nil
			end)
		end

		-- Resources just display, can't be used directly
	end))

	-- Hover handled by shared renderer

	return button
end

function InventoryTab:_toggleEquip(itemId: string, slot: string)
	if self._equipped[slot] == itemId then
		-- Unequip

		task.spawn(function()
			local result, err = ClientRF.call("UnequipItem", slot)

			if not err and result and result.success then
				log:info("Unequipped %s", itemId)

				PlayerProfileGuard.clearCache() -- Bust cache for immediate UI update
			else
				log:warn("Failed to unequip: %s", err or (result and result.reason) or "unknown")
			end
		end)
	else
		-- Equip

		task.spawn(function()
			local result, err = ClientRF.call("EquipItem", itemId)

			if not err and result and result.success then
				log:info("Equipped %s", itemId)

				PlayerProfileGuard.clearCache() -- Bust cache for immediate UI update
			else
				log:warn("Failed to equip: %s", err or (result and result.reason) or "unknown")
			end
		end)
	end
end

function InventoryTab:_useConsumable(itemId: string, _button: TextButton?, onDone: (() -> ())?)
	task.spawn(function()
		local result, err = ClientRF.call("UseConsumable", itemId)

		if not err and result and result.success then
			log:info("Used %s", itemId)

			-- (cache not cleared; rely on deltas/snapshots to update UI)
		else
			-- Treat server-side dedupe as success from UX perspective
			local reason = (result and result.reason) or tostring(err or "")
			if not (reason == "DEDUPED_BUSY" or reason == "DEDUPED_RATELIMIT") then
				log:warn("Failed to use: %s", err or (result and result.reason) or "unknown")
			end
		end

		if onDone then
			ClientError.try("InventoryTab.onDone", onDone)
		end
	end)
end

function InventoryTab:_updateDisplay()
	-- Defer rebuilds while tab is not visible to avoid background churn

	if not self._active then
		self._pendingRefresh = true

		return
	end

	-- Cancel existing animations before clearing buttons

	for _, thread in ipairs(self._animationTasks) do
		if thread then
			task.cancel(thread)
		end
	end

	self._animationTasks = {}

	-- Clear existing buttons

	for _, button in pairs(self._itemButtons) do
		button:Destroy()
	end

	self._itemButtons = {}

	-- Create buttons for each item (respect filters when applicable)

	for itemId, count in pairs(self._inventory) do
		local button: TextButton? = self:_createItemButton(itemId, count)

		if button then
			-- Get item definition to determine type

			local itemDef = ItemDefinitions.get(itemId)

			if itemDef then
				-- Apply filters: rarity only applies to resources; search applies to all

				local pass = true

				local rf = tostring(self._rarityFilter or "ALL"):upper()

				if rf ~= "ALL" and itemDef.type == "resource" then
					pass = (tostring(itemDef.rarity or ""):upper() == rf)
				end

				if pass then
					local q = tostring(self._searchQuery or ""):lower()

					if q ~= "" then
						local nm = tostring(itemDef.name or itemId):lower()

						pass = (string.find(nm, q, 1, true) ~= nil)
					end
				end

				if not pass then
					button:Destroy()

					button = nil
				end
			end

			if itemDef and button then
				-- Place in appropriate grid

				if itemDef.type == "cosmetic" then
					button.Parent = self.cosmeticsGrid
				elseif itemDef.type == "resource" then
					button.Parent = self.resourcesGrid
				elseif itemDef.type == "consumable" then
					button.Parent = self.consumablesGrid
				end

				table.insert(self._itemButtons, button)
			end
		end
	end
end

function InventoryTab:_refreshInventory()
	task.spawn(function()
		local profile, err = PlayerProfileGuard.get()

		if profile then
			self._inventory = profile.inventory or {}

			self._equipped = profile.equipped or {}

			self:_updateDisplay()
		else
			log:warn("Failed to get profile:", err)
		end
	end)
end

type InvSnapshot = {
	profile: {
		inventory: { [string]: number }?,
		equipped: { [string]: string }?,
	}?,
}

function InventoryTab:_applySnapshot(snapshot: InvSnapshot)
	if snapshot and snapshot.profile then
		self._inventory = snapshot.profile.inventory or {}

		self._equipped = snapshot.profile.equipped or {}

		local inventoryCount = 0

		for _ in pairs(self._inventory) do
			inventoryCount = inventoryCount + 1
		end

		log:debug(
			"Applying snapshot - %d items in inventory, %d equipped",
			inventoryCount,
			next(self._equipped) and 1 or 0
		)

		self:_updateDisplay()
	else
		log:warn("Invalid snapshot structure: %s", tostring(snapshot))
	end
end

function InventoryTab:_onInventoryChanged(change)
	-- Update cache based on change

	if change.action == "add" or change.action == "remove" then
		if change.total and change.total > 0 then
			self._inventory[change.itemId] = change.total
		else
			self._inventory[change.itemId] = nil
		end
	elseif change.action == "equip" then
		if change.slot then
			self._equipped[change.slot] = change.itemId
		end
	elseif change.action == "unequip" then
		if change.slot then
			self._equipped[change.slot] = nil
		end
	end

	-- Batch updates to avoid excessive rebuilds

	self:_markDirtyAndSchedule()
end

-- Internal: mark UI as dirty and schedule a single rebuild (debounced by one tick)

function InventoryTab:_markDirtyAndSchedule()
	self._dirty = true

	if not self._updateScheduled then
		self._updateScheduled = true

		task.defer(function()
			if self._dirty then
				-- If inactive, remember to refresh when activated

				if self._active then
					self:_updateDisplay()

					self._dirty = false
				else
					self._pendingRefresh = true
				end
			end

			self._updateScheduled = false
		end)
	end
end

-- Public: toggle active state to control background rebuilds

function InventoryTab:setActive(isActive: boolean)
	self._active = isActive and true or false

	if self._active and (self._pendingRefresh or self._dirty) then
		-- Ensure UI is up to date when becoming visible

		self:_updateDisplay()

		self._pendingRefresh = false

		self._dirty = false
	end
end

function InventoryTab:refresh()
	-- Restore visibility after BasePanel hide made everything transparent

	if self._dataProvider then
		local snap = self._dataProvider:getSnapshot()

		self:_applySnapshot(snap)
	end
end

-- Override destroy for tab-specific cleanup

function InventoryTab:destroy()
	-- Cancel all animation tasks

	for _, animTask in ipairs(self._animationTasks) do
		if animTask then
			task.cancel(animTask)
		end
	end

	-- Clear tab-specific state (reset to safe defaults)

	self._itemButtons = {}

	self._inventory = {}

	self._equipped = {}

	self._animationTasks = {}

	self._dirty = false

	self._updateScheduled = false

	self.cosmeticsGrid = nil

	self.resourcesGrid = nil

	self.consumablesGrid = nil

	-- Call base destroy (handles connections, container, periodic updates)

	BaseTabComponent.destroy(self)
end

-- Public: show only a specific category (resources|cosmetics|consumables|all)

function InventoryTab:setCategory(category: string)
	category = string.lower(category or "all")

	local function showCardFor(grid, shouldShow)
		if grid and grid.Parent then
			grid.Parent.Visible = shouldShow and true or false
		end
	end

	local showAll = (category == "all")

	showCardFor(self.resourcesGrid, showAll or category == "resources")

	showCardFor(self.cosmeticsGrid, showAll or category == "cosmetics")

	showCardFor(self.consumablesGrid, showAll or category == "consumables")
end

-- Public: update filters for rarity/search

function InventoryTab:setFilters(rarity: string?, search: string?)
	self._rarityFilter = (rarity and tostring(rarity) or "ALL")

	self._searchQuery = search and tostring(search) or ""

	-- Trigger rebuild if active, else mark dirty

	if self._active then
		self:_updateDisplay()

		self._dirty = false

		self._pendingRefresh = false
	else
		self._dirty = true

		self._pendingRefresh = true
	end
end

return InventoryTab
