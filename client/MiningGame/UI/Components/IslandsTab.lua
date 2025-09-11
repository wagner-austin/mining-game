--!strict
-- IslandsTab.lua
-- Simple floating cube island spawner for debug menu
-- Uses actual CubeThemes from the game
-- Migrated to use BaseTabComponent for consistent UI patterns

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(MiningGame:WaitForChild("Logger"))
local CubeThemes = require(MiningGame:WaitForChild("CubeThemes"))
local UIFolder = MiningGame:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))
local UIx = require(UIFolder:WaitForChild("UIConstants"))
local ClientRF = require(MiningGame:WaitForChild("ClientRF"))

local BaseTabComponent = require(script.Parent:WaitForChild("BaseTabComponent"))

local log = Logger.new("IslandsTab")

local IslandsTab = {}
IslandsTab.__index = IslandsTab
setmetatable(IslandsTab, { __index = BaseTabComponent })

type Props = {
    parent: GuiObject,
    position: UDim2?,
    size: UDim2?,
}

type IslandsTabT = typeof(setmetatable({} :: any, IslandsTab)) & {
    selectedPreset: string,
    selectedTheme: string,
    presetButtons: {[string]: TextButton},
    themeButtons: {[string]: TextButton},
    statusLabel: TextLabel?,
    new: (props: Props) -> IslandsTabT,
    selectPreset: (self: IslandsTabT, preset: string) -> (),
    selectTheme: (self: IslandsTabT, themeName: string) -> (),
    updateStatus: (self: IslandsTabT, message: string, isError: boolean?) -> (),
    spawnIsland: (self: IslandsTabT) -> (),
    clearIslands: (self: IslandsTabT) -> (),
}

function IslandsTab.new(props: Props): IslandsTabT
    -- Initialize base component with stacked=true for vertical sections
    local self = setmetatable(BaseTabComponent.new({
        parent = props.parent,
        position = props.position,
        size = props.size,
        stacked = true,
        name = "IslandsTab",
    }), IslandsTab)
    
    -- Tab-specific state
    self.selectedPreset = "medium"
    self.selectedTheme = "underwater_cave"
    self.presetButtons = {}
    self.themeButtons = {}
    
    -- Build UI
    self:setupUI()
    
    return self :: any
end

function IslandsTab:setupUI()
    -- Helper to create inline button row
    local function createButtonRow(): Frame
        local row = Instance.new("Frame")
        row.Name = "ButtonRow"
        row.Size = UIx.px(nil, UIx.Size.BUTTON_SMALL_HEIGHT)
        row.BackgroundTransparency = 1
        row.Parent = self.container
        
        local rowLayout = Instance.new("UIListLayout")
        rowLayout.FillDirection = Enum.FillDirection.Horizontal
        rowLayout.Padding = UIx.pad(UIx.Spacing.SM)
        rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
        rowLayout.Parent = row
        
        return row
    end
    
    -- Helper to create toggle button
    local function createToggleButton(text: string, value: string, isSelected: boolean, onClick: () -> ()): TextButton
        local button = Instance.new("TextButton")
        button.Name = value
        button.Size = UDim2.new(0.24, -UIx.Spacing.SM + 2, 0, UIx.Size.BUTTON_SMALL_HEIGHT)
        button.BackgroundColor3 = isSelected and self._theme.colors.Primary or self._theme.colors.Surface
        button.BackgroundTransparency = Theme.button.surfaceTransparency
        button.BorderSizePixel = 0
        button.Text = text
        button.TextColor3 = self._theme.colors.Text
        button.TextScaled = false
        button.TextSize = UIx.Visual.TEXT_SMALL
        button.Font = self._theme.fonts.Primary
        button.AutoButtonColor = false
        
        self:bindToTheme(button, { 
            BackgroundColor3 = isSelected and "Primary" or "Surface",
            TextColor3 = "Text"
        })
        
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, self._theme.sizes.CornerRadius)
        corner.Parent = button
        
        -- Re-apply non-bound props on theme change
        self:_addThemeUpdater(function()
            button.BackgroundTransparency = Theme.button.surfaceTransparency
            corner.CornerRadius = UDim.new(0, Theme.sizes.CornerRadius)
        end)
        
        self:addConnection(button.Activated:Connect(onClick))
        
        return button
    end
    
    -- Size Selection
    self:createLabel(self.container, "Island Size", {
        size = UIx.px(nil, UIx.Size.ROW_SMALL),
        alignment = Enum.TextXAlignment.Left,
        textSize = UIx.Visual.TEXT_BODY
    })
    
    local presetRow = createButtonRow()
    
    local presets = {
        {id = "tiny", label = "TINY"},
        {id = "small", label = "SMALL"},
        {id = "medium", label = "MEDIUM"},
        {id = "large", label = "LARGE"},
        {id = "massive", label = "MASSIVE"}
    }
    
    for i, preset in ipairs(presets) do
        local btn = createToggleButton(preset.label, preset.id, preset.id == self.selectedPreset, function()
            self:selectPreset(preset.id)
        end)
        btn.LayoutOrder = i
        btn.Parent = presetRow
        self.presetButtons[preset.id] = btn
    end
    
    -- Theme Selection (pulled directly from CubeThemes)
    self:createLabel(self.container, "Cube Theme", {
        size = UIx.px(nil, UIx.Size.ROW_SMALL),
        alignment = Enum.TextXAlignment.Left,
        textSize = UIx.Visual.TEXT_BODY
    })
    
    local themeRow1 = createButtonRow()
    local themeRow2 = createButtonRow()
    
    -- Get themes directly from CubeThemes
    local themes = {}
    for themeId, themeData in pairs(CubeThemes.Themes) do
        table.insert(themes, {
            id = themeId,
            name = themeData.name
        })
    end
    
    -- Sort themes alphabetically
    table.sort(themes, function(a, b) return a.name < b.name end)
    
    for i, themeDef in ipairs(themes) do
        local btn = createToggleButton(themeDef.name, themeDef.id, themeDef.id == self.selectedTheme, function()
            self:selectTheme(themeDef.id)
        end)
        btn.LayoutOrder = i
        btn.Parent = i <= 4 and themeRow1 or themeRow2
        self.themeButtons[themeDef.id] = btn
    end
    
    -- Spacer
    local spacer1 = Instance.new("Frame")
    spacer1.Name = "Spacer"
    spacer1.Size = UIx.px(nil, UIx.Spacing.SM)
    spacer1.BackgroundTransparency = 1
    spacer1.Parent = self.container
    
    -- Simple spawn button
    self:createButton(
        self.container,
        "🏝️ Spawn Floating Island",
        function()
            self:spawnIsland()
        end,
        {
            variant = "success",
            size = UIx.px(nil, UIx.Size.BUTTON_SMALL_HEIGHT)
        }
    )
    
    -- Clear button
    self:createButton(
        self.container,
        "🗑️ Clear All Islands",
        function()
            self:clearIslands()
        end,
        {
            variant = "danger",
            size = UIx.px(nil, UIx.Size.BUTTON_SMALL_HEIGHT)
        }
    )
    
    -- Spacer
    local spacer2 = Instance.new("Frame")
    spacer2.Name = "Spacer"
    spacer2.Size = UIx.px(nil, UIx.Spacing.SM)
    spacer2.BackgroundTransparency = 1
    spacer2.Parent = self.container
    
    -- Status text
    self.statusLabel = self:createLabel(self.container, "Ready", {
        size = UIx.px(nil, UIx.Size.ROW_STANDARD),
        alignment = Enum.TextXAlignment.Center,
        textSize = UIx.Visual.TEXT_SMALL,
        textColor = "TextDim"
    })
end

function IslandsTab:selectPreset(preset: string)
    self.selectedPreset = preset
    for name, btn in pairs(self.presetButtons) do
        local isSelected = name == preset
        btn.BackgroundColor3 = isSelected and self._theme.colors.Primary or self._theme.colors.Surface
        self:bindToTheme(btn, { 
            BackgroundColor3 = isSelected and "Primary" or "Surface"
        })
    end
    self:updateStatus(("Size: %s"):format(preset))
end

function IslandsTab:selectTheme(themeName: string)
    self.selectedTheme = themeName
    for name, btn in pairs(self.themeButtons) do
        local isSelected = name == themeName
        btn.BackgroundColor3 = isSelected and self._theme.colors.Primary or self._theme.colors.Surface
        self:bindToTheme(btn, {
            BackgroundColor3 = isSelected and "Primary" or "Surface"
        })
    end
    
    -- Show full theme name from CubeThemes
    local themeData = CubeThemes.GetTheme(themeName)
    if themeData then
        self:updateStatus(("Theme: %s"):format(themeData.name))
    else
        self:updateStatus(("Theme: %s"):format(themeName))
    end
end

function IslandsTab:updateStatus(message: string, isError: boolean?)
    if self.statusLabel then
        self.statusLabel.Text = message
        self.statusLabel.TextColor3 = isError and self._theme.colors.Error or self._theme.colors.Success
        self:bindToTheme(self.statusLabel, {
            TextColor3 = isError and "Error" or "Success"
        })
        
        -- Fade back to dim after 2 seconds
        task.wait(UIx.Anim.VERY_SLOW * 2)  -- Status display duration
        if self.statusLabel and self.statusLabel.Text == message then
            self.statusLabel.TextColor3 = self._theme.colors.TextDim
            self:bindToTheme(self.statusLabel, { TextColor3 = "TextDim" })
        end
    end
end

-- Helper to call remote function with error handling
local function callRF(self, payload)
    task.spawn(function()
        local data, err = ClientRF.call("Debug_SpawnIsland", payload)
        if err then
            self:updateStatus("✗ " .. err, true)
            return
        end
        if data and data.success then
            self:updateStatus("✓ " .. (data.message or "Spawned!"))
        else
            self:updateStatus("✗ " .. (data and data.error or "Failed"), true)
        end
    end)
end

function IslandsTab:spawnIsland()
    local player = Players.LocalPlayer
    if not player.Character then
        self:updateStatus("No character", true)
        return
    end
    
    self:updateStatus(("Spawning %s island..."):format(self.selectedPreset))
    callRF(self, {
        action = "single",
        preset = self.selectedPreset,
        theme = self.selectedTheme,
    })
end

function IslandsTab:clearIslands()
    self:updateStatus("Clearing all islands...")
    callRF(self, {
        action = "clear",
    })
end

-- Override destroy for tab-specific cleanup
function IslandsTab:destroy()
    -- Clear tab-specific state
    self.selectedPreset = nil
    self.selectedTheme = nil
    self.presetButtons = nil
    self.themeButtons = nil
    self.statusLabel = nil
    
    -- Call base destroy (handles connections, container, periodic updates)
    BaseTabComponent.destroy(self)
end

-- Legacy compatibility
function IslandsTab:Destroy()
    self:destroy()
end

return IslandsTab
