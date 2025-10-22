--!strict
-- HomeButton.lua
-- Frosted glass HOME button to teleport player to their spawn point
-- Now uses BaseChip for consistency

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage:WaitForChild("MiningGame"):WaitForChild("UI"):WaitForChild("Theme"))
local BaseChip = require(script.Parent:WaitForChild("BaseChip"))

local HomeButton = {}
HomeButton.__index = HomeButton

type Props = {
    parent: GuiObject,
    onClick: (() -> ())?
}

type HomeButtonT = typeof(setmetatable({} :: any, HomeButton)) & {
    chip: any,
    onClick: (() -> ())?,
    new: (props: Props) -> HomeButtonT,
    pulse: (self: HomeButtonT) -> (),
    destroy: (self: HomeButtonT) -> (),
}

function HomeButton.new(props: Props): HomeButtonT
    local self = setmetatable({}, HomeButton)
    
    local config = Theme.homeButton
    
    -- Use BaseChip for consistent behavior
    local chip = BaseChip.new({
        parent = props.parent,
        size = UDim2.new(0, config.width, 0, config.height),
        
        -- Content
        icon = Theme.icons.home,
        iconSize = config.iconSize,
        text = "HOME",
        
        -- Behavior
        onClick = props.onClick,
        squishIntensity = 0.92,  -- Same as original
    })
    
    -- Store references
    self.chip = chip
    self.onClick = props.onClick
    
    return self :: any
end

function HomeButton:pulse()
    self.chip:pulse(1.1)  -- Same intensity as original
end

function HomeButton:destroy()
    self.chip:destroy()
end

return HomeButton
