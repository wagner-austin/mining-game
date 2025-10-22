--!strict
-- CurrencyChip.lua
-- Currency display component that extends BaseChip for consistency

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage:WaitForChild("MiningGame"):WaitForChild("UI"):WaitForChild("Theme"))
local UIUtils = require(ReplicatedStorage:WaitForChild("MiningGame"):WaitForChild("UI"):WaitForChild("UIUtils"))
local BaseChip = require(script.Parent:WaitForChild("BaseChip"))

local CurrencyChip = {}
CurrencyChip.__index = CurrencyChip

type Props = {
    parent: GuiObject,
    currencyType: "coins" | "gems",
    value: number,
    position: UDim2?,
    size: UDim2?,
    onClick: (() -> ())?  -- For future functionality
}

type CurrencyChipT = typeof(setmetatable({} :: any, CurrencyChip)) & {
    chip: any,
    currencyType: "coins" | "gems",
    new: (props: Props) -> CurrencyChipT,
    setValue: (self: CurrencyChipT, value: number) -> (),
    pulse: (self: CurrencyChipT, intensity: number?) -> (),
    destroy: (self: CurrencyChipT) -> (),
}

function CurrencyChip.new(props: Props): CurrencyChipT
    local self = setmetatable({}, CurrencyChip)
    
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
        pulseOnUpdate = true,  -- Pulse when value increases
        squishIntensity = props.squishIntensity or 0.92,  -- Default to 0.92, same as HomeButton
    })
    
    -- Store references
    self.chip = chip
    self.currencyType = props.currencyType
    
    return self :: any
end

function CurrencyChip:setValue(value: number)
    self.chip:setValue(value)
end

function CurrencyChip:pulse(intensity: number?)
    self.chip:pulse(intensity or 1.1)
end

function CurrencyChip:destroy()
    self.chip:destroy()
end

return CurrencyChip
