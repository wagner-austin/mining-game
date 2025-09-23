--!strict
-- ItemTileRenderer.lua
-- Shared helper to build item tiles (button, corner, rarity stroke) for Inventory/Index

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UIFolder = MiningGame:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))
local UIx = require(UIFolder:WaitForChild("UIConstants"))
local UIUtils = require(UIFolder:WaitForChild("UIUtils"))
local GameConfig = require(MiningGame:WaitForChild("GameConfig"))
local Time = require(MiningGame:WaitForChild("Time"))
local IconEffects = require(UIFolder:WaitForChild("IconEffects"))

export type CreateOptions = {
    item: any,
    parent: Instance?,
    sizeMode: ("grid" | "fixed")?,
    fixedSize: UDim2?,
    backgroundTransparency: number?,
    rarityEffects: boolean?, -- auto-apply rarity effects to symbol
}

local ItemTileRenderer = {}

-- Minimal, module-scoped symbol resolver so both create() and
-- symbolFor() can use the same logic without cross-scope calls.
local function chooseSymbol(it: any): string
    -- Prefer explicit icon from data if provided
    if it then
        local icon = (it :: any).icon
        if typeof(icon) == "string" and icon ~= "" then return icon end
        local meta = (it :: any).meta
        if meta and typeof(meta.icon) == "string" and meta.icon ~= "" then return meta.icon end
    end
    local id = tostring(it and (it :: any).id or "")
    local typ = tostring(it and (it :: any).type or "")
    local slot = tostring(it and (it :: any).slot or "")

    if typ == "resource" then
        local lid = id:lower()
        if lid:find("stone") then return "⬜" end
        if lid:find("coal") then return "⚫" end
        if lid:find("copper") then return "🟫" end
        if lid:find("iron") then return "⚪" end
        if lid:find("silver") then return "🔘" end
        if lid:find("gold") then return "🟡" end
        if lid:find("ruby") then return "🔴" end
        if lid:find("emerald") then return "🟢" end
        if lid:find("obsidian") then return "⬛" end
        if lid:find("void") then return "🌀" end
        if lid:find("glass") then return "🔷" end
        if lid:find("ice") or lid:find("frozen") then return "❄️" end
        if lid:find("prismatic") or lid:find("rainbow") then return "🌈" end
        if lid:find("chromatic") then return "🎨" end
        if lid:find("cosmic") then return "✨" end
        if lid:find("dark") then return "🌑" end
        if lid:find("crystal") or lid:find("diamond") then return "💎" end
        return "💎"
    elseif typ == "pickaxe" then
        return "⛏️"
    elseif typ == "consumable" then
        return "🧪"
    elseif typ == "cosmetic" then
        local ls = slot:lower()
        if ls == "head" then return "◯" end
        if ls == "chest" or ls == "armor" then return "🛡️" end
        if ls == "feet" or ls == "boots" then return "👢" end
        if ls == "back" or ls == "wings" then return "🦋" end
        if ls == "aura" then return "✨" end
        if ls == "trail" then return "💫" end
        if ls == "accessory" then return "💍" end
        if ls == "pickaxe" or ls == "hand" then return "⛏" end
        return "🎨"
    end
    return "✨"
end

function ItemTileRenderer.create(opts: CreateOptions)
    local item = opts.item
    local button = Instance.new("TextButton")
    button.Name = item and item.id or "ItemTile"
    if opts.sizeMode == "fixed" and opts.fixedSize then
        button.Size = opts.fixedSize
    else
        -- grid mode: let UIGridLayout cell size control the footprint
        button.Size = UDim2.new(1, 0, 1, 0)
    end
    button.Text = ""
    button.AutoButtonColor = true
    button.BackgroundColor3 = Theme.colors.Surface
    button.BackgroundTransparency = (opts.backgroundTransparency ~= nil) and opts.backgroundTransparency or 0.1
    button.BorderSizePixel = 0
    if opts.parent then button.Parent = opts.parent end

    -- Theme binding
    local ThemeRefresher = require(UIFolder:WaitForChild("ThemeRefresher"))
    ThemeRefresher.Bind(button, { BackgroundColor3 = "Surface" })

    -- Corner radius
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UIx.corner()
    corner.Parent = button

    -- Rarity border
    local rData = GameConfig and GameConfig.Loot and GameConfig.Loot.RARITIES and GameConfig.Loot.RARITIES[item and item.rarity or ""] or nil
    if rData then
        local stroke = Instance.new("UIStroke")
        stroke.Color = rData.color
        stroke.Thickness = UIx.Visual.BORDER_WIDTH
        stroke.Parent = button
        if item and (item.rarity == "MYTHIC" or item.rarity == "LEGENDARY") then
            stroke.Transparency = 0
            local gradient = Instance.new("UIGradient")
            gradient.Rotation = 90
            gradient.Parent = stroke
        end
    end

    local helpers = {}
    local autoEffects = (opts and opts.rarityEffects) and true or false

    function helpers.addNameLabel(text: string, options: {useRarityColor: boolean?, item: any?, align: ("left"|"center")?}?)
        local nameLabel = Instance.new("TextLabel")
        nameLabel.Name = "Name"
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = text
        nameLabel.TextScaled = false
        nameLabel.TextWrapped = true
        local align = options and options.align or "left"
        nameLabel.TextXAlignment = (align == "center") and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left
        nameLabel.Font = Theme.fonts.Primary
        nameLabel.TextSize = UIx.Visual.TEXT_SMALL
        nameLabel.Size = UDim2.new(1, -UIx.Spacing.SM, 0, UIx.Size.ROW_LARGE)
        nameLabel.Position = UDim2.new(0, UIx.Spacing.TINY, 1, -(UIx.Size.ROW_LARGE + UIx.Spacing.TINY))
        -- Optionally color by rarity
        local useRarity = options and options.useRarityColor
        local it = options and options.item
        if useRarity and it and it.rarity then
            local rData = (GameConfig and GameConfig.Loot and GameConfig.Loot.RARITIES) and GameConfig.Loot.RARITIES[it.rarity] or nil
            nameLabel.TextColor3 = (rData and rData.color) or Theme.colors.Text
        else
            nameLabel.TextColor3 = Theme.colors.Text
        end
        nameLabel.Parent = button
        local ThemeRefresher = require(UIFolder:WaitForChild("ThemeRefresher"))
        if not (options and options.useRarityColor and (options.item and options.item.rarity)) then
            ThemeRefresher.Bind(nameLabel, { TextColor3 = "Text" })
        end
        return nameLabel
    end

    function helpers.addSymbol(it: any)
        local symbol = chooseSymbol(it)
        local function isAssetString(s: any): boolean
            if typeof(s) ~= "string" then return false end
            if s == "" then return false end
            -- Recognize common Roblox asset forms or raw numeric ids
            return s:match("^rbxassetid://%d+$") ~= nil
                or s:match("^rbxasset://") ~= nil
                or s:match("^https?://") ~= nil
                or s:match("^%d+$") ~= nil
        end
        -- Resolve clip-art icon via IconAtlas first
        local IconAtlas = require(ReplicatedStorage:WaitForChild("MiningGame"):WaitForChild("UI"):WaitForChild("IconAtlas"))
        local atlasIcon = IconAtlas.getForItem(it)

        -- Common item metadata
        local typ = tostring(it and it.type or "")
        local slot = tostring(it and it.slot or "")
        local meta = (it and (it.meta or it))
        local eff = meta and meta.effect or nil
        local auraColor = meta and meta.color or nil

        -- If we have a clip-art image (rbxassetid/http), prefer it
        if isAssetString(atlasIcon) then
            local img = Instance.new("ImageLabel")
            img.Name = "ItemDisplay"
            img.Size = UDim2.new(1, -UIx.Spacing.SM, 1, -UIx.Size.ROW_LARGE)
            img.Position = UDim2.new(0, UIx.Spacing.TINY, 0, UIx.Spacing.TINY)
            img.BackgroundTransparency = 1
            if atlasIcon:match("^%d+$") then
                img.Image = "rbxassetid://" .. atlasIcon
            else
                img.Image = atlasIcon
            end
            img.ScaleType = Enum.ScaleType.Fit
            img.Parent = button
            -- Color-tint any aura that isn't cosmic
            if typ == "cosmetic" and slot == "aura" and eff ~= "cosmic" and typeof(auraColor) == "Color3" then
                img.ImageColor3 = auraColor
            end
            if autoEffects then helpers.applyRarityEffects(img, it) end
            return img
        end

        -- If we don't have a clip-art image, build a colored star (text) for aura
        if typ == "cosmetic" and slot == "aura" and not isAssetString(symbol) then
            local lbl = Instance.new("TextLabel")
            lbl.Name = "ItemDisplay"
            lbl.Size = UDim2.new(1, -UIx.Spacing.SM, 1, -UIx.Size.ROW_LARGE)
            lbl.Position = UDim2.new(0, UIx.Spacing.TINY, 0, UIx.Spacing.TINY)
            lbl.BackgroundTransparency = 1
            lbl.Text = symbol
            lbl.TextScaled = true
            lbl.Font = Theme.fonts.Primary
            if eff ~= "cosmic" and typeof(auraColor) == "Color3" then
                lbl.TextColor3 = auraColor
            else
                lbl.TextColor3 = Theme.colors.Text
            end
            lbl.Parent = button
            local ThemeRefresher = require(UIFolder:WaitForChild("ThemeRefresher"))
            if not (eff ~= "cosmic" and typeof(auraColor) == "Color3") then
                ThemeRefresher.Bind(lbl, { TextColor3 = "Text" })
            end
            if autoEffects then
                helpers.applyRarityEffects(lbl, it)
            end
            return lbl
        end

        if isAssetString(symbol) then
            local image = symbol
            if symbol:match("^%d+$") then
                image = "rbxassetid://" .. symbol
            end
            local img = Instance.new("ImageLabel")
            img.Name = "ItemDisplay"
            img.Size = UDim2.new(1, -UIx.Spacing.SM, 1, -UIx.Size.ROW_LARGE)
            img.Position = UDim2.new(0, UIx.Spacing.TINY, 0, UIx.Spacing.TINY)
            img.BackgroundTransparency = 1
            img.Image = image
            img.ScaleType = Enum.ScaleType.Fit
            img.Parent = button
            -- Tint aura icons based on aura color (except cosmic, which uses rainbow shimmer)
            if typ == "cosmetic" and slot == "aura" and eff ~= "cosmic" and typeof(auraColor) == "Color3" then
                img.ImageColor3 = auraColor
            end
            if autoEffects then
                helpers.applyRarityEffects(img, it)
            end
            return img
        else
            local lbl = Instance.new("TextLabel")
            lbl.Name = "ItemDisplay"
            lbl.Size = UDim2.new(1, -UIx.Spacing.SM, 1, -UIx.Size.ROW_LARGE)
            lbl.Position = UDim2.new(0, UIx.Spacing.TINY, 0, UIx.Spacing.TINY)
            lbl.BackgroundTransparency = 1
            lbl.Text = symbol
            lbl.TextScaled = true
            lbl.Font = Theme.fonts.Primary
            -- Regular text icons (non-aura or asset-unavailable fallback)
            lbl.TextColor3 = Theme.colors.Text
            lbl.Parent = button
            local ThemeRefresher = require(UIFolder:WaitForChild("ThemeRefresher"))
            ThemeRefresher.Bind(lbl, { TextColor3 = "Text" })
            if autoEffects then
                -- Apply rarity effects automatically when requested
                helpers.applyRarityEffects(lbl, it)
            end
            return lbl
        end
    end

    -- Apply rarity-specific effects to a target (TextLabel or ImageLabel)
    function helpers.applyRarityEffects(target: GuiObject, it: any)
        if not (target and it and it.rarity) then return end

        local rarity = tostring(it.rarity)
        -- Skip non-cosmic effects on custom Frame icons to avoid distracting pulses
        if target:IsA("Frame") and rarity ~= "MYTHIC" then return end
        -- Allow pluggable icon effects (e.g., uiIconEffect on item meta)
        local handled = IconEffects.apply(target, it)
        if handled then return end
        if rarity == "MYTHIC" then
            -- Cosmic shimmer handled via IconEffects at the top (early return)
            -- Non-cosmic MYTHIC: subtle breathing transparency
            task.spawn(function()
                while target.Parent do
                    local key
                    if target:IsA("ImageLabel") then key = "ImageTransparency"
                    elseif target:IsA("TextLabel") then key = "TextTransparency"
                    else key = "BackgroundTransparency" end
                    game:GetService("TweenService"):Create(target, TweenInfo.new(UIx.Anim.EXTRA_SLOW, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
                        [key] = 0.2
                    }):Play()
                    task.wait(UIx.Anim.EXTRA_SLOW)
                    game:GetService("TweenService"):Create(target, TweenInfo.new(UIx.Anim.EXTRA_SLOW, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
                        [key] = 0
                    }):Play()
                    task.wait(UIx.Anim.EXTRA_SLOW)
                end
            end)
        elseif rarity == "LEGENDARY" then
            -- Golden pulse
            task.spawn(function()
                while target.Parent do
                    local key
                    if target:IsA("ImageLabel") then key = "ImageTransparency"
                    elseif target:IsA("TextLabel") then key = "TextTransparency"
                    else key = "BackgroundTransparency" end
                    game:GetService("TweenService"):Create(target, TweenInfo.new(UIx.Anim.EXTRA_SLOW, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
                        [key] = 0.3
                    }):Play()
                    task.wait(UIx.Anim.EXTRA_SLOW)
                    game:GetService("TweenService"):Create(target, TweenInfo.new(UIx.Anim.EXTRA_SLOW, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
                        [key] = 0
                    }):Play()
                    task.wait(UIx.Anim.EXTRA_SLOW)
                end
            end)
        elseif rarity == "EPIC" then
            -- Subtle shimmer using rarity color
            local rData = GameConfig and GameConfig.Loot and GameConfig.Loot.RARITIES and GameConfig.Loot.RARITIES[rarity] or nil
            local baseColor = (rData and rData.color) or Theme.colors.Text
            local shimmer = Instance.new("UIGradient")
            shimmer.Color = ColorSequence.new(baseColor, baseColor:Lerp(Color3.new(1,1,1), 0.3))
            shimmer.Rotation = 45
            shimmer.Parent = target

            task.spawn(function()
                while target.Parent do
                    shimmer.Rotation = 45 + math.sin(Time.mono() * 2) * 15
                    task.wait(UIx.Anim.TINY)
                end
            end)
        end
    end

    function helpers.addCountBadge(count: number)
        if count and count > 1 then
            local badge = Instance.new("TextLabel")
            badge.Name = "CountBadge"
            badge.Size = UDim2.new(0, UIx.Size.BADGE_WIDTH, 0, UIx.Size.BADGE_HEIGHT)
            badge.Position = UDim2.new(1, -(UIx.Size.BADGE_WIDTH + UIx.Spacing.TINY), 0, UIx.Spacing.TINY)
            badge.BackgroundColor3 = Theme.colors.Background
            badge.BackgroundTransparency = 0.1
            badge.Text = tostring(count)
            badge.TextColor3 = Theme.colors.Text
            badge.Font = Theme.fonts.Primary
            badge.TextSize = UIx.Visual.TEXT_SMALL
            badge.Parent = button
            local corner2 = Instance.new("UICorner")
            corner2.CornerRadius = UDim.new(0, UIx.Spacing.TINY)
            corner2.Parent = badge
            local ThemeRefresher = require(UIFolder:WaitForChild("ThemeRefresher"))
            ThemeRefresher.Bind(badge, { BackgroundColor3 = "Background", TextColor3 = "Text" })
            return badge
        end
        return nil
    end

    function helpers.addOwnedMeta(text: string)
        local meta = Instance.new("TextLabel")
        meta.Name = "Meta"
        meta.BackgroundTransparency = 1
        meta.Text = text
        meta.TextScaled = true
        meta.Font = Theme.fonts.Secondary
        meta.TextColor3 = Theme.colors.Text
        meta.Size = UDim2.new(0, UIx.Size.GRID_CELL_PX/2, 0, UIx.Size.ROW_STANDARD)
        meta.Position = UDim2.new(1, -UIx.Size.GRID_CELL_PX/2 - UIx.Spacing.TINY, 0, UIx.Spacing.TINY)
        meta.TextXAlignment = Enum.TextXAlignment.Right
        meta.Parent = button
        local ThemeRefresher = require(UIFolder:WaitForChild("ThemeRefresher"))
        ThemeRefresher.Bind(meta, { TextColor3 = "Text" })
        return meta
    end

    -- Price badge (coins) – pill with coin icon + formatted number
    function helpers.addPriceBadge(price: number)
        local pill = Instance.new("Frame")
        pill.Name = "PriceBadge"
        -- Top-right placement to avoid name overlap
        pill.AnchorPoint = Vector2.new(1, 0)
        pill.Position = UDim2.new(1, -UIx.Spacing.TINY, 0, UIx.Spacing.TINY)
        pill.Size = UDim2.new(0, math.max(78, UIx.Size.GRID_CELL_PX/2), 0, UIx.Size.ROW_STANDARD)
        pill.BackgroundColor3 = Theme.colors.Background
        pill.BackgroundTransparency = 0.1
        pill.Parent = button
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, UIx.Spacing.MD)
        corner.Parent = pill
        local list = Instance.new("UIListLayout")
        list.FillDirection = Enum.FillDirection.Horizontal
        list.VerticalAlignment = Enum.VerticalAlignment.Center
        list.HorizontalAlignment = Enum.HorizontalAlignment.Center
        list.Padding = UDim.new(0, UIx.Spacing.TINY)
        list.Parent = pill

        local icon = Instance.new("TextLabel")
        icon.BackgroundTransparency = 1
        icon.Text = (Theme.icons and Theme.icons.currency and Theme.icons.currency.coins) or "$"
        icon.Font = Theme.fonts.Secondary
        icon.TextScaled = true
        icon.TextColor3 = Theme.colors.Text
        icon.Size = UDim2.new(0, UIx.Size.ROW_STANDARD - 2, 0, UIx.Size.ROW_STANDARD - 2)
        icon.Parent = pill

        local lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency = 1
        lbl.Text = UIUtils.formatNumber(tonumber(price) or 0)
        lbl.Font = Theme.fonts.Secondary
        lbl.TextScaled = true
        lbl.TextColor3 = Theme.colors.Text
        lbl.Size = UDim2.new(1, -UIx.Size.ROW_STANDARD, 1, 0)
        lbl.Parent = pill

        local ThemeRefresher = require(UIFolder:WaitForChild("ThemeRefresher"))
        ThemeRefresher.Bind(pill, { BackgroundColor3 = "Background" })
        ThemeRefresher.Bind(icon, { TextColor3 = "Text" })
        ThemeRefresher.Bind(lbl, { TextColor3 = "Text" })
        return pill
    end

    -- Price button below the icon (above the name label). If onClick is provided, creates a clickable area.
    function helpers.addPriceButtonBelow(price: number, onClick: (() -> ())?, enabled: boolean?)
        local btn = Instance.new("TextButton")
        btn.Name = "PriceButton"
        -- Centered horizontally, just above the name label area
        btn.AnchorPoint = Vector2.new(0.5, 1)
        btn.Position = UDim2.new(0.5, 0, 1, -(UIx.Spacing.TINY + UIx.Size.ROW_LARGE))
        local maxWidth = math.max(56, UIx.Size.INVENTORY_CELL_WIDTH - UIx.Spacing.SM * 2)
        local widthPx = math.min(72, maxWidth)
        btn.Size = UDim2.new(0, widthPx, 0, UIx.Size.ROW_STANDARD)
        btn.BackgroundColor3 = Theme.colors.Background
        btn.BackgroundTransparency = 0.1
        btn.AutoButtonColor = true
        btn.Text = ""
        btn.Parent = button
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, UIx.Spacing.MD)
        corner.Parent = btn

        local list = Instance.new("UIListLayout")
        list.FillDirection = Enum.FillDirection.Horizontal
        list.VerticalAlignment = Enum.VerticalAlignment.Center
        list.HorizontalAlignment = Enum.HorizontalAlignment.Center
        list.Padding = UDim.new(0, UIx.Spacing.TINY)
        list.Parent = btn

        local icon = Instance.new("TextLabel")
        icon.BackgroundTransparency = 1
        icon.Text = (Theme.icons and Theme.icons.currency and Theme.icons.currency.coins) or "$"
        icon.Font = Theme.fonts.Secondary
        icon.TextScaled = true
        icon.TextColor3 = Theme.colors.Text
        icon.Size = UDim2.new(0, UIx.Size.ROW_STANDARD - 2, 0, UIx.Size.ROW_STANDARD - 2)
        icon.Parent = btn

        local lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency = 1
        lbl.Text = UIUtils.formatNumber(tonumber(price) or 0)
        lbl.Font = Theme.fonts.Secondary
        lbl.TextScaled = true
        lbl.TextColor3 = Theme.colors.Text
        lbl.Size = UDim2.new(1, -UIx.Size.ROW_STANDARD, 1, 0)
        lbl.Parent = btn

        local ThemeRefresher = require(UIFolder:WaitForChild("ThemeRefresher"))
        ThemeRefresher.Bind(btn, { BackgroundColor3 = "Background" })
        ThemeRefresher.Bind(icon, { TextColor3 = "Text" })
        ThemeRefresher.Bind(lbl, { TextColor3 = "Text" })

        local canClick = (enabled ~= false) and (onClick ~= nil)
        btn.Active = canClick
        btn.AutoButtonColor = canClick
        if not (canClick and onClick) then
            btn.BackgroundTransparency = 0.3
            lbl.TextColor3 = Theme.colors.TextSecondary or Theme.colors.Text
        else
            btn.Activated:Connect(onClick)
        end

        return { button = btn, label = lbl, width = widthPx }
    end

    -- Price button anchored bottom-right within the name row; returns {button, label, width}
    function helpers.addPriceButtonBottomRight(price: number, onClick: (() -> ())?, enabled: boolean?)
        local btn = Instance.new("TextButton")
        btn.Name = "PriceButton"
        btn.AnchorPoint = Vector2.new(1, 1)
        btn.Position = UDim2.new(1, -UIx.Spacing.TINY, 1, -UIx.Spacing.TINY)
        local maxWidth = math.max(56, UIx.Size.INVENTORY_CELL_WIDTH - UIx.Spacing.SM * 2)
        local widthPx = math.min(72, maxWidth)
        btn.Size = UDim2.new(0, widthPx, 0, UIx.Size.ROW_STANDARD)
        btn.BackgroundColor3 = Theme.colors.Background
        btn.BackgroundTransparency = 0.1
        btn.AutoButtonColor = true
        btn.Text = ""
        btn.Parent = button
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, UIx.Spacing.MD)
        corner.Parent = btn

        local list = Instance.new("UIListLayout")
        list.FillDirection = Enum.FillDirection.Horizontal
        list.VerticalAlignment = Enum.VerticalAlignment.Center
        list.HorizontalAlignment = Enum.HorizontalAlignment.Center
        list.Padding = UDim.new(0, UIx.Spacing.TINY)
        list.Parent = btn

        local icon = Instance.new("TextLabel")
        icon.BackgroundTransparency = 1
        icon.Text = (Theme.icons and Theme.icons.currency and Theme.icons.currency.coins) or "$"
        icon.Font = Theme.fonts.Secondary
        icon.TextScaled = true
        icon.TextColor3 = Theme.colors.Text
        icon.Size = UDim2.new(0, UIx.Size.ROW_STANDARD - 2, 0, UIx.Size.ROW_STANDARD - 2)
        icon.Parent = btn

        local lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency = 1
        lbl.Text = UIUtils.formatNumber(tonumber(price) or 0)
        lbl.Font = Theme.fonts.Secondary
        lbl.TextScaled = true
        lbl.TextColor3 = Theme.colors.Text
        lbl.Size = UDim2.new(1, -UIx.Size.ROW_STANDARD, 1, 0)
        lbl.Parent = btn

        local ThemeRefresher = require(UIFolder:WaitForChild("ThemeRefresher"))
        ThemeRefresher.Bind(btn, { BackgroundColor3 = "Background" })
        ThemeRefresher.Bind(icon, { TextColor3 = "Text" })
        ThemeRefresher.Bind(lbl, { TextColor3 = "Text" })

        local canClick = (enabled ~= false) and (onClick ~= nil)
        btn.Active = canClick
        btn.AutoButtonColor = canClick
        if not (canClick and onClick) then
            btn.BackgroundTransparency = 0.3
            lbl.TextColor3 = Theme.colors.TextSecondary or Theme.colors.Text
        else
            btn.Activated:Connect(onClick)
        end

        return { button = btn, label = lbl, width = widthPx }
    end

    -- Ownership badge (clearer than plain text): top-right pill
    function helpers.addOwnershipBadge(it: any, ownedCount: number)
        local badge = Instance.new("TextLabel")
        badge.Name = "OwnershipBadge"
        badge.AnchorPoint = Vector2.new(1, 0)
        badge.Position = UDim2.new(1, -UIx.Spacing.TINY, 0, UIx.Spacing.TINY)
        badge.Size = UDim2.new(0, math.max(56, UIx.Size.GRID_CELL_PX/2), 0, UIx.Size.ROW_STANDARD)
        badge.BackgroundTransparency = 0.15
        badge.TextScaled = true
        badge.Font = Theme.fonts.Secondary
        badge.TextXAlignment = Enum.TextXAlignment.Center
        badge.TextYAlignment = Enum.TextYAlignment.Center
        badge.Parent = button
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, UIx.Spacing.MD)
        corner.Parent = badge

        local isResource = (it and it.type == "resource")
        local owned = tonumber(ownedCount or 0) or 0
        if isResource then
            if owned > 0 then
                badge.Text = "x" .. tostring(owned)
                badge.BackgroundColor3 = Theme.colors.Background
                badge.TextColor3 = Theme.colors.Text
            else
                badge.Text = "Unowned"
                badge.BackgroundColor3 = Theme.colors.Error
                badge.TextColor3 = Theme.colors.OnPrimary or Theme.colors.Text
            end
        else
            if owned > 0 then
                badge.Text = "Owned"
                badge.BackgroundColor3 = Theme.colors.Success
                badge.TextColor3 = Theme.colors.Text
            else
                badge.Text = "Unowned"
                badge.BackgroundColor3 = Theme.colors.Error
                badge.TextColor3 = Theme.colors.OnPrimary or Theme.colors.Text
            end
        end
        return badge
    end

    -- Ownership badge placed at top-left (to avoid price pill in top-right)
    function helpers.addOwnershipBadgeLeft(it: any, ownedCount: number)
        local badge = Instance.new("TextLabel")
        badge.Name = "OwnershipBadge"
        badge.AnchorPoint = Vector2.new(0, 0)
        badge.Position = UDim2.new(0, UIx.Spacing.TINY, 0, UIx.Spacing.TINY)
        badge.Size = UDim2.new(0, math.max(56, UIx.Size.GRID_CELL_PX/2), 0, UIx.Size.ROW_STANDARD)
        badge.BackgroundTransparency = 0.15
        badge.TextScaled = true
        badge.Font = Theme.fonts.Secondary
        badge.TextXAlignment = Enum.TextXAlignment.Center
        badge.TextYAlignment = Enum.TextYAlignment.Center
        badge.Parent = button
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, UIx.Spacing.MD)
        corner.Parent = badge

        local isResource = (it and it.type == "resource")
        local owned = tonumber(ownedCount or 0) or 0
        if isResource then
            if owned > 0 then
                badge.Text = "x" .. tostring(owned)
                badge.BackgroundColor3 = Theme.colors.Background
                badge.TextColor3 = Theme.colors.Text
            else
                badge.Text = "Unowned"
                badge.BackgroundColor3 = Theme.colors.Error
                badge.TextColor3 = Theme.colors.OnPrimary or Theme.colors.Text
            end
        else
            if owned > 0 then
                badge.Text = "Owned"
                badge.BackgroundColor3 = Theme.colors.Success
                badge.TextColor3 = Theme.colors.Text
            else
                badge.Text = "Unowned"
                badge.BackgroundColor3 = Theme.colors.Error
                badge.TextColor3 = Theme.colors.OnPrimary or Theme.colors.Text
            end
        end
        return badge
    end

    -- (Info button helper removed; use tile click -> ItemDetailsPopup for details)

    -- Dim visuals for missing items (no reading required)
    function helpers.applyOwnershipVisuals(it: any, ownedCount: number, labels: {symbol: GuiObject?, name: TextLabel?}?)
        local owned = tonumber(ownedCount or 0) or 0
        local isResource = (it and it.type == "resource")
        local missing = (owned <= 0)
        if not missing then return end

        -- Slightly increase background transparency (subtle fade)
        button.BackgroundTransparency = math.max((button.BackgroundTransparency or 0.1), 0.25)

        -- Dim and desaturate labels if available
        local sym = labels and labels.symbol or (button:FindFirstChild("ItemDisplay") :: GuiObject)
        local name = labels and labels.name or (button:FindFirstChild("Name") :: TextLabel)
        if sym then
            if sym:IsA("TextLabel") then
                -- Fade a bit, but preserve original color (no forced gray)
                sym.TextTransparency = 0.15
            elseif sym:IsA("ImageLabel") then
                local img = (sym :: ImageLabel)
                -- Fade slightly; do not recolor so multi-color icons remain
                img.ImageTransparency = 0.15
            elseif sym:IsA("Frame") then
                sym.BackgroundTransparency = 0.15
                local s = sym:FindFirstChildOfClass("UIStroke")
                if s then s.Transparency = math.min(1, (s.Transparency or 0) + 0.2) end
            end
        end
        if name and name:IsA("TextLabel") then
            -- Fade name and use secondary text color
            name.TextTransparency = 0.1
            name.TextColor3 = Theme.colors.TextSecondary or Theme.colors.Text
        end

        -- Soften rarity stroke
        local stroke = button:FindFirstChildOfClass("UIStroke")
        if stroke then stroke.Transparency = 0.5 end
    end

    function helpers.showEquippedOverlay()
        local overlay = Instance.new("TextLabel")
        overlay.Name = "Equipped"
        overlay.Size = UDim2.new(1, 0, 0, UIx.Size.ROW_TINY)
        overlay.Position = UDim2.new(0, 0, 0.5, -(UIx.Size.ROW_TINY / 2))
        overlay.BackgroundColor3 = Theme.colors.Success
        overlay.BackgroundTransparency = 0.8
        overlay.Text = "EQUIPPED"
        overlay.TextColor3 = Theme.colors.Text
        overlay.Font = Theme.fonts.Primary
        overlay.TextSize = UIx.Visual.TEXT_TINY
        overlay.Parent = button
        local corner2 = Instance.new("UICorner")
        corner2.CornerRadius = UDim.new(0, UIx.Spacing.TINY)
        corner2.Parent = overlay
        local ThemeRefresher = require(UIFolder:WaitForChild("ThemeRefresher"))
        ThemeRefresher.Bind(overlay, { BackgroundColor3 = "Success", TextColor3 = "Text" })
        return overlay
    end

    -- Hover effect (match Inventory style)
    button.MouseEnter:Connect(function()
        game:GetService("TweenService"):Create(button, TweenInfo.new(UIx.Anim.FAST), { BackgroundTransparency = 0 }):Play()
    end)
    button.MouseLeave:Connect(function()
        game:GetService("TweenService"):Create(button, TweenInfo.new(UIx.Anim.FAST), { BackgroundTransparency = (opts.backgroundTransparency ~= nil) and opts.backgroundTransparency or 0.1 }):Play()
    end)

    return { button = button, helpers = helpers }
end

-- Expose a symbol helper for other UIs (e.g., detail popups)
function ItemTileRenderer.symbolFor(it: any): string
    -- Reuse internal logic; synthesize minimal item shape
    local ref = it
    return (function()
        if ref then
            if typeof((ref :: any).icon) == "string" and (ref :: any).icon ~= "" then return (ref :: any).icon end
            local meta = (ref :: any).meta
            if meta and typeof(meta.icon) == "string" and meta.icon ~= "" then return meta.icon end
        end
        return chooseSymbol(ref)
    end)()
end

return ItemTileRenderer
