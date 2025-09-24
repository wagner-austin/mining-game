--!strict
-- ThemeTab.lua
-- Modular theme configuration tab component for UI and Sound themes
-- Migrated to use BaseTabComponent for consistent UI patterns

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UIFolder = MiningGame:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))
local UIx = require(UIFolder:WaitForChild("UIConstants"))
local ThemeManager = require(UIFolder:WaitForChild("ThemeManager"))
local ThemePacks = require(UIFolder:WaitForChild("ThemePacks"))
local SoundTheme = require(MiningGame:WaitForChild("SoundThemeManager"))
local SoundManager = require(MiningGame:WaitForChild("SoundManager"))
local ClientRF = require(MiningGame:WaitForChild("ClientRF"))
local Logger = require(MiningGame:WaitForChild("Logger"))
local log = Logger.new("ThemeTab")

-- Type definitions
type ThemeSettings = {uiTheme: string?, soundTheme: string?, musicVolume: number?}
type UpdateResponse = {success: boolean}
type TypedCaller<T> = (...any) -> (T?, string?)

-- Typed RF calls for theme settings
local Calls = {
    GetThemeSettings = ClientRF.typed("GetThemeSettings") :: TypedCaller<ThemeSettings>,
    UpdateThemeSettings = ClientRF.typed("UpdateThemeSettings") :: TypedCaller<UpdateResponse>,
}

local BaseTabComponent = require(script.Parent:WaitForChild("BaseTabComponent"))

local ThemeTab = {}
ThemeTab.__index = ThemeTab
setmetatable(ThemeTab, { __index = BaseTabComponent })

export type ThemeTabConfig = {
    parent: Instance,
    position: UDim2?,
    size: UDim2?,
    portalParent: Instance?, -- For dropdown portals
}

type ThemeTabT = typeof(setmetatable({} :: any, ThemeTab)) & {
    _dragging: boolean,
    uiDropdown: any?,
    soundDropdown: any?,
    musicVolumeFill: Frame?,
    musicVolumeHandle: Frame?,
    musicVolumeValueLabel: TextLabel?,
    new: (config: ThemeTabConfig) -> ThemeTabT,
    getCurrentSettings: (self: ThemeTabT) -> any,
}

function ThemeTab.new(config: ThemeTabConfig): ThemeTabT
    -- Initialize base component with stacked=false for manual layout (like MaterialsTab)
    local self = setmetatable(BaseTabComponent.new({
        parent = config.parent,
        position = config.position,
        size = config.size,
        portalParent = config.portalParent,
        stacked = false, -- Keep manual Y-based positioning for now
        name = "ThemeTab",
    }), ThemeTab)
    
    -- Tab-specific state
    self._dragging = false
    
    -- Build UI sections
    self:_buildThemeOptions()
    
    -- Load saved preferences after data is ready
    self:waitForDataLoaded(function()
        self:hydrate(
            function()
                local data, err = Calls.GetThemeSettings()
                if err then
                    warn("[ThemeTab] Failed to get theme settings:", err)
                    return nil
                end
                return data
            end,
            function(settings)
                if settings then
                    log:info("Loaded saved theme settings")
                    
                    -- Set UI theme dropdown
                    if settings.uiTheme then
                        self:selectOptionById(self.uiDropdown, settings.uiTheme)
                    end
                    
                    -- Set sound pack dropdown
                    if settings.soundPack then
                        self:selectOptionById(self.soundDropdown, settings.soundPack)
                    end
                    
                    -- Set music volume slider
                    local mv = tonumber(settings.musicVolume)
                    if mv ~= nil then
                        self:_setVolumeSlider(math.clamp(mv, 0, 1))
                    end
                else
                    log:info("No saved theme settings found")
                    -- Set defaults
                    self:setHydrating(true)
                    self:selectOptionById(self.uiDropdown, "Default")
                    self:selectOptionById(self.soundDropdown, "default")
                    self:setHydrating(false)
                end
            end
        )
    end)
    
    return self :: any
end

function ThemeTab:_buildThemeOptions()
    -- Build UI theme options with colors
    local uiThemeOptions = {}
    for name, pack in pairs(ThemePacks) do
        if name ~= "Default" then
            local themeColor = pack.colors and pack.colors.Primary or Color3.fromRGB(100, 100, 100)
            table.insert(uiThemeOptions, {
                id = name,
                label = name,
                color = themeColor,
            })
        end
    end
    -- Add default option at beginning
    table.insert(uiThemeOptions, 1, {
        id = "Default",
        label = "Default",
        color = Color3.fromRGB(150, 150, 255),
    })
    -- Sort by label (keeping default first)
    table.sort(uiThemeOptions, function(a, b)
        if a.id == "Default" then return true end
        if b.id == "Default" then return false end
        return a.label < b.label
    end)
    
    -- Build sound pack options with colors
    local soundPackOptions = {
        { 
            id = "default", 
            label = "Default",
            color = Color3.fromRGB(100, 200, 150)
        }
    }
    
    -- Look for available sound packs
    local SoundPacks = MiningGame:FindFirstChild("SoundPacks")
    if SoundPacks then
        for _, child in ipairs(SoundPacks:GetChildren()) do
            if child:IsA("ModuleScript") then
                local ok, pack = pcall(require, child)
                if ok and typeof(pack) == "table" then
                    local packColor
                    if pack.themeColor then
                        packColor = pack.themeColor
                    else
                        -- Generate a unique color from the pack name
                        local hash = 0
                        for i = 1, #child.Name do
                            hash = ((hash * 31) + string.byte(child.Name, i)) % 1000000
                        end
                        local hue = (hash % 360) / 360
                        packColor = Color3.fromHSV(hue, 0.7, 0.8)
                    end
                    
                    table.insert(soundPackOptions, {
                        id = child.Name,
                        label = pack.name or child.Name,
                        color = packColor,
                    })
                end
            end
        end
    end
    -- Sort sound packs (keeping default first)
    table.sort(soundPackOptions, function(a, b)
        if a.id == "default" then return true end
        if b.id == "default" then return false end
        return a.label < b.label
    end)
    
    local y = UIx.Spacing.SECTION
    
    -- UI Theme Section
    self:createLabel(self.container, "UI Theme", {
        position = UDim2.new(0, UIx.Spacing.SECTION, 0, y),
        size = UDim2.new(1, -(UIx.Spacing.SECTION * 2), 0, UIx.Size.ROW_HEADER),
        alignment = Enum.TextXAlignment.Left,
        textSize = UIx.Visual.TEXT_HEADER
    })
    
    self.uiDropdown = self:createDropdown({
        parent = self.container,
        position = UDim2.new(0, UIx.Spacing.SECTION, 0, y + UIx.Size.ROW_HEADER + UIx.Spacing.XS),
        size = UDim2.new(1, -(UIx.Spacing.SECTION * 2), 0, UIx.Size.INPUT_HEIGHT),
        placeholder = "Select UI theme...",
        options = uiThemeOptions,
        portalParent = self.portalParent,
        onSelect = function(opt)
            self:_onUIThemeSelect(opt)
        end
    })
    y = y + UIx.Size.ROW_HEADER + UIx.Size.INPUT_HEIGHT + UIx.Spacing.MD
    
    -- Sound Pack Section
    self:createLabel(self.container, "Sound Pack", {
        position = UDim2.new(0, UIx.Spacing.SECTION, 0, y),
        size = UDim2.new(1, -(UIx.Spacing.SECTION * 2), 0, UIx.Size.ROW_HEADER),
        alignment = Enum.TextXAlignment.Left,
        textSize = UIx.Visual.TEXT_HEADER
    })
    
    self.soundDropdown = self:createDropdown({
        parent = self.container,
        position = UDim2.new(0, UIx.Spacing.SECTION, 0, y + UIx.Size.ROW_HEADER + UIx.Spacing.XS),
        size = UDim2.new(1, -(UIx.Spacing.SECTION * 2), 0, UIx.Size.INPUT_HEIGHT),
        placeholder = "Select sound pack...",
        options = soundPackOptions,
        portalParent = self.portalParent,
        onSelect = function(opt)
            self:_onSoundPackSelect(opt)
        end
    })
    y = y + UIx.Size.ROW_HEADER + UIx.Size.INPUT_HEIGHT + UIx.Spacing.MD
    
    -- Music Volume Section
    self:createLabel(self.container, "Music Volume", {
        position = UDim2.new(0, UIx.Spacing.SECTION, 0, y),
        size = UDim2.new(1, -(UIx.Spacing.SECTION * 2), 0, UIx.Size.ROW_HEADER),
        alignment = Enum.TextXAlignment.Left,
        textSize = UIx.Visual.TEXT_HEADER
    })
    
    -- Create volume slider
    self:_createVolumeSlider(y + UIx.Size.ROW_HEADER + UIx.Spacing.XS)
end

function ThemeTab:_createVolumeSlider(yPos: number)
    -- Slider container
    local sliderContainer = Instance.new("Frame")
    sliderContainer.Size = UDim2.new(1, -(UIx.Spacing.SECTION * 2), 0, UIx.Size.INPUT_HEIGHT)
    sliderContainer.Position = UDim2.new(0, UIx.Spacing.SECTION, 0, yPos)
    sliderContainer.BackgroundColor3 = self._theme.colors.Surface
    sliderContainer.BackgroundTransparency = Theme.card.backgroundTransparency
    sliderContainer.BorderSizePixel = 0
    sliderContainer.Parent = self.container
    
    self:bindToTheme(sliderContainer, { BackgroundColor3 = "Surface" })
    
    local sliderCorner = Instance.new("UICorner")
    sliderCorner.CornerRadius = UIx.corner()
    sliderCorner.Parent = sliderContainer
    
    -- Re-apply non-bound props on theme change
    self:_addThemeUpdater(function()
        sliderContainer.BackgroundTransparency = Theme.card.backgroundTransparency
        sliderCorner.CornerRadius = UIx.corner()
    end)
    
    -- Slider track
    local track = Instance.new("Frame")
    track.Size = UDim2.new(1, -(UIx.Size.AVATAR_PX), 0, UIx.Size.SLIDER_TRACK_HEIGHT)
    track.Position = UDim2.new(0, UIx.Spacing.LG - 1, 0.5, -(UIx.Size.SLIDER_TRACK_HEIGHT / 2))
    track.BackgroundColor3 = self._theme.colors.TextSecondary
    track.BorderSizePixel = 0
    track.Parent = sliderContainer
    
    self:bindToTheme(track, { BackgroundColor3 = "TextSecondary" })
    
    -- Slider fill
    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(0.2, 0, 1, 0) -- Default 20% volume
    fill.BackgroundColor3 = self._theme.colors.Primary
    fill.BorderSizePixel = 0
    fill.Parent = track
    
    self:bindToTheme(fill, { BackgroundColor3 = "Primary" })
    
    -- Slider handle (positioned relative to the track for accurate alignment)
    local handle = Instance.new("TextButton")
    handle.Name = "Handle"
    handle.Size = UIx.square(UIx.Size.SLIDER_HANDLE)
    handle.AnchorPoint = Vector2.new(0.5, 0.5)
    handle.Position = UDim2.new(0.2, 0, 0.5, 0) -- Centered on track
    handle.BackgroundColor3 = self._theme.colors.Primary
    handle.BorderSizePixel = 0
    handle.Text = ""
    handle.AutoButtonColor = false
    handle.ZIndex = (track.ZIndex or 1) + 1
    handle.Parent = track
    
    self:bindToTheme(handle, { BackgroundColor3 = "Primary" })
    
    local handleCorner = Instance.new("UICorner")
    handleCorner.CornerRadius = UDim.new(0.5, 0)
    handleCorner.Parent = handle
    
    -- Volume percentage label
    local volumeValueLabel = self:createLabel(sliderContainer, "20%", {
        position = UDim2.new(1, -(UIx.Size.ROW_SECTION + UIx.Spacing.XS), 0, 0),
        size = UDim2.new(0, UIx.Size.ROW_SECTION, 1, 0),
        textSize = UIx.Visual.TEXT_BODY + 2
    })
    
    -- Store references
    self.musicVolumeFill = fill
    self.musicVolumeHandle = handle
    self.musicVolumeValueLabel = volumeValueLabel
    
    -- Get current MUSIC group volume
    local currentVolume = SoundManager.GetGroupVolume("Music")
    self:_setVolumeSlider(currentVolume)
    
    -- Create debounced save for volume
    local saveVolume = self:createDebouncedSave(function(vol)
        Calls.UpdateThemeSettings({ musicVolume = vol })
    end, 0.2)
    
    -- Slider interaction handlers
    local function updateVolume(x)
        local trackAbsPos = track.AbsolutePosition.X
        local trackAbsSize = track.AbsoluteSize.X
        local relativeX = math.clamp((x - trackAbsPos) / trackAbsSize, 0, 1)
        
        self:_setVolumeSlider(relativeX)
        
        -- Apply volume change
        SoundManager.SetGroupVolume("Music", relativeX)
        
        if not self:isHydrating() then
            print(string.format("[ThemeTab] Music volume set to: %d%%", math.floor(relativeX * 100)))
            saveVolume(relativeX)
        end
        
        -- Play feedback sound at extremes
        if not self._dragging or relativeX == 0 or relativeX == 1 then
            SoundManager.PlayUI("buttonclick")
        end
    end
    
    -- Handle dragging
    self:addConnection(handle.MouseButton1Down:Connect(function()
        self._dragging = true
    end))
    
    self:addConnection(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or 
           input.UserInputType == Enum.UserInputType.Touch then
            self._dragging = false
        end
    end))
    
    self:addConnection(UserInputService.InputChanged:Connect(function(input)
        if self._dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or
                               input.UserInputType == Enum.UserInputType.Touch) then
            updateVolume(input.Position.X)
        end
    end))
    
    -- Click on track to jump to position
    self:addConnection(track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or
           input.UserInputType == Enum.UserInputType.Touch then
            updateVolume(input.Position.X)
        end
    end))
end

function ThemeTab:_setVolumeSlider(value: number)
    value = math.clamp(value, 0, 1)
    
    if self.musicVolumeFill then
        self.musicVolumeFill.Size = UDim2.new(value, 0, 1, 0)
    end
    if self.musicVolumeHandle then
        self.musicVolumeHandle.Position = UDim2.new(value, 0, 0.5, 0)
    end
    if self.musicVolumeValueLabel then
        self.musicVolumeValueLabel.Text = string.format("%d%%", math.floor(value * 100))
    end
    -- Log at DEBUG to avoid spam while dragging
    log:debug("Music volume set to: %d%%", math.floor(value * 100))
    
    -- Also apply to sound system
    SoundManager.SetGroupVolume("Music", value)
end

function ThemeTab:_onUIThemeSelect(option)
    -- Skip if we're hydrating from saved preferences
    if self:isHydrating() then return end
    
    -- Apply the theme locally
    local ok, err = pcall(function()
        ThemeManager.Apply(option.id)
    end)
    
    if ok then
        log:info("UI theme set to: %s", tostring(option.label))
        
        -- Save the preference to server
        pcall(function()
            Calls.UpdateThemeSettings({
                uiTheme = option.id
            })
        end)
        
        -- Play UI sound for theme change
        SoundManager.PlayUI("buttonclick")
    else
        warn("[ThemeTab] Failed to set UI theme:", err)
    end
end

function ThemeTab:_onSoundPackSelect(option)
    -- Skip if we're hydrating from saved preferences
    if self:isHydrating() then return end
    
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
        log:info("Sound pack set to: %s", tostring(option.label))
        
        -- Save the preference to server
        pcall(function()
            Calls.UpdateThemeSettings({
                soundPack = option.id
            })
        end)
        
        -- Play UI sound with new pack
        SoundManager.PlayUI("buttonclick")
    else
        warn("[ThemeTab] Failed to set sound pack:", err)
    end
end

-- Get current selections
function ThemeTab:getCurrentSettings()
    return {
        uiTheme = self.uiDropdown and self.uiDropdown:getValue(),
        soundPack = self.soundDropdown and self.soundDropdown:getValue(),
    }
end

-- Override destroy for tab-specific cleanup
function ThemeTab:destroy()
    -- Clear tab-specific state
    self._dragging = false
    self.musicVolumeFill = nil
    self.musicVolumeHandle = nil
    self.musicVolumeValueLabel = nil
    self.uiDropdown = nil
    self.soundDropdown = nil
    
    -- Call base destroy (handles connections, widgets, container)
    BaseTabComponent.destroy(self)
end

return ThemeTab
