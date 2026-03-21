--!strict
-- Widgets.lua: small UI construction helpers for UIManager

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UI = MiningGame:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local UIx = require(UI:WaitForChild("UIConstants"))

local Widgets = {}

function Widgets.createButton(self, parent: GuiObject, text: string, position: UDim2?, size: UDim2?): TextButton
	local button = Instance.new("TextButton")
	button.Size = size or UDim2.new(0, UIx.Size.BUTTON_WIDTH, 0, UIx.Size.BUTTON_HEIGHT)
	button.Position = position or UIx.Common.ORIGIN
	button.BackgroundColor3 = Theme.colors.Primary
	button.TextColor3 = Theme.colors.Text
	button.Text = text
	button.Font = Enum.Font.SourceSansBold
	button.TextScaled = true
	button.AutoButtonColor = false
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, UIx.CORNER_SMALL)
	corner.Parent = button

	local textConstraint = Instance.new("UITextSizeConstraint")
	textConstraint.MinTextSize = UIx.Visual.TEXT_TINY
	textConstraint.MaxTextSize = UIx.Visual.TEXT_LARGE
	textConstraint.Parent = button

	button.MouseEnter:Connect(function()
		TweenService:Create(button, (self.tweenInfo or Theme.animations.Standard), {
			BackgroundColor3 = Theme.colors.Primary:Lerp(Color3.new(1, 1, 1), 0.2),
		}):Play()
	end)

	button.MouseLeave:Connect(function()
		TweenService:Create(button, (self.tweenInfo or Theme.animations.Standard), {
			BackgroundColor3 = Theme.colors.Primary,
		}):Play()
	end)

	button.Activated:Connect(function()
		-- optional pulse animation could be added here
	end)

	return button
end

function Widgets.createPanel(
	_self,
	parent: GuiObject,
	position: UDim2,
	size: UDim2,
	opts: { variant: ("glass" | "solid")?, border: ("ink" | "subtle")? }?
): Frame
	local options = (opts or ({} :: { variant: ("glass" | "solid")?, border: ("ink" | "subtle")? }))
	local variant = options.variant or "glass"
	local _border = options.border or "ink"

	local panel = Instance.new("Frame")
	panel.Size = size
	panel.Position = position
	panel.BackgroundColor3 = Theme.colors.Surface
	panel.BackgroundTransparency = (variant == "glass") and 0.15 or 0
	panel.BorderSizePixel = 0
	panel.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.sizes.LargeCornerRadius)
	corner.Parent = panel

	if variant == "glass" then
		local grad = Instance.new("UIGradient")
		grad.Rotation = 90
		grad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(1, Theme.colors.Surface),
		})
		grad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.6),
			NumberSequenceKeypoint.new(0.35, 0.8),
			NumberSequenceKeypoint.new(1, 0.9),
		})
		grad.Parent = panel
	end

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = Theme.glassEdge.thickness or 1
	stroke.LineJoinMode = Theme.glassEdge.lineJoinMode or Enum.LineJoinMode.Miter
	stroke.Transparency = Theme.glassEdge.transparency
	stroke.Parent = panel

	return panel
end

return Widgets
