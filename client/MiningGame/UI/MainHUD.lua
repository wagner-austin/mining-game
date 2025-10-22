--!strict
-- MainHUD.lua
-- Main game HUD with currency display and extraction progress bar

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UI = MiningGame:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local UIx = require(UI:WaitForChild("UIConstants"))
local CurrencyChip = require(script.Parent:WaitForChild("Components"):WaitForChild("CurrencyChip"))
local HomeButton = require(script.Parent:WaitForChild("Components"):WaitForChild("HomeButton"))
local SettingsButton = require(script.Parent:WaitForChild("Components"):WaitForChild("SettingsButton"))
local GameConfig = require(MiningGame:WaitForChild("GameConfig"))
local BaseChip = require(script.Parent:WaitForChild("Components"):WaitForChild("BaseChip"))
local ClientRF = require(MiningGame:WaitForChild("ClientRF"))
local Logger = require(MiningGame:WaitForChild("Logger"))
local log = Logger.new("MainHUD")

local MainHUD = {}
MainHUD.__index = MainHUD

    type MainHUDT = typeof(setmetatable({} :: any, MainHUD)) & {
        name: string,
        frame: Frame?,
    topRightGroup: Frame?,
    centerTopGroup: Frame?,
    coinsChip: any?,
    gemsChip: any?,
    homeButton: any?,
    settingsButton: any?,
    actionChip: any?,
    _cons: {RBXScriptConnection},
    _activeTweens: {any},
        _hideTask: thread?,
        _actionHideTask: thread?,
        _timers: {thread},
        new: () -> MainHUDT,
    }

function MainHUD.new(): MainHUDT
    return setmetatable({
        name = "MainHUD",
        frame = nil :: Frame?,
        _cons = {},
        _activeTweens = {}, -- Track active tweens to cancel them
        _hideTask = nil,    -- Track hide delay task
        _actionHideTask = nil, -- Track action chip hide timeout
        _timers = {} :: {thread}, -- Track timers for cleanup
    }, MainHUD)
end

function MainHUD:init(manager)
    self.manager = manager  -- Store manager reference
    self._cons = self._cons or {} -- Initialize connections table if not already
    local colors = Theme.colors
    local fonts = Theme.fonts
    local sizes = Theme.sizes
    local anims = Theme.animations

    -- Root
    local root = Instance.new("Frame")
    root.Name = "MainHUD"
    root.Size = UDim2.fromScale(1, 1)
    root.BackgroundTransparency = 1
    root.Parent = manager.container
    self.frame = root

    -- === TOP-RIGHT GROUP (coins, gems, settings) ===
    local chipConfig = Theme.currencyChip
    local settingsConfig = Theme.settingsButton
    local rightMargin = UIx.Spacing.LG
    local topMargin = Theme.sizes.TopMargin  -- Use Theme value
    
    -- Container anchored to top-right; auto-sizes horizontally to fit children
    local topRightGroup = Instance.new("Frame")
    topRightGroup.Name = "TopRightGroup"
    topRightGroup.BackgroundTransparency = 1
    topRightGroup.AnchorPoint = Vector2.new(1, 0)
    topRightGroup.Position = UDim2.new(1, -rightMargin, 0, topMargin)
    topRightGroup.Size = UDim2.new(0, 0, 0, math.max(chipConfig.height, settingsConfig.height))
    topRightGroup.AutomaticSize = Enum.AutomaticSize.X
    topRightGroup.Parent = root
    self.topRightGroup = topRightGroup
    
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.Padding = UDim.new(0, chipConfig.gap)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = topRightGroup
    
    -- Helper to create fixed-size slots
    local function makeSlot(w, h, order)
        local slot = Instance.new("Frame")
        slot.Name = "Slot"..order
        slot.BackgroundTransparency = 1
        slot.Size = UDim2.fromOffset(w, h)
        slot.LayoutOrder = order
        slot.Parent = topRightGroup
        return slot
    end
    
    -- === COINS CHIP (in slot) ===
    local coinsSlot = makeSlot(chipConfig.width, chipConfig.height, 1)
    self.coinsChip = CurrencyChip.new({
        parent = coinsSlot,
        currencyType = "coins",
        value = 0,
    })
    -- Chip centers itself now, no manual positioning needed
    
    -- === SETTINGS BUTTON (in slot) ===
    local settingsSlot = makeSlot(settingsConfig.width, settingsConfig.height, 2)
    self.settingsButton = SettingsButton.new({
        parent = settingsSlot,
        onClick = function()
            if self.manager then
                self.manager:showScene("SettingsPanel")
            end
        end
    })
    -- Button centers itself now, no manual positioning needed
    
    -- === HOME BUTTON (center top, separate container) ===
    local homeConfig = Theme.homeButton
    
    -- Create center container for home button
    local centerTopGroup = Instance.new("Frame")
    centerTopGroup.Name = "CenterTopGroup"
    centerTopGroup.BackgroundTransparency = 1
    centerTopGroup.Size = UDim2.fromOffset(homeConfig.width, homeConfig.height)
    centerTopGroup.AnchorPoint = Vector2.new(0.5, 0)
    centerTopGroup.Position = UDim2.new(0.5, 0, 0, topMargin)
    centerTopGroup.Parent = root
    self.centerTopGroup = centerTopGroup  -- Store reference for fading
    
    -- Create home button in center container
    local homeSlot = Instance.new("Frame")
    homeSlot.Name = "HomeSlot"
    homeSlot.BackgroundTransparency = 1
    homeSlot.Size = UDim2.fromScale(1, 1)
    homeSlot.Parent = centerTopGroup
    
    self.homeButton = HomeButton.new({
        parent = homeSlot,
        onClick = function()
            -- Call teleport to home remote
            local data, err = ClientRF.call("TeleportToHome")
            if not err then
                log:info("Teleporting home...")
            else
                log:warn("Failed to teleport home: %s", tostring(err))
            end
        end
    })
    -- HomeButton centers itself now, no manual positioning needed
    
    -- === BOTTOM CENTER ACTION CHIP (for tree climbing, etc.) ===
    -- EXACTLY mirror the home button pattern (use Theme sizes like Home button)
    local actionConfig = Theme.homeButton
    local actionChipWidth = actionConfig.width
    local actionChipHeight = actionConfig.height
    
    local bottomCenterGroup = Instance.new("Frame")
    bottomCenterGroup.Name = "BottomCenterGroup"
    bottomCenterGroup.BackgroundTransparency = 1
    bottomCenterGroup.Size = UDim2.fromOffset(actionChipWidth, actionChipHeight)
    bottomCenterGroup.AnchorPoint = Vector2.new(0.5, 1)
    bottomCenterGroup.Position = UDim2.new(0.5, 0, 1, -(UIx.Spacing.LG * 4)) -- Bottom with margin
    bottomCenterGroup.Visible = false -- Hidden by default
    bottomCenterGroup.Parent = root
    self.bottomCenterGroup = bottomCenterGroup
    
    -- Function to update bottom margin dynamically (same as home button logic)
    local function updateBottomMargin()
        local bottomMargin = UIx.Spacing.LG * 4 -- Simple fixed margin like we might do for testing
        self.bottomCenterGroup.Position = UDim2.new(0.5, 0, 1, -bottomMargin)
    end
    updateBottomMargin()
    
    -- Update on viewport changes (rotation, device changes)
    local camera = workspace.CurrentCamera
    if camera then
        local viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateBottomMargin)
        table.insert(self._cons, viewportConnection)
    end
    
    -- Debug check for centering (simplified)
    self:_setTimeout(0.5, function()
        if camera and self.bottomCenterGroup then
            local screenCenterX = camera.ViewportSize.X / 2
            local chipPos = self.bottomCenterGroup.AbsolutePosition
            local chipSize = self.bottomCenterGroup.AbsoluteSize
            local chipCenterX = chipPos.X + chipSize.X / 2
            local delta = chipCenterX - screenCenterX
            
            log:debug("Action chip center: %.1f, Screen center: %.1f, Delta: %.1f", 
                chipCenterX, screenCenterX, delta)
        end
    end)
    
    -- Track last values for pulse effect
    local lastCoins = 0
    
    -- Update toast position now that chips are created
    if manager.updateToastPosition then
        manager:updateToastPosition()
    end

    -- Extraction bar removed - no longer needed

    -- === LEFT NAV (feature-gated) ===
    if GameConfig.Features and GameConfig.Features.SHOW_LEFT_NAV == true then
        local chipConfig = Theme.currencyChip
        -- Icon-only nav across all devices: width equals chip height
        local navWidth = chipConfig.height
        local leftNav = Instance.new("Frame")
        leftNav.Name = "LeftNav"
        leftNav.BackgroundTransparency = 1
        leftNav.AnchorPoint = Vector2.new(0, 0.5)
        leftNav.Position = UDim2.new(0, UIx.Spacing.LG, 0.5, -UIx.Spacing.SM)
        leftNav.Size = UDim2.new(0, navWidth, 0, 0)
        leftNav.AutomaticSize = Enum.AutomaticSize.Y
        leftNav.Parent = root
        self.leftNavGroup = leftNav

        local vLayout = Instance.new("UIListLayout")
        vLayout.FillDirection = Enum.FillDirection.Vertical
        vLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
        vLayout.VerticalAlignment = Enum.VerticalAlignment.Center
        vLayout.Padding = UDim.new(0, UIx.Spacing.SECTION) -- tighten spacing slightly (12 -> 10px)
        vLayout.Parent = leftNav

        -- Always icon-only: ensure left nav is narrow on all devices
        leftNav.Size = UDim2.new(0, chipConfig.height, 0, 0)

        local function chipIconText(kind: string): (string?, string?)
            -- Icon-only labels for all devices
            if kind == "inventory" then
                return "🎒", nil
            elseif kind == "shop" then
                local icon = (Theme.icons and Theme.icons.currency and Theme.icons.currency.coins) or "$"
                return icon, nil
            elseif kind == "index" then
                return "📖", nil
            elseif kind == "upgrades" then
                return "💪", nil
            end
            return nil, nil
        end

        self._leftNavChips = {}

        local function styleChip(kind: string, chip)
            -- Keep all nav chips visually identical (no active highlight)
            chip:setBackgroundColor(Theme.colors.Surface)
            chip:setTextColor(Theme.colors.Text)
        end

        local function makeNavChip(kind: string, onClick: () -> ())
            local icon, _ = chipIconText(kind)
            -- Provide fallback icons if Theme lacks them
            local fallbackIcons = { inventory = "🎒", shop = (Theme.icons and Theme.icons.currency and Theme.icons.currency.coins) or "🛒", index = "📇", upgrades = "💪" }
            icon = icon or fallbackIcons[kind]
            local chip = BaseChip.new({
                parent = leftNav,
                size = UDim2.new(0, chipConfig.height, 0, chipConfig.height),
                icon = icon,
                text = nil, -- icon-only
                align = "center",
                onClick = function()
                    self._leftNavActive = kind
                    for k, c in pairs(self._leftNavChips) do
                        styleChip(k, c)
                    end
                    onClick()
                end,
                squishIntensity = 0.92,
            })
            self._leftNavChips[kind] = chip
            styleChip(kind, chip)
            return chip
        end

        -- Inventory chip (always available)
        makeNavChip("inventory", function()
            if self.manager then
                task.defer(function()
                    self.manager:showScene("InventoryPanel")
                end)
            end
        end)

        -- Shop chip (only if flag enabled)
        if GameConfig.Features.SHOW_SHOP_TAB == true then
            makeNavChip("shop", function()
                if self.manager then
                    task.defer(function()
                        self.manager:showScene("CashShopPanel")
                    end)
                end
            end)
        end

        -- Upgrades chip (dedicated panel) — place before Index
        makeNavChip("upgrades", function()
            if self.manager then
                task.defer(function()
                    self.manager:showScene("UpgradesPanel")
                end)
            end
        end)

        -- Item Index chip (last)
        if GameConfig.Features.SHOW_ITEM_INDEX == true then
            makeNavChip("index", function()
                if self.manager then
                    task.defer(function()
                        self.manager:showScene("ItemIndexPanel")
                    end)
                end
            end)
        end
    end

    -- === Public updaters ===
    function self:SetCurrencies(c: number, g: number)
        c = c or 0
        -- g parameter kept for backwards compatibility but ignored
        
        -- Pulse on increase
        if c > lastCoins then 
            self.coinsChip:pulse(1.1)
        end
        
        lastCoins = c
        
        self.coinsChip:setValue(c)
    end

    -- SetExtraction removed - no longer needed
    
    -- === ACTION CHIP METHODS ===
      function self:showActionChip(text: string, icon: string?, onActivate: () -> (), widthPx: number?)
        if not self.bottomCenterGroup then return end

        -- Cancel any pending action-chip hide that might nuke a newly shown chip
        if self._actionHideTask then
            self:_clearTimeout(self._actionHideTask)
            self._actionHideTask = nil
        end

        -- Destroy existing chip if any
        if self.actionChip then
            self.actionChip:destroy()
            self.actionChip = nil
        end
        
        -- Create slot frame (exactly like home button does)
        local actionSlot = Instance.new("Frame")
        actionSlot.Name = "ActionSlot"
        actionSlot.BackgroundTransparency = 1
        actionSlot.Size = UDim2.fromScale(1, 1)
        actionSlot.Parent = self.bottomCenterGroup
        
        -- Create new action chip using HUDActionChip component
        local HUDActionChip = require(script.Parent:WaitForChild("Components"):WaitForChild("HUDActionChip"))
        self.actionChip = HUDActionChip.new({
            parent = actionSlot,
            text = text or "Interact",
            icon = icon or "🌳",
            key = Enum.KeyCode.E,
            onActivate = onActivate,
              widthPx = widthPx,
        })
        
        -- Show with animation (ensure group is visible and cancel any fade-out)
        self.bottomCenterGroup.Visible = true
        self:_tweenTransparency(self.bottomCenterGroup, false)
        self.actionChip:show()
    end
    
    function self:hideActionChip()
        if not self.bottomCenterGroup then return end

        -- Fade out then hide
        self:_tweenTransparency(self.bottomCenterGroup, true)
        -- Cancel any previous scheduled hide to avoid racing with show
        if self._actionHideTask then
            self:_clearTimeout(self._actionHideTask)
            self._actionHideTask = nil
        end
        self._actionHideTask = self:_setTimeout(Theme.animations.Standard.Time, function()
            if self.bottomCenterGroup then
                self.bottomCenterGroup.Visible = false
            end
            if self.actionChip then
                self.actionChip:destroy()
                self.actionChip = nil
            end
            self._actionHideTask = nil
        end)
    end
    
    function self:updateActionChip(text: string?, icon: string?)
        if not self.actionChip then return end
        if text then self.actionChip:setText(text) end
        if icon then self.actionChip:setIcon(icon) end
    end
end

-- === Fade helpers ===

-- Snapshot original transparencies so we can restore exactly
function MainHUD:_snapshotTransparency(root: Instance)
    for _, inst in ipairs(root:GetDescendants()) do
        if inst:IsA("Frame") or inst:IsA("ScrollingFrame") then
            if inst:GetAttribute("orig_bg_t") == nil then
                inst:SetAttribute("orig_bg_t", inst.BackgroundTransparency)
            end
        elseif inst:IsA("TextLabel") or inst:IsA("TextButton") then
            if inst:GetAttribute("orig_text_t") == nil then
                inst:SetAttribute("orig_text_t", inst.TextTransparency)
            end
        elseif inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
            if inst:GetAttribute("orig_img_t") == nil then
                inst:SetAttribute("orig_img_t", inst.ImageTransparency)
            end
        elseif inst:IsA("UIStroke") then
            if inst:GetAttribute("orig_stroke_t") == nil then
                inst:SetAttribute("orig_stroke_t", inst.Transparency)
            end
        end
    end
end

-- Cancel the delayed visibility-off task, if any
function MainHUD:_cancelHideTask()
    if self._hideTask then
        self:_clearTimeout(self._hideTask)
        self._hideTask = nil
    end
end

-- Cancel all active tweens created by this HUD
function MainHUD:_cancelAllTweens()
    if not self._activeTweens then return end
    for _, tw in pairs(self._activeTweens) do
        pcall(function() tw:Cancel() end)
    end
    table.clear(self._activeTweens)
end

-- Create a tween that replaces any older tween on the same instance
function MainHUD:_playTween(inst: Instance, info: TweenInfo, props: {[string]: any})
    if not self._activeTweens then self._activeTweens = {} end
    local prev = self._activeTweens[inst]
    if prev then pcall(function() prev:Cancel() end) end
    
    local tw = TweenService:Create(inst, info, props)
    self._activeTweens[inst] = tw
    
    tw.Completed:Connect(function()
        -- only clear if this is still the current tween for this instance
        if self._activeTweens and self._activeTweens[inst] == tw then
            self._activeTweens[inst] = nil
        end
    end)
    
    tw:Play()
end

-- Tween all relevant descendants to hidden (1) or restored (saved attrs)
function MainHUD:_tweenTransparency(root: Instance, toHidden: boolean)
    local info = Theme.animations.Standard
    self:_snapshotTransparency(root)

    for _, inst in ipairs(root:GetDescendants()) do
        if inst:IsA("Frame") or inst:IsA("ScrollingFrame") then
            local target = toHidden and 1 or (inst:GetAttribute("orig_bg_t") or inst.BackgroundTransparency)
            if inst.BackgroundTransparency ~= nil then
                self:_playTween(inst, info, { BackgroundTransparency = target })
            end
        elseif inst:IsA("TextLabel") or inst:IsA("TextButton") then
            local target = toHidden and 1 or (inst:GetAttribute("orig_text_t") or 0)
            self:_playTween(inst, info, { TextTransparency = target })
        elseif inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
            local target = toHidden and 1 or (inst:GetAttribute("orig_img_t") or 0)
            self:_playTween(inst, info, { ImageTransparency = target })
        elseif inst:IsA("UIStroke") then
            local target = toHidden and 1 or (inst:GetAttribute("orig_stroke_t") or 0)
            self:_playTween(inst, info, { Transparency = target })
        end
    end
end

-- Timer helpers
function MainHUD:_setTimeout(delay: number, fn: () -> ())
    local th
    th = task.delay(delay, function()
        if self and self.frame then
            local ok, err = pcall(fn)
            if not ok then warn(("[MainHUD] timer error: %s"):format(tostring(err))) end
        end
        for i, h in ipairs(self._timers) do
            if h == th then table.remove(self._timers, i) break end
        end
    end)
    table.insert(self._timers, th)
    return th
end

function MainHUD:_clearTimeout(h: thread?)
    if not h then return end
    pcall(task.cancel, h)
    for i, hh in ipairs(self._timers) do
        if hh == h then table.remove(self._timers, i) break end
    end
end

function MainHUD:fadeOutChips()
    if self.topRightGroup then
        self:_tweenTransparency(self.topRightGroup, true)
    end
    if self.centerTopGroup then
        self:_tweenTransparency(self.centerTopGroup, true)
    end
    if self.leftNavGroup then
        self:_tweenTransparency(self.leftNavGroup, true)
    end
end

function MainHUD:fadeInChips()
    if self.topRightGroup then
        self:_tweenTransparency(self.topRightGroup, false)
    end
    if self.centerTopGroup then
        self:_tweenTransparency(self.centerTopGroup, false)
    end
    if self.leftNavGroup then
        self:_tweenTransparency(self.leftNavGroup, false)
    end
end

function MainHUD:show()
    -- Kill any pending hide logic and in-flight tweens
    self:_cancelHideTask()
    self:_cancelAllTweens()
    
    if self.frame then
        self.frame.Visible = true
        self:fadeInChips()
    end
end

function MainHUD:hide()
    if not self.frame then return end
    
    -- Prevent overlap with previous hide attempts
    self:_cancelHideTask()
    self:_cancelAllTweens()
    
    -- Cross-fade with the next panel; hide after tween completes
    self:fadeOutChips()
    local t = Theme.animations.Standard.Time + Theme.animations.Standard.DelayTime
    self._hideTask = self:_setTimeout(t, function()
        if self and self.frame then
            self.frame.Visible = false
        end
        self._hideTask = nil
    end)
end

function MainHUD:cleanup()
    -- Cancel all timers first
    if self._timers then
        for _, h in ipairs(self._timers) do pcall(task.cancel, h) end
        self._timers = {}
    end
    
    -- Cancel any pending animations/tasks
    self:_cancelHideTask()
    self:_cancelAllTweens()
    
    for _, c in ipairs(self._cons) do 
        if c.Disconnect then 
            c:Disconnect() 
        end 
    end
    self._cons = {}
    
    -- Destroy individual components
    if self.coinsChip then
        self.coinsChip:destroy()
    end
    if self.gemsChip then
        self.gemsChip:destroy()
    end
    if self.homeButton then
        self.homeButton:destroy()
    end
    if self.settingsButton then
        self.settingsButton:destroy()
    end
    if self.actionChip then
        self.actionChip:destroy()
    end
    
    -- Destroy the top-right group container
    if self.topRightGroup then
        self.topRightGroup:Destroy()
        self.topRightGroup = nil
    end
    
    if self.frame then 
        self.frame:Destroy() 
    end
    self.frame = nil
end

return MainHUD

