--!strict
-- MainHUD.lua
-- Main game HUD with currency display and extraction progress bar

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UI = ReplicatedStorage:WaitForChild("MiningGame"):WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local CurrencyChip = require(script.Parent:WaitForChild("Components"):WaitForChild("CurrencyChip"))
local HomeButton = require(script.Parent:WaitForChild("Components"):WaitForChild("HomeButton"))
local SettingsButton = require(script.Parent:WaitForChild("Components"):WaitForChild("SettingsButton"))

local MainHUD = {}
MainHUD.__index = MainHUD

function MainHUD.new()
    return setmetatable({
        name = "MainHUD",
        frame = nil :: Frame?,
        _cons = {},
        _activeTweens = {}, -- Track active tweens to cancel them
        _hideTask = nil,    -- Track hide delay task
    }, MainHUD)
end

function MainHUD:init(manager)
    self.manager = manager  -- Store manager reference
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
    local rightMargin = 20
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
            local Remotes = require(ReplicatedStorage:WaitForChild("MiningGame"):WaitForChild("Remotes"))
            local success, result = pcall(function()
                return Remotes.RF.TeleportToHome:InvokeServer()
            end)
            if success then
                print("[MainHUD] Teleporting home...")
            else
                print("[MainHUD] Failed to teleport home:", result)
            end
        end
    })
    -- HomeButton centers itself now, no manual positioning needed
    
    -- Track last values for pulse effect
    local lastCoins = 0
    
    -- Update toast position now that chips are created
    if manager.updateToastPosition then
        manager.updateToastPosition()
    end

    -- Extraction bar removed - no longer needed

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
        task.cancel(self._hideTask)
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

function MainHUD:fadeOutChips()
    if self.topRightGroup then
        self:_tweenTransparency(self.topRightGroup, true)
    end
    if self.centerTopGroup then
        self:_tweenTransparency(self.centerTopGroup, true)
    end
end

function MainHUD:fadeInChips()
    if self.topRightGroup then
        self:_tweenTransparency(self.topRightGroup, false)
    end
    if self.centerTopGroup then
        self:_tweenTransparency(self.centerTopGroup, false)
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
    self._hideTask = task.delay(t, function()
        if self and self.frame then
            self.frame.Visible = false
        end
        self._hideTask = nil
    end)
end

function MainHUD:cleanup()
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