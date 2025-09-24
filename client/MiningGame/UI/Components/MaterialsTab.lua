--!strict
-- MaterialsTab.lua
-- Modular materials configuration tab component
-- Migrated to use BaseTabComponent for consistent UI patterns

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UIFolder = MiningGame:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))
local UIx = require(UIFolder:WaitForChild("UIConstants"))
local MaterialManager = require(MiningGame:WaitForChild("MaterialManager"))
local MaterialPalettes = require(MiningGame:WaitForChild("MaterialPalettes"))
local MaterialKeys = require(MiningGame:WaitForChild("MaterialKeys"))
local MaterialDefinitions = require(MiningGame:WaitForChild("MaterialDefinitions"))
local MaterialCompositions = require(MiningGame:WaitForChild("MaterialCompositions"))
local Logger = require(MiningGame:WaitForChild("Logger"))
local GameConfig = require(MiningGame:WaitForChild("GameConfig"))
local ClientRF = require(MiningGame:WaitForChild("ClientRF"))

local BaseTabComponent = require(script.Parent:WaitForChild("BaseTabComponent"))

local log = Logger.new("MaterialsTab")

local MaterialsTab = {}
MaterialsTab.__index = MaterialsTab
setmetatable(MaterialsTab, { __index = BaseTabComponent })

export type MaterialsTabConfig = {
    parent: Instance,
    position: UDim2?,
    size: UDim2?,
    portalParent: Instance?, -- For dropdown portals
}

type MaterialsTabT = typeof(setmetatable({} :: any, MaterialsTab)) & {
    paletteDropdown: any?,
    floorDropdown: any?,
    compositionDropdown: any?,
    compositionLabel: TextLabel?,
    regenerateButton: TextButton?,
    previewFrame: Frame?,
    _savedThemeId: string?,
    new: (config: MaterialsTabConfig) -> MaterialsTabT,
    getCurrentSettings: (self: MaterialsTabT) -> any,
}

function MaterialsTab.new(config: MaterialsTabConfig): MaterialsTabT
    -- Initialize base component with stacked=false to preserve Y-based positioning
    local self = setmetatable(BaseTabComponent.new({
        parent = config.parent,
        position = config.position,
        size = config.size,
        portalParent = config.portalParent,
        stacked = false, -- Keep manual Y-based layout for parity
        name = "MaterialsTab",
    }), MaterialsTab)
    
    -- Build UI sections
    self:_buildMaterialOptions()
    
    -- Load saved preferences after data is ready
    self:waitForDataLoaded(function()
        self:hydrate(
            function()
                local prefs, err = ClientRF.call("GetMaterialPreferences")
                if err then
                    log:warn("GetMaterialPreferences failed: %s", tostring(err))
                    return nil
                end
                return prefs  -- return data only
            end,
            function(prefs)
                if prefs then
                    log:debug("Loading saved preferences: %s", tostring(prefs))
                    self:setHydrating(true)
                    if prefs.palette then
                        self:selectOptionById(self.paletteDropdown, string.lower(prefs.palette))
                    end
                    if prefs.floorMaterial then
                        self:selectOptionById(self.floorDropdown, prefs.floorMaterial)
                    end
                    -- Store the saved theme ID to restore after compositions load
                    self._savedThemeId = prefs.activeThemeId
                    self:setHydrating(false)
                end
                -- Always hydrate compositions even if no prefs
                self:_hydrateCompositions()
            end
        )
    end)
    
    return self :: any
end

function MaterialsTab:_buildMaterialOptions()
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
    
    local floorOptions = optsFromKeys(MaterialKeys.FloorMaterials)
    
    local y = UIx.Spacing.SECTION
    
    -- Palette Theme Section
    self:createLabel(self.container, "Palette Theme", {
        position = UDim2.new(0, UIx.Spacing.SECTION, 0, y),
        size = UDim2.new(1, -(UIx.Spacing.SECTION * 2), 0, UIx.Size.ROW_HEADER),
        alignment = Enum.TextXAlignment.Left,
        textSize = UIx.Visual.TEXT_HEADER
    })
    
    self.paletteDropdown = self:createDropdown({
        parent = self.container,
        position = UDim2.new(0, UIx.Spacing.SECTION, 0, y + UIx.Size.ROW_HEADER + UIx.Spacing.XS),
        size = UDim2.new(1, -(UIx.Spacing.SECTION * 2), 0, UIx.Size.INPUT_HEIGHT),
        placeholder = "Select palette...",
        options = paletteOptions,
        portalParent = self.portalParent,
        onSelect = function(opt)
            self:_onPaletteSelect(opt)
        end
    })
    y = y + UIx.Size.ROW_HEADER + UIx.Size.INPUT_HEIGHT + UIx.Spacing.MD
    
    -- Floor Material Section
    self:createLabel(self.container, "Floor Material", {
        position = UDim2.new(0, UIx.Spacing.SECTION, 0, y),
        size = UDim2.new(1, -(UIx.Spacing.SECTION * 2), 0, UIx.Size.ROW_HEADER),
        alignment = Enum.TextXAlignment.Left,
        textSize = UIx.Visual.TEXT_HEADER
    })
    
    self.floorDropdown = self:createDropdown({
        parent = self.container,
        position = UDim2.new(0, UIx.Spacing.SECTION, 0, y + UIx.Size.ROW_HEADER + UIx.Spacing.XS),
        size = UDim2.new(1, -(UIx.Spacing.SECTION * 2), 0, UIx.Size.INPUT_HEIGHT),
        placeholder = "Select floor material...",
        options = floorOptions,
        portalParent = self.portalParent,
        onSelect = function(opt)
            self:_onFloorMaterialSelect(opt)
        end
    })
    y = y + UIx.Size.ROW_HEADER + UIx.Size.INPUT_HEIGHT + UIx.Spacing.MD
    
    -- Cube Theme Section (replaces old material/composition system)
    self.compositionLabel = self:createLabel(self.container, "Cube Theme", {
        position = UDim2.new(0, UIx.Spacing.SECTION, 0, y),
        size = UDim2.new(1, -(UIx.Spacing.SECTION * 2), 0, UIx.Size.ROW_HEADER),
        alignment = Enum.TextXAlignment.Left,
        textSize = UIx.Visual.TEXT_HEADER
    })
    
    self.compositionDropdown = self:createDropdown({
        parent = self.container,
        position = UDim2.new(0, UIx.Spacing.SECTION, 0, y + UIx.Size.ROW_HEADER + UIx.Spacing.XS),
        size = UDim2.new(1, -(UIx.Spacing.SECTION * 2), 0, UIx.Size.INPUT_HEIGHT),
        placeholder = "Select theme...",
        options = {}, -- Will be populated dynamically
        portalParent = self.portalParent,
        onSelect = function(opt)
            self:_onCompositionSelect(opt)
        end
    })
    y = y + UIx.Size.ROW_HEADER + UIx.Size.INPUT_HEIGHT + UIx.Spacing.MD
    
    -- Regenerate button
    self.regenerateButton = self:createButton(
        self.container,
        "🔄 Regenerate Pattern",
        function()
            self:_onRegenerateClick()
        end,
        {
            variant = "primary",
            position = UDim2.new(0, UIx.Spacing.SECTION, 0, y),
            size = UDim2.new(1, -(UIx.Spacing.SECTION * 2), 0, UIx.Size.INPUT_HEIGHT)
        }
    )
    
    -- Optional: Preview frame for future visual feedback
    self.previewFrame = nil -- Can add visual preview later
end

function MaterialsTab:_onPaletteSelect(option)
    -- Skip if we're hydrating from saved preferences
    if self:isHydrating() then return end
    
    local ok, err = pcall(function()
        MaterialManager.SetPalette(option.id)
    end)
    
    if ok then
        log:info("Palette set to: %s", option.label)
        
        -- Save the palette preference to server
        ClientRF.call("SetPalettePreference", option.id)
        
        -- Optional: Update any visual preview
        if self.previewFrame then
            -- Update preview colors based on palette
        end
    else
        log:warn("Failed to set palette: %s", tostring(err))
    end
end

function MaterialsTab:_onFloorMaterialSelect(option)
    -- Skip if we're hydrating from saved preferences
    if self:isHydrating() then return end
    
    -- Call server to repaint terrain (which also saves the preference)
    local res, err = ClientRF.call("ApplyFloorMaterial", option.id)
    
    if not err then
        log:info("Floor terrain changed to: %s", option.label)
    else
        log:warn("Failed to change floor terrain to: %s - %s", tostring(option.id), tostring(err))
    end
end

function MaterialsTab:_hydrateCompositions()
    log:debug("Hydrating compositions from server")
    local data, err = ClientRF.call("ListCompositions")
    if err then
        log:warn("ListCompositions failed: %s", tostring(err))
        return
    end
    if not data then
        log:warn("ListCompositions returned nil")
        return
    end
    
    -- Theme-based compositions only
    local list = data.compositions or {}
    log:debug("Received %d items, mode: %s, active: %s", 
        #list, tostring(data.mode), tostring(data.activeComposition))
    
    -- Helper to get theme-appropriate colors
    local themeColors = {
        classic_mine = Color3.fromRGB(120, 120, 120),      -- Gray for rock
        icy_cavern = Color3.fromRGB(150, 200, 255),        -- Ice blue
        volcanic_rift = Color3.fromRGB(255, 100, 50),      -- Lava orange-red
        desert_oasis = Color3.fromRGB(255, 220, 150),      -- Sandy beige
        swamp_bog = Color3.fromRGB(80, 140, 80),           -- Swampy green
        underwater_cave = Color3.fromRGB(50, 150, 200),    -- Ocean blue
        mixed_geology = Color3.fromRGB(180, 150, 120),     -- Mixed brown
        infernal_depths = Color3.fromRGB(255, 60, 30),     -- Intense red
    }
    
    -- Build options list
    local opts = {}
    for _, item in ipairs(list) do
        -- Handle both composition and material formats
        local id = item.id or item.materialKey
        local label = item.name
        -- Themes are always unlocked in the new system
        table.insert(opts, {
            id = id,
            label = label,
            unlocked = true, -- Always unlocked
            color = themeColors[id], -- Add theme-specific color
        })
    end

    -- Populate dropdown (support either setOptions or direct assignment)
    if self.compositionDropdown.setOptions then
        self.compositionDropdown:setOptions(opts)
    else
        self.compositionDropdown.options = opts
    end

    -- Select active composition - prefer saved theme over server's activeComposition
    local themeToSelect = self._savedThemeId or data.activeComposition
    if themeToSelect then
        self:setHydrating(true)
        self:selectOptionById(self.compositionDropdown, themeToSelect)
        self:setHydrating(false)
    end
end

function MaterialsTab:_onCompositionSelect(opt)
    if self:isHydrating() then return end
    if not opt then return end
    
    log:debug("Selected composition: %s", opt.id)

    -- Themes are always unlocked in the new system (no coin cost)
    -- Just apply directly
    log:debug("Applying composition %s", tostring(opt.id))
    local resA, errA = ClientRF.call("ApplyComposition", opt.id, true)
    if errA then
        log:warn("ApplyComposition failed: %s", tostring(errA))
    else
        log:info("Applied composition: %s", tostring(opt.id))
    end
end

function MaterialsTab:_onRegenerateClick()
    local res, err = ClientRF.call("RegenerateComposition")
    if not err then
        log:info("Successfully regenerated composition")
        if self.regenerateButton then
            self.regenerateButton.Text = "✓ Regenerated!"
            self:setTimeout(1, function()
                if self.regenerateButton then
                    self.regenerateButton.Text = "🔄 Regenerate Pattern"
                end
            end)
        end
    else
        log:warn("RegenerateComposition failed")
    end
end

-- Get current selections
function MaterialsTab:getCurrentSettings()
    return {
        palette = self.paletteDropdown and self.paletteDropdown:getValue(),
        floorMaterial = self.floorDropdown and self.floorDropdown:getValue(),
        theme = self.compositionDropdown and self.compositionDropdown:getValue(),
    }
end

-- Override destroy for tab-specific cleanup
function MaterialsTab:destroy()
    -- Clear tab-specific references
    self.paletteDropdown = nil
    self.floorDropdown = nil
    self.compositionDropdown = nil
    self.compositionLabel = nil
    self.regenerateButton = nil
    self.previewFrame = nil
    
    -- Call base destroy (handles widgets, connections, container)
    BaseTabComponent.destroy(self)
end

return MaterialsTab
