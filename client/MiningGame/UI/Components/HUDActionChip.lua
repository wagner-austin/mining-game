--!strict
-- HUDActionChip.lua
-- Child component for world interaction prompts (hosted by MainHUD)
-- Handles both click/tap and keyboard input

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UIFolder = MiningGame:WaitForChild("UI")
-- Strict Theme typing mirrors actual Theme.lua
local _Theme = require(UIFolder:WaitForChild("Theme"))
type ThemeHAC = typeof(_Theme)
local Theme: ThemeHAC = _Theme
local BaseChip = require(script.Parent:WaitForChild("BaseChip"))
local Logger = require(MiningGame:WaitForChild("Logger"))

local log = Logger.new("HUDActionChip")

export type Props = {
	parent: GuiObject, -- Parent frame (provided by MainHUD)
	text: string,
	icon: string?,
	key: Enum.KeyCode?, -- default E
	onActivate: (() -> ())?, -- callback when activated
	widthPx: number?, -- optional width override (defaults to Theme.homeButton.width)
}

local HUDActionChip = {}
HUDActionChip.__index = HUDActionChip

type BaseChipT = BaseChip.BaseChipT

export type HUDActionChipT = {
	_container: Frame,
	setText: (self: HUDActionChipT, text: string) -> (),
	setIcon: (self: HUDActionChipT, icon: string) -> (),
	setEnabled: (self: HUDActionChipT, enabled: boolean) -> (),
	show: (self: HUDActionChipT) -> (),
	hide: (self: HUDActionChipT) -> (),
	destroy: (self: HUDActionChipT) -> (),
}

function HUDActionChip.new(props: Props): HUDActionChipT
	-- Container lives INSIDE the provided parent (bottomCenterGroup from MainHUD)
	local container = Instance.new("Frame")
	container.Name = "HUDActionChipContainer"
	container.BackgroundTransparency = 1
	container.Size = UDim2.fromScale(1, 1) -- Fill the parent
	container.Parent = props.parent
	local _container = container

	-- Create chip using BaseChip (EXACTLY like HomeButton does)
	local iconSize: number
	if typeof(Theme.homeButton.iconSize) == "number" then
		iconSize = Theme.homeButton.iconSize
	else
		iconSize = Theme.textSizes and Theme.textSizes.Medium and Theme.textSizes.Medium.Max or 20
	end
	-- Prepare locals for closures
	local _onActivate = props.onActivate
	local _key = props.key or Enum.KeyCode.E
	local _enabled = true
	local chip = BaseChip.new({
		parent = container,
		size = UDim2.new(0, (props.widthPx or Theme.homeButton.width), 0, Theme.homeButton.height),
		-- No position needed - BaseChip centers itself
		icon = props.icon or "🌳",
		iconSize = iconSize,
		text = props.text or "Climb",
		onClick = function()
			log:debug("Chip clicked")
			if _enabled and _onActivate then
				_onActivate()
			end
		end,
		squishIntensity = 0.92, -- Same as home button
	})
	local _chip = chip

	-- Keyboard support (handles E key globally when chip is enabled)
	local _inputConnection = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if _enabled and input.KeyCode == _key then
			log:debug("Key %s pressed", tostring(_key))
			if _onActivate then
				_onActivate()
			end
		end
	end)

	log:debug("HUDActionChip created with key=%s", tostring(_key))
	local rec: HUDActionChipT = {
		_container = _container,
		setText = function(_, text: string)
			_chip:setText(text)
			log:debug("Text changed to: %s", text)
		end,
		setIcon = function(_, icon: string)
			_chip:setIcon(icon)
		end,
		setEnabled = function(_, enabled: boolean)
			_enabled = enabled
			log:debug("Enabled set to: %s", tostring(enabled))
		end,
		show = function(_)
			_container.Visible = true
		end,
		hide = function(_)
			_container.Visible = false
		end,
		destroy = function(_)
			if _inputConnection then
				_inputConnection:Disconnect()
			end
			_chip:destroy()
			_container:Destroy()
			log:debug("HUD chip destroyed")
		end,
	}
	return rec
end

-- methods are provided via closures in new()

return HUDActionChip
