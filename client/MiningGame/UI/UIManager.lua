--!strict
-- UIManager.lua
-- Core UI management system with scene-based architecture

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MathUtils = require(ReplicatedStorage:WaitForChild("MiningGame"):WaitForChild("MathUtils"))
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

-- Import Theme and UIUtils
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UIFolder = MiningGame:WaitForChild("UI")
local Time = require(MiningGame:WaitForChild("Time"))
local Theme = require(UIFolder:WaitForChild("Theme"))
local UIx = require(UIFolder:WaitForChild("UIConstants"))
local UIUtils = require(UIFolder:WaitForChild("UIUtils"))
local Timer = require(MiningGame:WaitForChild("Timer"))
local ClientError = require(MiningGame:WaitForChild("ClientError"))
local ThemeManager = require(UIFolder:WaitForChild("ThemeManager"))
local ThemeRefresher = require(UIFolder:WaitForChild("ThemeRefresher"))
local Logger = require(MiningGame:WaitForChild("Logger"))
local log = Logger.new("UIManager")
local TypesMgr = require(script.Parent:WaitForChild("Manager"):WaitForChild("Types"))
type SceneT = TypesMgr.SceneT
type UIManagerT = TypesMgr.UIManagerT
local TypesShared = require(MiningGame:WaitForChild("Types"))
type JsonValue = TypesShared.JsonValue
local Manager = require(script.Parent:WaitForChild("Manager"))
local Animations = Manager.Animations
local Widgets = Manager.Widgets
local Scenes = Manager.Scenes
local Layers = Manager.Layers
local Toasts = Manager.Toasts
local MiniPopup = Manager.MiniPopup

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Use Theme colors
local UI_COLORS = Theme.colors -- Will be updated in refreshTheme
local RARITY_COLORS = Theme.rarityColors

-- Types
type Scene = SceneT

-- color formatting moved to Toasts module

local UIManager = {}
UIManager.__index = UIManager

function UIManager.new()
	local self = setmetatable({}, UIManager)

	self.screenGui = nil :: ScreenGui?
	self.scenes = {} :: { [string]: Scene }
	self.activeScene = nil :: Scene?
	self.sceneStack = {} :: { Scene } -- Track scene stack for proper back navigation
	self.mainHUD = nil :: Frame?
	self.isInitialized = false
	self._cons = {} :: { RBXScriptConnection }
	self._transitionUnlockAt = 0 :: number -- Timestamp for transition cooldown
	self._watchdogNextCheckAt = 0 :: number -- Next watchdog check time
	self._watchdogLastVisibleAt = 0 :: number -- Last time UI was visible
	self._isRecovering = false :: boolean -- Prevent re-entry during recovery

	-- Toast queue management
	self._toastQueue = {} :: { TypesMgr.ToastQueueItem }
	self._toastActive = 0 :: number
	self._toastMaxVisible = Theme.toast.maxVisible or 3

	-- Optional mini-popup handle
	self._miniPopup = nil :: { anchor: Frame, chip: any, fadeOut: (() -> ())? }?

	-- Timer tracking for auto-cleanup
	self._timer = Timer.new()

	-- Animation defaults from Theme
	self.tweenInfo = Theme.animations.Standard

	-- Optional data provider for panels/tabs to read snapshots from
	type DataProvider = {
		getSnapshot: (self: DataProvider) -> { [string]: JsonValue }?,
		onChanged: (self: DataProvider) -> RBXScriptSignal,
	}
	self.accountDataProvider = nil :: DataProvider?

	return self
end

function UIManager:init()
	if self.isInitialized then
		return
	end

	-- Create main screen GUI with full-bleed layout (still notch-safe)
	self.screenGui = Instance.new("ScreenGui")
	self.screenGui.Name = "MiningGameUI"
	self.screenGui.ResetOnSpawn = false
	self.screenGui.DisplayOrder = 1
	self.screenGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	self.screenGui.ClipToDeviceSafeArea = true
	self.screenGui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
	self.screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	self.screenGui.IgnoreGuiInset = true
	self.screenGui.Parent = playerGui

	-- Container (unchanged)
	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.new(1, 0, 1, 0)
	container.BackgroundTransparency = 1
	container.Parent = self.screenGui

	-- Overlay GUI for modals only now (toasts moved to main container)
	self.overlayGui = Instance.new("ScreenGui")
	self.overlayGui.Name = "MiningGameUI_Overlay"
	self.overlayGui.ResetOnSpawn = false
	self.overlayGui.DisplayOrder = 100
	self.overlayGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	self.overlayGui.ClipToDeviceSafeArea = true
	self.overlayGui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
	self.overlayGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	self.overlayGui.IgnoreGuiInset = true
	self.overlayGui.Parent = playerGui

	-- Full-bleed overlay for truly centered elements (like action chip)
	self.fullBleedGui = Instance.new("ScreenGui")
	self.fullBleedGui.Name = "MiningGameUI_FullBleed"
	self.fullBleedGui.ResetOnSpawn = false
	self.fullBleedGui.DisplayOrder = 2 -- Above main UI but below modals
	self.fullBleedGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	self.fullBleedGui.IgnoreGuiInset = true
	self.fullBleedGui.ScreenInsets = Enum.ScreenInsets.None -- No safe area clipping
	self.fullBleedGui.ClipToDeviceSafeArea = false -- Full screen access
	self.fullBleedGui.Parent = playerGui

	self.fullBleedContainer = Instance.new("Frame")
	self.fullBleedContainer.Name = "FullBleedContainer"
	self.fullBleedContainer.Size = UDim2.fromScale(1, 1)
	self.fullBleedContainer.BackgroundTransparency = 1
	self.fullBleedContainer.Parent = self.fullBleedGui

	-- Bind the whole UI to ThemeRefresher so theme flips repaint everything
	ThemeRefresher.BindTree(self.screenGui)
	ThemeRefresher.BindTree(self.overlayGui)
	ThemeRefresher.BindTree(self.fullBleedGui)

	-- Removed UIScale - we want full screen UI without scaling

	-- Toast stack container (now inside main container, dynamically positioned)
	self.toastStack = Instance.new("Frame")
	self.toastStack.Name = "ToastStack"
	self.toastStack.BackgroundTransparency = 1
	self.toastStack.Parent = container -- Now parented to main container

	local stackLayout = Instance.new("UIListLayout")
	stackLayout.FillDirection = Enum.FillDirection.Vertical
	stackLayout.Padding = UDim.new(0, Theme.toast.gap)
	stackLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	stackLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	stackLayout.SortOrder = Enum.SortOrder.LayoutOrder
	stackLayout.Parent = self.toastStack
	self.toastLayout = stackLayout

	-- React to runtime theme changes
	table.insert(
		self._cons,
		ThemeManager.Changed():Connect(function()
			-- Repaint all bound instances, then update frosted surfaces and do any layout tweaks
			ThemeRefresher.Refresh()
			UIUtils.refreshFrosting()
			if self.refreshTheme then
				self:refreshTheme()
			end
		end)
	)

	-- Keep ScreenGuis attached to PlayerGui
	self:_bindAncestryGuard(self.screenGui)
	self:_bindAncestryGuard(self.overlayGui)

	-- Watchdog: scan ~2x/sec; recover if nothing visible for >1.5s
	self._watchdogLastVisibleAt = Time.mono()
	self._lastWatchdogLog = 0
	table.insert(
		self._cons,
		RunService.Heartbeat:Connect(function()
			local now = Time.mono()
			if now < self._watchdogNextCheckAt then
				return
			end
			self._watchdogNextCheckAt = now + 0.5

			local hasUI = self:_anyUIVisible()
			if hasUI then
				self._watchdogLastVisibleAt = now
				return
			end

			-- Log once per second when UI is missing
			if math.floor(now) ~= self._lastWatchdogLog then
				self._lastWatchdogLog = math.floor(now)
				log:debug(
					"Watchdog: No UI visible, will recover in %.1fs",
					MathUtils.saturatingSub(1.5, now - self._watchdogLastVisibleAt)
				)
			end

			if (now - self._watchdogLastVisibleAt) > 1.5 then
				log:debug("Watchdog triggered recovery!")
				self:_showMainHUDNow()
				self._watchdogLastVisibleAt = now
			end
		end)
	)

	-- Desktop hotkey escape hatch (F10 to recover)
	local UserInputService = game:GetService("UserInputService")
	if UserInputService.KeyboardEnabled then
		table.insert(
			self._cons,
			UserInputService.InputBegan:Connect(function(input, gp)
				if gp then
					return
				end
				if input.KeyCode == Enum.KeyCode.F10 then
					self:_showMainHUDNow()
					log:info("F10 triggered UI recovery")
				end
			end)
		)
	end

	-- Apply initial theme + position
	if self.refreshTheme then
		self:refreshTheme()
	else
		self:updateToastPosition()
	end

	self.container = container
	self.isInitialized = true

	log:info("Initialized with mobile-safe settings")
end

-- UIScale removed - no longer needed

function UIManager:refreshLayout()
	-- Update toast stack position based on current theme values
	self:updateToastPosition()
end

function UIManager:updateToastPosition()
	if not self.toastStack or not self.toastLayout then
		return
	end

	local chipConfig = Theme.currencyChip
	local topPosition = UIx.Spacing.LG + chipConfig.height + UIx.Spacing.SM -- Below chips with gap
	self.toastStack.Size = UDim2.new(0, Theme.toast.maxWidth, 0.5, 0)

	if Theme.toast.anchor == "topCenter" then
		self.toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		self.toastStack.AnchorPoint = Vector2.new(0.5, 0)
		self.toastStack.Position = UDim2.new(0.5, 0, 0, topPosition)
	else -- default to topRight
		self.toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
		self.toastStack.AnchorPoint = Vector2.new(1, 0)
		self.toastStack.Position = UDim2.new(1, -UIx.Spacing.LG, 0, topPosition)
	end
end

function UIManager:refreshTheme()
	-- Update the global colors reference
	UI_COLORS = Theme.colors
	RARITY_COLORS = Theme.rarityColors

	-- 1) If themes change gap/width/anchor, update those:
	if self.toastLayout then
		self.toastLayout.Padding = UDim.new(0, Theme.toast.gap)
	end

	-- Keep queue cap synced to theme
	self._toastMaxVisible = Theme.toast.maxVisible

	-- 2) Recompute exact position with chip height offset etc.
	self:updateToastPosition()

	-- 3) Refresh all active scenes to pick up new colors
	for _, scene in pairs(self.scenes) do
		if scene.frame and typeof(scene.refreshTheme) == "function" then
			scene:refreshTheme()
		end
	end
end

function UIManager:registerScene(scene: Scene)
	return Scenes.registerScene(self, scene)
end

-- cooldown helper moved to Scenes module

-- Timer helpers
function UIManager:_setTimeout(delay: number, fn: () -> ())
	return self._timer:set(delay, function()
		ClientError.try("UIManager:timer", fn)
	end)
end

function UIManager:_clearTimeout(h: thread?)
	if h then
		self._timer:clear(h)
	end
end

function UIManager:showScene(sceneName: string, ...)
	return Scenes.showScene(self, sceneName, ...)
end

function UIManager:hideScene(sceneName: string)
	return Scenes.hideScene(self, sceneName)
end

function UIManager:hideAllScenes()
	return Scenes.hideAllScenes(self)
end

function UIManager:createButton(parent: GuiObject, text: string, position: UDim2?, size: UDim2?): TextButton
	return Widgets.createButton(self, parent, text, position, size)
end

function UIManager:createPanel(parent: GuiObject, position: UDim2, size: UDim2, opts): Frame
	return Widgets.createPanel(self, parent, position, size, opts)
end

function UIManager:pulse(gui: GuiObject, scaleUp: number?)
	return Animations.pulse(self, gui, scaleUp)
end

function UIManager:animateIn(guiObject: GuiObject, animationType: string?)
	return Animations.animateIn(self, guiObject, animationType)
end

function UIManager:animateOut(guiObject: GuiObject, animationType: string?)
	return Animations.animateOut(self, guiObject, animationType)
end

function UIManager:formatNumber(value: number): string
	return UIUtils.formatNumber(value)
end

-- createCurrencyDisplay removed - now using modular CurrencyChip component

-- Compute toast duration once, reuse everywhere
function UIManager:_durationFor(message: string): number
	local t = Theme.toast
	local base = t.duration or 3.0
	local perChar = t.perChar or 0.02
	local minD = t.minDuration or 2.0
	local maxD = t.maxDuration or 6.0
	return math.clamp(base + #message * perChar, minD, maxD)
end

-- Single queue-or-spawn path for all toasts
-- args matches _spawnToastBase signature
function UIManager:_queueOrSpawn(args)
	return Toasts.queueOrSpawn(self, args)
end

-- Queue management for toasts - fills up to max capacity
function UIManager:_pumpToastQueue()
	return Toasts.pumpToastQueue(self)
end

-- Public interface for server announcements (player found item messages)
function UIManager:showServerAnnouncement(message: string, rarityColor: Color3)
	return Toasts.showServerAnnouncement(self, message, rarityColor)
end

-- Public interface for showing notifications with rarity coloring
function UIManager:showNotificationWithRarity(message: string, rarity: string)
	return Toasts.showNotificationWithRarity(self, message, rarity)
end

-- Public interface for showing notifications
function UIManager:showNotification(message: string, notificationType: string?)
	return Toasts.showNotification(self, message, notificationType)
end

-- Public interface for custom colored notifications (for banners)
function UIManager:showNotificationCustom(message: string, tintColor: Color3, iconText: string?)
	return Toasts.showNotificationCustom(self, message, tintColor, iconText)
end

-- Core toast builder - used by both plain and rarity toasts
function UIManager:_spawnToastBase(args: {
	labelText: string,
	iconText: string,
	accentColor: Color3,
	textColor: Color3?,
	richText: boolean,
	duration: number,
})
	self._toastActive = (self._toastActive :: number) + 1

	local tcfg = Theme.toast
	local colors = Theme.colors
	local _tint = args.accentColor

	-- Container controls height for collapse; child toast animates visuals/slide
	local container = Instance.new("Frame")
	container.Name = "ToastContainer"
	container.BackgroundTransparency = 1
	container.Size = UDim2.new(1, 0, 0, 0)
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.ClipsDescendants = true
	container.ZIndex = Theme.z.Notification
	container.Active = true -- Ensures it receives input on all platforms
	container.LayoutOrder = -Time.monoMs() -- Newest toasts appear first
	container.Parent = self.toastStack

	local toast = Instance.new("Frame")
	toast.Name = "Toast"
	toast.BackgroundColor3 = colors.Surface
	toast.BackgroundTransparency = Theme.effects.frosted.backgroundTransparency
	toast.Size = UDim2.new(1, 0, 0, 0)
	toast.AutomaticSize = Enum.AutomaticSize.Y
	toast.ZIndex = container.ZIndex + 1
	toast.Parent = container

	-- Glass edge border
	local stroke = UIUtils.applyGlassEdge(toast)

	-- Rounding
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.sizes.LargeCornerRadius)
	corner.Parent = toast

	-- Soft highlight using theme's frosted gradient values
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(Color3.new(1, 1, 1), colors.Surface)
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, Theme.effects.frosted.gradientTopT),
		NumberSequenceKeypoint.new(
			0.5,
			(Theme.effects.frosted.gradientTopT + Theme.effects.frosted.gradientBottomT) / 2
		),
		NumberSequenceKeypoint.new(1, Theme.effects.frosted.gradientBottomT),
	})
	grad.Parent = toast

	-- Keep children inside the rounded shape
	toast.ClipsDescendants = true

	-- Inset by the stroke thickness so content sits inside the bevel
	local inset = math.max(1, Theme.glassEdge.thickness)

	local clip = Instance.new("Frame")
	clip.Name = "ToastClip"
	clip.BackgroundTransparency = 1
	clip.Size = UDim2.new(1, -inset * 2, 0, 0) -- No Y scale in an auto-sized parent
	clip.AutomaticSize = Enum.AutomaticSize.Y -- Let content determine height
	clip.Position = UDim2.new(0, inset, 0, inset)
	clip.ClipsDescendants = true
	clip.ZIndex = toast.ZIndex + 1
	clip.Parent = toast

	local clipCorner = Instance.new("UICorner")
	clipCorner.CornerRadius = UDim.new(0, MathUtils.saturatingSub(Theme.sizes.LargeCornerRadius, inset))
	clipCorner.Parent = clip

	-- Left accent strip (now properly clipped)
	local accent = Instance.new("Frame")
	accent.BackgroundColor3 = args.accentColor
	accent.BackgroundTransparency = Theme.card.backgroundTransparency
	accent.Size = UDim2.new(0, UIx.ACCENT_WIDTH, 1, 0)
	accent.Position = UIx.Common.ORIGIN
	accent.ZIndex = clip.ZIndex + 1
	accent.Parent = clip

	-- Content row
	local content = Instance.new("Frame")
	content.BackgroundTransparency = 1
	content.Size = UDim2.new(1, -UIx.Spacing.SM, 0, 0)
	content.Position = UDim2.new(0, UIx.CORNER_SMALL, 0, 0)
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.ZIndex = clip.ZIndex + 1
	content.Parent = clip

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

	-- Icon
	local icon = Instance.new("TextLabel")
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromOffset(UIx.Size.ICON_SMALL_PX, UIx.Size.ICON_SMALL_PX)
	icon.Text = args.iconText
	icon.TextColor3 = args.accentColor
	icon.TextScaled = true
	icon.ZIndex = content.ZIndex + 1
	icon.Parent = content

	-- Message
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -(UIx.Size.ICON_SMALL_PX + UIx.Spacing.SM), 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.RichText = args.richText
	label.Text = args.labelText
	label.TextColor3 = args.textColor or colors.Text
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Font = Theme.fonts.Primary
	label.TextSize = Theme.textSizes.Medium.Max
	label.ZIndex = content.ZIndex + 1
	label.Parent = content

	-- Add text size constraint
	local textConstraint = Instance.new("UITextSizeConstraint")
	textConstraint.MinTextSize = Theme.textSizes.Medium.Min
	textConstraint.MaxTextSize = Theme.textSizes.Medium.Max
	textConstraint.Parent = label

	-- Entrance state (anchor-aware slide)
	local fromX = (tcfg.anchor == "topRight") and UIx.Spacing.LG or -UIx.Spacing.LG
	toast.Position = UDim2.new(0, fromX, 0, 0)
	toast.BackgroundTransparency = 1
	accent.BackgroundTransparency = 1
	icon.TextTransparency = 1
	label.TextTransparency = 1
	stroke.Transparency = 1
	container.Visible = true

	-- Animate in
	TweenService:Create(toast, Theme.animations.Quick, {
		BackgroundTransparency = Theme.effects.frosted.backgroundTransparency,
		Position = UIx.Common.ORIGIN,
	}):Play()
	TweenService:Create(accent, Theme.animations.Quick, {
		BackgroundTransparency = Theme.card.backgroundTransparency,
	}):Play()
	TweenService:Create(icon, Theme.animations.Quick, { TextTransparency = 0 }):Play()
	TweenService:Create(label, Theme.animations.Quick, { TextTransparency = 0 }):Play()
	TweenService:Create(stroke, Theme.animations.Quick, {
		Transparency = Theme.glassEdge.transparency,
	}):Play()

	local isDismissing = false
	local function dismissToast()
		if isDismissing then
			return
		end
		isDismissing = true

		-- Ensure container has a concrete height to tween
		RunService.Heartbeat:Wait()
		local collapseFrom = container.AbsoluteSize.Y
		container.AutomaticSize = Enum.AutomaticSize.None
		container.Size = UDim2.new(1, 0, 0, collapseFrom)

		-- Fade + slight slide
		local fadeOut = TweenService:Create(toast, Theme.animations.Quick, {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, fromX, 0, 0),
		})
		TweenService:Create(accent, Theme.animations.Quick, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(icon, Theme.animations.Quick, { TextTransparency = 1 }):Play()
		TweenService:Create(label, Theme.animations.Quick, { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, Theme.animations.Quick, { Transparency = 1 }):Play()
		-- Gradients can't be tweened, just set it directly for instant fade
		grad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 1),
		})

		local collapse = TweenService:Create(container, Theme.animations.Standard, {
			Size = UDim2.new(1, 0, 0, 0),
		})

		fadeOut:Play()
		collapse:Play()

		collapse.Completed:Connect(function()
			container:Destroy()
			self._toastActive = self._toastActive - 1
			self:_pumpToastQueue()
		end)
	end

	-- Auto dismiss
	self:_setTimeout(args.duration, dismissToast)

	-- Tap to dismiss
	container.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			dismissToast()
		end
	end)
end

function UIManager:getRarityColor(rarity: string): Color3
	if typeof(rarity) ~= "string" then
		return UI_COLORS.Text
	end
	-- Normalize to title case for lookup
	local key = rarity:sub(1, 1):upper() .. rarity:sub(2):lower()
	return RARITY_COLORS[key] or UI_COLORS.Text
end

-- Helper to bind ancestry guard to a GUI
function UIManager:_bindAncestryGuard(gui: Instance)
	return Layers.bindAncestryGuard(self, gui)
end

-- Is this GuiObject effectively visible? (self.Visible + all GuiObject parents Visible, and root ScreenGui Enabled)
local function _isEffectivelyVisible(inst: GuiObject, stopAt: Instance?)
	if not inst.Visible then
		return false
	end
	local p = inst.Parent
	while p and p ~= stopAt do
		if p:IsA("GuiObject") and (p.Visible == false) then
			return false
		end
		p = p.Parent
	end
	return true
end

-- A GuiObject is "visually meaningful" (not a transparent container / empty image/text)
local function _isMeaningfullyDrawn(inst: GuiObject): boolean
	-- Ignore explicit scrims/backdrops
	if inst:GetAttribute("isScrim") == true or inst.Name == "Scrim" then
		return false
	end

	local w, h = inst.AbsoluteSize.X, inst.AbsoluteSize.Y
	if w <= 2 or h <= 2 then
		return false
	end

	if inst:IsA("Frame") then
		-- Pure container? (nearly fully transparent)
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
		-- Other GuiObjects (ViewportFrame, etc.) – assume meaningful if not tiny
		return true
	end
end

local function _anyVisibleUnder(root: Instance?): boolean
	if not root then
		return false
	end
	for _, inst in ipairs(root:GetDescendants()) do
		if inst:IsA("GuiObject") then
			if _isEffectivelyVisible(inst, root) and _isMeaningfullyDrawn(inst) then
				return true
			end
		end
	end
	return false
end

-- Alias for cleanup
function UIManager:destroy()
	self:cleanup()
end

function UIManager:_anyUIVisible(): boolean
	return Layers.anyUIVisible(self)
end

function UIManager:_ensureRootsExist()
	return Layers.ensureRootsExist(self)
end

function UIManager:_showMainHUDNow()
	return Scenes.showMainHUDNow(self)
end

function UIManager:cleanup()
	-- Cancel delayed timers first
	if self._timer then
		self._timer:clearAll()
	end

	-- Disconnect all connections (including theme listener)
	for _, c in ipairs(self._cons) do
		if c.Connected then
			c:Disconnect()
		end
	end
	self._cons = {}

	do
		local sg = self.screenGui
		self.screenGui = nil
		if sg then
			sg:Destroy()
		end
	end

	do
		local og = self.overlayGui
		self.overlayGui = nil
		if og then
			og:Destroy()
		end
	end

	do
		local fb = self.fullBleedGui
		self.fullBleedGui = nil
		if fb then
			fb:Destroy()
		end
	end

	for _, scene in pairs(self.scenes) do
		if scene.cleanup then
			scene:cleanup()
		end
	end

	self.scenes = {}
	self.activeScene = nil
	self.isInitialized = false
end

--[[
-- Debug helpers (uncomment when needed)
function UIManager:enableDebugLogging()
    -- Add these lines where needed:
    -- print("[UIManager DEBUG] Initializing UIManager...")
    -- print("[UIManager DEBUG] Toast stack created, parent:", self.toastStack.Parent and self.toastStack.Parent:GetFullName() or "nil")
    -- print("[UIManager DEBUG] _queueOrSpawn called, active:", self._toastActive, "max:", self._toastMaxVisible)
    -- print("[UIManager DEBUG] Toast message:", args.labelText)
    -- print("[UIManager DEBUG] _spawnToastBase called")
    -- print("[UIManager DEBUG] Toast container created, parent:", container.Parent and container.Parent:GetFullName() or "nil")
end
--]]

-- Mini popup API (optional helper)
do
	function UIManager:showMiniPopup(message: string, iconText: string?, position: UDim2?)
		return MiniPopup.show(self, message, iconText, position)
	end
	function UIManager:hideMiniPopup()
		return MiniPopup.hide(self)
	end
end

return UIManager
