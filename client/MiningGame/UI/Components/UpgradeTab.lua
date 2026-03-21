--!strict
-- UpgradeTab.lua — Profile upgrade panel component
-- Allows players to purchase upgrades using coins
-- Migrated to use BaseTabComponent for consistent UI patterns

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UIFolder = MiningGame:WaitForChild("UI")
-- Strict Theme typing mirrors actual Theme.lua
local _Theme = require(UIFolder:WaitForChild("Theme"))
type ThemeUT = typeof(_Theme)
local Theme: ThemeUT = _Theme
local UIx = require(UIFolder:WaitForChild("UIConstants"))
local UIUtils = require(UIFolder:WaitForChild("UIUtils"))
local GameConfig = require(MiningGame:WaitForChild("GameConfig"))
local Logger = require(MiningGame:WaitForChild("Logger"))
local ClientRF = require(MiningGame:WaitForChild("ClientRF"))
local BoostDefs = require(MiningGame:WaitForChild("BoostDefs"))
local Upgrades = require(MiningGame:WaitForChild("Upgrades"))
local ClientError = require(MiningGame:WaitForChild("ClientError"))
local UIFactory = require(MiningGame:WaitForChild("UI"):WaitForChild("Factory"))
local Types = require(MiningGame:WaitForChild("Types"))

-- Type definitions for RF responses
type UpgradeResponse = { success: boolean, reason: string?, newLevel: number? }
type TypedCaller<T> = (...Types.JsonValue) -> (T?, string?)

-- Typed RF calls for upgrades
local Calls = {
	PurchaseUpgrade = ClientRF.typed("PurchaseUpgrade") :: TypedCaller<UpgradeResponse>,
	-- GetProfile removed - now using PlayerProfileGuard via AccountDataProvider
}

local BaseTabComponent = require(script.Parent:WaitForChild("BaseTabComponent"))

local log = Logger.new("UpgradeTab")

-- UIUtils is required; no optional fallback

local UpgradeTab = {}
UpgradeTab.__index = UpgradeTab
setmetatable(UpgradeTab, { __index = BaseTabComponent })

type Props = {
	parent: GuiObject,
	position: UDim2?,
	size: UDim2?,
	dataProvider: BaseTabComponent.DataProvider?, -- injected provider
}

type TweenT = Tween

export type UpgradeTab = BaseTabComponent.BaseTab & {
	-- tab-local state
	_upgradeCards: { [string]: Frame },
	_upgradeButtons: { [string]: TextButton },
	_progressBars: { [string]: Frame },
	_valueFormatters: { [string]: (number) -> string },
	_pending: { [string]: boolean },
	_progressTweens: { [string]: TweenT },
	-- _labels and _dataProvider inherited from BaseTabComponent.BaseTab

	-- local methods (declare for analyzer visibility)
	_sectionCard: (self: UpgradeTab, height: number?) -> Frame,
	_createCurrencySection: (self: UpgradeTab) -> (),
	_createSpeedUpgradeSection: (self: UpgradeTab) -> (),
	_createSizeUpgradeSection: (self: UpgradeTab) -> (),
	_createUpgradeSection: (
		self: UpgradeTab,
		upgradeType: string,
		config: { title: string, icon: string, description: string, getValueText: (number) -> string }
	) -> (),
	_applySnapshot: (self: UpgradeTab, snapshot: { [string]: Types.JsonValue }, string?, Types.JsonValue?) -> (),
	_purchaseUpgrade: (self: UpgradeTab, upgradeType: string) -> (),
	_updateUpgrade: (self: UpgradeTab, upgradeType: string, profile: ProfileT) -> (),

	-- ctor
	new: (props: Props) -> UpgradeTab,
}

-- Profile shape used by data provider snapshots
type ProfileT = { coins: number?, upgrades: { [string]: number }? }

function UpgradeTab.new(props: Props): UpgradeTab
	-- Initialize base component with stacked=true for vertical sections
	local baseAny: any = BaseTabComponent.new({
		parent = props.parent,
		position = props.position,
		size = props.size,
		dataProvider = props.dataProvider,
		stacked = true,
		name = "UpgradeTab",
	})

	-- Create typed instance by subclassing base
	local self: UpgradeTab = setmetatable(baseAny, UpgradeTab)

	-- Tab-specific state (initialized here)
	self._upgradeCards = {} :: { [string]: Frame }
	self._upgradeButtons = {} :: { [string]: TextButton }
	self._progressBars = {} :: { [string]: Frame }
	self._valueFormatters = {} :: { [string]: (number) -> string }
	self._pending = {} :: { [string]: boolean }
	self._progressTweens = {} :: { [string]: TweenT }

	log:info("[UpgradeTab] Initializing with dataProvider: %s", tostring(props.dataProvider))

	-- Tab-specific state (already created above)

	-- Build UI sections
	self:_createCurrencySection()
	self:_createSpeedUpgradeSection()
	self:_createSizeUpgradeSection()

	-- Hook data provider if available (base handles initial connection)
	if props.dataProvider then
		self:connectDataProvider(props.dataProvider, function(snapshot)
			self:_applySnapshot(snapshot)
		end)
	end

	return self
end

function UpgradeTab._sectionCard(self: UpgradeTab, height: number?): Frame
	-- Use base component's section card helper
	return self:createSectionCard(self.container, {
		size = height and UDim2.new(1, 0, 0, height) or nil,
		autoSize = not height,
	})
end

function UpgradeTab._createCurrencySection(self: UpgradeTab)
	local section = self:_sectionCard(UIx.Size.UPGRADE_COINS_HEIGHT)

	-- Title
	self:createSectionTitle(section, "Available Currency")

	-- Coins display
	local coinsFrame = Instance.new("Frame")
	coinsFrame.Size = UDim2.new(1, 0, 0, UIx.Size.ICON_LARGE_PX)
	coinsFrame.BackgroundTransparency = 1
	coinsFrame.LayoutOrder = 1
	coinsFrame.Parent = section

	local coinIcon = Instance.new("TextLabel")
	coinIcon.Size = UIx.square(UIx.Size.ICON_LARGE_PX)
	coinIcon.BackgroundTransparency = 1
	coinIcon.Text = "💰"
	coinIcon.TextScaled = true
	coinIcon.Font = self._theme.fonts.Primary
	coinIcon.Parent = coinsFrame

	local coinsLabel = self:createLabel(coinsFrame, "0", {
		position = UDim2.new(0, UIx.Size.ICON_LARGE_PX + UIx.Spacing.SECTION, 0, 0),
		size = UDim2.new(1, -(UIx.Size.ICON_LARGE_PX + UIx.Spacing.SECTION), 0, UIx.Size.ICON_LARGE_PX),
		alignment = Enum.TextXAlignment.Left,
		textSize = UIx.Visual.TEXT_TITLE,
	})

	self._labels.coins = coinsLabel
end

function UpgradeTab._createSpeedUpgradeSection(self: UpgradeTab)
	self:_createUpgradeSection("speed", {
		title = "Dig Speed",
		icon = BoostDefs.icons().speed,
		description = "Reduce delay between digs",
		getValueText = function(level: number): string
			local def = Upgrades.getLevelDef("speed", level) :: Upgrades.SpeedLevelDef?
			if def and type(def) == "table" then
				local mult = (type(def.multiplier) == "number") and def.multiplier or 1
				local delay: number = GameConfig.Digging.BASE_DIG_DELAY * mult
				return string.format("%.2fs delay", delay)
			end
			return "—"
		end,
	})
end

function UpgradeTab._createSizeUpgradeSection(self: UpgradeTab)
	self:_createUpgradeSection("size", {
		title = "Dig Size",
		icon = "📦",
		description = "Increase the area you dig",
		getValueText = function(level: number): string
			local def = Upgrades.getLevelDef("size", level) :: Upgrades.SizeLevelDef?
			if def and type(def) == "table" then
				local size = (type(def.size) == "number") and def.size or 0
				local diameter: number = size * 2 + 1
				local volume: number = diameter * diameter * diameter
				return string.format("%dx%dx%d (%d cells)", diameter, diameter, diameter, volume)
			end
			return "—"
		end,
	})
end

function UpgradeTab._createUpgradeSection(
	self: UpgradeTab,
	upgradeType: string,
	config: {
		title: string,
		icon: string,
		description: string,
		getValueText: (number) -> string,
	}
)
	local section = self:_sectionCard()
	self._upgradeCards[upgradeType] = section

	-- Title row container (contains icon, title, level)
	local titleRow = Instance.new("Frame")
	titleRow.Size = UDim2.new(1, 0, 0, UIx.Size.ICON_LARGE_PX + UIx.Size.ROW_TINY)
	titleRow.BackgroundTransparency = 1
	titleRow.LayoutOrder = 1
	titleRow.Parent = section

	local icon = Instance.new("TextLabel")
	icon.Size = UIx.square(UIx.Size.ICON_MEDIUM_PX)
	icon.Position = UDim2.new(0, 0, 0, UIx.Spacing.TINY / 2)
	icon.BackgroundTransparency = 1
	icon.Text = config.icon
	icon.TextScaled = true
	icon.Font = self._theme.fonts.Primary
	icon.Parent = titleRow

	self:createLabel(titleRow, config.title, {
		position = UDim2.new(0, UIx.Size.ICON_MEDIUM_PX + UIx.Spacing.SECTION, 0, 0),
		size = UDim2.new(0.5, -(UIx.Size.ICON_MEDIUM_PX + UIx.Spacing.SECTION), 0, UIx.Size.ROW_STANDARD),
		alignment = Enum.TextXAlignment.Left,
		textSize = UIx.Visual.TEXT_HEADER,
	})

	local levelLabel = self:createLabel(titleRow, "Level 0/15", {
		position = UDim2.new(0.5, 0, 0, 0),
		size = UDim2.new(0.5, 0, 0, UIx.Size.ROW_STANDARD),
		alignment = Enum.TextXAlignment.Right,
		textSize = UIx.Visual.TEXT_BODY,
		isDim = true,
	})
	self._labels[upgradeType .. "_level"] = levelLabel

	-- Description (positioned below title within the same container)
	self:createLabel(titleRow, config.description, {
		position = UDim2.new(
			0,
			UIx.Size.ICON_MEDIUM_PX + UIx.Spacing.SECTION,
			0,
			UIx.Size.ROW_STANDARD + UIx.Spacing.TINY / 2
		),
		size = UDim2.new(1, -(UIx.Size.ICON_MEDIUM_PX + UIx.Spacing.SECTION), 0, UIx.Size.ROW_TINY),
		alignment = Enum.TextXAlignment.Left,
		textSize = UIx.Visual.TEXT_SMALL,
		isDim = true,
	})

	-- Progress bar (via UIFactory)
	local _progressBg, progressFill =
		UIFactory.progressBar({ parent = section, height = UIx.Size.PROGRESS_HEIGHT, layoutOrder = 2 })

	self._progressBars[upgradeType] = progressFill

	-- Stats row
	local statsRow = Instance.new("Frame")
	statsRow.Size = UDim2.new(1, 0, 0, UIx.Size.ROW_STANDARD)
	statsRow.BackgroundTransparency = 1
	statsRow.LayoutOrder = 3
	statsRow.Parent = section

	local currentLabel = self:createLabel(statsRow, "Current: —", {
		position = UDim2.new(0, 0, 0, 0),
		size = UDim2.new(0.5, -UIx.Spacing.XS, 1, 0),
		alignment = Enum.TextXAlignment.Left,
		textSize = UIx.Visual.TEXT_SMALL,
		isDim = true,
	})
	self._labels[upgradeType .. "_current"] = currentLabel

	local nextLabel = self:createLabel(statsRow, "Next: —", {
		position = UDim2.new(0.5, UIx.Spacing.XS, 0, 0),
		size = UDim2.new(0.5, -UIx.Spacing.XS, 1, 0),
		alignment = Enum.TextXAlignment.Right,
		textSize = UIx.Visual.TEXT_SMALL,
		isDim = false, -- Will be green text
	})
	self._labels[upgradeType .. "_next"] = nextLabel

	-- Cost and button row
	local buttonRow = Instance.new("Frame")
	buttonRow.Size = UDim2.new(1, 0, 0, UIx.Size.BUTTON_MEDIUM_HEIGHT)
	buttonRow.BackgroundTransparency = 1
	buttonRow.LayoutOrder = 4
	buttonRow.Parent = section

	local costLabel = self:createLabel(buttonRow, "Cost: —", {
		position = UDim2.new(0, 0, 0, 0),
		size = UDim2.new(0.5, -UIx.Spacing.XS, 1, 0),
		alignment = Enum.TextXAlignment.Left,
		textSize = UIx.Visual.TEXT_BODY,
		isDim = false,
	})
	self._labels[upgradeType .. "_cost"] = costLabel

	-- Custom button since we need special states
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0.5, -UIx.Spacing.XS, 1, 0)
	button.Position = UDim2.new(0.5, UIx.Spacing.XS, 0, 0)
	button.BackgroundColor3 = self._theme.colors.Primary
	button.Text = "UPGRADE"
	button.TextColor3 = self._theme.colors.OnPrimary
	button.Font = self._theme.fonts.Primary
	button.TextSize = UIx.Visual.TEXT_BODY
	button.AutoButtonColor = false
	button.Parent = buttonRow

	self:bindToTheme(button, { BackgroundColor3 = "Primary", TextColor3 = "OnPrimary" })

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, self._theme.sizes.CornerRadius)
	btnCorner.Parent = button

	-- Re-apply non-bound props on theme change
	self:_addThemeUpdater(function()
		btnCorner.CornerRadius = UDim.new(0, Theme.sizes.CornerRadius)
	end)

	self:addConnection(button.MouseEnter:Connect(function()
		if button:GetAttribute("CanAfford") ~= false then
			TweenService:Create(button, TweenInfo.new(UIx.Anim.QUICK), {
				BackgroundTransparency = Theme.button.surfaceHoverTransparency or 0.5,
			}):Play()
		end
	end))

	self:addConnection(button.MouseLeave:Connect(function()
		if button:GetAttribute("CanAfford") ~= false then
			TweenService:Create(button, TweenInfo.new(UIx.Anim.QUICK), {
				BackgroundTransparency = 0,
			}):Play()
		end
	end))

	self:addConnection(button.Activated:Connect(function()
		self:_purchaseUpgrade(upgradeType)
	end))

	UIUtils.pulse(button, 0.95)

	self._upgradeButtons[upgradeType] = button

	-- Store formatter for value updates
	self._valueFormatters[upgradeType] = config.getValueText

	-- Adjust section height
	section.Size = UDim2.new(1, 0, 0, UIx.Size.UPGRADE_SECTION_HEIGHT)
end

--

function UpgradeTab._purchaseUpgrade(self: UpgradeTab, upgradeType: string)
	log:info("[UpgradeTab] Purchase requested for: %s", upgradeType)

	-- Guard against spam clicks
	if self._pending[upgradeType] then
		log:debug("[UpgradeTab] Purchase already pending for: %s", upgradeType)
		return
	end

	-- Check if already at max level
	local provider = self._dataProvider
	local snapshot: any = nil
	if provider and provider.getSnapshot then
		snapshot = provider:getSnapshot()
	end
	snapshot = snapshot or { profile = {} }
	local profile: ProfileT? = (snapshot :: any).profile or nil
	if not profile then
		return
	end
	local upgrades = profile.upgrades or {}
	local currentLevel = upgrades[upgradeType] or 0
	local maxLevel = 0
	if upgradeType == "speed" or upgradeType == "size" then
		maxLevel = Upgrades.getMaxLevel(upgradeType)
	end

	log:debug("[UpgradeTab] Current level: %d, Max level: %d, Coins: %d", currentLevel, maxLevel, profile.coins or 0)

	if currentLevel >= maxLevel then
		log:info("[UpgradeTab] Already at max level for: %s", upgradeType)
		return
	end

	-- Client-side affordability guard
	local button = self._upgradeButtons[upgradeType]
	if button and button:GetAttribute("CanAfford") == false then
		-- Quick feedback, no server roundtrip
		button.Text = "NOT ENOUGH"
		button.BackgroundColor3 = self._theme.colors.Error
		task.wait(UIx.Anim.SLOW + UIx.Anim.SMOOTH) -- Wait for animation completion
		button.BackgroundColor3 = self._theme.colors.Surface
		button.TextColor3 = self._theme.colors.TextSecondary
		button.Text = "INSUFFICIENT"
		return
	end

	self._pending[upgradeType] = true
	if button then
		button.Text = "PURCHASING..."
		button.AutoButtonColor = false
	end

	-- Play click sound
	local sm = MiningGame:FindFirstChild("SoundManager")
	if sm then
		ClientError.try("UpgradeTab.Sound", function()
			require(sm).PlayUI("buttonclick")
		end)
	end

	-- Call server remote
	log:info("[UpgradeTab] Calling server for upgrade: %s", upgradeType)
	local result, err = Calls.PurchaseUpgrade(upgradeType)

	log:debug("[UpgradeTab] Server response - error: %s, result: %s", tostring(err), tostring(result))

	if err then
		-- Handle call failure
		if button then
			button.Text = "FAILED"
			button.BackgroundColor3 = self._theme.colors.Error
			self:setTimeout(1, function()
				if not button then
					return
				end
				button.BackgroundColor3 = self._theme.colors.Primary
				button.Text = "UPGRADE"
				button.AutoButtonColor = true
			end)
		end
		self._pending[upgradeType] = false
		log:error("[UpgradeTab] Purchase call failed for %s: %s", upgradeType, err)
		return
	end

	if not err and result and result.success then
		log:info("[UpgradeTab] Upgrade purchased: %s - level %s", upgradeType, tostring(result.newLevel or "unknown"))
		-- Visual feedback
		if button then
			button.Text = "SUCCESS!"
			button.BackgroundColor3 = self._theme.colors.Success
			self:setTimeout(1, function()
				if not button then
					return
				end
				button.BackgroundColor3 = self._theme.colors.Primary
				button.Text = "UPGRADE"
				button.AutoButtonColor = true
			end)
		end
	else
		local reason = err or (result and result.reason) or "Unknown reason"
		log:warn("[UpgradeTab] Upgrade failed: %s - reason: %s", upgradeType, reason)
		-- Error feedback
		if button then
			local originalText = "UPGRADE"
			if reason == "Insufficient coins" then
				button.Text = "NOT ENOUGH"
			else
				button.Text = reason or "FAILED"
			end
			button.BackgroundColor3 = self._theme.colors.Error
			self:setTimeout(1.5, function()
				if not button then
					return
				end
				button.BackgroundColor3 = self._theme.colors.Primary
				button.Text = originalText
				button.AutoButtonColor = true
			end)
		end
	end

	self._pending[upgradeType] = false

	-- Don't force refresh - provider will update via events
end

function UpgradeTab._applySnapshot(
	self: UpgradeTab,
	snapshot: { profile: ProfileT, lastUpdated: number?, isLoading: boolean? }
)
	log:debug("[UpgradeTab] Applying snapshot")
	local profile: ProfileT
	if snapshot.profile then
		profile = snapshot.profile
	else
		profile = {}
	end

	log:debug(
		"[UpgradeTab] Profile data - coins: %s, speed upgrade: %s, size upgrade: %s",
		profile.coins or "nil",
		profile.upgrades and profile.upgrades.speed or "nil",
		profile.upgrades and profile.upgrades.size or "nil"
	)

	-- Helper for safe formatting
	local function fmt(n: number): string
		return UIUtils.formatNumber(n)
	end

	-- Update coins
	if self._labels.coins and profile.coins ~= nil then
		self._labels.coins.Text = fmt(profile.coins)
	end

	-- Update each upgrade
	self:_updateUpgrade("speed", profile)
	self:_updateUpgrade("size", profile)
end

function UpgradeTab._updateUpgrade(self: UpgradeTab, upgradeType: string, profile: ProfileT)
	log:debug("[UpgradeTab] Updating upgrade: %s", upgradeType)

	local upgrades = profile.upgrades or {}
	local currentLevel = upgrades[upgradeType] or 0
	local coins = profile.coins or 0

	log:debug("[UpgradeTab] %s - current level: %d, coins: %d", upgradeType, currentLevel, coins)

	-- Get level definitions
	local maxLevel = 0
	if upgradeType == "speed" or upgradeType == "size" then
		maxLevel = Upgrades.getMaxLevel(upgradeType)
	end

	-- Get current and next definitions
	-- currentDef not used here; rely on nextDef for UI
	local nextDef = nil
	if upgradeType == "speed" or upgradeType == "size" then
		nextDef = Upgrades.getLevelDef(upgradeType, currentLevel + 1)
	end

	-- Update level label
	local levelLabel = self._labels[upgradeType .. "_level"]
	if levelLabel then
		levelLabel.Text = string.format("Level %d/%d", currentLevel, maxLevel)
	end

	-- Update progress bar with de-duplication
	local progressBar = self._progressBars[upgradeType]
	if progressBar then
		local progress = maxLevel > 0 and (currentLevel / maxLevel) or 0

		-- Cancel previous tween if exists
		if self._progressTweens[upgradeType] then
			self._progressTweens[upgradeType]:Cancel()
		end

		-- Create and play new tween
		local tween = TweenService:Create(progressBar, TweenInfo.new(UIx.Anim.SMOOTH), {
			Size = UDim2.new(progress, 0, 1, 0),
		})
		self._progressTweens[upgradeType] = tween
		tween:Play()
	end

	-- Get value formatter from memory
	local getValueText = self._valueFormatters[upgradeType]

	-- Update current value
	local currentLabel = self._labels[upgradeType .. "_current"]
	if currentLabel and getValueText then
		currentLabel.Text = "Current: " .. getValueText(currentLevel)
	end

	-- Update next value
	local nextLabel = self._labels[upgradeType .. "_next"]
	if nextLabel and getValueText then
		if nextDef then
			nextLabel.Text = "Next: " .. getValueText(currentLevel + 1)
			nextLabel.TextColor3 = self._theme.colors.Success
		else
			nextLabel.Text = "MAX LEVEL"
			nextLabel.TextColor3 = self._theme.colors.Accent
		end
	end

	-- Update cost
	local costLabel = self._labels[upgradeType .. "_cost"]
	if costLabel then
		if nextDef then
			local cost = nextDef.cost
			costLabel.Text = string.format("Cost: %s 💰", UIUtils.formatNumber(cost))
			costLabel.TextColor3 = coins >= cost and self._theme.colors.Success or self._theme.colors.Error
		else
			costLabel.Text = "MAX LEVEL"
			costLabel.TextColor3 = self._theme.colors.Accent
		end
	end

	-- Update button state
	local button = self._upgradeButtons[upgradeType]
	if button then
		if nextDef then
			local cost = nextDef.cost
			local canAfford = coins >= cost
			button:SetAttribute("CanAfford", canAfford)

			if canAfford then
				button.Text = "UPGRADE"
				button.BackgroundColor3 = self._theme.colors.Primary
				button.BackgroundTransparency = 0
				button.TextColor3 = self._theme.colors.OnPrimary
				button.AutoButtonColor = true
			else
				button.Text = "INSUFFICIENT"
				button.BackgroundColor3 = self._theme.colors.Surface
				button.BackgroundTransparency = 0
				button.TextColor3 = self._theme.colors.TextDim
				button.AutoButtonColor = false
			end
		else
			button:SetAttribute("CanAfford", false)
			button.Text = "MAX LEVEL"
			button.BackgroundColor3 = self._theme.colors.Surface
			button.BackgroundTransparency = 0
			button.TextColor3 = self._theme.colors.TextDim
			button.AutoButtonColor = false
		end
	end
end

-- removed _formatNumber; using UIUtils.formatNumber strictly

-- Override destroy for tab-specific cleanup
function UpgradeTab:destroy()
	-- Cancel any active progress tweens
	for _, tween in pairs(self._progressTweens) do
		if tween then
			tween:Cancel()
		end
	end

	-- Clear tab-specific state
	self._upgradeCards = {}
	self._upgradeButtons = {}
	self._progressBars = {}
	self._valueFormatters = {}
	self._pending = {}
	self._progressTweens = {}

	-- Call base destroy (handles connections, container, periodic updates)
	BaseTabComponent.destroy(self)
end

return UpgradeTab
