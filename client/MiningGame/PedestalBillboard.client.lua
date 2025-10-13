--!strict
-- PedestalBillboard.client.lua
-- Attaches a themed BillboardGui to each Respawn pedestal to label it clearly.

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Client UI components live under the local PlayerScripts tree
-- This script lives under PlayerScripts.MiningGame, so script.Parent is the client root
local ClientRoot = script.Parent
local UIComponents = ClientRoot:WaitForChild("UI"):WaitForChild("Components")
local BaseBillboard = require(UIComponents:WaitForChild("BaseBillboard"))
local RepMG = ReplicatedStorage:WaitForChild("MiningGame")
local Theme = require(RepMG:WaitForChild("UI"):WaitForChild("Theme"))
local ThemeRefresher = require(RepMG:WaitForChild("UI"):WaitForChild("ThemeRefresher"))
local EventBus = require(RepMG:WaitForChild("EventBus"))
local EventNames = require(RepMG:WaitForChild("EventNames"))
local Logger = require(RepMG:WaitForChild("Logger"))
local Bus = EventBus.global()
local log = Logger.new("PedestalBillboard")

local function attachBillboard(model: Model)
    log:info("attachBillboard called for: %s", model and model.Name or "nil")
    if not model or not model.Parent then
        log:warn("Model or parent is nil")
        return
    end
    local base = model:FindFirstChild("PedestalBase")
    if not base or not base:IsA("BasePart") then
        log:warn("PedestalBase not found or not a BasePart in model: %s", model.Name)
        return
    end
    -- Remove any legacy overhead billboard
    local pre = base:FindFirstChild("PedestalTopBillboard")
    if pre and pre:IsA("BillboardGui") then pcall(function() pre:Destroy() end) end

    -- Create a UIPanel like banners and mount a SurfaceGui via BaseBillboard
    local panel = model:FindFirstChild("UIPanel") :: BasePart?
    if not panel then
        panel = Instance.new("Part")
        panel.Name = "UIPanel"
        panel.Anchored = true
        panel.CanCollide = false
        panel.CanTouch = false
        panel.CanQuery = false
        panel.Transparency = 1
        -- Slightly wider panel to accommodate larger text
        panel.Size = Vector3.new(5.2, 2.2, 0.2)
        panel.Parent = model
    end

    -- Keep the panel positioned above the pedestal and facing camera yaw
    -- Lower the panel closer to the pedestal top
    local posOffsetY = base.Size.Y * 0.5 + 2.5
    local function updatePanel()
        local cam = Workspace.CurrentCamera
        if not cam then return end
        local pos = base.Position + Vector3.new(0, posOffsetY, 0)
        local camPos = cam.CFrame.Position
        local lookAt = Vector3.new(camPos.X, pos.Y, camPos.Z)
        -- Face front toward camera (match banner mounting)
        panel.CFrame = CFrame.lookAt(pos, lookAt)
    end
    updatePanel()
    local rsConn = RunService.RenderStepped:Connect(function()
        if not model.Parent or not base.Parent then
            if rsConn then rsConn:Disconnect() end
            return
        end
        updatePanel()
    end)
    panel.AncestryChanged:Connect(function(_, parent)
        if not parent and rsConn then pcall(function() rsConn:Disconnect() end) end
    end)

    -- Mount BaseBillboard without a header; add centered label instead
    if not panel:FindFirstChild("BaseBillboard") then
        local bb = BaseBillboard.new({
            adornee = panel,
            face = Enum.NormalId.Front,
            -- Wider canvas and a bit taller
            canvasSize = Vector2.new(520, 120),
            -- No title -> we will center our own label
            zIndex = 10,
            accentColor = Theme.colors.Accent,
        })
        -- Centered big label inside the content area
        local content = bb.root:FindFirstChild("Content")
        if content and content:IsA("Frame") then
            local center = Instance.new("TextLabel")
            center.Name = "CenterText"
            center.BackgroundTransparency = 1
            center.Size = UDim2.fromScale(1, 1)
            center.Position = UDim2.fromScale(0, 0)
            -- Use header/display font from theme for larger, wider glyphs
            center.Font = Theme.fonts.Display or Theme.fonts.Primary
            center.Text = "RESPAWN CUBE"
            center.TextColor3 = Theme.colors.Text
            center.TextXAlignment = Enum.TextXAlignment.Center
            center.TextYAlignment = Enum.TextYAlignment.Center
            center.TextScaled = true
            center.ZIndex = 12
            center.Parent = content

            local c = Instance.new("UITextSizeConstraint")
            -- Bump sizes to header scale
            c.MinTextSize = 48
            c.MaxTextSize = 96
            c.Parent = center

            -- Bind center label to theme for live color updates
            ThemeRefresher.Bind(center, { TextColor3 = "Text" })
        end

        -- Update accent color when theme changes (BaseBillboard root background already binds)
        Bus:on(EventNames.THEME_CHANGED, function()
            bb:setAccentColor(Theme.colors.Accent)
        end)
    end
end

local function attachInBase(baseModel: Model)
    log:info("Scanning base model for pedestals: %s", baseModel.Name)
    -- Attach for any existing pedestals under this player's base
    local foundCount = 0
    for _, ch in ipairs(baseModel:GetChildren()) do
        if ch:IsA("Model") and ch.Name:find("RespawnPedestal_") then
            log:info("Found pedestal in base: %s", ch.Name)
            foundCount = foundCount + 1
            attachBillboard(ch)
        end
    end
    log:info("Found %d pedestals in base: %s", foundCount, baseModel.Name)
    -- Watch for future pedestals added under this base
    baseModel.ChildAdded:Connect(function(ch)
        if ch:IsA("Model") and ch.Name:find("RespawnPedestal_") then
            log:info("New pedestal added to base: %s", ch.Name)
            attachBillboard(ch)
        end
    end)
end

local function scanExisting()
    log:info("Scanning for existing pedestals...")
    local bases = Workspace:FindFirstChild("PlayerBases")
    if not bases then
        log:warn("PlayerBases folder not found in workspace")
        return
    end
    log:info("Found PlayerBases, scanning children...")
    for _, m in ipairs(bases:GetChildren()) do
        if m:IsA("Model") and m.Name:match("^PlayerBase_%d+") then
            log:info("Found PlayerBase: %s", m.Name)
            attachInBase(m)
        elseif m:IsA("Model") and m.Name:find("RespawnPedestal_") then
            log:info("Found direct pedestal: %s", m.Name)
            -- Fallback if pedestals are ever direct children (unlikely)
            attachBillboard(m)
        end
    end
    log:info("Scan complete")
end

-- Scan for any pedestals that already exist (hot reload support)
scanExisting()

-- Listen for PEDESTAL_READY event when server spawns pedestal (at 5% mined threshold)
-- Note: Server bridges only the payload to the client, not the full event structure
Bus:on(EventNames.PEDESTAL_READY, function(evt)
    log:info("PEDESTAL_READY event received")
    local pedestal = evt and evt.pedestal
    if pedestal and pedestal:IsA("Model") then
        log:info("Attaching billboard to pedestal: %s", pedestal.Name)
        attachBillboard(pedestal)
    else
        log:warn("PEDESTAL_READY event missing pedestal model")
    end
end)

-- Listen for PEDESTAL_REMOVED event to clean up billboard
Bus:on(EventNames.PEDESTAL_REMOVED, function(evt)
    log:info("PEDESTAL_REMOVED event received")
    local pedestalName = evt and evt.pedestalName
    if pedestalName then
        log:info("Pedestal removed: %s (billboard will be cleaned up via ancestry change)", pedestalName)
        -- Billboard is parented to the pedestal's base part, so it will be destroyed automatically
        -- when the pedestal model is destroyed. No explicit cleanup needed.
    end
end)
