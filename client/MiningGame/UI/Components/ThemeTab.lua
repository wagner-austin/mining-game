--!strict
-- ThemeTab.lua
-- Modular theme configuration tab component for UI and Sound themes

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Theme = require(MiningGame:WaitForChild("UI"):WaitForChild("Theme"))
local Dropdown = require(script.Parent:WaitForChild("Dropdown"))
local ThemeManager = require(MiningGame:WaitForChild("UI"):WaitForChild("ThemeManager"))
local ThemePacks = require(MiningGame:WaitForChild("UI"):WaitForChild("ThemePacks"))
local SoundTheme = require(MiningGame:WaitForChild("SoundThemeManager"))
local Remotes = require(MiningGame:WaitForChild("Remotes"))

local ThemeTab = {}
ThemeTab.__index = ThemeTab

export type ThemeTabConfig = {
    parent: Instance,
    position: UDim2?,
    size: UDim2?,
    portalParent: Instance?, -- For dropdown portals
}

function ThemeTab.new(config: ThemeTabConfig)
    local self = setmetatable({}, ThemeTab)
    
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
        lbl.TextSize = 20  -- Bigger for better readability
        lbl.Parent = parent
        return lbl
    end
    
    -- Build UI theme options
    local uiThemeOptions = {}
    for name, pack in pairs(ThemePacks) do
        if name ~= "default" then -- Skip default since it's not a theme pack
            table.insert(uiThemeOptions, {
                id = name,
                label = pack.name or name,
            })
        end
    end
    -- Add default option at beginning
    table.insert(uiThemeOptions, 1, {
        id = "default",
        label = "Default",
    })
    -- Sort by label (keeping default first)
    local function sortThemes(a, b)
        if a.id == "default" then return true end
        if b.id == "default" then return false end
        return a.label < b.label
    end
    table.sort(uiThemeOptions, sortThemes)
    
    -- Build sound pack options
    local soundPackOptions = {
        { id = "default", label = "Default" }
    }
    
    -- Look for available sound packs
    local SoundPacks = MiningGame:FindFirstChild("SoundPacks")
    if SoundPacks then
        for _, child in ipairs(SoundPacks:GetChildren()) do
            if child:IsA("ModuleScript") then
                -- Try to require it to get the name
                local ok, pack = pcall(require, child)
                if ok and typeof(pack) == "table" then
                    table.insert(soundPackOptions, {
                        id = child.Name,
                        label = pack.name or child.Name,
                    })
                end
            end
        end
    end
    -- Sort sound packs (keeping default first)
    table.sort(soundPackOptions, sortThemes)
    
    local y = 10
    
    -- Section: UI Theme
    self.uiLabel = makeFieldLabel(container, y, "UI Theme")
    self.uiDropdown = Dropdown.new({
        parent = container,
        position = UDim2.new(0, 10, 0, y + 35),
        size = UDim2.new(1, -20, 0, 36),
        placeholder = "Select UI theme...",
        options = uiThemeOptions,
        portalParent = self.portalParent,
        onSelect = function(opt)
            self:onUIThemeSelect(opt)
        end
    })
    table.insert(self.widgets, self.uiDropdown)
    y = y + 35 + 36 + 12
    
    -- Section: Sound Pack
    self.soundLabel = makeFieldLabel(container, y, "Sound Pack")
    self.soundDropdown = Dropdown.new({
        parent = container,
        position = UDim2.new(0, 10, 0, y + 35),
        size = UDim2.new(1, -20, 0, 36),
        placeholder = "Select sound pack...",
        options = soundPackOptions,
        portalParent = self.portalParent,
        onSelect = function(opt)
            self:onSoundPackSelect(opt)
        end
    })
    table.insert(self.widgets, self.soundDropdown)
    y = y + 35 + 36 + 12  -- Reduced padding since we're removing info text
    
    -- Info text removed for better readability
    
    -- Hydration flag to prevent triggering saves during initial load
    self._hydrating = false
    
    -- Load saved preferences from server AFTER player data is ready
    local player = Players.LocalPlayer
    
    task.spawn(function()
        if not player:GetAttribute("DataLoaded") then
            player:GetAttributeChangedSignal("DataLoaded"):Wait()
        end
        
        -- Get current theme settings
        local ok, settings = pcall(function()
            return Remotes.RF.GetThemeSettings:InvokeServer()
        end)
        
        if ok and settings then
            print("[ThemeTab] Loading saved theme settings:", settings)
            self._hydrating = true
            
            -- Set UI theme dropdown
            if settings.uiTheme then
                self:setUITheme(settings.uiTheme)
            end
            
            -- Set sound pack dropdown
            if settings.soundPack then
                self:setSoundPack(settings.soundPack)
            end
            
            self._hydrating = false
        else
            print("[ThemeTab] No saved theme settings found or failed to load")
            -- Set defaults
            self._hydrating = true
            self:setUITheme("default")
            self:setSoundPack("default")
            self._hydrating = false
        end
    end)
    
    return self
end

function ThemeTab:onUIThemeSelect(option)
    -- Skip if we're hydrating from saved preferences
    if self._hydrating then return end
    
    -- Apply the theme locally
    local ok, err = pcall(function()
        ThemeManager.Apply(option.id)
    end)
    
    if ok then
        print(("[ThemeTab] UI theme set to: %s"):format(option.label))
        
        -- Save the preference to server
        pcall(function()
            Remotes.RF.UpdateThemeSettings:InvokeServer({
                uiTheme = option.id
            })
        end)
        
        -- Play UI sound for theme change
        local SoundManager = require(MiningGame:WaitForChild("SoundManager"))
        SoundManager.PlayUI("buttonclick")
    else
        warn("[ThemeTab] Failed to set UI theme:", err)
    end
end

function ThemeTab:onSoundPackSelect(option)
    -- Skip if we're hydrating from saved preferences
    if self._hydrating then return end
    
    -- Load the sound pack if it's not default
    local pack = nil
    if option.id ~= "default" then
        local SoundPacks = MiningGame:FindFirstChild("SoundPacks")
        if SoundPacks then
            local packModule = SoundPacks:FindFirstChild(option.id)
            if packModule and packModule:IsA("ModuleScript") then
                local ok, loadedPack = pcall(require, packModule)
                if ok and typeof(loadedPack) == "table" then
                    pack = loadedPack
                else
                    warn("[ThemeTab] Failed to load sound pack:", option.id)
                    return
                end
            end
        end
    end
    
    -- Apply the sound pack locally
    local ok, err = pcall(function()
        SoundTheme.Apply(option.id, pack)
    end)
    
    if ok then
        print(("[ThemeTab] Sound pack set to: %s"):format(option.label))
        
        -- Save the preference to server
        pcall(function()
            Remotes.RF.UpdateThemeSettings:InvokeServer({
                soundPack = option.id
            })
        end)
        
        -- Play UI sound with new pack
        local SoundManager = require(MiningGame:WaitForChild("SoundManager"))
        SoundManager.PlayUI("buttonclick")
    else
        warn("[ThemeTab] Failed to set sound pack:", err)
    end
end

-- Set current values programmatically
function ThemeTab:setUITheme(themeId: string)
    for i, opt in ipairs(self.uiDropdown.options) do
        if opt.id == themeId then
            self.uiDropdown:select(i)
            break
        end
    end
end

function ThemeTab:setSoundPack(packId: string)
    for i, opt in ipairs(self.soundDropdown.options) do
        if opt.id == packId then
            self.soundDropdown:select(i)
            break
        end
    end
end

-- Get current selections
function ThemeTab:getCurrentSettings()
    return {
        uiTheme = self.uiDropdown:getValue(),
        soundPack = self.soundDropdown:getValue(),
    }
end

-- Enable/disable the tab
function ThemeTab:setEnabled(enabled: boolean)
    self.container.Visible = enabled
end

-- Cleanup
function ThemeTab:destroy()
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

return ThemeTab
