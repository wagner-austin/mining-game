--!strict
-- Layers.lua: roots (ScreenGuis), ancestry guards, and visibility helpers

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UI = MiningGame:WaitForChild("UI")
local ThemeRefresher = require(UI:WaitForChild("ThemeRefresher"))
local ClientError = require(MiningGame:WaitForChild("ClientError"))

local Types = require(script.Parent:WaitForChild("Types"))
type UIManagerT = Types.UIManagerT

local Layers = {}

local function getPlayerGui(): PlayerGui
	local p = Players.LocalPlayer
	return p:WaitForChild("PlayerGui")
end

-- Is this GuiObject effectively visible? (self.Visible + all GuiObject parents Visible)
local function isEffectivelyVisible(inst: GuiObject, stopAt: Instance?): boolean
	if not inst.Visible then
		return false
	end
	local p = inst.Parent
	while p and p ~= stopAt do
		if p:IsA("GuiObject") and (p.Visible == false) then
			return false
		end
		if p:IsA("ScreenGui") and (p.Enabled == false) then
			return false
		end
		p = p.Parent
	end
	return true
end

-- A GuiObject is "visually meaningful" (not a transparent container / empty image/text)
local function isMeaningfullyDrawn(inst: GuiObject): boolean
	if inst:GetAttribute("isScrim") == true or inst.Name == "Scrim" then
		return false
	end
	local w, h = inst.AbsoluteSize.X, inst.AbsoluteSize.Y
	if w <= 2 or h <= 2 then
		return false
	end
	if inst:IsA("Frame") then
		return (inst.BackgroundTransparency or 0) < 0.99
	elseif inst:IsA("TextLabel") or inst:IsA("TextButton") then
		local tt = inst.TextTransparency or 0
		local bt = inst.BackgroundTransparency or 0
		return (tt < 0.99) or (bt < 0.99)
	elseif inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
		local it = inst.ImageTransparency or 0
		local bt = inst.BackgroundTransparency or 0
		return (it < 0.99) or (bt < 0.99)
	else
		return true
	end
end

local function anyVisibleUnder(root: Instance?): boolean
	if not root then
		return false
	end
	for _, inst in ipairs(root:GetDescendants()) do
		if inst:IsA("GuiObject") then
			if isEffectivelyVisible(inst, root) and isMeaningfullyDrawn(inst) then
				return true
			end
		end
	end
	return false
end

function Layers.anyUIVisible(self: UIManagerT): boolean
	if not self.screenGui or not self.screenGui.Parent then
		return false
	end
	if (self.screenGui.Enabled ~= nil) and (self.screenGui.Enabled == false) then
		return false
	end
	if self.activeScene and self.activeScene.name == "MainHUD" and self.activeScene.frame then
		return true
	end
	-- Scan the mounted roots; ScreenGui.Enabled is observed via isEffectivelyVisible
	return anyVisibleUnder(self.container) or anyVisibleUnder(self.screenGui)
end

function Layers.bindAncestryGuard(self: UIManagerT, gui: Instance)
	local playerGui = getPlayerGui()
	table.insert(
		self._cons,
		gui.AncestryChanged:Connect(function()
			if not gui:IsDescendantOf(playerGui) then
				local ok = ClientError.try("UIManager.ReparentGUI", function()
					gui.Parent = playerGui
				end)
				if not ok then
					return
				end
			end
		end)
	)
end

function Layers.ensureRootsExist(self: UIManagerT)
	local playerGui = getPlayerGui()

	do
		local sg0 = self.screenGui
		if not sg0 then
			local newSg = Instance.new("ScreenGui")
			newSg.Name = "MiningGameUI"
			newSg.ResetOnSpawn = false
			newSg.DisplayOrder = 1
			newSg.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
			newSg.ClipToDeviceSafeArea = true
			newSg.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
			newSg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
			newSg.IgnoreGuiInset = true
			newSg.Parent = playerGui
			self.screenGui = newSg
			ThemeRefresher.BindTree(newSg)
			Layers.bindAncestryGuard(self, newSg)
		else
			ClientError.try("UIManager.ReparentScreenGui", function()
				sg0.Parent = playerGui
			end)
			self.screenGui = sg0
			ThemeRefresher.BindTree(sg0)
			Layers.bindAncestryGuard(self, sg0)
		end
	end

	if not self.container or not self.container.Parent then
		local container = Instance.new("Frame")
		container.Name = "Container"
		container.Size = UDim2.new(1, 0, 1, 0)
		container.BackgroundTransparency = 1
		container.Parent = self.screenGui
		self.container = container
	end

	do
		local og0 = self.overlayGui
		if og0 then
			ClientError.try("UIManager.ReparentScreenGui", function()
				og0.Parent = playerGui
			end)
		end
		self.overlayGui = og0
	end

	if not self.overlayGui then
		local og = Instance.new("ScreenGui")
		og.Name = "MiningGameUI_Overlay"
		og.ResetOnSpawn = false
		og.DisplayOrder = 100
		og.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
		og.ClipToDeviceSafeArea = true
		og.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
		og.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		og.IgnoreGuiInset = true
		og.Parent = playerGui
		self.overlayGui = og
		ThemeRefresher.BindTree(og)
		Layers.bindAncestryGuard(self, og)
	end

	if not self.toastStack or not self.toastStack.Parent then
		local ts = Instance.new("Frame")
		ts.Name = "ToastStack"
		ts.BackgroundTransparency = 1
		ts.Parent = self.container
		self.toastStack = ts

		local stackLayout = Instance.new("UIListLayout")
		stackLayout.FillDirection = Enum.FillDirection.Vertical
		stackLayout.Padding = UDim.new(0, require(UI:WaitForChild("Theme")).toast.gap)
		stackLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
		stackLayout.VerticalAlignment = Enum.VerticalAlignment.Top
		stackLayout.SortOrder = Enum.SortOrder.LayoutOrder
		stackLayout.Parent = ts
		self.toastLayout = stackLayout

		do
			local up = self.updateToastPosition
			if up then
				up(self)
			end
		end
	end
end

return Layers
