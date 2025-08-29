--!strict
-- MaterialsTab.lua
-- Modular materials configuration tab component

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Theme = require(MiningGame:WaitForChild("UI"):WaitForChild("Theme"))
local Dropdown = require(script.Parent:WaitForChild("Dropdown"))
local MaterialManager = require(MiningGame:WaitForChild("MaterialManager"))
local MaterialPalettes = require(MiningGame:WaitForChild("MaterialPalettes"))
local MaterialKeys = require(MiningGame:WaitForChild("MaterialKeys"))
local MaterialDefinitions = require(MiningGame:WaitForChild("MaterialDefinitions"))
local Remotes = require(MiningGame:WaitForChild("Remotes"))

local MaterialsTab = {}
MaterialsTab.__index = MaterialsTab

export type MaterialsTabConfig = {
    parent: Instance,
    position: UDim2?,
    size: UDim2?,
    portalParent: Instance?, -- NEW: for dropdown portals
}

function MaterialsTab.new(config: MaterialsTabConfig)
    local self = setmetatable({}, MaterialsTab)
    
    local colors = Theme.colors
    
    -- Store config
    self.widgets = {}
    self.portalParent = config.portalParent
    
    -- Main container
    local container = Instance.new("Frame")
    container.Size = config.size or UDim2.new(1, 0, 0, 0)
    container.Position = config.position or UDim2.new(0, 0, 0, 0)
    container.AutomaticSize = Enum.AutomaticSize.Y
    container.BackgroundTransparency = 1
    container.Parent = config.parent
    self.container = container
    
    -- Helper function for creating labels
    local function makeFieldLabel(parent, y, text)
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 0, 30)
        lbl.Position = UDim2.new(0, 0, 0, y)
        lbl.BackgroundTransparency = 1
        lbl.Text = text
        lbl.TextColor3 = colors.Text
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Font = Theme.fonts.Primary
        lbl.TextSize = 18
        lbl.Parent = parent
        return lbl
    end
    
    -- Build palette options
    local paletteKeys = MaterialPalettes.GetPaletteNames()
    table.sort(paletteKeys)
    local paletteOptions = {}
    for _, key in ipairs(paletteKeys) do
        local def = MaterialPalettes.Palettes[key]
        table.insert(paletteOptions, { 
            id = key, 
            label = (def and def.name) or key,
            color = def and def.glowColor -- Optional: use glow color as preview
        })
    end
    
    -- Helper function to get color from MaterialDefinitions
    local function colorForKey(key: string): Color3?
        local def = MaterialDefinitions.Materials[key]
        return def and def.properties and def.properties.color or nil
    end
    
    -- Build material options from keys with colors
    local function optsFromKeys(keys)
        local out = {}
        for _, key in ipairs(keys) do
            local label = (MaterialKeys.DisplayNames and MaterialKeys.DisplayNames[key]) or key
            table.insert(out, { 
                id = key, 
                label = label,
                color = colorForKey(key) -- Get color from MaterialDefinitions
            })
        end
        table.sort(out, function(a,b) return a.label < b.label end)
        return out
    end
    
    local cubeOptions = optsFromKeys(MaterialKeys.CubeMaterials)
    local floorOptions = optsFromKeys(MaterialKeys.FloorMaterials)
    
    local y = 10
    
    -- Section: Palette Theme
    self.paletteLabel = makeFieldLabel(container, y, "Palette Theme")
    self.paletteDropdown = Dropdown.new({
        parent = container,
        position = UDim2.new(0, 10, 0, y + 35),
        size = UDim2.new(1, -20, 0, 36),
        placeholder = "Select palette...",
        options = paletteOptions,
        portalParent = self.portalParent, -- NEW
        onSelect = function(opt)
            self:onPaletteSelect(opt)
        end
    })
    table.insert(self.widgets, self.paletteDropdown)
    y = y + 35 + 36 + 12
    
    -- Section: Cube Material
    self.cubeLabel = makeFieldLabel(container, y, "Cube Material")
    self.cubeDropdown = Dropdown.new({
        parent = container,
        position = UDim2.new(0, 10, 0, y + 35),
        size = UDim2.new(1, -20, 0, 36),
        placeholder = "Select cube material...",
        options = cubeOptions,
        portalParent = self.portalParent, -- NEW
        onSelect = function(opt)
            self:onCubeMaterialSelect(opt)
        end
    })
    table.insert(self.widgets, self.cubeDropdown)
    y = y + 35 + 36 + 12
    
    -- Section: Floor Material
    self.floorLabel = makeFieldLabel(container, y, "Floor Material")
    self.floorDropdown = Dropdown.new({
        parent = container,
        position = UDim2.new(0, 10, 0, y + 35),
        size = UDim2.new(1, -20, 0, 36),
        placeholder = "Select floor material...",
        options = floorOptions,
        portalParent = self.portalParent, -- NEW
        onSelect = function(opt)
            self:onFloorMaterialSelect(opt)
        end
    })
    table.insert(self.widgets, self.floorDropdown)
    y = y + 35 + 36 + 20
    
    -- Info text
    local infoLabel = Instance.new("TextLabel")
    infoLabel.Size = UDim2.new(1, -20, 0, 60)
    infoLabel.Position = UDim2.new(0, 10, 0, y)
    infoLabel.BackgroundTransparency = 1
    infoLabel.Text = "Material changes affect your mining cube's appearance.\nPalette themes change lighting and visual atmosphere."
    infoLabel.TextColor3 = colors.TextDim
    infoLabel.TextXAlignment = Enum.TextXAlignment.Left
    infoLabel.TextYAlignment = Enum.TextYAlignment.Top
    infoLabel.Font = Theme.fonts.Secondary
    infoLabel.TextSize = 14
    infoLabel.TextWrapped = true
    infoLabel.Parent = container
    
    -- Optional: Preview frame for future visual feedback
    self.previewFrame = nil -- Can add visual preview later
    
    -- Hydration flag to prevent triggering saves during initial load
    self._hydrating = false
    
    -- Load saved preferences from server AFTER player data is ready
    local Players = game:GetService("Players")
    local player = Players.LocalPlayer
    
    task.spawn(function()
        if not player:GetAttribute("DataLoaded") then
            player:GetAttributeChangedSignal("DataLoaded"):Wait()
        end
        local ok, prefs = pcall(function()
            return Remotes.RF.GetMaterialPreferences:InvokeServer()
        end)
        if ok and prefs then
            print("[MaterialsTab] Loading saved preferences:", prefs)
            self._hydrating = true
            if prefs.palette then self:setPalette(string.lower(prefs.palette)) end
            if prefs.cubeMaterial then self:setCubeMaterial(prefs.cubeMaterial) end
            if prefs.floorMaterial then self:setFloorMaterial(prefs.floorMaterial) end
            self._hydrating = false
        else
            print("[MaterialsTab] No saved preferences found or failed to load")
        end
    end)
    
    return self
end

function MaterialsTab:onPaletteSelect(option)
    -- Skip if we're hydrating from saved preferences
    if self._hydrating then return end
    
    local ok, err = pcall(function()
        MaterialManager.SetPalette(option.id)
    end)
    
    if ok then
        print(("[MaterialsTab] Palette set to: %s"):format(option.label))
        
        -- Save the palette preference to server
        pcall(function()
            Remotes.RF.SetPalettePreference:InvokeServer(option.id)
        end)
        
        -- Optional: Update any visual preview
        if self.previewFrame then
            -- Update preview colors based on palette
        end
    else
        warn("[MaterialsTab] Failed to set palette:", err)
    end
end

function MaterialsTab:onCubeMaterialSelect(option)
    -- Skip if we're hydrating from saved preferences
    if self._hydrating then return end
    
    -- Update visual system if available
    pcall(function()
        if MaterialManager.SetCubeMaterial then
            MaterialManager.SetCubeMaterial(option.id)
        end
    end)
    
    -- Call server to repaint terrain (which also saves the preference)
    local ok, res = pcall(function()
        return Remotes.RF.ApplyCubeSurfaceMaterial:InvokeServer(option.id)
    end)
    
    if ok and res then
        print(("[MaterialsTab] Cube terrain changed to: %s"):format(option.label))
    else
        warn("[MaterialsTab] Failed to change cube terrain to:", option.id)
    end
end

function MaterialsTab:onFloorMaterialSelect(option)
    -- Skip if we're hydrating from saved preferences
    if self._hydrating then return end
    
    -- Call server to repaint terrain (which also saves the preference)
    local ok, res = pcall(function()
        return Remotes.RF.ApplyFloorMaterial:InvokeServer(option.id)
    end)
    
    if ok and res then
        print(("[MaterialsTab] Floor terrain changed to: %s"):format(option.label))
    else
        warn("[MaterialsTab] Failed to change floor terrain to:", option.id)
    end
end

-- Set current values programmatically
function MaterialsTab:setPalette(paletteId: string)
    for i, opt in ipairs(self.paletteDropdown.options) do
        if opt.id == paletteId then
            self.paletteDropdown:select(i)
            break
        end
    end
end

function MaterialsTab:setCubeMaterial(materialId: string)
    for i, opt in ipairs(self.cubeDropdown.options) do
        if opt.id == materialId then
            self.cubeDropdown:select(i)
            break
        end
    end
end

function MaterialsTab:setFloorMaterial(materialId: string)
    for i, opt in ipairs(self.floorDropdown.options) do
        if opt.id == materialId then
            self.floorDropdown:select(i)
            break
        end
    end
end

-- Get current selections
function MaterialsTab:getCurrentSettings()
    return {
        palette = self.paletteDropdown:getValue(),
        cubeMaterial = self.cubeDropdown:getValue(),
        floorMaterial = self.floorDropdown:getValue(),
    }
end

-- Enable/disable the tab
function MaterialsTab:setEnabled(enabled: boolean)
    -- Could add visual feedback for disabled state
    self.container.Visible = enabled
end

-- Cleanup
function MaterialsTab:destroy()
    for _, widget in ipairs(self.widgets) do
        if widget and widget.destroy then
            widget:destroy()
        end
    end
    self.widgets = {}
    
    if self.container then
        self.container:Destroy()
    end
end

return MaterialsTab