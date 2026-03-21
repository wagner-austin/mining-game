--!strict
-- HomeButton.lua
-- Frosted glass HOME button to teleport player to their spawn point
-- Now uses BaseChip for consistency

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Strict Theme typing mirrors actual Theme.lua
local _Theme = require(ReplicatedStorage:WaitForChild("MiningGame"):WaitForChild("UI"):WaitForChild("Theme"))
type ThemeHB = typeof(_Theme)
local Theme: ThemeHB = _Theme
local BaseChip = require(script.Parent:WaitForChild("BaseChip"))

local HomeButton = {}
HomeButton.__index = HomeButton

type Props = {
	parent: GuiObject,
	onClick: (() -> ())?,
}

type BaseChipT = BaseChip.BaseChipT

export type HomeButtonT = {
	onClick: (() -> ())?,
	pulse: (self: HomeButtonT) -> (),
	destroy: (self: HomeButtonT) -> (),
}

function HomeButton.new(props: Props): HomeButtonT
	local config = Theme.homeButton

	-- Use BaseChip for consistent behavior
	local iconSize: number
	if typeof(config.iconSize) == "number" then
		iconSize = config.iconSize
	else
		iconSize = 24
	end
	local chip = BaseChip.new({
		parent = props.parent,
		size = UDim2.new(0, config.width, 0, config.height),

		-- Content
		icon = Theme.icons.home,
		iconSize = iconSize,
		text = "HOME",

		-- Behavior
		onClick = props.onClick,
		squishIntensity = 0.92, -- Same as original
	})

	local rec: HomeButtonT = {
		onClick = props.onClick,
		pulse = function(_)
			chip:pulse(1.1)
		end,
		destroy = function(_)
			chip:destroy()
		end,
	}
	return rec
end

return HomeButton
