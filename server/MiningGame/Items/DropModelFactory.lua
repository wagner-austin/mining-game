--!strict
-- DropModelFactory.lua
-- Builds world drop models in one place for reuse and theming

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local TextUtils = require(Shared:WaitForChild("TextUtils"))

local DropModelFactory = {}

-- Create item drop model (anchored, with VFX and label)
function DropModelFactory.create(itemDef: any, position: Vector3, count: number): Model
    local model = Instance.new("Model")
    model.Name = "ItemDrop_" .. tostring(itemDef.id or "unknown")

    -- Main part (visual representation)
    local part = Instance.new("Part")
    part.Name = "ItemPart"
    part.Size = Vector3.new(1.5, 1.5, 1.5)
    -- Place near top of dug cell with a small margin
    local cellHalf = (GameConfig.Grid and GameConfig.Grid.CELL_SIZE_STUDS or 4) / 2
    local margin = 0.25
    part.Position = position + Vector3.new(0, cellHalf - margin, 0)
    part.Material = Enum.Material.Neon
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    part.CanCollide = false
    part.Anchored = true
    part.Parent = model

    -- Color based on rarity (fallback to white)
    local rarity = itemDef.rarity or "COMMON"
    local rarityData = GameConfig.Loot and GameConfig.Loot.RARITIES and GameConfig.Loot.RARITIES[rarity]
    local rarityColor = rarityData and rarityData.color or Color3.new(1, 1, 1)
    part.Color = rarityColor

    -- Glow
    local pointLight = Instance.new("PointLight")
    pointLight.Brightness = 2
    pointLight.Range = 10
    pointLight.Color = rarityColor
    pointLight.Parent = part

    -- Outline
    local selectionBox = Instance.new("SelectionBox")
    selectionBox.Adornee = part
    selectionBox.Color3 = rarityColor
    selectionBox.LineThickness = 0.05
    selectionBox.SurfaceColor3 = rarityColor
    selectionBox.SurfaceTransparency = 0.75
    selectionBox.Parent = part

    -- Nameplate (smaller, styled chip with background and border)
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "NameBillboard"
    billboard.Adornee = part
    billboard.Size = UDim2.new(0, 150, 0, 28)
    billboard.StudsOffset = Vector3.new(0, 1.6, 0)
    billboard.AlwaysOnTop = true
    local labelMaxDist = (GameConfig.Loot and GameConfig.Loot.LABEL_MAX_DISTANCE) or 200
    billboard.MaxDistance = labelMaxDist
    billboard.Parent = part

    -- Background chip
    local bg = Instance.new("Frame")
    bg.Name = "LabelBg"
    bg.Size = UDim2.new(0, 136, 0, 22)
    bg.AnchorPoint = Vector2.new(0.5, 0.5)
    bg.Position = UDim2.new(0.5, 0, 0.5, 0)
    bg.BackgroundColor3 = Color3.new(0, 0, 0)
    bg.BackgroundTransparency = 0.35
    bg.BorderSizePixel = 0
    bg.ZIndex = 1
    bg.Parent = billboard
    local bgCorner = Instance.new("UICorner")
    bgCorner.CornerRadius = UDim.new(0, 8)
    bgCorner.Parent = bg
    local bgStroke = Instance.new("UIStroke")
    bgStroke.Thickness = 1
    bgStroke.Transparency = 0.2
    bgStroke.Color = rarityColor
    bgStroke.Parent = bg

    -- Foreground text
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "NameLabel"
    nameLabel.Size = UDim2.new(0, 136, 0, 22)
    nameLabel.AnchorPoint = Vector2.new(0.5, 0.5)
    nameLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.TextScaled = true
    nameLabel.Font = Enum.Font.GothamSemibold
    nameLabel.TextColor3 = Color3.new(1, 1, 1)
    nameLabel.TextStrokeTransparency = 0.55
    nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    nameLabel.ZIndex = 2
    local displayName = TextUtils.prettifyItemName(itemDef and itemDef.id or nil, itemDef)
    nameLabel.Text = (count and count > 1) and (string.format("%s x%d", displayName, count)) or displayName
    local limit = Instance.new("UITextSizeConstraint")
    limit.MinTextSize = 9
    limit.MaxTextSize = 16
    limit.Parent = nameLabel
    nameLabel.Parent = billboard

    -- Ambient particles (subtle)
    local particleEmitter = Instance.new("ParticleEmitter")
    particleEmitter.Name = "AmbientParticles"
    particleEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    particleEmitter.Rate = 20
    particleEmitter.Lifetime = NumberRange.new(1, 2)
    particleEmitter.VelocityInheritance = 0
    particleEmitter.EmissionDirection = Enum.NormalId.Top
    particleEmitter.Speed = NumberRange.new(2, 4)
    particleEmitter.Color = ColorSequence.new(rarityColor)
    particleEmitter.LightEmission = 1
    particleEmitter.Parent = part

    -- Mythic beam effect
    if tostring(rarity):upper() == "MYTHIC" then
        local attachment1 = Instance.new("Attachment")
        attachment1.Position = Vector3.new(0, -0.75, 0)
        attachment1.Parent = part

        local attachment2 = Instance.new("Attachment")
        attachment2.Position = Vector3.new(0, 10, 0)
        attachment2.Parent = part

        local beam = Instance.new("Beam")
        beam.Attachment0 = attachment1
        beam.Attachment1 = attachment2
        beam.Color = ColorSequence.new(rarityColor)
        beam.LightEmission = 1
        beam.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.5),
            NumberSequenceKeypoint.new(0.5, 0),
            NumberSequenceKeypoint.new(1, 0.5)
        })
        beam.Width0 = 2
        beam.Width1 = 4
        beam.Parent = part
    end

    -- Tag for identification
    CollectionService:AddTag(model, "ItemDrop")

    -- Primary part
    model.PrimaryPart = part

    -- Attribute for count to allow UI updates later
    model:SetAttribute("Count", count or 1)
    model:SetAttribute("ItemId", itemDef.id)

    return model
end

return DropModelFactory
