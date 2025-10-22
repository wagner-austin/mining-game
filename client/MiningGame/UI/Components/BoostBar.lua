--!strict
-- BoostBar.lua
-- Bottom-right dynamic group of boost badges (chips) showing active effects

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Theme = require(MiningGame:WaitForChild("UI"):WaitForChild("Theme"))
local UIx = require(MiningGame:WaitForChild("UI"):WaitForChild("UIConstants"))
local UIUtils = require(MiningGame:WaitForChild("UI"):WaitForChild("UIUtils"))
local BaseChip = require(script.Parent:WaitForChild("BaseChip"))
local BoostDefs = require(MiningGame:WaitForChild("BoostDefs"))
local Time = require(MiningGame:WaitForChild("Time"))
local CharacterStateClient = require(MiningGame:WaitForChild("Character"):WaitForChild("CharacterStateClient"))

local localPlayer = Players.LocalPlayer

local BoostBar = {}
BoostBar.__index = BoostBar

type BoostBarT = typeof(setmetatable({} :: any, BoostBar)) & {
    mount: (parent: GuiObject) -> (),
    unmount: () -> (),
}

function BoostBar.new()
    local self = setmetatable({}, BoostBar)
    self._chips = {} :: {[string]: any}
    self._chipConnections = {} :: {[string]: {any}}
    self._conn = nil
    self._timerConn = nil
    self._lastPotionTier = 0
    return self
end

local function _formatTimeRemaining(expiry: number?): string
    if not expiry or type(expiry) ~= "number" then return "" end
    local remain = math.max(0, math.floor(expiry - Time.unix()))
    local m = math.floor(remain / 60)
    local s = remain % 60
    return string.format("%d:%02d", m, s)
end

function BoostBar:mount(parent: GuiObject)
    if self.frame and self.frame.Parent then return end
    local frame = Instance.new("Frame")
    frame.Name = "BoostBar"
    frame.BackgroundTransparency = 1
    frame.AnchorPoint = Vector2.new(1, 1)
    frame.Size = UDim2.new(0, 420, 0, 52)
    frame.Position = UDim2.new(1, -UIx.Spacing.XL, 1, -UIx.Spacing.XL)
    frame.Parent = parent
    self.frame = frame

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
    layout.Padding = UDim.new(0, UIx.Spacing.SM)
    layout.Parent = frame

    -- Update immediately and on changes
    local function refresh()
        local effects = CharacterStateClient.getEffects()
        local seen: {[string]: boolean} = {}
        -- Expand virtual entries for potion stacks and leave cosmetics as-is (may include #suffix)
        local entries: {string} = {}
        local tier = 0
        for id, _ in pairs(effects) do
            local sid = tostring(id)
            local n = string.match(sid, "^potion_speed_tier_(%d+)$")
            if n then
                local count = tonumber(n) or 1
                tier = math.max(tier, count)
                for i = 1, count do
                    table.insert(entries, sid .. "#" .. tostring(i))
                end
            else
                table.insert(entries, sid)
            end
        end
        -- Create/update chips for known effects (including virtual duplicates)
        for _, effectId in ipairs(entries) do
            local def = BoostDefs.get(effectId)
            if def then
                seen[effectId] = true
                local chip = self._chips[effectId]
                -- Emoji-only chips: no text, icon only (keep timer hidden)
                local text = ""

                -- Hover mini popup at mouse location with text from single source of truth
                local function showInfo()
                    local mgr = _G and _G.UIManager
                    if not mgr or not mgr.showMiniPopup then return end
                    -- Show immediately; do not throttle so quick re-enters work smoothly
                    local defB = BoostDefs.get(effectId)
                    local msg = (BoostDefs.label and BoostDefs.label(effectId)) or (defB and defB.baseLabel) or "Boost"
                    -- Position mini popup at the chip's top-left corner (screen space)
                    local gui = chip.container
                    local screenPos = gui.AbsolutePosition
                    -- Nudge popup a bit to the left for better alignment
                    local pos = UDim2.fromOffset(math.floor(screenPos.X - UIx.Spacing.MD), math.floor(screenPos.Y))
                    local tipIcon = (defB and defB.icon) or ""
                    mgr:showMiniPopup(msg, tipIcon, pos)
                end

                if not chip then
                    chip = BaseChip.new({
                        parent = frame,
                        icon = def.icon,
                        iconSize = UIx.Size.ROW_MEDIUM - UIx.Spacing.XS, -- slightly shorter icon
                        iconPaddingTop = 1, -- nudge to visually center tall glyphs (e.g., 🚀)
                        text = "",
                        align = "center",
                        pulseOnUpdate = false,
                        innerPadding = UIx.Spacing.NONE,
                        size = UDim2.new(0, UIx.Size.ROW_MEDIUM + UIx.Spacing.SM, 0, UIx.Size.ROW_MEDIUM),
                    })
                    self._chips[effectId] = chip
                else
                    chip:setIcon(def.icon)
                    chip:setText("")
                end
                -- Hover handlers: show mini popup at cursor with details
                local chipGui = chip.container
                if chipGui and not chipGui:GetAttribute("HoverInfoBound") then
                    chipGui:SetAttribute("HoverInfoBound", true)
                    chipGui.MouseEnter:Connect(function()
                        showInfo()
                    end)
                    chipGui.MouseLeave:Connect(function()
                        local mgr = _G and _G.UIManager
                        if mgr and mgr.hideMiniPopup then mgr:hideMiniPopup() end
                    end)
                end
            end
        end
        -- Remove chips for effects no longer active
        for id, chip in pairs(self._chips) do
            if not seen[id] then
                chip:destroy()
                self._chips[id] = nil
            end
        end

        -- If potion tier increased, show a mini popup with current effective speed
        -- No global popups on tier changes (avoid spam)
        self._lastPotionTier = tier
    end

    self._conn = CharacterStateClient.changed():Connect(refresh)
    refresh()

    -- No timer updates (emoji-only chips)
    self._timerConn = RunService.Heartbeat:Connect(function()
        -- Intentionally no-op to prevent text updates
    end)
end

function BoostBar:unmount()
    if self._conn then self._conn:Disconnect() self._conn = nil end
    if self._timerConn then self._timerConn:Disconnect() self._timerConn = nil end
    for _, chip in pairs(self._chips) do
        pcall(function() chip:destroy() end)
    end
    self._chips = {}
    if self.frame then self.frame:Destroy() self.frame = nil end
end

-- Export a singleton-like API for convenience
local singleton
return {
    mount = function(parent: GuiObject)
        singleton = singleton or BoostBar.new()
        singleton:mount(parent)
        return singleton
    end,
    unmount = function()
        if singleton then singleton:unmount() singleton = nil end
    end
}
