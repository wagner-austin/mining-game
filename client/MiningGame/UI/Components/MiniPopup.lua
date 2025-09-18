--!strict
-- MiniPopup.lua
-- Lightweight BaseChip-based popup that appears and auto-dismisses

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Theme = require(MiningGame:WaitForChild("UI"):WaitForChild("Theme"))
local UIx = require(MiningGame:WaitForChild("UI"):WaitForChild("UIConstants"))
local UIUtils = require(MiningGame:WaitForChild("UI"):WaitForChild("UIUtils"))
local BaseChip = require(script.Parent:WaitForChild("BaseChip"))

local MiniPopup = {}

export type PopupOpts = {
    position: UDim2?,  -- Defaults to bottom-right offset
    lifetimeSec: number?, -- Defaults to 2.5s
}

function MiniPopup.show(parent: GuiObject, message: string, iconText: string?, opts: PopupOpts?)
    opts = opts or {}
    local lifetime = opts.lifetimeSec or 2.5

    -- Create anchor container
    local anchor = Instance.new("Frame")
    anchor.BackgroundTransparency = 1
    anchor.Size = UDim2.new(0, 1, 0, 1)
    if opts.position then
        anchor.AnchorPoint = Vector2.new(0, 0)
        anchor.Position = opts.position
    else
        anchor.AnchorPoint = Vector2.new(1, 1)
        -- Bottom-right default using theme tokens (no magic numbers)
        anchor.Position = UDim2.new(1, -UIx.Spacing.XL, 1, -(UIx.Spacing.XL + Theme.currencyChip.height))
    end
    anchor.Parent = parent

    -- Create chip
    local chip = BaseChip.new({
        parent = anchor,
        icon = iconText,
        text = message,
        align = "left",
        -- Slightly wider than currency chip to avoid clipping longer messages
        size = UDim2.new(0, Theme.currencyChip.width + 120, 0, Theme.currencyChip.height),
        -- Compact spacing for mini popups to reduce gap between icon and text
        innerPadding = UIx.Spacing.TINY,
        textPaddingLeft = UIx.Spacing.TINY,
        textPaddingRight = UIx.Spacing.SM,
    })
    local chipGui = chip.container
    local bg = chip.background
    local iconLabel = chip.iconLabel
    local textLabel = chip.textLabel
    local stroke = bg and bg:FindFirstChildOfClass("UIStroke")
    local noiseChildren = {}
    if bg then
        for _, child in ipairs(bg:GetChildren()) do
            if child:IsA("ImageLabel") then
                table.insert(noiseChildren, child)
            end
        end
    end
    -- For custom-positioned popups, treat given position as top-left corner
    if opts.position then
        chipGui.AnchorPoint = Vector2.new(0, 0)
        chipGui.Position = UDim2.new(0, 0, 0, 0)
    else
        chipGui.AnchorPoint = Vector2.new(1, 1)
        chipGui.Position = UDim2.new(0, 0, 0, 0)
    end
    -- Initialize fully transparent (we'll fade in bg, stroke, noise and labels)
    if bg then bg.BackgroundTransparency = 1 end
    if stroke then stroke.Transparency = 1 end
    for _, img in ipairs(noiseChildren) do
        img.ImageTransparency = 1
    end
    if iconLabel then iconLabel.TextTransparency = 1 end
    if textLabel then textLabel.TextTransparency = 1 end

    -- Clamp popup inside the screen (parent) bounds on different screen sizes
    local function clampToBounds()
        if not parent or not parent.Parent then return end
        if not anchor or not anchor.Parent then return end
        local parentSize = parent.AbsoluteSize
        local chipSize = chipGui.AbsoluteSize
        local margin = UIx.Spacing.SM
        -- Current desired offsets
        local x = anchor.Position.X.Offset
        local y = anchor.Position.Y.Offset
        -- Clamp to keep entire chip visible with a small margin
        local maxX = math.max(0, parentSize.X - chipSize.X - margin)
        local maxY = math.max(0, parentSize.Y - chipSize.Y - margin)
        local clampedX = math.clamp(x, margin, maxX)
        local clampedY = math.clamp(y, margin, maxY)
        if clampedX ~= x or clampedY ~= y then
            anchor.Position = UDim2.fromOffset(clampedX, clampedY)
        end
    end

    -- Defer to next frame to get correct AbsoluteSize, then clamp
    task.defer(function()
        clampToBounds()
    end)
    -- Re-clamp on size changes
    local _conns = {}
    table.insert(_conns, chipGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(clampToBounds))
    local parentGui = anchor.Parent
    if parentGui and parentGui:IsA("GuiObject") then
        table.insert(_conns, parentGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(clampToBounds))
    end

    -- Fade-in (background and text) using theme animation
    local fadeIn = Theme.animations.Quick
    if bg then UIUtils.tweenProps(bg, { BackgroundTransparency = Theme.effects.frosted.backgroundTransparency }, fadeIn) end
    if stroke then UIUtils.tweenProps(stroke, { Transparency = Theme.glassEdge.transparency }, fadeIn) end
    for _, img in ipairs(noiseChildren) do
        UIUtils.tweenProps(img, { ImageTransparency = Theme.effects.frosted.noiseTransparency }, fadeIn)
    end
    if iconLabel then UIUtils.tweenProps(iconLabel, { TextTransparency = 0 }, fadeIn) end
    if textLabel then UIUtils.tweenProps(textLabel, { TextTransparency = 0 }, fadeIn) end

    -- Forward declarations for cleanup
    local closed = false
    local function destroyNow() end
    local function fadeOut() end

    -- Also hide when cursor leaves the popup itself
    table.insert(_conns, chipGui.MouseLeave:Connect(function()
        -- Immediate fade-out on mouse leave
        fadeOut()
    end))

    -- Helper: fade-out and destroy
    destroyNow = function()
        if closed then return end
        closed = true
        -- Disconnect listeners
        for _, c in ipairs(_conns) do pcall(function() c:Disconnect() end) end
        pcall(function() chip:destroy() end)
        pcall(function() anchor:Destroy() end)
    end

    fadeOut = function()
        if closed then return end
        closed = true
        local fadeOutInfo = Theme.animations.Quick
        local pending = 0
        local function add(inst: Instance?, props)
            if not inst then return end
            local tw = UIUtils.tweenProps(inst, props, fadeOutInfo)
            pending += 1
            tw.Completed:Connect(function()
                pending -= 1
                if pending == 0 then destroyNow() end
            end)
        end
        add(bg, { BackgroundTransparency = 1 })
        add(stroke, { Transparency = 1 })
        for _, img in ipairs(noiseChildren) do
            add(img, { ImageTransparency = 1 })
        end
        add(iconLabel, { TextTransparency = 1 })
        add(textLabel, { TextTransparency = 1 })
        if pending == 0 then destroyNow() end
    end

    -- Auto-dismiss with fade-out
    task.delay(lifetime, function()
        if closed then return end
        fadeOut()
    end)

    return { chip = chip, anchor = anchor, fadeOut = fadeOut }
end

return MiniPopup
