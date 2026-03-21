--!strict
-- Animations.lua: pulse and simple in/out animations for UIManager

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UI = MiningGame:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local UIUtils = require(UI:WaitForChild("UIUtils"))

local Animations = {}

function Animations.pulse(_self, gui: GuiObject, scaleUp: number?)
	UIUtils.pulse(gui, scaleUp)
end

function Animations.animateIn(self, guiObject: GuiObject, animationType: string?)
	local tweenInfo = (self.tweenInfo or Theme.animations.Standard)
	animationType = animationType or "fade"

	if animationType == "fade" then
		guiObject.Visible = true
		guiObject.BackgroundTransparency = 1
		TweenService:Create(guiObject, tweenInfo, {
			BackgroundTransparency = 0,
		}):Play()
	elseif animationType == "slide" then
		local originalPosition = guiObject.Position
		guiObject.Position = UDim2.new(
			originalPosition.X.Scale,
			originalPosition.X.Offset,
			originalPosition.Y.Scale,
			originalPosition.Y.Offset + 100
		)
		guiObject.Visible = true
		TweenService:Create(guiObject, tweenInfo, {
			Position = originalPosition,
		}):Play()
	elseif animationType == "scale" then
		local finalSize = guiObject.Size
		guiObject.Size = UDim2.fromOffset(0, 0)
		guiObject.Visible = true
		TweenService:Create(guiObject, tweenInfo, {
			Size = finalSize,
		}):Play()
	end
end

function Animations.animateOut(self, guiObject: GuiObject, animationType: string?)
	local tweenInfo = (self.tweenInfo or Theme.animations.Standard)
	animationType = animationType or "fade"

	local tween
	if animationType == "fade" then
		tween = TweenService:Create(guiObject, tweenInfo, {
			BackgroundTransparency = 1,
		})
	elseif animationType == "slide" then
		tween = TweenService:Create(guiObject, tweenInfo, {
			Position = UDim2.new(
				guiObject.Position.X.Scale,
				guiObject.Position.X.Offset,
				guiObject.Position.Y.Scale,
				guiObject.Position.Y.Offset + 100
			),
		})
	elseif animationType == "scale" then
		local originalSize = guiObject.Size
		tween = TweenService:Create(guiObject, tweenInfo, {
			Size = UDim2.fromOffset(0, 0),
		})
		tween.Completed:Connect(function()
			guiObject.Size = originalSize
		end)
	end

	if tween then
		tween:Play()
		tween.Completed:Connect(function()
			guiObject.Visible = false
		end)
	end
end

return Animations
