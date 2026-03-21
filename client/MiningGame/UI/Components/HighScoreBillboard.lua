--!strict
-- HighScoreBillboard.lua
-- Minimal high score panel that mounts on a banner using BaseBillboard

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UIFolder = MiningGame:WaitForChild("UI")
-- Strict Theme typing mirrors actual Theme.lua
local _Theme = require(UIFolder:WaitForChild("Theme"))
type ThemeHS = typeof(_Theme)
local Theme: ThemeHS = _Theme
local UIx = require(UIFolder:WaitForChild("UIConstants"))

-- BaseBillboard lives alongside this module in client UI Components
local BaseBillboard = require(script.Parent:WaitForChild("BaseBillboard"))
local ClientRF = require(MiningGame:WaitForChild("ClientRF"))
local Logger = require(MiningGame:WaitForChild("Logger"))
local ThemeRefresher = require(UIFolder:WaitForChild("ThemeRefresher"))
local log = Logger.new("HighScoreBillboard")

export type Entry = { name: string, value: number }

export type Props = {
	adornee: BasePart, -- Attachment/BasePart
	category: string, -- "blocks" | "donator" | "coins" | other
	accentColor: Color3?,
	title: string?,
	limit: number?, -- default 5
	refreshSec: number?, -- default 30 (no RF yet; placeholder)
	face: Enum.NormalId?, -- Surface face to render on (default Front)
}

type BaseBillboardT = {
	content: Frame,
	root: Frame,
	setTitle: (self: BaseBillboardT, title: string) -> (),
	setAccentColor: (self: BaseBillboardT, color: Color3) -> (),
	destroy: (self: BaseBillboardT) -> (),
}

export type HighScoreBillboardT = {
	bb: BaseBillboardT,
	root: Frame,
	list: Frame,
	_running: boolean,
	_refreshTask: thread?,
	setEntries: (self: HighScoreBillboardT, entries: { Entry }) -> (),
	destroy: (self: HighScoreBillboardT) -> (),
}

local HighScoreBillboard = {}
HighScoreBillboard.__index = HighScoreBillboard

local function titleFor(category: string): string
	local c = string.lower(category or "")
	if c == "donator" then
		return "Top Donators"
	end
	if c == "coins" then
		return "Top Coins"
	end
	if c == "blocks" then
		return "Blocks Dug"
	end
	return "High Scores"
end

function HighScoreBillboard.new(props: Props): HighScoreBillboardT
	assert(props and props.adornee, "HighScoreBillboard.new: props.adornee is required")

	local limit = math.max(1, props.limit or 5)
	local title = props.title or titleFor(props.category)
	local accent = props.accentColor or Theme.colors.Primary

	local categoryLower = string.lower(props.category or "")
	local hideValueColumn = (categoryLower == "teleport")
	-- Compute canvas height to fit header + rows based on Theme.billboard.rowHeight
	local rowHeight = (Theme.billboard and Theme.billboard.rowHeight) or UIx.Size.ROW_LARGE
	local rows = limit
	local listPaddingBetween = UIx.Spacing.SM
	local contentMarginsY = UIx.Spacing.LG * 2
	local headerHeight = UIx.Size.ROW_SECTION
	local extraGapBelowHeader = UIx.Spacing.SM
	local listHeightNeeded = rows * rowHeight + math.max(0, rows - 1) * listPaddingBetween
	local canvasHeight = math.max(260, contentMarginsY + headerHeight + extraGapBelowHeader + listHeightNeeded)

	local bb = BaseBillboard.new({
		adornee = props.adornee,
		title = title,
		accentColor = accent,
		face = props.face or Enum.NormalId.Front,
		canvasSize = Vector2.new(380, canvasHeight),
		zIndex = 10,
	})

	-- Content layout below title
	local content = bb.content
	local list = Instance.new("Frame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	-- Position list below the title; match title height (ROW_SECTION) and keep a small gap
	list.Size = UDim2.new(1, 0, 1, -(UIx.Size.ROW_SECTION + UIx.Spacing.SM))
	list.Position = UDim2.fromOffset(0, UIx.Size.ROW_SECTION)
	list.ZIndex = 12
	list.Parent = content

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, UIx.Spacing.SM)
	layout.Parent = list

	local function makeRow(i: number, entry: Entry?)
		local row = Instance.new("Frame")
		row.Name = "Row" .. tostring(i)
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, rowHeight)
		row.LayoutOrder = i
		row.Parent = list

		local idxW = (Theme.billboard and tonumber(Theme.billboard.idxWidth)) or 28
		local valW = (string.lower(props.category or "") == "teleport") and 0
			or ((Theme.billboard and tonumber(Theme.billboard.valueWidth)) or 112)
		local gap = UIx.Spacing.SM

		local idx = Instance.new("TextLabel")
		idx.Name = "Idx"
		idx.BackgroundTransparency = 1
		idx.Size = UDim2.new(0, idxW, 1, 0)
		idx.Position = UDim2.fromOffset(0, 0)
		idx.Font = Theme.fonts.Primary
		idx.TextScaled = true
		idx.TextXAlignment = Enum.TextXAlignment.Left
		idx.TextColor3 = Theme.colors.Text
		idx.Text = string.format("%d.", i)
		idx.ZIndex = 13
		idx.Parent = row

		local idxConstraint = Instance.new("UITextSizeConstraint")
		local idxSizes = (Theme.billboard and Theme.billboard.index) or Theme.textSizes.Display
		idxConstraint.MinTextSize = idxSizes.Min
		idxConstraint.MaxTextSize = idxSizes.Max
		idxConstraint.Parent = idx

		ThemeRefresher.Bind(idx, { TextColor3 = "Text" })

		local name = Instance.new("TextLabel")
		name.Name = "Name"
		name.BackgroundTransparency = 1
		name.Size = (string.lower(props.category or "") == "teleport") and UDim2.new(1, -(idxW + gap), 1, 0)
			or UDim2.new(1, -(valW + idxW + gap), 1, 0)
		name.Position = UDim2.fromOffset(idxW + gap, 0)
		name.Font = Theme.fonts.Secondary
		name.TextScaled = true
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextColor3 = Theme.colors.Text
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Text = entry and entry.name or ""
		name.ZIndex = 13
		name.Parent = row

		local nameConstraint = Instance.new("UITextSizeConstraint")
		local rowSizes = (Theme.billboard and Theme.billboard.row) or Theme.textSizes.Display
		nameConstraint.MinTextSize = rowSizes.Min
		nameConstraint.MaxTextSize = rowSizes.Max
		nameConstraint.Parent = name

		ThemeRefresher.Bind(name, { TextColor3 = "Text" })

		if not hideValueColumn then
			local value = Instance.new("TextLabel")
			value.Name = "Value"
			value.BackgroundTransparency = 1
			value.Size = UDim2.new(0, valW, 1, 0)
			value.Position = UDim2.new(1, -valW, 0, 0)
			value.Font = Theme.fonts.Primary
			value.TextScaled = true
			value.TextXAlignment = Enum.TextXAlignment.Right
			value.TextColor3 = Theme.colors.Text
			value.Text = entry and tostring(entry.value) or ""
			value.ZIndex = 13
			value.Parent = row

			local valueConstraint = Instance.new("UITextSizeConstraint")
			local valSizes = (Theme.billboard and Theme.billboard.value) or Theme.textSizes.Display
			valueConstraint.MinTextSize = valSizes.Min
			valueConstraint.MaxTextSize = valSizes.Max
			valueConstraint.Parent = value

			ThemeRefresher.Bind(value, { TextColor3 = "Text" })
		end
	end
	-- Placeholder rows
	for i = 1, limit do
		makeRow(i, nil)
	end

	local hb: HighScoreBillboardT = {
		bb = bb,
		root = bb.root,
		list = list,
		_running = true,
		_refreshTask = nil,
		setEntries = function(self: HighScoreBillboardT, entries: { Entry })
			entries = entries or {}
			for _, child in ipairs(self.list:GetChildren()) do
				if child:IsA("Frame") and child.Name:match("^Row") then
					child:Destroy()
				end
			end
			local n = math.min(limit, #entries)
			for i = 1, n do
				makeRow(i, entries[i])
			end
			for i = n + 1, limit do
				makeRow(i, nil)
			end
		end,
		destroy = function(self: HighScoreBillboardT)
			self._running = false
			self.bb:destroy()
		end,
	}

	-- Omit metatable to keep strict structural typing; methods are defined on the table

	-- Fetch + refresh loop (server-local high scores)
	local refreshSec = math.max(5, props.refreshSec or 30)
	hb._refreshTask = task.spawn(function()
		while hb._running do
			local res, err = ClientRF.call("GetHighScores", props.category, limit)
			if res and type(res) == "table" and res.entries then
				local entries = {}
				for _, e in ipairs(res.entries) do
					if type(e) == "table" and type(e.name) == "string" then
						local v = (type(e.value) == "number") and e.value or 0
						table.insert(entries, { name = e.name, value = v })
					end
				end
				hb:setEntries(entries)
			else
				if err then
					log:debug("GetHighScores error: %s", tostring(err))
				end
			end
			local t0 = os.clock()
			while hb._running and (os.clock() - t0) < refreshSec do
				task.wait(0.5)
			end
		end
	end)

	return hb
end

return HighScoreBillboard
