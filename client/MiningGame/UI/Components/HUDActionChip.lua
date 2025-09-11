--!strict
-- HUDActionChip.lua
-- Child component for world interaction prompts (hosted by MainHUD)
-- Handles both click/tap and keyboard input

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UIFolder = MiningGame:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))
local BaseChip = require(script.Parent:WaitForChild("BaseChip"))
local Logger = require(MiningGame:WaitForChild("Logger"))

local log = Logger.new("HUDActionChip")

export type Props = {
    parent: GuiObject,           -- Parent frame (provided by MainHUD)
    text: string,
    icon: string?,
    key: Enum.KeyCode?,          -- default E
    onActivate: (() -> ())?,     -- callback when activated
}

local HUDActionChip = {}
HUDActionChip.__index = HUDActionChip

type HUDActionChipT = typeof(setmetatable({} :: any, HUDActionChip)) & {
    _container: Frame,
    _chip: any,
    _onActivate: (() -> ())?,
    _key: Enum.KeyCode,
    _enabled: boolean,
    _inputConnection: RBXScriptConnection?,
    new: (props: Props) -> HUDActionChipT,
    setText: (self: HUDActionChipT, text: string) -> (),
    setIcon: (self: HUDActionChipT, icon: string) -> (),
    setEnabled: (self: HUDActionChipT, enabled: boolean) -> (),
    show: (self: HUDActionChipT) -> (),
    hide: (self: HUDActionChipT) -> (),
    destroy: (self: HUDActionChipT) -> (),
}

function HUDActionChip.new(props: Props): HUDActionChipT
    local self = setmetatable({}, HUDActionChip)

    -- Container lives INSIDE the provided parent (bottomCenterGroup from MainHUD)
    local container = Instance.new("Frame")
    container.Name = "HUDActionChipContainer"
    container.BackgroundTransparency = 1
    container.Size = UDim2.fromScale(1, 1)  -- Fill the parent
    container.Parent = props.parent
    self._container = container

    -- Create chip using BaseChip (EXACTLY like HomeButton does)
    local chip = BaseChip.new({
        parent = container,
        size = UDim2.new(0, Theme.homeButton.width, 0, Theme.homeButton.height),
        -- No position needed - BaseChip centers itself
        icon = props.icon or "🌳",
        iconSize = Theme.homeButton.iconSize,
        text = props.text or "Climb",
        onClick = function()
            log:debug("Chip clicked")
            if self._enabled and self._onActivate then
                self._onActivate()
            end
        end,
        squishIntensity = 0.92,  -- Same as home button
    })
    self._chip = chip

    self._onActivate = props.onActivate
    self._key = props.key or Enum.KeyCode.E
    self._enabled = true

    -- Keyboard support (handles E key globally when chip is enabled)
    self._inputConnection = UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        if self._enabled and input.KeyCode == self._key then
            log:debug("Key %s pressed", tostring(self._key))
            if self._onActivate then 
                self._onActivate() 
            end
        end
    end)

    log:debug("HUDActionChip created with key=%s", tostring(self._key))
    return self :: any
end

function HUDActionChip:setText(text: string) 
    if self._chip then 
        self._chip:setText(text) 
        log:debug("Text changed to: %s", text)
    end 
end

function HUDActionChip:setIcon(icon: string) 
    if self._chip then 
        self._chip:setIcon(icon) 
    end 
end

function HUDActionChip:setEnabled(enabled: boolean) 
    self._enabled = enabled 
    log:debug("Enabled set to: %s", tostring(enabled))
end

function HUDActionChip:show()
    -- MainHUD handles visibility and animations
    self._container.Visible = true
end

function HUDActionChip:hide()
    -- MainHUD handles visibility and animations
    self._container.Visible = false
end

function HUDActionChip:destroy()
    if self._inputConnection then 
        self._inputConnection:Disconnect() 
    end
    if self._chip then 
        self._chip:destroy() 
    end
    if self._container then 
        self._container:Destroy() 
    end
    log:debug("HUD chip destroyed")
end

return HUDActionChip
