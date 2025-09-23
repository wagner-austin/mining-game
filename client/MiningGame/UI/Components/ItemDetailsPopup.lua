--!strict
-- ItemDetailsPopup.lua
-- Modern item details modal with proper typography and visual hierarchy

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MG = ReplicatedStorage:WaitForChild("MiningGame")
local UIFolder = MG:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))
local UIx = require(UIFolder:WaitForChild("UIConstants"))
local UIUtils = require(UIFolder:WaitForChild("UIUtils"))
local ThemeRefresher = require(UIFolder:WaitForChild("ThemeRefresher"))
local ItemInsights = require(MG:WaitForChild("ItemInsights"))
local LootMath = require(MG:WaitForChild("LootMath"))
local ClientRF = require(MG:WaitForChild("ClientRF"))
local TextUtils = require(MG:WaitForChild("TextUtils"))
local PlayerProfileGuard = require(MG:WaitForChild("PlayerProfileGuard"))
local BaseChip = require(script.Parent:WaitForChild("BaseChip"))
local Renderer = require(script.Parent:WaitForChild("ItemTileRenderer"))
local BaseInfoPopup = require(script.Parent:WaitForChild("BaseInfoPopup"))

type Props = { parent: Instance, itemId: string }

local ItemDetailsPopup = {}
ItemDetailsPopup.__index = ItemDetailsPopup

local function createSection(parent: Instance, title: string): Frame
    local section = Instance.new("Frame")
    section.BackgroundTransparency = 1
    section.Size = UDim2.new(1, 0, 0, 0)
    section.Parent = parent

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.Padding = UDim.new(0, UIx.Spacing.SM)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = section

    if title then
        local header = Instance.new("TextLabel")
        header.BackgroundTransparency = 1
        header.Text = title:upper()
        header.TextXAlignment = Enum.TextXAlignment.Left
        header.TextSize = UIx.Visual.TEXT_HEADER
        header.Font = Theme.fonts.Display
        header.TextColor3 = Theme.colors.Text
        header.Size = UDim2.new(1, 0, 0, UIx.Size.ROW_HEADER)
        header.LayoutOrder = 1
        header.Parent = section
        ThemeRefresher.Bind(header, { TextColor3 = "Text" })

        local divider = Instance.new("Frame")
        divider.BackgroundColor3 = Theme.colors.Text
        divider.BackgroundTransparency = 0.7
        divider.Size = UDim2.new(1, 0, 0, 1)
        divider.LayoutOrder = 2
        divider.Parent = section
        ThemeRefresher.Bind(divider, { BackgroundColor3 = "Text" })
    end

    section.AutomaticSize = Enum.AutomaticSize.Y

    return section
end

local function row(parent: Instance, label: string, value: string, color: Color3?, layoutOrder: number?)
    local r = Instance.new("Frame")
    r.BackgroundTransparency = 1
    r.Size = UDim2.new(1, 0, 0, UIx.Size.ROW_LARGE)
    r.LayoutOrder = layoutOrder or 0
    r.Parent = parent

    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Text = label
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextSize = UIx.Visual.TEXT_HEADER
    l.Font = Theme.fonts.Secondary
    l.TextColor3 = Theme.colors.TextSecondary or Theme.colors.Text
    l.Size = UDim2.new(0.4, -UIx.Spacing.MD, 1, 0)
    l.Parent = r
    ThemeRefresher.Bind(l, { TextColor3 = "TextSecondary" })

    local v = Instance.new("TextLabel")
    v.BackgroundTransparency = 1
    v.Text = value
    v.TextXAlignment = Enum.TextXAlignment.Left
    v.TextSize = UIx.Visual.TEXT_HEADER
    v.Font = Theme.fonts.Primary
    v.TextColor3 = color or Theme.colors.Text
    v.Size = UDim2.new(0.6, 0, 1, 0)
    v.Position = UDim2.new(0.4, UIx.Spacing.MD, 0, 0)
    v.TextWrapped = true
    v.Parent = r
    if not color then
        ThemeRefresher.Bind(v, { TextColor3 = "Text" })
    end

    return r
end

local function chipRow(parent: Instance, chips: {{text: string, icon: string?, color: Color3?}}, layoutOrder: number?)
    local container = Instance.new("Frame")
    container.BackgroundTransparency = 1
    container.Size = UDim2.new(1, 0, 0, 36)
    container.LayoutOrder = layoutOrder or 0
    container.Parent = parent

    local chipLayout = Instance.new("UIListLayout")
    chipLayout.FillDirection = Enum.FillDirection.Horizontal
    chipLayout.Padding = UDim.new(0, UIx.Spacing.SM)
    chipLayout.SortOrder = Enum.SortOrder.LayoutOrder
    chipLayout.Parent = container

    for i, chip in ipairs(chips) do
        BaseChip.new({
            parent = container,
            size = nil,  -- Let BaseChip use its default size
            icon = chip.icon,
            text = chip.text,
            textColor = chip.color
        })
    end

    return container
end

function ItemDetailsPopup.new(props: Props)
    local self = setmetatable({}, ItemDetailsPopup)
    local insight = ItemInsights.get(props.itemId)
    if not insight then return self end

    -- Create base modal
    local base = BaseInfoPopup.new({ parent = props.parent, size = UDim2.new(0, 360, 0, 280) })
    local card = base.card :: Frame

    -- Main layout
    local mainLayout = Instance.new("UIListLayout")
    mainLayout.FillDirection = Enum.FillDirection.Vertical
    mainLayout.Padding = UDim.new(0, UIx.Spacing.SM)
    mainLayout.SortOrder = Enum.SortOrder.LayoutOrder
    mainLayout.Parent = card

    -- Compact header
    local header = Instance.new("Frame")
    header.BackgroundTransparency = 1
    header.Size = UDim2.new(1, 0, 0, 56)
    header.LayoutOrder = 1
    header.Parent = card

    local icon = Instance.new("ImageLabel")
    icon.BackgroundTransparency = 1
    icon.Size = UDim2.new(0, 48, 0, 48)
    icon.Position = UDim2.new(0, 0, 0.5, -24)
    icon.Image = (insight.icon and (insight.icon:match("^%d+$") and ("rbxassetid://"..insight.icon) or insight.icon)) or ""
    icon.ScaleType = Enum.ScaleType.Fit
    icon.Parent = header

    local displayName = insight.name or insight.id
    if displayName == insight.id or string.find(displayName, "_") or string.find(displayName, "%-") then
        displayName = TextUtils.prettifyItemName(insight.id, { id = insight.id, name = displayName })
    end

    local nameLabel = Instance.new("TextLabel")
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = displayName
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.TextYAlignment = Enum.TextYAlignment.Center
    nameLabel.Font = Theme.fonts.Display
    nameLabel.TextSize = UIx.Visual.TEXT_TITLE
    nameLabel.TextColor3 = insight.rarityColor or Theme.colors.Text
    nameLabel.Position = UDim2.new(0, 56, 0, 0)
    nameLabel.Size = UDim2.new(1, -56, 1, 0)
    nameLabel.TextWrapped = true
    nameLabel.TextStrokeTransparency = 0.8
    nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    nameLabel.Parent = header
    if not insight.rarityColor then
        ThemeRefresher.Bind(nameLabel, { TextColor3 = "Text" })
    end


    -- Content container (no scrolling needed for compact version)
    local content = Instance.new("Frame")
    content.BackgroundTransparency = 1
    content.Size = UDim2.new(1, 0, 1, -56)
    content.LayoutOrder = 2
    content.Parent = card

    local contentLayout = Instance.new("UIListLayout")
    contentLayout.FillDirection = Enum.FillDirection.Vertical
    contentLayout.Padding = UDim.new(0, UIx.Spacing.SM)
    contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
    contentLayout.Parent = content

    -- Essential info chips
    local statusChips = {}
    local typeSlot = insight.slot and (insight.type .. " • " .. insight.slot) or insight.type
    local symbol = Renderer.symbolFor({ id = insight.id, type = insight.type, slot = insight.slot, icon = insight.icon })

    if insight.rarity then
        table.insert(statusChips, {
            text = insight.rarity:upper(),
            icon = "✨",
            color = insight.rarityColor
        })
    end

    table.insert(statusChips, { text = typeSlot, icon = symbol })

    local ownedCount = 0
    local profile = select(1, PlayerProfileGuard.get())
    if profile and profile.inventory then
        ownedCount = tonumber(profile.inventory[insight.id] or 0) or 0
    end

    table.insert(statusChips, {
        text = ownedCount > 0 and ("×" .. tostring(ownedCount)) or "Unowned",
        icon = ownedCount > 0 and "✓" or "✕",
        color = ownedCount > 0 and Theme.colors.Success or Theme.colors.Error
    })

    chipRow(content, statusChips, 1)

    -- Key details only
    local detailsContainer = Instance.new("Frame")
    detailsContainer.BackgroundTransparency = 1
    detailsContainer.Size = UDim2.new(1, 0, 0, 0)
    detailsContainer.AutomaticSize = Enum.AutomaticSize.Y
    detailsContainer.LayoutOrder = 2
    detailsContainer.Parent = content

    local detailsLayout = Instance.new("UIListLayout")
    detailsLayout.FillDirection = Enum.FillDirection.Vertical
    detailsLayout.Padding = UDim.new(0, UIx.Spacing.TINY)
    detailsLayout.SortOrder = Enum.SortOrder.LayoutOrder
    detailsLayout.Parent = detailsContainer

    -- Compact rows with smaller text
    local function compactRow(label: string, value: string, color: Color3?, layoutOrder: number?)
        local r = Instance.new("Frame")
        r.BackgroundTransparency = 1
        r.Size = UDim2.new(1, 0, 0, UIx.Size.ROW_SMALL)
        r.LayoutOrder = layoutOrder or 0
        r.Parent = detailsContainer

        local l = Instance.new("TextLabel")
        l.BackgroundTransparency = 1
        l.Text = label
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.TextSize = UIx.Visual.TEXT_MEDIUM
        l.Font = Theme.fonts.Secondary
        l.TextColor3 = Theme.colors.TextSecondary
        l.Size = UDim2.new(0.35, 0, 1, 0)
        l.Parent = r
        ThemeRefresher.Bind(l, { TextColor3 = "TextSecondary" })

        local v = Instance.new("TextLabel")
        v.BackgroundTransparency = 1
        v.Text = value
        v.TextXAlignment = Enum.TextXAlignment.Left
        v.TextSize = UIx.Visual.TEXT_MEDIUM
        v.Font = Theme.fonts.Primary
        v.TextColor3 = color or Theme.colors.Text
        v.Size = UDim2.new(0.65, 0, 1, 0)
        v.Position = UDim2.new(0.35, 0, 0, 0)
        v.Parent = r
        if not color then
            ThemeRefresher.Bind(v, { TextColor3 = "Text" })
        end
    end

    -- Only show the most essential info
    if insight.value and insight.value > 0 then
        local valueText = tostring(insight.value):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
        compactRow("Value", valueText .. " coins", nil, 1)
    end

    -- Drop rate (per dig) only
    do
        local provider = (_G and _G.UIManager and _G.UIManager.accountDataProvider) or nil
        local matId = nil
        if provider and provider.getSnapshot then
            local snap = provider:getSnapshot()
            matId = snap and snap.profile and snap.profile.materialId
        end
        local luck = 1.0
        local size = 1
        local ok, res = pcall(function()
            return ClientRF.call("GetEffectiveStats")
        end)
        if ok and res and res.success and res.effectiveStats then
            local es = res.effectiveStats
            if typeof(es.luck) == "number" then luck = es.luck end
            if typeof(es.size) == "number" then size = es.size end
            if not matId and typeof(res.materialId) == "string" then matId = res.materialId end
        end

        local pDig = LootMath.dropRatePerDigAction(insight.id, {
            materialId = matId,
            luckMultiplier = luck,
            chanceMult = 1.0,
            size = size,
        })
        compactRow("Drop (per dig)", string.format("%.3f%%", (pDig or 0) * 100), nil, 2)
    end

    if insight.sources and #insight.sources > 0 then
        local sources = insight.sources[1] -- Just show first source
        if #insight.sources > 1 then sources = sources .. " (+"..(#insight.sources-1).." more)" end
        compactRow("Source", sources, nil, 3)
    end

    -- Event connections
    self._scrim = base.scrim
    self._card = card
    return self
end

function ItemDetailsPopup:destroy()
    if self._scrim then self._scrim:Destroy() end
    self._scrim = nil
    self._card = nil
end

return ItemDetailsPopup
