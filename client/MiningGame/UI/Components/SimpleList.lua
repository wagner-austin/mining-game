--!strict
-- SimpleList.lua
-- Minimal list helpers for DRY row/list construction in panels

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UIFolder = MiningGame:WaitForChild("UI")
-- Strict Theme typing mirrors actual Theme.lua
local _Theme = require(UIFolder:WaitForChild("Theme"))
type ThemeSL = typeof(_Theme)
local Theme: ThemeSL = _Theme
local UIx = require(UIFolder:WaitForChild("UIConstants"))
local UIUtils = require(UIFolder:WaitForChild("UIUtils"))

local SimpleList = {}

export type RowProps = {
	title: string,
	subtitle: string?,
	actionText: string?,
	disabled: boolean?,
	titleColor: Color3?,
	accentColor: Color3?,
	metaText: string?,
	onActivate: (() -> ())?,
}

function SimpleList.create(parent: Instance): ScrollingFrame
	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Size = UDim2.new(1, 0, 1, -UIx.Spacing.SM)
	list.Position = UIx.Common.ORIGIN
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = UIx.Spacing.SM
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, UIx.Spacing.SM)
	layout.Parent = list
	return list
end

function SimpleList.row(parent: Instance, props: RowProps): Frame
	local colors = Theme.colors
	local row = Instance.new("Frame")
	row.Name = "Row"
	row.Size = UDim2.new(1, 0, 0, UIx.Size.LIST_ROW_HEIGHT)
	row.BackgroundColor3 = colors.Surface
	row.BackgroundTransparency = Theme.effects.frosted.backgroundTransparency
	row.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, UIx.Visual.CORNER_RADIUS)
	corner.Parent = row

	UIUtils.applyGlassEdge(row)
	-- Optional accent strip on the left
	if props.accentColor then
		local accent = Instance.new("Frame")
		accent.Name = "Accent"
		accent.Size = UDim2.new(0, 4, 1, 0)
		accent.Position = UDim2.new(0, 0, 0, 0)
		accent.BackgroundColor3 = props.accentColor
		accent.BackgroundTransparency = 0
		accent.BorderSizePixel = 0
		accent.Parent = row
	end

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, UIx.Spacing.LG)
	pad.PaddingRight = UDim.new(0, UIx.Spacing.LG)
	pad.PaddingTop = UDim.new(0, UIx.Spacing.SM)
	pad.PaddingBottom = UDim.new(0, UIx.Spacing.SM)
	pad.Parent = row

	local titleL = Instance.new("TextLabel")
	titleL.Name = "Title"
	titleL.BackgroundTransparency = 1
	titleL.Text = props.title
	titleL.TextColor3 = props.titleColor or colors.Text
	titleL.TextScaled = true
	titleL.Font = Theme.fonts.Primary
	local reserve = UIx.Size.BUTTON_WIDTH + UIx.Spacing.SECTION
	if props.metaText and #props.metaText > 0 then
		reserve = reserve + UIx.Size.GRID_CELL_PX + UIx.Spacing.MD
	end
	titleL.Size = UDim2.new(1, -reserve, 0, UIx.Size.ROW_HEADER)
	titleL.TextXAlignment = Enum.TextXAlignment.Left
	titleL.Parent = row
	local titleSize = Instance.new("UITextSizeConstraint")
	titleSize.MinTextSize = Theme.textSizes.Medium.Min
	titleSize.MaxTextSize = Theme.textSizes.Medium.Max
	titleSize.Parent = titleL

	if props.subtitle and #props.subtitle > 0 then
		local sub = Instance.new("TextLabel")
		sub.Name = "Subtitle"
		sub.BackgroundTransparency = 1
		sub.Text = props.subtitle
		sub.TextColor3 = colors.Text
		sub.TextTransparency = 0.25
		sub.TextScaled = true
		sub.Font = Theme.fonts.Secondary
		sub.Size = UDim2.new(1, -reserve, 0, UIx.Size.ROW_LABEL)
		sub.Position = UDim2.new(0, 0, 0, UIx.Size.ROW_HEADER)
		sub.TextXAlignment = Enum.TextXAlignment.Left
		sub.Parent = row
		local subSize = Instance.new("UITextSizeConstraint")
		subSize.MinTextSize = Theme.textSizes.Small.Min
		subSize.MaxTextSize = Theme.textSizes.Small.Max
		subSize.Parent = sub
	end

	if props.metaText and #props.metaText > 0 then
		local m = Instance.new("TextLabel")
		m.Name = "Meta"
		m.BackgroundTransparency = 1
		m.Text = props.metaText
		m.TextColor3 = colors.Text
		m.TextTransparency = 0.15
		m.TextScaled = true
		m.Font = Theme.fonts.Secondary
		m.Size = UDim2.new(0, UIx.Size.GRID_CELL_PX, 1, -UIx.Spacing.SM)
		m.AnchorPoint = Vector2.new(1, 0)
		m.Position = UDim2.new(1, -(UIx.Size.BUTTON_WIDTH + UIx.Spacing.MD), 0, UIx.Spacing.SM / 2)
		m.TextXAlignment = Enum.TextXAlignment.Right
		m.Parent = row
		local mText = Instance.new("UITextSizeConstraint")
		mText.MinTextSize = Theme.textSizes.Small.Min
		mText.MaxTextSize = Theme.textSizes.Medium.Max
		mText.Parent = m
	end

	local action = Instance.new("TextButton")
	action.Name = "Action"
	action.Size = UDim2.new(0, UIx.Size.BUTTON_WIDTH, 1, -UIx.Spacing.SM)
	action.Position = UDim2.new(1, -UIx.Size.BUTTON_WIDTH, 0, UIx.Spacing.SM / 2)
	action.AnchorPoint = Vector2.new(1, 0)
	action.BackgroundColor3 = Theme.colors.Primary
	action.TextColor3 = Theme.colors.Text
	action.Text = props.actionText or "SELECT"
	action.TextScaled = true
	action.AutoButtonColor = not props.disabled
	action.Font = Theme.fonts.Primary
	action.Parent = row
	local c2 = Instance.new("UICorner")
	c2.CornerRadius = UDim.new(0, UIx.Visual.CORNER_RADIUS)
	c2.Parent = action
	local btnText = Instance.new("UITextSizeConstraint")
	btnText.MinTextSize = Theme.textSizes.Small.Min
	btnText.MaxTextSize = Theme.textSizes.Medium.Max
	btnText.Parent = action

	if props.disabled then
		action.TextTransparency = 0.5
		action.BackgroundTransparency = 0.3
		action.Active = false
		action.AutoButtonColor = false
	elseif props.onActivate then
		action.Activated:Connect(props.onActivate)
	end

	return row
end

return SimpleList
