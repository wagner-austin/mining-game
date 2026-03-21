--!strict
-- InteractionChip.lua
-- Reusable world interaction prompt chip (for trees, rocks, pets, etc.)
-- Shows above objects when player is near, handles both click and keyboard input

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local BaseChip = require(script.Parent:WaitForChild("BaseChip"))
local UIFolder = MiningGame:WaitForChild("UI")
-- Strict Theme typing mirrors actual Theme.lua
local _Theme = require(UIFolder:WaitForChild("Theme"))
type ThemeIC = typeof(_Theme)
local Theme: ThemeIC = _Theme
local UIx = require(UIFolder:WaitForChild("UIConstants"))
local Logger = require(MiningGame:WaitForChild("Logger"))

local log = Logger.new("InteractionChip")

local InteractionChip = {}
InteractionChip.__index = InteractionChip

export type Props = {
	-- Required
	object: Model | BasePart, -- The object to show the chip above
	text: string, -- Text to display (e.g., "Climb")
	icon: string?, -- Optional emoji/icon
	key: Enum.KeyCode?, -- Optional keyboard key (defaults to E)
	offset: Vector3?, -- Optional offset from object

	-- Callbacks
	onActivate: () -> (), -- Called when interaction happens
	canActivate: (() -> boolean)?, -- Optional check if interaction is available
}

type BaseChipT = {
	setText: (self: BaseChipT, text: string) -> (),
	setIcon: (self: BaseChipT, icon: string) -> (),
	destroy: (self: BaseChipT) -> (),
}

export type InteractionChipT = {
	object: Model | BasePart,
	key: Enum.KeyCode,
	offset: Vector3,
	onActivate: () -> (),
	canActivate: (() -> boolean)?,
	isActive: boolean,
	screenGui: ScreenGui,
	containerFrame: Frame,
	chip: BaseChipT,
	inputConnection: RBXScriptConnection?,
	heartbeatConnection: RBXScriptConnection?,
	new: (props: Props) -> InteractionChipT,
	canPerformAction: (self: InteractionChipT) -> boolean,
	updatePosition: (self: InteractionChipT) -> (),
	show: (self: InteractionChipT) -> (),
	hide: (self: InteractionChipT) -> (),
	setText: (self: InteractionChipT, text: string) -> (),
	setIcon: (self: InteractionChipT, icon: string) -> (),
	destroy: (self: InteractionChipT) -> (),
}

function InteractionChip.new(props: Props): InteractionChipT
	local self: InteractionChipT = setmetatable({} :: any, InteractionChip)

	-- Configuration
	self.object = props.object
	self.key = props.key or Enum.KeyCode.E
	self.offset = props.offset or Vector3.new(0, 8, 0) -- Default offset above object
	self.onActivate = props.onActivate
	self.canActivate = props.canActivate
	self.isActive = false

	-- Create the ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "InteractionChip"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
	self.screenGui = screenGui

	-- Create container frame for positioning
	local container = Instance.new("Frame")
	container.Size = UDim2.new(0, 1, 0, 1)
	container.BackgroundTransparency = 1
	container.Visible = false
	container.Parent = screenGui
	self.containerFrame = container

	-- Create the chip using BaseChip
	local chip: BaseChipT = BaseChip.new({
		parent = container,
		size = UDim2.new(0, UIx.Size.BUTTON_WIDTH, 0, UIx.Size.BUTTON_HEIGHT),
		position = UIx.Common.ORIGIN,
		icon = props.icon,
		iconSize = UIx.Size.ICON_SMALL_PX,
		text = props.text,
		backgroundColor = Theme.colors.Surface,
		backgroundTransparency = 0.1,
		onClick = function()
			if self:canPerformAction() then
				self.onActivate()
			end
		end,
		squishIntensity = 0.95,
	}) :: any
	self.chip = chip

	-- Input handling
	self.inputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end

		if input.KeyCode == self.key and self.isActive then
			if self:canPerformAction() then
				self.onActivate()
			end
		end
	end)

	-- Position update loop
	self.heartbeatConnection = RunService.Heartbeat:Connect(function()
		self:updatePosition()
	end)

	log:debug("InteractionChip created for %s", props.text)

	return self
end

function InteractionChip:canPerformAction(): boolean
	if self.canActivate then
		return self.canActivate()
	end
	return true
end

function InteractionChip:updatePosition()
	if not self.object or not self.object.Parent then
		self:hide()
		return
	end

	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	-- Get object position
	local objectPos: Vector3?
	if self.object:IsA("Model") then
		local primaryPart = self.object.PrimaryPart
		if primaryPart then
			objectPos = primaryPart.Position
		else
			-- Fallback to model center
			local cf, _size = self.object:GetBoundingBox()
			objectPos = cf.Position
		end
	else
		objectPos = self.object.Position
	end

	if not objectPos then
		self:hide()
		return
	end

	-- Apply offset
	local worldPos = (objectPos :: Vector3) + self.offset

	-- Convert to screen position
	local screenPos, onScreen = camera:WorldToScreenPoint(worldPos)

	if onScreen and self.isActive then
		self.containerFrame.Position = UDim2.new(0, screenPos.X, 0, screenPos.Y)
		self.containerFrame.Visible = true

		-- Scale based on distance (optional subtle effect)
		local distance = (camera.CFrame.Position - worldPos).Magnitude
		local scale = math.clamp(1 - (distance - UIx.Spacing.LG) / (UIx.Spacing.LG * 4), 0.8, 1)
		self.chip.container.Size = UDim2.new(0, UIx.Size.BUTTON_WIDTH * scale, 0, UIx.Size.BUTTON_HEIGHT * scale)
	else
		self.containerFrame.Visible = false
	end
end

function InteractionChip:show()
	self.isActive = true
	self.containerFrame.Visible = true

	-- Animate in with a pop
	local container = self.chip.container
	container.Size = UDim2.new(0, UIx.Size.BUTTON_WIDTH * 0.85, 0, UIx.Size.BUTTON_HEIGHT * 0.875)
	local tween = TweenService:Create(
		container,
		TweenInfo.new(UIx.Anim.MEDIUM, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.new(0, UIx.Size.BUTTON_WIDTH, 0, UIx.Size.BUTTON_HEIGHT) }
	)
	tween:Play()
end

function InteractionChip:hide()
	self.isActive = false
	self.containerFrame.Visible = false
end

function InteractionChip:setText(text: string)
	self.chip:setText(text)
end

function InteractionChip:setIcon(icon: string)
	self.chip:setIcon(icon)
end

function InteractionChip:destroy()
	if self.inputConnection then
		self.inputConnection:Disconnect()
	end
	if self.heartbeatConnection then
		self.heartbeatConnection:Disconnect()
	end
	if self.chip then
		self.chip:destroy()
	end
	if self.screenGui then
		self.screenGui:Destroy()
	end
end

return InteractionChip
