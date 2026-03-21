--!strict
-- MiniPopup manager: wraps component show/hide with UIManager bookkeeping

local _Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local ClientError = require(MiningGame:WaitForChild("ClientError"))

local MiniPopupComponent = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("MiniPopup"))

local Types = require(script.Parent:WaitForChild("Types"))
type UIManagerT = Types.UIManagerT

local MiniPopup = {}

function MiniPopup.show(self: UIManagerT, message: string, iconText: string?, position: UDim2?)
	local ensure = self._ensureRootsExist
	if ensure then
		ensure(self)
	end
	local parent: GuiObject? = self.fullBleedContainer or self.container
	if not parent and self.screenGui then
		local anchor = Instance.new("Frame")
		anchor.Name = "MiniPopupAnchor"
		anchor.BackgroundTransparency = 1
		anchor.Size = UDim2.new(1, 0, 1, 0)
		anchor.Parent = self.screenGui
		parent = anchor
	end
	if not parent then
		return
	end

	if self._miniPopup then
		ClientError.try("UIManager", function()
			local mp = self._miniPopup
			if mp and mp.fadeOut then
				mp.fadeOut()
			else
				if mp and mp.chip then
					mp.chip:destroy()
				end
				if mp and mp.anchor then
					mp.anchor:Destroy()
				end
			end
		end)
		self._miniPopup = nil
	end

	local popup = MiniPopupComponent.show(parent, message, iconText, { position = position })
	self._miniPopup = {
		anchor = popup.anchor,
		chip = {
			destroy = function(_)
				if popup.fadeOut then
					popup.fadeOut()
				else
					popup.anchor:Destroy()
				end
			end,
		},
		fadeOut = popup.fadeOut,
	}
end

function MiniPopup.hide(self: UIManagerT)
	local mp = self._miniPopup
	if not mp then
		return
	end
	self._miniPopup = nil
	ClientError.try("UIManager", function()
		if mp.fadeOut then
			mp.fadeOut()
		else
			if mp.chip then
				mp.chip:destroy()
			end
			if mp.anchor then
				mp.anchor:Destroy()
			end
		end
	end)
end

return MiniPopup
