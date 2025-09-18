--!strict
-- BaseInfoPopup.lua
-- Lightweight base for modal info popups (scrim + card), re-usable across panels

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MG = ReplicatedStorage:WaitForChild("MiningGame")
local UIFolder = MG:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))
local UIx = require(UIFolder:WaitForChild("UIConstants"))
local UIUtils = require(UIFolder:WaitForChild("UIUtils"))
local ThemeRefresher = require(UIFolder:WaitForChild("ThemeRefresher"))

export type BaseInfoPopupT = {
    scrim: TextButton?,
    card: Frame?,
    destroy: (self: BaseInfoPopupT) -> (),
}

type Props = {
    parent: Instance?,
    size: UDim2?,
    position: UDim2?,
    zIndex: number?,
}

local BaseInfoPopup = {}
BaseInfoPopup.__index = BaseInfoPopup

local function resolveParent(explicit: Instance?): Instance
    if explicit then return explicit end
    local ui = _G and _G.UIManager
    if ui and ui.overlayGui then
        return ui.overlayGui
    end
    local player = Players.LocalPlayer
    local pg = player and player:FindFirstChild("PlayerGui")
    if pg then return pg end
    -- Fallback to ReplicatedStorage UI container (not ideal but safe)
    return UIFolder
end

function BaseInfoPopup.new(props: Props): BaseInfoPopupT
    local self = setmetatable({}, BaseInfoPopup)

    local parent = resolveParent(props and props.parent)
    local z = props and props.zIndex or (Theme.z and Theme.z.Modal or UIx.ZIndex.MODAL)

    local scrim = Instance.new("TextButton")
    scrim.Name = "Scrim"
    scrim.BackgroundColor3 = Theme.colors.Scrim or Color3.new(0,0,0)
    scrim.BackgroundTransparency = Theme.modal and Theme.modal.scrimT or 0.25
    scrim.Text = ""
    scrim.AutoButtonColor = false
    scrim.Size = UDim2.fromScale(1, 1)
    scrim.ZIndex = z
    scrim.Parent = parent

    local card = Instance.new("Frame")
    card.Name = "InfoCard"
    card.Size = (props and props.size) or UDim2.new(0, 360, 0, 280)
    card.AnchorPoint = Vector2.new(0.5, 0.5)
    card.Position = (props and props.position) or UDim2.fromScale(0.5, 0.5)
    card.BackgroundColor3 = Theme.colors.Surface
    card.BackgroundTransparency = Theme.card and Theme.card.backgroundTransparency or 0.04
    card.ZIndex = z + 1
    card.Parent = scrim
    ThemeRefresher.Bind(card, { BackgroundColor3 = "Surface" })

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, UIx.Visual.CORNER_RADIUS)
    corner.Parent = card
    UIUtils.applyGlassEdge(card)

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, UIx.Spacing.MD)
    pad.PaddingBottom = UDim.new(0, UIx.Spacing.MD)
    pad.PaddingLeft = UDim.new(0, UIx.Spacing.MD)
    pad.PaddingRight = UDim.new(0, UIx.Spacing.MD)
    pad.Parent = card

    self.scrim = scrim
    self.card = card

    scrim.Activated:Connect(function()
        self:destroy()
    end)

    return self
end

function BaseInfoPopup:destroy()
    if self.scrim then self.scrim:Destroy() end
    self.scrim = nil
    self.card = nil
end

return BaseInfoPopup

