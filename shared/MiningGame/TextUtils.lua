--!strict
-- TextUtils.lua
-- Small helpers for consistent, human-friendly text formatting

local TextUtils = {}

-- Convert an identifier like "void_crystal" to "Void Crystal"
local function titleFromId(id: string): string
    local s = tostring(id or "")
    s = s:gsub("_", " ")
    s = s:gsub("%s+", " ")
    -- Title-case each word (simple heuristic)
    s = s:gsub("(%a)([%w']*)", function(f, r)
        return f:upper() .. r:lower()
    end)
    return s
end

-- Get a pretty display name using definition.name when present, otherwise derive from id
function TextUtils.prettifyItemName(id: string?, def: any?): string
    if def and type(def) == "table" then
        local name = def.name
        if type(name) == "string" and #name > 0 then
            return name
        end
        local did = def.id or id
        return titleFromId(tostring(did or "Item"))
    end
    return titleFromId(tostring(id or "Item"))
end

return TextUtils

