--!strict
-- TextUtils.lua
-- Small helpers for consistent, human-friendly text formatting

local TextUtils = {}

-- Convert an identifier like "void_crystal" to "Void Crystal"
local function titleFromId(id: string): string
	local s = tostring(id or "")
	s = s:gsub("_", " ")
	s = s:gsub("%s+", " ")
	-- Title-case each space-separated word without multi-capture gsub
	local out = {}
	for word in s:gmatch("%S+") do
		local first = string.sub(word, 1, 1)
		local rest = string.sub(word, 2)
		table.insert(out, string.upper(first) .. string.lower(rest))
	end
	return table.concat(out, " ")
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
