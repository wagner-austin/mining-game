--!strict
-- SettingsButton.lua
-- Minimal gear icon button with no background, just white icon

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Strict Theme typing mirrors actual Theme.lua
local _Theme = require(ReplicatedStorage:WaitForChild("MiningGame"):WaitForChild("UI"):WaitForChild("Theme"))
type ThemeSB = typeof(_Theme)
local Theme: ThemeSB = _Theme
local ThemeRefresher =
	require(ReplicatedStorage:WaitForChild("MiningGame"):WaitForChild("UI"):WaitForChild("ThemeRefresher"))
local ClientError = require(ReplicatedStorage:WaitForChild("MiningGame"):WaitForChild("ClientError"))

local SettingsButton = {}
SettingsButton.__index = SettingsButton

type Props = {
	parent: GuiObject,
	position: UDim2?,
	onClick: (() -> ())?,
}

export type SettingsButtonT = {
	container: Frame,
	rotator: Frame,
	button: TextButton,
	onClick: (() -> ())?,
	spinConnection: RBXScriptConnection?,
	targetSpeed: number,
	currentSpeed: number,
	_clickCooldown: boolean,
	_cooldownTimers: { thread },
	pulse: (self: SettingsButtonT) -> (),
	destroy: (self: SettingsButtonT) -> (),
}

type SettingsButtonShape = {
	container: Frame,
	rotator: Frame,
	button: TextButton,
	onClick: (() -> ())?,
	spinConnection: RBXScriptConnection?,
	targetSpeed: number,
	currentSpeed: number,
	_clickCooldown: boolean,
	_cooldownTimers: { thread },
}

function SettingsButton.new(props: Props): SettingsButtonT
	local colors = Theme.colors
	local config = Theme.settingsButton

	-- Outer container that centers in parent
	local container = Instance.new("Frame")
	container.Name = "SettingsButton"
	container.Size = UDim2.new(0, config.width, 0, config.height)
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.Position = UDim2.fromScale(0.5, 0.5)
	container.BackgroundTransparency = 1
	container.Parent = props.parent

	-- Inner frame for rotation (helps center the icon)
	local rotator = Instance.new("Frame")
	rotator.Name = "Rotator"
	rotator.Size = UDim2.fromScale(1, 1)
	rotator.BackgroundTransparency = 1
	rotator.AnchorPoint = Vector2.new(0.5, 0.5)
	rotator.Position = UDim2.new(0.5, 0, 0.5, -1) -- Move rotation axis up 1 pixel
	rotator.Parent = container

	-- Button with the icon
	local button = Instance.new("TextButton")
	button.Name = "Icon"
	button.Size = UDim2.fromScale(1, 1)
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale(0.5, 0.5) -- Keep it perfectly centered
	button.BackgroundTransparency = 1
	button.Text = Theme.icons.settings -- Use Theme icon
	button.TextColor3 = colors.Text -- White
	button.TextScaled = true
	button.Font = Theme.fonts.Primary
	button.TextXAlignment = Enum.TextXAlignment.Center -- Force center X
	button.TextYAlignment = Enum.TextYAlignment.Center -- Force center Y
	button.AutoButtonColor = false
	button.Parent = rotator

	-- Bind to theme refresher for automatic color updates
	ThemeRefresher.Bind(button, {
		TextColor3 = "Text",
	})

	-- Text size constraint from Theme
	local textConstraint = Instance.new("UITextSizeConstraint")
	textConstraint.MinTextSize = config.iconSize.Min
	textConstraint.MaxTextSize = config.iconSize.Max
	textConstraint.Parent = button

	-- Assemble instance table with all fields
	local timers: { thread } = {}
	local ret: SettingsButtonT = {
		container = container,
		rotator = rotator,
		button = button,
		onClick = props.onClick,
		spinConnection = nil,
		targetSpeed = 0,
		currentSpeed = 0,
		_clickCooldown = false,
		_cooldownTimers = timers,
		pulse = function() end,
		destroy = function() end,
	}
	-- Setup interactions inline
	do
		local RunService = game:GetService("RunService")
		local function startSpinLoop()
			if ret.spinConnection then
				return
			end
			ret.spinConnection = RunService.Heartbeat:Connect(function(dt)
				ret.currentSpeed = ret.currentSpeed + (ret.targetSpeed - ret.currentSpeed) * 0.1
				if math.abs(ret.currentSpeed) > 0.01 then
					ret.rotator.Rotation = ret.rotator.Rotation + (ret.currentSpeed * dt * 60)
				elseif ret.targetSpeed == 0 then
					if ret.spinConnection then
						ret.spinConnection:Disconnect()
						ret.spinConnection = nil
					end
				end
			end)
		end
		ret.button.MouseEnter:Connect(function()
			ret.targetSpeed = 1.5
			startSpinLoop()
			TweenService:Create(ret.button, Theme.animations.Quick, { TextTransparency = 0.1 }):Play()
		end)
		ret.button.MouseLeave:Connect(function()
			ret.targetSpeed = 0
			TweenService:Create(ret.button, Theme.animations.Quick, { TextTransparency = 0 }):Play()
		end)
		ret.button.Activated:Connect(function()
			if ret._clickCooldown then
				return
			end
			ret._clickCooldown = true
			local th
			th = task.delay(0.25, function()
				ret._clickCooldown = false
				for i, h in ipairs(ret._cooldownTimers) do
					if h == th then
						table.remove(ret._cooldownTimers, i)
						break
					end
				end
			end)
			table.insert(ret._cooldownTimers, th)
			local SoundManager = require(ReplicatedStorage.MiningGame:WaitForChild("SoundManager"))
			SoundManager.PlayUI("buttonclick")
			if ret.onClick then
				ret.onClick()
			end
		end)
	end
	-- Instance methods
	ret.pulse = function(self)
		local scale = Instance.new("UIScale")
		scale.Parent = self.container
		local tween = TweenService:Create(scale, Theme.animations.Quick, { Scale = 1.2 })
		local tweenBack = TweenService:Create(scale, Theme.animations.Smooth, { Scale = 1 })
		tween:Play()
		tween.Completed:Connect(function()
			tweenBack:Play()
			tweenBack.Completed:Connect(function()
				scale:Destroy()
			end)
		end)
	end
	ret.destroy = function(self)
		if self._cooldownTimers then
			for _, th in ipairs(self._cooldownTimers) do
				ClientError.try("SettingsButton.cancel", function()
					task.cancel(th)
				end)
			end
			self._cooldownTimers = {}
		end
		if self.spinConnection then
			self.spinConnection:Disconnect()
			self.spinConnection = nil
		end
		if self.container then
			self.container:Destroy()
		end
	end
	return ret
end

return SettingsButton
