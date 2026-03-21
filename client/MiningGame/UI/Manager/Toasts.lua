--!strict
-- UI Toasts module: queued notifications, rarity formatting, and spawn logic

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Theme = require(MiningGame:WaitForChild("UI"):WaitForChild("Theme"))
local UIx = require(MiningGame:WaitForChild("UI"):WaitForChild("UIConstants"))

local Types = require(script.Parent:WaitForChild("Types"))
type UIManagerT = Types.UIManagerT

local Toasts = {}

local function color3ToHex(c: Color3): string
	local r = math.floor(c.R * 255 + 0.5)
	local g = math.floor(c.G * 255 + 0.5)
	local b = math.floor(c.B * 255 + 0.5)
	return string.format("%02X%02X%02X", r, g, b)
end

local function rarityColor(rarity: string): Color3
	if typeof(rarity) ~= "string" then
		return Theme.colors.Text
	end
	local key = rarity:sub(1, 1):upper() .. rarity:sub(2):lower()
	return Theme.rarityColors[key] or Theme.colors.Text
end

function Toasts.queueOrSpawn(
	self: UIManagerT,
	args: {
		labelText: string,
		iconText: string,
		accentColor: Color3,
		richText: boolean,
		duration: number,
		textColor: Color3?,
	}
)
	if self._toastActive >= self._toastMaxVisible then
		table.insert(self._toastQueue, { custom = args })
		task.defer(function()
			Toasts.pumpToastQueue(self)
		end)
		return
	end
	Toasts.spawnToastBase(self, args)
end

function Toasts.pumpToastQueue(self: UIManagerT)
	while self._toastActive < self._toastMaxVisible and #self._toastQueue > 0 do
		local nextItem = table.remove(self._toastQueue, 1)
		if not nextItem then
			break
		end
		if nextItem.custom then
			Toasts.spawnToastBase(self, nextItem.custom)
		elseif nextItem.rarityData and type(nextItem.message) == "string" then
			local color = rarityColor(nextItem.rarityData:upper())
			local hex = color3ToHex(color)
			local replacement =
				string.format('%%1%%2 <font color="#%s">(%s)</font>%%3', hex, nextItem.rarityData:upper())
			local rich = nextItem.message:gsub("^(Found )(.+)( x%d+)$", replacement)
			Toasts.spawnToastBase(self, {
				labelText = rich,
				iconText = "",
				accentColor = color,
				textColor = Theme.colors.Text,
				richText = true,
				duration = nextItem.duration or self:_durationFor(rich),
			})
		else
			local t = Theme.toast
			local kind = nextItem.kind or "info"
			local msgText = tostring(nextItem.message)
			Toasts.spawnToastBase(self, {
				labelText = msgText,
				iconText = (t.icon and t.icon[kind]) or (t.icon and t.icon.info) or "",
				accentColor = t.tint[kind] or t.tint.info,
				textColor = t.tint[kind] or t.tint.info,
				richText = false,
				duration = nextItem.duration or self:_durationFor(msgText),
			})
		end
	end
end

function Toasts.showServerAnnouncement(self: UIManagerT, message: string, rarityColor3: Color3)
	local msg = (message or ""):gsub("^%s*dY'Z%s*", "")
	local base, rarity = msg:match("^(.+ just found .+)%s*%(([^%)]+)%)%s*$")
	if not base or not rarity then
		base, rarity = msg:match("^(.+ just found .+)%s+(%u+)%s*$")
	end
	if not base or not rarity then
		return Toasts.showNotificationCustom(self, msg, rarityColor3, "")
	end
	local hex = color3ToHex(rarityColor3)
	local rich = string.format('%s <font color="#%s">%s</font>', base, hex, rarity:upper())
	Toasts.queueOrSpawn(self, {
		labelText = rich,
		iconText = "",
		accentColor = rarityColor3,
		richText = true,
		textColor = Theme.colors.Text,
		duration = self:_durationFor(rich),
	})
end

function Toasts.showNotificationWithRarity(self: UIManagerT, message: string, rarity: string)
	local color = rarityColor(rarity:upper())
	local hex = color3ToHex(color)
	local replacement = string.format('%%1%%2 <font color="#%s">(%s)</font>%%3', hex, rarity:upper())
	local rich = message:gsub("^(Found )(.+)( x%d+)$", replacement)
	Toasts.queueOrSpawn(self, {
		labelText = rich,
		iconText = "",
		accentColor = color,
		richText = true,
		textColor = Theme.colors.Text,
		duration = self:_durationFor(message),
	})
end

function Toasts.showNotification(self: UIManagerT, message: string, notificationType: string?)
	local t = Theme.toast
	local validTypes = { "info", "success", "error", "warning" }
	local kind = "info"
	if notificationType then
		for _, v in ipairs(validTypes) do
			if notificationType:lower() == v then
				kind = v
				break
			end
		end
	end
	local tint = t.tint[kind] or t.tint.info
	local icon = (t.icon and t.icon[kind]) or (t.icon and t.icon.info) or ""
	Toasts.queueOrSpawn(self, {
		labelText = message,
		iconText = icon,
		accentColor = tint,
		richText = false,
		textColor = tint,
		duration = self:_durationFor(message),
	})
end

function Toasts.showNotificationCustom(self: UIManagerT, message: string, tintColor: Color3, iconText: string?)
	Toasts.queueOrSpawn(self, {
		labelText = message,
		iconText = iconText or (Theme.toast.icon and Theme.toast.icon.info) or "",
		accentColor = tintColor,
		richText = false,
		textColor = tintColor,
		duration = self:_durationFor(message),
	})
end

function Toasts.spawnToastBase(
	self: UIManagerT,
	args: {
		labelText: string,
		iconText: string,
		accentColor: Color3,
		textColor: Color3?,
		richText: boolean,
		duration: number,
	}
)
	self._toastActive = self._toastActive + 1
	local tcfg = Theme.toast
	local colors = Theme.colors
	local _tint = args.accentColor

	local container = Instance.new("Frame")
	container.Name = "ToastContainer"
	container.BackgroundTransparency = 1
	container.Size = UDim2.new(1, 0, 0, 0)
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.ClipsDescendants = true
	container.ZIndex = Theme.z.Notification
	container.Active = true

	local toast = Instance.new("Frame")
	toast.Name = "Toast"
	toast.BackgroundColor3 = colors.Surface
	toast.BackgroundTransparency = 1
	toast.Size = UDim2.new(1, 0, 0, 0)
	toast.AutomaticSize = Enum.AutomaticSize.Y
	toast.Position = UIx.Common.ORIGIN
	toast.ZIndex = container.ZIndex + 1
	toast.Parent = container

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = Theme.glassEdge.thickness or 1
	stroke.LineJoinMode = Theme.glassEdge.lineJoinMode or Enum.LineJoinMode.Miter
	stroke.Transparency = 1
	stroke.Parent = toast

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.sizes.CornerRadius)
	corner.Parent = toast

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
	grad.Parent = toast

	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.BackgroundColor3 = _tint
	accent.BackgroundTransparency = Theme.card.backgroundTransparency
	accent.Size = UDim2.new(0, UIx.ACCENT_WIDTH, 1, 0)
	accent.Position = UIx.Common.ORIGIN
	accent.ZIndex = toast.ZIndex + 1
	accent.Parent = toast

	local content = Instance.new("Frame")
	content.BackgroundTransparency = 1
	content.Size = UDim2.new(1, -UIx.Spacing.SM, 0, 0)
	content.Position = UDim2.new(0, UIx.CORNER_SMALL, 0, 0)
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.ZIndex = toast.ZIndex + 1
	content.Parent = toast

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, UIx.CORNER_SMALL)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = content

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, tcfg.padding)
	pad.PaddingBottom = UDim.new(0, tcfg.padding)
	pad.PaddingLeft = UDim.new(0, tcfg.padding)
	pad.PaddingRight = UDim.new(0, tcfg.padding)
	pad.Parent = content

	local icon = Instance.new("TextLabel")
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromOffset(UIx.Size.ICON_SMALL_PX, UIx.Size.ICON_SMALL_PX)
	icon.Text = args.iconText
	icon.TextColor3 = args.accentColor
	icon.TextScaled = true
	icon.ZIndex = content.ZIndex + 1
	icon.Parent = content

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -(UIx.Size.ICON_SMALL_PX + UIx.Spacing.SM), 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.RichText = args.richText
	label.Text = args.labelText
	label.TextColor3 = args.textColor or Theme.colors.Text
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Font = Theme.fonts.Primary
	label.TextSize = Theme.textSizes.Medium.Max
	label.ZIndex = content.ZIndex + 1
	label.Parent = content

	local textConstraint = Instance.new("UITextSizeConstraint")
	textConstraint.MinTextSize = Theme.textSizes.Medium.Min
	textConstraint.MaxTextSize = Theme.textSizes.Medium.Max
	textConstraint.Parent = label

	local fromX = (tcfg.anchor == "topRight") and UIx.Spacing.LG or -UIx.Spacing.LG
	toast.Position = UDim2.new(0, fromX, 0, 0)
	toast.BackgroundTransparency = 1
	accent.BackgroundTransparency = 1
	icon.TextTransparency = 1
	label.TextTransparency = 1
	stroke.Transparency = 1
	if self.toastStack then
		self.toastStack.Visible = true
	end

	TweenService:Create(
		toast,
		Theme.animations.Quick,
		{ BackgroundTransparency = Theme.effects.frosted.backgroundTransparency, Position = UIx.Common.ORIGIN }
	):Play()
	TweenService:Create(accent, Theme.animations.Quick, { BackgroundTransparency = Theme.card.backgroundTransparency })
		:Play()
	TweenService:Create(icon, Theme.animations.Quick, { TextTransparency = 0 }):Play()
	TweenService:Create(label, Theme.animations.Quick, { TextTransparency = 0 }):Play()
	TweenService:Create(stroke, Theme.animations.Quick, { Transparency = Theme.glassEdge.transparency }):Play()

	local isDismissing = false
	local function dismissToast()
		if isDismissing then
			return
		end
		isDismissing = true
		game:GetService("RunService").Heartbeat:Wait()
		local collapseFrom = container.AbsoluteSize.Y
		container.AutomaticSize = Enum.AutomaticSize.None
		container.Size = UDim2.new(1, 0, 0, collapseFrom)

		local fadeOut = TweenService:Create(
			toast,
			Theme.animations.Quick,
			{ BackgroundTransparency = 1, Position = UDim2.new(0, fromX, 0, 0) }
		)
		TweenService:Create(accent, Theme.animations.Quick, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(icon, Theme.animations.Quick, { TextTransparency = 1 }):Play()
		TweenService:Create(label, Theme.animations.Quick, { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, Theme.animations.Quick, { Transparency = 1 }):Play()
		grad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 1) })

		local collapse = TweenService:Create(container, Theme.animations.Standard, { Size = UDim2.new(1, 0, 0, 0) })
		fadeOut:Play()
		collapse:Play()
		collapse.Completed:Connect(function()
			container:Destroy()
			self._toastActive = self._toastActive - 1
			Toasts.pumpToastQueue(self)
		end)
	end

	self:_setTimeout(args.duration, dismissToast)
	container.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			dismissToast()
		end
	end)

	if self.toastStack then
		container.Parent = self.toastStack
	end
end

return Toasts
