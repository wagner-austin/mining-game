--!strict
-- PassDetailsPopup.lua
-- Compact details popup for Gamepasses (permanent upgrades via Robux)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MG = ReplicatedStorage:WaitForChild("MiningGame")
local UI = MG:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local UIx = require(UI:WaitForChild("UIConstants"))
local ThemeRefresher = require(UI:WaitForChild("ThemeRefresher"))
local BaseInfoPopup = require(script.Parent:WaitForChild("BaseInfoPopup"))
local UIUtils = require(UI:WaitForChild("UIUtils"))
local ClientRF = require(MG:WaitForChild("ClientRF"))
local GameConfig = require(MG:WaitForChild("GameConfig"))

type Props = { parent: Instance, passId: string }

local PassDetailsPopup = {}
PassDetailsPopup.__index = PassDetailsPopup

local function findPass(passId: string)
    local list = (GameConfig.Monetization and GameConfig.Monetization.GAMEPASSES) or {}
    for _, p in ipairs(list) do
        if p.id == passId then return p end
    end
    return nil
end

local function isAssetString(s: any): boolean
    if typeof(s) ~= "string" then return false end
    if s == "" then return false end
    return s:match("^rbxassetid://%d+$") ~= nil
        or s:match("^rbxasset://") ~= nil
        or s:match("^https?://") ~= nil
        or s:match("^%d+$") ~= nil
end

local function row(parent: Instance, label: string, value: string)
    local r = Instance.new("Frame")
    r.BackgroundTransparency = 1
    r.Size = UDim2.new(1, 0, 0, UIx.Size.ROW_SMALL)
    r.Parent = parent

    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Text = label
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Font = Theme.fonts.Secondary
    l.TextSize = UIx.Visual.TEXT_MEDIUM
    l.TextColor3 = Theme.colors.TextSecondary or Theme.colors.Text
    l.Size = UDim2.new(0.4, -UIx.Spacing.MD, 1, 0)
    l.Parent = r
    ThemeRefresher.Bind(l, { TextColor3 = "TextSecondary" })

    local v = Instance.new("TextLabel")
    v.BackgroundTransparency = 1
    v.Text = value
    v.TextXAlignment = Enum.TextXAlignment.Left
    v.Font = Theme.fonts.Primary
    v.TextSize = UIx.Visual.TEXT_MEDIUM
    v.TextColor3 = Theme.colors.Text
    v.Size = UDim2.new(0.6, 0, 1, 0)
    v.Position = UDim2.new(0.4, UIx.Spacing.MD, 0, 0)
    v.Parent = r
    ThemeRefresher.Bind(v, { TextColor3 = "Text" })
end

function PassDetailsPopup.new(props: Props)
    local self = setmetatable({}, PassDetailsPopup)
    local pass = findPass(props.passId)
    if not pass then return self end

    local base = BaseInfoPopup.new({ parent = props.parent, size = UDim2.new(0, 360, 0, 220) })
    local card = base.card :: Frame

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.Padding = UDim.new(0, UIx.Spacing.SM)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = card

    -- Header with icon + name
    local header = Instance.new("Frame")
    header.BackgroundTransparency = 1
    header.Size = UDim2.new(1, 0, 0, 56)
    header.LayoutOrder = 1
    header.Parent = card
    local title = pass.name or pass.id or "Gamepass"

    -- Get official icon from GetGamepasses
    local iconStr: string? = nil
    do
        local ok, res = pcall(function()
            return ClientRF.call("GetGamepasses")
        end)
        if ok and res and res.list then
            for _, entry in ipairs(res.list) do
                if entry.id == pass.id and typeof(entry.icon) == "string" and entry.icon ~= "" then
                    iconStr = entry.icon
                    break
                end
            end
        end
    end

    if isAssetString(iconStr) then
        local img = Instance.new("ImageLabel")
        img.BackgroundTransparency = 1
        img.Size = UDim2.new(0, 48, 0, 48)
        img.Position = UDim2.new(0, 0, 0.5, -24)
        img.Image = iconStr:match("^%d+$") and ("rbxassetid://" .. iconStr) or iconStr
        img.ScaleType = Enum.ScaleType.Fit
        img.Parent = header
    else
        local lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency = 1
        lbl.Text = "PASS"
        lbl.Font = Theme.fonts.Display
        lbl.TextSize = UIx.Visual.TEXT_TITLE
        lbl.TextColor3 = Theme.colors.Text
        lbl.Size = UDim2.new(0, 48, 0, 48)
        lbl.Position = UDim2.new(0, 0, 0.5, -24)
        lbl.TextXAlignment = Enum.TextXAlignment.Center
        lbl.TextYAlignment = Enum.TextYAlignment.Center
        lbl.Parent = header
        ThemeRefresher.Bind(lbl, { TextColor3 = "Text" })
    end

    local nameLabel = Instance.new("TextLabel")
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = title
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.TextYAlignment = Enum.TextYAlignment.Center
    nameLabel.Font = Theme.fonts.Display
    nameLabel.TextSize = UIx.Visual.TEXT_TITLE
    nameLabel.TextColor3 = Theme.colors.Text
    nameLabel.Position = UDim2.new(0, 56, 0, 0)
    nameLabel.Size = UDim2.new(1, -56, 1, 0)
    nameLabel.TextWrapped = true
    nameLabel.Parent = header
    ThemeRefresher.Bind(nameLabel, { TextColor3 = "Text" })

    -- Owned status (query RF; tolerate failure)
    local ownedText = "Checking..."
    local ok, res = pcall(function()
        return ClientRF.call("GetGamepasses")
    end)
    if ok and res and res.list then
        local owned = false
        for _, entry in ipairs(res.list) do
            if entry.id == pass.id then owned = entry.owned == true break end
        end
        ownedText = owned and "Owned" or "Unowned"
    else
        ownedText = "Unknown"
    end
    row(card, "Status", ownedText)

    -- Price (Robux)
    if tonumber(pass.robux) then
        row(card, "Price", string.format("R$ %s", UIUtils.formatNumber(tonumber(pass.robux))))
    end

    -- Effects summary
    local effects = pass.effects
    if type(effects) == "table" then
        local parts = {}
        for k, v in pairs(effects) do
            local key = tostring(k)
            if key == "loot_multiplier" and typeof(v) == "number" then
                table.insert(parts, string.format("Loot x%.2f", v))
            elseif key == "size_bonus" and typeof(v) == "number" then
                table.insert(parts, string.format("Tool Size +%d", v))
            else
                table.insert(parts, string.format("%s: %s", key, tostring(v)))
            end
        end
        if #parts > 0 then
            row(card, "Effects", table.concat(parts, "; "))
        end
    else
        row(card, "Type", "Permanent upgrade")
    end

    self._scrim = base.scrim
    self._card = card
    return self
end

function PassDetailsPopup:destroy()
    if self._scrim then self._scrim:Destroy() end
    self._scrim = nil
    self._card = nil
end

return PassDetailsPopup
