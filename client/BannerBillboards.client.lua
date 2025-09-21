--!strict
-- BannerBillboards.client.lua
-- Mounts billboard UI on banner models tagged via CollectionService

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(MiningGame:WaitForChild("Logger"))
local Theme = require(MiningGame:WaitForChild("UI"):WaitForChild("Theme"))
local EventBus = require(MiningGame:WaitForChild("EventBus"))
local EventNames = require(MiningGame:WaitForChild("EventNames"))

local log = Logger.new("BannerBillboards")
local ClientError = require(script.Parent:WaitForChild("ClientErrorHandler"))

-- Client-side UI components live under StarterPlayerScripts (client tree), not ReplicatedStorage
local ClientRoot = script.Parent:WaitForChild("MiningGame")
local UIComponents = ClientRoot:WaitForChild("UI"):WaitForChild("Components")
local HighScoreBillboard = require(UIComponents:WaitForChild("HighScoreBillboard"))

type Mount = { destroy: (() -> ())?, ancestryConn: RBXScriptConnection? }
local mounted: {[Model]: Mount} = {}
local pending: {[Model]: (() -> ())} = {}

local function getBannerColor(m: Instance): Color3?
    local ok, v = pcall(function() return (m :: any):GetAttribute("BannerColor") end)
    if ok and typeof(v) == "Color3" then return v :: Color3 end
    return nil
end

local function getBannerCategory(m: Instance): string
    local ok, v = pcall(function() return (m :: any):GetAttribute("BannerCategory") end)
    if ok and type(v) == "string" then return v :: string end
    return ""
end

local function getBannerFeature(m: Instance): string
    local ok, v = pcall(function() return (m :: any):GetAttribute("BannerFeature") end)
    if ok and type(v) == "string" then return v :: string end
    return "" -- default: no feature -> no billboard
end

local function getBannerFace(m: Instance): Enum.NormalId
    local ok, v = pcall(function() return (m :: any):GetAttribute("BannerFace") end)
    if ok and type(v) == "string" then
        local s = string.lower(v)
        if s == "front" then return Enum.NormalId.Front end
        if s == "back" then return Enum.NormalId.Back end
        if s == "left" then return Enum.NormalId.Left end
        if s == "right" then return Enum.NormalId.Right end
        if s == "top" then return Enum.NormalId.Top end
        if s == "bottom" then return Enum.NormalId.Bottom end
    end
    return Enum.NormalId.Front
end

-- No face auto-mapping: respect BannerFace from server config exactly.

local function findAdornee(model: Model): BasePart?
    -- Prefer explicitly oriented UI panel if present (created server-side)
    local uiPanel = model:FindFirstChild("UIPanel")
    if uiPanel and uiPanel:IsA("BasePart") then return uiPanel end
    -- Otherwise use PrimaryPart (mesh)
    if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then return model.PrimaryPart end
    return nil
end
local function mountBanner(model: Model, overrides: any?)
    if mounted[model] then return end
    local adornee = findAdornee(model)
    if not adornee then
        -- Defer until PrimaryPart/BasePart exists using signals (event-driven)
        if pending[model] then return end
        local conns = {}
        local function cleanup()
            for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
            pending[model] = nil
        end
        local function tryNow()
            if mounted[model] then cleanup(); return end
            local p = findAdornee(model)
            if p then
                cleanup()
                task.defer(function() mountBanner(model) end)
            end
        end
        conns[#conns+1] = model:GetPropertyChangedSignal("PrimaryPart"):Connect(tryNow)
        conns[#conns+1] = model.DescendantAdded:Connect(function(inst)
            if inst:IsA("BasePart") then tryNow() end
        end)
        conns[#conns+1] = model.AncestryChanged:Connect(function(_, parent)
            if not parent then cleanup() end
        end)
        pending[model] = cleanup
        -- Immediate re-check closes race window where adornee appears just before listeners are wired
        tryNow()
        log:debug("Deferring billboard mount until adornee exists: %s", model:GetFullName())
        return
    end

    local feature = (overrides and overrides.feature) or getBannerFeature(model)
    local accent = (overrides and overrides.color) or getBannerColor(model) or Theme.colors.Primary
    local category = (overrides and overrides.category) or getBannerCategory(model)
    -- Use face: if using UIPanel, mount on Front (vertical aligned by server).
    local face = Enum.NormalId.Front
    if adornee.Name ~= "UIPanel" then
        face = (overrides and overrides.face and typeof(overrides.face) == "EnumItem" and overrides.face)
            or (type(overrides and overrides.face) == "string" and (
                (string.lower(overrides.face) == "front" and Enum.NormalId.Front)
                or (string.lower(overrides.face) == "back" and Enum.NormalId.Back)
                or (string.lower(overrides.face) == "left" and Enum.NormalId.Left)
                or (string.lower(overrides.face) == "right" and Enum.NormalId.Right)
                or (string.lower(overrides.face) == "top" and Enum.NormalId.Top)
                or (string.lower(overrides.face) == "bottom" and Enum.NormalId.Bottom)
            ))
            or getBannerFace(model)
    end

    if feature == "HighScore" then
        local ok, hs = ClientError.try("BannerBillboards.HighScoreMount", function()
            return HighScoreBillboard.new({
                adornee = adornee,
                category = category,
                accentColor = accent,
                face = face,
            })
        end)
        if ok and hs then
            -- Handle streaming: if model streams out, destroy and clear; on reparent, remount
            local function destroy()
                ClientError.try("BannerBillboards.Destroy", function() hs:destroy() end)
            end
            local conn
            conn = model.AncestryChanged:Connect(function(_, parent)
                if not parent then
                    -- Streamed out: tear down and mark unmounted
                    destroy()
                    if mounted[model] then mounted[model] = nil end
                else
                    -- Streamed back in: attempt to remount if not mounted
                    if not mounted[model] then task.defer(function() mountBanner(model) end) end
                end
            end)
            mounted[model] = { destroy = destroy, ancestryConn = conn }
            log:info("Mounted HighScore billboard on %s (face=%s, category=%s)", adornee:GetFullName(), tostring(face), tostring(category))
        else
            log:error("Failed to create HighScore billboard: %s", tostring(hs))
        end
    else
        -- Unknown feature; mount a simple placeholder later
        log:debug("Unknown banner feature '%s' on %s", tostring(feature), model:GetFullName())
    end
end

local function unmountBanner(model: Model)
    local pend = pending[model]
    if pend then pcall(pend) end
    local m = mounted[model]
    if m then
        if m.ancestryConn then pcall(function() m.ancestryConn:Disconnect() end) end
        if m.destroy then pcall(m.destroy) end
    end
    mounted[model] = nil
end

local Bus = EventBus.global()

-- Listen for banner ready events (reliable, after full setup)
Bus:on(EventNames.BANNER_READY, function(evt)
    -- Server bridges only the payload; route is already per-player
    local banners = evt and evt.banners
    if type(banners) ~= "table" then return end
    for _, b in ipairs(banners) do
        if typeof(b) == "Instance" then
            if b:IsA("Model") then mountBanner(b) end
        elseif type(b) == "table" then
            local m = b.model
            if typeof(m) == "Instance" and m:IsA("Model") then
                mountBanner(m, b)
            end
        end
    end
end)

-- Keep CollectionService as fallback for existing banners and cleanup
CollectionService:GetInstanceRemovedSignal("Banner"):Connect(function(inst)
    if inst:IsA("Model") then unmountBanner(inst) end
end)
