--!strict
-- BaseBillboard.lua
-- Reusable theme-matching frosted billboard for world-space panels (e.g., High Score)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UIFolder = MiningGame:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))
local UIx = require(UIFolder:WaitForChild("UIConstants"))
local UIUtils = require(UIFolder:WaitForChild("UIUtils"))
local ThemeManager = require(UIFolder:WaitForChild("ThemeManager"))
local ThemeRefresher = require(UIFolder:WaitForChild("ThemeRefresher"))

export type Props = {
    adornee: BasePart,            -- BasePart to attach to (SurfaceGui)
    parent: Instance?,            -- Optional parent for the SurfaceGui (defaults to adornee)
    face: Enum.NormalId?,         -- Face to render on (default Front)
    canvasSize: Vector2?,         -- CanvasSize in pixels (default 520x220)
    pixelsPerStud: number?,       -- When using PixelsPerStud sizing (unused by default)
    zIndex: number?,              -- Base ZIndex for internal frames
    title: string?,               -- Optional heading text
    accentColor: Color3?,         -- Accent strip color (defaults Theme.colors.Primary)
}

export type BaseBillboardT = {
    gui: SurfaceGui,
    root: Frame,
    content: Frame,
    setTitle: (self: BaseBillboardT, title: string) -> (),
    setAccentColor: (self: BaseBillboardT, color: Color3) -> (),
    destroy: (self: BaseBillboardT) -> (),
}

local BaseBillboard = {}
BaseBillboard.__index = BaseBillboard
function BaseBillboard.new(props: Props): BaseBillboardT
    assert(props and props.adornee and props.adornee:IsA("BasePart"), "BaseBillboard.new: props.adornee BasePart is required")

    local adornee = props.adornee
    local z = props.zIndex or 10
    local face = props.face or Enum.NormalId.Front
    local canvasSize: Vector2 = props.canvasSize or Vector2.new(520, 220)
    local accentColor = props.accentColor or Theme.colors.Primary

    local gui = Instance.new("SurfaceGui")
    gui.Name = "BaseBillboard"
    gui.Adornee = adornee
    gui.Face = face
    gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
    gui.CanvasSize = canvasSize
    gui.LightInfluence = 0
    gui.AlwaysOnTop = true
    gui.ResetOnSpawn = false
    gui.Parent = props.parent or adornee

    -- Root background (frosted)
    local root = Instance.new("Frame")
    root.Name = "Root"
    root.AnchorPoint = Vector2.new(0.5, 0.5)
    root.Position = UDim2.fromScale(0.5, 0.5)
    root.Size = UDim2.fromScale(1, 1)
    root.BackgroundColor3 = Theme.colors.Surface
    root.BackgroundTransparency = Theme.effects.frosted.backgroundTransparency
    root.ClipsDescendants = true
    root.ZIndex = z
    root.Parent = gui

    -- Corners
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, Theme.sizes.LargeCornerRadius)
    corner.Parent = root

    -- Glass edge
    UIUtils.applyGlassEdge(root)

    -- Frosted gradient
    local gradient = Instance.new("UIGradient")
    gradient.Rotation = 90
    gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(1, 1, 1))
    local frosted = Theme.effects.frosted
    gradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, frosted.gradientTopT),
        NumberSequenceKeypoint.new(1, frosted.gradientBottomT),
    })
    gradient.Parent = root

    -- Noise texture
    local noise = Instance.new("ImageLabel")
    noise.Name = "Noise"
    noise.BackgroundTransparency = 1
    noise.Image = "rbxasset://textures/ui/GuiImagePlaceholder.png"
    local base = Theme.colors[frosted.noiseColorKey] or Theme.colors.Background
    local t = math.clamp(frosted.noiseLighten or 0, 0, 1)
    local tinted = t > 0 and base:Lerp(Color3.new(1, 1, 1), t) or base
    noise.ImageColor3 = tinted
    noise.ImageTransparency = frosted.noiseTransparency
    noise.ScaleType = Enum.ScaleType.Tile
    noise.TileSize = UDim2.fromOffset(64, 64)
    noise.Size = UDim2.fromScale(1, 1)
    noise.ZIndex = z
    noise.Parent = root

    -- Register frosted bits for live theme refresh
    UIUtils.registerFrosted(root, gradient, noise)

    -- Register root background for theme updates
    ThemeRefresher.Bind(root, { Background = "Surface" })

    -- Accent bar
    local accent = Instance.new("Frame")
    accent.Name = "Accent"
    accent.BackgroundColor3 = accentColor
    accent.BorderSizePixel = 0
    accent.Size = UDim2.new(0, UIx.ACCENT_WIDTH, 1, 0)
    accent.Position = UDim2.fromOffset(0, 0)
    accent.ZIndex = z + 1
    accent.Parent = root

    -- Content container (padding to the right of accent with proper margins)
    local content = Instance.new("Frame")
    content.Name = "Content"
    content.BackgroundTransparency = 1
    content.Size = UDim2.new(1, -UIx.ACCENT_WIDTH - UIx.Spacing.LG * 2, 1, -UIx.Spacing.LG * 2)
    content.Position = UDim2.new(0, UIx.ACCENT_WIDTH + UIx.Spacing.LG, 0, UIx.Spacing.LG)
    content.ZIndex = z + 2
    content.Parent = root

    -- Optional title
    local titleLabel: TextLabel? = nil
    if props.title and #props.title > 0 then
        titleLabel = Instance.new("TextLabel")
        titleLabel.Name = "Title"
        titleLabel.BackgroundTransparency = 1
        titleLabel.Size = UDim2.new(1, 0, 0, UIx.Size.ROW_HEADER)
        titleLabel.Position = UDim2.fromOffset(0, 0)
        titleLabel.Font = Theme.fonts.Display or Theme.fonts.Primary
        titleLabel.Text = props.title
        titleLabel.TextColor3 = Theme.colors.Text
        titleLabel.TextXAlignment = Enum.TextXAlignment.Left
        titleLabel.TextYAlignment = Enum.TextYAlignment.Top
        titleLabel.TextScaled = true
        titleLabel.ZIndex = z + 3
        titleLabel.Parent = content

        -- Text size constraint
        local titleConstraint = Instance.new("UITextSizeConstraint")
        titleConstraint.MinTextSize = Theme.textSizes.Medium.Min
        titleConstraint.MaxTextSize = Theme.textSizes.Medium.Max
        titleConstraint.Parent = titleLabel

        -- Bind to theme for dynamic color
        ThemeRefresher.Bind(titleLabel, { TextColor3 = "Text" })
    end

    local self: BaseBillboardT = setmetatable({
        gui = gui,
        root = root,
        content = content,
    }, BaseBillboard)

    function self:setTitle(title: string)
        local lbl = root:FindFirstChild("Content") and (root.Content:FindFirstChild("Title") :: any)
        if lbl and lbl:IsA("TextLabel") then
            lbl.Text = title
        elseif title and #title > 0 then
            -- Create title if it didn't exist
            local tl = Instance.new("TextLabel")
            tl.Name = "Title"
            tl.BackgroundTransparency = 1
            tl.Size = UDim2.new(1, 0, 0, UIx.Size.ROW_HEADER)
            tl.Position = UDim2.fromOffset(0, 0)
            tl.Font = Theme.fonts.Display or Theme.fonts.Primary
            tl.Text = title
            tl.TextColor3 = Theme.colors.Text
            tl.TextXAlignment = Enum.TextXAlignment.Left
            tl.TextYAlignment = Enum.TextYAlignment.Top
            tl.TextScaled = true
            tl.ZIndex = z + 3
            tl.Parent = content

            -- Text size constraint
            local titleConstraint = Instance.new("UITextSizeConstraint")
            titleConstraint.MinTextSize = Theme.textSizes.Medium.Min
            titleConstraint.MaxTextSize = Theme.textSizes.Medium.Max
            titleConstraint.Parent = tl

            -- Bind to theme for dynamic color
            ThemeRefresher.Bind(tl, { TextColor3 = "Text" })
        end
    end

    function self:setAccentColor(color: Color3)
        local a = root:FindFirstChild("Accent")
        if a and a:IsA("Frame") then
            a.BackgroundColor3 = color
        end
    end

    function self:destroy()
        gui:Destroy()
    end


    return self
end

return BaseBillboard
