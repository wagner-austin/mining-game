--!strict
-- CurrencyChip.lua
-- Currency display component that extends BaseChip for consistency

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Strict Theme typing mirrors actual Theme.lua
local _Theme = require(ReplicatedStorage:WaitForChild("MiningGame"):WaitForChild("UI"):WaitForChild("Theme"))
type ThemeCC = typeof(_Theme)
local Theme: ThemeCC = _Theme
local BaseChip = require(script.Parent:WaitForChild("BaseChip"))

local CurrencyChip = {}
CurrencyChip.__index = CurrencyChip

type Props = {
	parent: GuiObject,
	currencyType: "coins" | "gems",
	value: number,
	position: UDim2?,
	size: UDim2?,
	squishIntensity: number?,
	onClick: (() -> ())?, -- For future functionality
}

type BaseChipT = BaseChip.BaseChipT

export type CurrencyChipT = {
	currencyType: "coins" | "gems",
	setValue: (self: CurrencyChipT, value: number) -> (),
	pulse: (self: CurrencyChipT, intensity: number?) -> (),
	destroy: (self: CurrencyChipT) -> (),
}

function CurrencyChip.new(props: Props): CurrencyChipT
	local chipConfig = Theme.currencyChip

	-- Use BaseChip for consistent behavior
	local chip = BaseChip.new({
		parent = props.parent,
		size = props.size or UDim2.new(0, chipConfig.width, 0, chipConfig.height),
		position = props.position,

		-- Content
		icon = Theme.icons.currency[props.currencyType],
		iconSize = chipConfig.iconSize,
		value = props.value,

		-- Behavior
		onClick = props.onClick,
		pulseOnUpdate = true, -- Pulse when value increases
		squishIntensity = props.squishIntensity or 0.92, -- Default to 0.92, same as HomeButton
	})

	local rec: CurrencyChipT = {
		currencyType = props.currencyType,
		setValue = function(_, value: number)
			chip:setValue(value)
		end,
		pulse = function(_, intensity: number?)
			chip:pulse(intensity or 1.1)
		end,
		destroy = function(_)
			chip:destroy()
		end,
	}
	return rec
end

return CurrencyChip
