--!strict
-- ThemeRefresher.lua
-- Centralized theme binding system for automatic UI updates

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UI = MiningGame:WaitForChild("UI")
-- Strict Theme typing for this module
type ThemeTR = {
	colors: { [string]: Color3 },
	glassEdge: {
		color: Color3,
		transparency: number,
		thickness: number,
		applyStrokeMode: Enum.ApplyStrokeMode?,
		lineJoinMode: Enum.LineJoinMode?,
	},
}
local Theme: ThemeTR = require(UI:WaitForChild("Theme"))
local _ = require(ReplicatedStorage:WaitForChild("MiningGame"):WaitForChild("ClientError"))

local ThemeRefresher = {}

-- Weak registry to avoid memory leaks
local bindings: { [Instance]: { [string]: string } } = {}
setmetatable(bindings, { __mode = "k" })
local attributePrefix = "Theme_"

-- Map attribute names to property names and theme paths
local attributeMap = {
	Background = { property = "BackgroundColor3", path = "colors" },
	Text = { property = "TextColor3", path = "colors" },
	Image = { property = "ImageColor3", path = "colors" },
	Stroke = { property = "Color", path = "colors" },
	ScrollBar = { property = "ScrollBarImageColor3", path = "colors" },
}

-- Get a value from Theme using a path like "colors.Primary"
local function getThemeValue(path: string, key: string)
	local value = Theme

	-- Navigate to the path (e.g., "colors")
	if path then
		for segment in path:gmatch("[^.]+") do
			value = value[segment]
			if not value then
				return nil
			end
		end
	end

	-- Get the final key value
	if key and value then
		return value[key]
	end

	return nil
end

-- Apply theme to a single instance based on its bindings
local function applyTheme(instance: Instance, spec: { [string]: string })
	for propertyName, themeKey in pairs(spec) do
		-- Handle special cases
		if propertyName == "Stroke" and instance:IsA("UIStroke") then
			-- For UIStroke, use the glassEdge settings
			if themeKey == "glassEdge" then
				local ge: any = Theme.glassEdge or {}
				if ge.color then
					instance.Color = ge.color
				end
				if ge.transparency ~= nil then
					instance.Transparency = ge.transparency
				end
				if ge.thickness ~= nil then
					instance.Thickness = ge.thickness
				end
			else
				-- Regular color
				local color = getThemeValue("colors", themeKey)
				if color then
					instance.Color = color
				end
			end
		else
			-- Regular property binding
			local color
			local path, key = themeKey:match("(.+)%.(.+)")
			if path and key then
				-- Full path like "colors.Primary"
				color = getThemeValue(path, key)
			else
				-- Simple key like "Primary"
				color = getThemeValue("colors", themeKey)
			end

			if color then
				-- Set only if the property exists; avoid crashing refresh
				if propertyName == "BackgroundColor3" then
					if instance:IsA("GuiObject") then
						instance.BackgroundColor3 = color
					end
				elseif propertyName == "TextColor3" then
					if instance:IsA("TextLabel") then
						(instance :: TextLabel).TextColor3 = color
					elseif instance:IsA("TextButton") then
						(instance :: TextButton).TextColor3 = color
					elseif instance:IsA("TextBox") then
						(instance :: TextBox).TextColor3 = color
					end
				elseif propertyName == "ImageColor3" then
					if instance:IsA("ImageLabel") then
						(instance :: ImageLabel).ImageColor3 = color
					elseif instance:IsA("ImageButton") then
						(instance :: ImageButton).ImageColor3 = color
					end
				elseif propertyName == "ScrollBarImageColor3" then
					if instance:IsA("ScrollingFrame") then
						instance.ScrollBarImageColor3 = color
					end
				end
			end
		end
	end
end

-- Bind an instance with a specification
function ThemeRefresher.Bind(instance: Instance, spec: { [string]: string })
	bindings[instance] = spec
	applyTheme(instance, spec)

	-- Clean up when destroyed
	instance.AncestryChanged:Connect(function()
		if not instance.Parent then
			bindings[instance] = nil
		end
	end)
end

-- Scan an instance for theme attributes
local function scanInstance(instance: Instance)
	local spec = {}

	for attrName, mapping in pairs(attributeMap) do
		local fullAttrName = attributePrefix .. attrName
		local value = instance:GetAttribute(fullAttrName)

		if value and typeof(value) == "string" then
			spec[mapping.property] = value
		end
	end

	-- Only bind if we found attributes
	if next(spec) then
		ThemeRefresher.Bind(instance, spec)
	end
end

-- Bind all descendants with theme attributes
function ThemeRefresher.BindTree(root: Instance)
	-- Scan existing descendants
	for _, descendant in ipairs(root:GetDescendants()) do
		scanInstance(descendant)
	end

	-- Listen for new descendants
	root.DescendantAdded:Connect(scanInstance)
end

-- Refresh all bound instances
function ThemeRefresher.Refresh()
	for instance, spec in pairs(bindings) do
		if instance and instance.Parent then
			applyTheme(instance, spec)
		else
			-- Clean up destroyed instances
			if instance then
				bindings[instance] = nil
			end
		end
	end
end

return ThemeRefresher
