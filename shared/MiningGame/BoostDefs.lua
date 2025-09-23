--!strict
-- BoostDefs.lua
-- Single source of truth for boost/effect display metadata (icons, labels)

local BoostDefs = {}

-- Icons are sourced from Theme to avoid hardcoding and enable skinning
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Theme = require(MiningGame:WaitForChild("UI"):WaitForChild("Theme"))

-- Build icons robustly using utf8 to avoid source encoding issues
local function emoji(cp: number, fallback: string): string
    local ok, s = pcall(function() return utf8.char(cp) end)
    if ok and type(s) == "string" and #s > 0 then return s end
    return fallback
end

local ICONS = {
    speed = emoji(0x26A1, "*"),   -- ⚡
    jumps = emoji(0x1F680, "^"),   -- 🚀
    jumps2 = emoji(0x1F680, "^"),  -- 🚀
    luck  = emoji(0x1F340, "+"),  -- 🍀
}

-- Apply theme overrides if provided
do
    local t = (Theme.icons and Theme.icons.boost) or {}
    local function isSingleRune(s: any): boolean
        if type(s) ~= "string" then return false end
        local ok, len = pcall(function() return utf8.len(s) end)
        return ok and len == 1
    end
    if isSingleRune(t.speed) then ICONS.speed = t.speed end
    if isSingleRune(t.jumps) then ICONS.jumps = t.jumps end
    if isSingleRune(t.jumps2) then ICONS.jumps2 = t.jumps2 end
    if isSingleRune(t.luck) then ICONS.luck = t.luck end
    if isSingleRune(t.dig) then ICONS.dig = t.dig end
    if isSingleRune(t.size) then ICONS.size = t.size end
    if isSingleRune(t.wet) then ICONS.wet = t.wet end
end

-- Ensure defaults for additional effect icons (post-override)
ICONS.dig = ICONS.dig or emoji(0x26A1, "*")
-- Use pickaxe for expanded dig/size icon
ICONS.size = ICONS.size or emoji(0x26CF, "⛏")
ICONS.wet = ICONS.wet or emoji(0x1F4A7, "~")

-- Map effectId to display meta
type Meta = { icon: string, baseLabel: string, showTimer: boolean?, stackExtractor: ((string) -> (number?))? }
local MAP: {[string]: Meta} = {
    -- Potion speed tiers (stacking)
    potion_speed_tier_1 = { icon = ICONS.speed, baseLabel = "Speed", stackExtractor = function(_id) return 1 end },
    potion_speed_tier_2 = { icon = ICONS.speed, baseLabel = "Speed", stackExtractor = function(_id) return 2 end },
    potion_speed_tier_3 = { icon = ICONS.speed, baseLabel = "Speed", stackExtractor = function(_id) return 3 end },
    potion_speed_tier_4 = { icon = ICONS.speed, baseLabel = "Speed", stackExtractor = function(_id) return 4 end },

    -- Extra jumps (cosmetic)
    cosmetic_extra_jumps_1 = { icon = ICONS.jumps, baseLabel = "+1 Jump", showTimer = false },
    cosmetic_extra_jumps_2 = { icon = ICONS.jumps2, baseLabel = "+2 Jumps", showTimer = false },
    cosmetic_extra_jumps_3 = { icon = ICONS.jumps, baseLabel = "+3 Jumps", showTimer = false },
    cosmetic_extra_jumps_4 = { icon = ICONS.jumps, baseLabel = "+4 Jumps", showTimer = false },

    -- Luck (timed)
    luck = { icon = ICONS.luck, baseLabel = "Luck", showTimer = true },

    -- Dig size (persisted/profile-based or upgrades)
    size = { icon = ICONS.size, baseLabel = "Dig Size", showTimer = false },

    -- Debuff (environmental)
    wet = { icon = ICONS.wet, baseLabel = "Slowed", showTimer = true },
}

local function _normalizeBase(id: string): string
    local s = tostring(id)
    s = s:gsub("#%d+$", "")
    s = s:gsub("@([0-9%.]+)", "")
    return s
end

local function _parseMult(id: string): number?
    local s = tostring(id)
    local m = string.match(s, "@([0-9%.]+)")
    return m and tonumber(m) or nil
end

function BoostDefs.get(effectId: string)
    local base = _normalizeBase(effectId)
    -- Direct mapping known?
    if MAP[base] then return MAP[base] end
    -- Derived bases (no explicit entries): cosmetic/potion speed, cosmetic luck, dig speed
    if string.find(base, "^cosmetic_speed") or string.find(base, "^potion_speed") then
        return { icon = ICONS.speed, baseLabel = "Speed", showTimer = false }
    end
    if string.find(base, "^cosmetic_luck") then
        return { icon = ICONS.luck, baseLabel = "Luck", showTimer = false }
    end
    if string.find(base, "^dig_speed") then
        return { icon = ICONS.dig, baseLabel = "Dig Speed", showTimer = false }
    end
    return nil
end

-- Return a consistent, human-facing label for the given effect.
-- For speed effects, compute "+X%" from canonical Effects.movement.speedMult.
function BoostDefs.label(effectId: string): string
    local base = _normalizeBase(effectId)
    local meta = MAP[base]
    if not meta then
        -- Dynamic labels for @mult encoding
        local mult = _parseMult(effectId)
        if mult and (string.find(base, "^cosmetic_speed") or string.find(base, "^potion_speed")) then
            local pct = math.floor((mult - 1.0) * 100 + 0.5)
            return string.format("Speed +%d%%", pct)
        end
        if mult and string.find(base, "^cosmetic_luck") then
            local pct = math.floor((mult - 1.0) * 100 + 0.5)
            return string.format("Luck +%d%%", pct)
        end
        if mult and string.find(base, "^dig_speed") then
            local pct = math.floor((1.0 - mult) * 100 + 0.5)
            return string.format("Dig Speed +%d%%", pct)
        end
        return "Boost"
    end
    -- Fixed label for any speed-related effect (cosmetic or potion)
    if string.find(base, "^potion_speed_tier_") then
        return "Speed +10%"
    end
    -- Fixed label for any luck-related effect (timed or cosmetic)
    if string.find(base, "luck") then
        return "Luck +10%"
    end
    -- Dig size
    if base == "size" then
        return "Bigger Dig Area"
    end
    -- Debuff
    if base == "wet" then
        return "Slowed"
    end
    -- Fallback to provided baseLabel for non-speed effects
    return meta.baseLabel or "Boost"
end

function BoostDefs.icons()
    return ICONS
end

return BoostDefs
