--!strict
-- ItemDetailsPopup.lua
-- Modern item details modal with proper typography and visual hierarchy

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MG = ReplicatedStorage:WaitForChild("MiningGame")
local UIFolder = MG:WaitForChild("UI")
-- Strict Theme typing mirrors actual Theme.lua
local _Theme = require(UIFolder:WaitForChild("Theme"))
type ThemeIDP = typeof(_Theme)
local Theme: ThemeIDP = _Theme
local UIx = require(UIFolder:WaitForChild("UIConstants"))
local ThemeRefresher = require(UIFolder:WaitForChild("ThemeRefresher"))
local UIFactory = require(UIFolder:WaitForChild("Factory"))
local ClientError = require(MG:WaitForChild("ClientError"))
local ItemInsights = require(MG:WaitForChild("ItemInsights"))
local LootMath = require(MG:WaitForChild("LootMath"))
local ClientRF = require(MG:WaitForChild("ClientRF"))
local TextUtils = require(MG:WaitForChild("TextUtils"))
local PlayerProfileGuard = require(MG:WaitForChild("PlayerProfileGuard"))
local BaseChip = require(script.Parent:WaitForChild("BaseChip"))
local Renderer = require(script.Parent:WaitForChild("ItemTileRenderer"))
local BaseInfoPopup = require(script.Parent:WaitForChild("BaseInfoPopup"))
local ClientRegistry = require(MG:WaitForChild("ClientRegistry"))

type Props = { parent: Instance, itemId: string }

local ItemDetailsPopup = {}
ItemDetailsPopup.__index = ItemDetailsPopup

export type ItemDetailsPopupT = {
	_scrim: TextButton?,
	_card: Frame?,
	destroy: (self: ItemDetailsPopupT) -> (),
}

local function chipRow(
	parent: Instance,
	chips: { { text: string, icon: string?, color: Color3? } },
	layoutOrder: number?
)
	local container = Instance.new("Frame")
	container.BackgroundTransparency = 1
	container.Size = UDim2.new(1, 0, 0, 36)
	container.LayoutOrder = layoutOrder or 0
	container.Parent = parent

	local chipLayout = Instance.new("UIListLayout")
	chipLayout.FillDirection = Enum.FillDirection.Horizontal
	chipLayout.Padding = UDim.new(0, UIx.Spacing.SM)
	chipLayout.SortOrder = Enum.SortOrder.LayoutOrder
	chipLayout.Parent = container

	for _, chip in ipairs(chips) do
		BaseChip.new({
			parent = container,
			size = nil, -- Let BaseChip use its default size
			icon = chip.icon,
			text = chip.text,
			textColor = chip.color,
		})
	end

	return container
end

function ItemDetailsPopup.new(props: Props): ItemDetailsPopupT
	local self: ItemDetailsPopupT = setmetatable({} :: any, ItemDetailsPopup)
	local insight = ItemInsights.get(props.itemId)
	if not insight then
		return self
	end

	-- Create base modal
	local base = BaseInfoPopup.new({ parent = props.parent, size = UDim2.new(0, 360, 0, 280) })
	local card = base.card :: Frame

	-- Main layout
	local mainLayout = Instance.new("UIListLayout")
	mainLayout.FillDirection = Enum.FillDirection.Vertical
	mainLayout.Padding = UDim.new(0, UIx.Spacing.SM)
	mainLayout.SortOrder = Enum.SortOrder.LayoutOrder
	mainLayout.Parent = card

	-- Compact header
	local header = Instance.new("Frame")
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 56)
	header.LayoutOrder = 1
	header.Parent = card

	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.new(0, 48, 0, 48)
	icon.Position = UDim2.new(0, 0, 0.5, -24)
	icon.Image = (insight.icon and (insight.icon:match("^%d+$") and ("rbxassetid://" .. insight.icon) or insight.icon))
		or ""
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = header

	local displayName = insight.name or insight.id
	if displayName == insight.id or string.find(displayName, "_") or string.find(displayName, "%-") then
		displayName = TextUtils.prettifyItemName(insight.id, { id = insight.id, name = displayName })
	end

	local nameLabel = UIFactory.label({
		parent = header,
		text = displayName,
		size = UDim2.new(1, -56, 1, 0),
		position = UDim2.new(0, 56, 0, 0),
		alignment = Enum.TextXAlignment.Left,
		textSize = UIx.Visual.TEXT_TITLE,
	})
	nameLabel.TextYAlignment = Enum.TextYAlignment.Center
	nameLabel.Font = Theme.fonts.Display
	nameLabel.TextWrapped = true
	nameLabel.TextStrokeTransparency = 0.8
	nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	if insight.rarityColor then
		nameLabel.TextColor3 = insight.rarityColor
	else
		ThemeRefresher.Bind(nameLabel, { TextColor3 = "Text" })
	end

	-- Content container (no scrolling needed for compact version)
	local content = Instance.new("Frame")
	content.BackgroundTransparency = 1
	content.Size = UDim2.new(1, 0, 1, -56)
	content.LayoutOrder = 2
	content.Parent = card

	local contentLayout = Instance.new("UIListLayout")
	contentLayout.FillDirection = Enum.FillDirection.Vertical
	contentLayout.Padding = UDim.new(0, UIx.Spacing.SM)
	contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	contentLayout.Parent = content

	-- Essential info chips
	local statusChips = {}
	local typeSlot = insight.slot and (insight.type .. " • " .. insight.slot) or insight.type
	local symbol =
		Renderer.symbolFor({ id = insight.id, type = insight.type, slot = insight.slot, icon = insight.icon })

	if insight.rarity then
		table.insert(statusChips, {
			text = insight.rarity:upper(),
			icon = "✨",
			color = insight.rarityColor,
		})
	end

	table.insert(statusChips, { text = typeSlot, icon = symbol })

	local ownedCount = 0
	local profile = select(1, PlayerProfileGuard.get())
	if profile and profile.inventory then
		ownedCount = tonumber(profile.inventory[insight.id] or 0) or 0
	end

	table.insert(statusChips, {
		text = ownedCount > 0 and ("×" .. tostring(ownedCount)) or "Unowned",
		icon = ownedCount > 0 and "✓" or "✕",
		color = ownedCount > 0 and Theme.colors.Success or Theme.colors.Error,
	})

	chipRow(content, statusChips, 1)

	-- Key details only
	local detailsContainer = Instance.new("Frame")
	detailsContainer.BackgroundTransparency = 1
	detailsContainer.Size = UDim2.new(1, 0, 0, 0)
	detailsContainer.AutomaticSize = Enum.AutomaticSize.Y
	detailsContainer.LayoutOrder = 2
	detailsContainer.Parent = content

	local detailsLayout = Instance.new("UIListLayout")
	detailsLayout.FillDirection = Enum.FillDirection.Vertical
	detailsLayout.Padding = UDim.new(0, UIx.Spacing.TINY)
	detailsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	detailsLayout.Parent = detailsContainer

	-- Compact rows with smaller text
	local function compactRow(label: string, value: string, color: Color3?, layoutOrder: number?)
		local r = Instance.new("Frame")
		r.BackgroundTransparency = 1
		r.Size = UDim2.new(1, 0, 0, UIx.Size.ROW_SMALL)
		r.LayoutOrder = layoutOrder or 0
		r.Parent = detailsContainer

		local l = UIFactory.label({
			parent = r,
			text = label,
			size = UDim2.new(0.35, 0, 1, 0),
			alignment = Enum.TextXAlignment.Left,
			textSize = UIx.Visual.TEXT_MEDIUM,
			isDim = true,
		})
		l.Font = Theme.fonts.Secondary

		local v = UIFactory.label({
			parent = r,
			text = value,
			size = UDim2.new(0.65, 0, 1, 0),
			position = UDim2.new(0.35, 0, 0, 0),
			alignment = Enum.TextXAlignment.Left,
			textSize = UIx.Visual.TEXT_MEDIUM,
			isDim = false,
		})
		if color then
			v.TextColor3 = color
		else
			ThemeRefresher.Bind(v, { TextColor3 = "Text" })
		end
	end

	-- Only show the most essential info
	if insight.value and insight.value > 0 then
		local valueText = tostring(insight.value):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
		compactRow("Value", valueText .. " coins", nil, 1)
	end

	-- Drop rate (per dig) only
	do
		local mgr = ClientRegistry.getUIManager()
		local provider = (mgr and mgr.accountDataProvider) or nil
		local matId = nil
		if provider and provider.getSnapshot then
			local snap = provider:getSnapshot()
			matId = snap and snap.profile and snap.profile.materialId
		end
		local luck = 1.0
		local size = 1
		local ok, res = ClientError.try("ItemDetailsPopup.GetEffectiveStats", function()
			return ClientRF.call("GetEffectiveStats")
		end)
		if ok and res and res.success and res.effectiveStats then
			local es = res.effectiveStats
			if typeof(es.luck) == "number" then
				luck = es.luck
			end
			if typeof(es.size) == "number" then
				size = es.size
			end
			if not matId and typeof(res.materialId) == "string" then
				matId = res.materialId
			end
		end

		local pDig = LootMath.dropRatePerDigAction(insight.id, {
			materialId = matId,
			luckMultiplier = luck,
			chanceMult = 1.0,
			size = size,
		})
		compactRow("Drop (per dig)", string.format("%.3f%%", (pDig or 0) * 100), nil, 2)
	end

	if insight.sources and #insight.sources > 0 then
		local sources = insight.sources[1] -- Just show first source
		if #insight.sources > 1 then
			sources = sources .. " (+" .. (#insight.sources - 1) .. " more)"
		end
		compactRow("Source", sources, nil, 3)
	end

	-- Event connections
	self._scrim = base.scrim
	self._card = card
	return self
end

function ItemDetailsPopup.destroy(self: ItemDetailsPopupT)
	local s = self._scrim
	if s then
		s:Destroy()
	end
	self._scrim = nil
	self._card = nil
end

return ItemDetailsPopup
