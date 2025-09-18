--!strict
-- IconAtlas.lua
-- Central place to resolve UI clip-art icons for items (by id/slot/type)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MG = ReplicatedStorage:WaitForChild("MiningGame")

local IconAtlas = {}

-- Simple validator for Roblox asset ids
local function isAssetId(str: string?): boolean
    if type(str) ~= "string" or str == "" then return false end
    if string.match(str, "^rbxassetid://%d+$") then return true end
    if string.match(str, "^https?://") then return true end
    if string.match(str, "^%d+$") then return true end
    return false
end

-- Default slot icons (set to real assets when available)
local DEFAULTS = {
    cosmetic = {
        aura = nil,         -- e.g., "rbxassetid://<AURA_ICON_ID>"
        back = nil,         -- e.g., "rbxassetid://<WINGS_ICON_ID>"
        trail = nil,        -- e.g., "rbxassetid://<TRAIL_ICON_ID>"
        head = nil,         -- e.g., "rbxassetid://<HELM_ICON_ID>"
        accessory = nil,
        pickaxe = nil,
        hand = nil,
    },
    resource = nil,
    pickaxe = nil,
    consumable = nil,
}

-- Resolve an icon for a generic item table (ItemDefinitions shape)
function IconAtlas.getForItem(item: any): string?
    if not item then return nil end
    local icon = (item :: any).icon or (item.meta and item.meta.icon)
    if isAssetId(icon) then
        if string.match(icon, "^%d+$") then
            return "rbxassetid://" .. icon
        end
        return icon
    end

    -- Slot/type based default
    local typ = tostring((item :: any).type or "")
    local slot = tostring((item :: any).slot or "")
    local def = DEFAULTS[typ]
    if type(def) == "table" then
        local slotIcon = def[slot]
        if isAssetId(slotIcon) then
            if string.match(slotIcon, "^%d+$") then return "rbxassetid://" .. slotIcon end
            return slotIcon
        end
    elseif type(def) == "string" and isAssetId(def) then
        if string.match(def, "^%d+$") then return "rbxassetid://" .. def end
        return def
    end
    return nil
end

return IconAtlas
