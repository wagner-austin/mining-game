--!strict
-- ThemeRefresher.lua
-- Centralized theme binding system for automatic UI updates

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UI = MiningGame:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))

local ThemeRefresher = {}

-- Weak registry to avoid memory leaks
local bindings = setmetatable({}, { __mode = "k" })
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
            if not value then return nil end
        end
    end
    
    -- Get the final key value
    if key and value then
        return value[key]
    end
    
    return nil
end

-- Apply theme to a single instance based on its bindings
local function applyTheme(instance: Instance, spec: {[string]: string})
    for propertyName, themeKey in pairs(spec) do
        -- Handle special cases
        if propertyName == "Stroke" and instance:IsA("UIStroke") then
            -- For UIStroke, use the glassEdge settings
            if themeKey == "glassEdge" then
                instance.Color = Theme.glassEdge.color
                instance.Transparency = Theme.glassEdge.transparency
                instance.Thickness = Theme.glassEdge.thickness
            else
                -- Regular color
                local color = getThemeValue("colors", themeKey)
                if color then
                    instance.Color = color
                end
            end
        else
            -- Regular property binding
            local pathAndKey = themeKey:match("(.+)%.(.+)")
            local color
            
            if pathAndKey then
                -- Full path like "colors.Primary"
                local path, key = themeKey:match("(.+)%.(.+)")
                color = getThemeValue(path, key)
            else
                -- Simple key like "Primary"
                color = getThemeValue("colors", themeKey)
            end
            
            if color then
                -- Set only if the property exists; avoid crashing refresh
                pcall(function()
                    (instance :: any)[propertyName] = color
                end)
            end
        end
    end
end

-- Bind an instance with a specification
function ThemeRefresher.Bind(instance: Instance, spec: {[string]: string})
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
            bindings[instance] = nil
        end
    end
end

return ThemeRefresher