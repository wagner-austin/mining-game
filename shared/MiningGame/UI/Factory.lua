--!strict
-- Factory.lua
-- Small, reusable UI builders with Theme bindings

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UIFolder = MiningGame:WaitForChild("UI")
local _Theme = require(UIFolder:WaitForChild("Theme"))
local Theme: typeof(_Theme) = _Theme
local UIx = require(UIFolder:WaitForChild("UIConstants"))
local ThemeRefresher = require(UIFolder:WaitForChild("ThemeRefresher"))

local Factory = {}

export type LabelProps = {
	parent: GuiObject,
	text: string,
	position: UDim2?,
	size: UDim2?,
	autoSize: boolean?,
	alignment: Enum.TextXAlignment?,
	textSize: number?,
	isDim: boolean?,
	richText: boolean?,
	layoutOrder: number?,
	zIndex: number?,
}

function Factory.label(props: LabelProps): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.Name = "Label"
	lbl.Text = props.text
	lbl.RichText = props.richText or false
	lbl.BackgroundTransparency = 1
	if props.size then
		lbl.Size = props.size
		lbl.AutomaticSize = Enum.AutomaticSize.None
	else
		-- Default to auto-size vertically for flexibility in wrappers
		lbl.Size = UDim2.new(1, 0, 0, 0)
		local auto = props.autoSize
		if auto == nil or auto == true then
			lbl.AutomaticSize = Enum.AutomaticSize.Y
		else
			lbl.AutomaticSize = Enum.AutomaticSize.None
			lbl.Size = UDim2.new(1, 0, 0, Theme.textSizes.Medium.Max)
		end
	end
	lbl.Position = props.position or UDim2.new()
	lbl.TextXAlignment = props.alignment or Enum.TextXAlignment.Left
	lbl.TextScaled = false
	lbl.TextSize = props.textSize or Theme.textSizes.Medium.Max
	lbl.Font = Theme.fonts.Primary
	lbl.LayoutOrder = props.layoutOrder or 0
	lbl.ZIndex = props.zIndex or 1

	lbl.TextColor3 = (props.isDim and Theme.colors.TextDim) or Theme.colors.Text
	-- live theme binding
	ThemeRefresher.Bind(lbl, { TextColor3 = props.isDim and "TextDim" or "Text" })

	lbl.Parent = props.parent
	return lbl
end

export type ProgressBarProps = {
	parent: Instance,
	height: number?,
	layoutOrder: number?,
}

-- Returns: background Frame, fill Frame
function Factory.progressBar(props: ProgressBarProps): (Frame, Frame)
	local height = props.height or UIx.Size.PROGRESS_HEIGHT
	local bg = Instance.new("Frame")
	bg.Name = "ProgressBg"
	bg.Size = UDim2.new(1, 0, 0, height)
	bg.BackgroundColor3 = Theme.colors.Surface
	bg.BackgroundTransparency = 0.5
	bg.LayoutOrder = props.layoutOrder or 0
	bg.Parent = props.parent
	ThemeRefresher.Bind(bg, { BackgroundColor3 = "Surface" })

	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0, UIx.Visual.CORNER_RADIUS_SMALL)
	bgCorner.Parent = bg

	local fill = Instance.new("Frame")
	fill.Name = "ProgressFill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = Theme.colors.Primary
	fill.Parent = bg
	ThemeRefresher.Bind(fill, { BackgroundColor3 = "Primary" })

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, UIx.Visual.CORNER_RADIUS_SMALL)
	fillCorner.Parent = fill

	return bg, fill
end

return Factory
