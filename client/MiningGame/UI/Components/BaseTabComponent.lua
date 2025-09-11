--!strict
-- BaseTabComponent.lua
-- Base class for all tab components providing common UI utilities and patterns

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local MathUtils = require(MiningGame:WaitForChild("MathUtils"))
local UIFolder = MiningGame:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))
local ThemeRefresher = require(UIFolder:WaitForChild("ThemeRefresher"))
local UIx = require(UIFolder:WaitForChild("UIConstants"))
local Dropdown = require(script.Parent:WaitForChild("Dropdown"))

local BaseTabComponent = {}
BaseTabComponent.__index = BaseTabComponent

-- Button variant type for cleaner API
export type ButtonVariant = "primary" | "danger" | "surface"

export type BaseTabConfig = {
    parent: Instance,
    position: UDim2?,
    size: UDim2?,
    portalParent: Instance?, -- For dropdown portals
    dataProvider: any?, -- Optional data provider
    stacked: boolean?, -- Optional: default true; false keeps manual layout
    name: string?, -- Optional container name
}

export type BaseTab = {
    container: Frame,
    portalParent: Instance?,
    _connections: {RBXScriptConnection},
    _widgets: {any},
    _hydrating: boolean,
    _theme: {
        colors: typeof(Theme.colors),
        fonts: typeof(Theme.fonts),
        sizes: typeof(Theme.sizes),
        titleSize: number,
        buttonSize: number,
        labelSize: number,
        smallSize: number,
    },
}

function BaseTabComponent.new(config: BaseTabConfig): BaseTab
    local self = setmetatable({}, BaseTabComponent)
    
    -- Common properties
    self._connections = {}
    self._widgets = {}
    self._labels = {} -- Track label references for updates
    self._hydrating = false
    self._dataProvider = config.dataProvider
    self.portalParent = config.portalParent
    self._themeBoundElements = {} -- Track elements bound to theme
    self._themeUpdaters = {} -- Array of functions to re-apply non-bound theme props
    self._timers = {} -- Track task.delay threads
    self._destroyed = false
    
    -- Theme cache with standard sizes
    self._theme = {
        colors = Theme.colors,
        fonts = Theme.fonts,
        sizes = Theme.sizes,
        -- Standard text sizes (consistent across all tabs)
        titleSize = UIx.Visual.TEXT_LARGE,
        buttonSize = UIx.Visual.TEXT_MEDIUM,
        labelSize = UIx.Visual.TEXT_STANDARD,
        smallSize = UIx.Visual.TEXT_SMALL,
    }
    
    -- Listen for theme changes to update our cache (guard against missing signal)
    local signal = rawget(ThemeRefresher, "onThemeChanged")
                or rawget(ThemeRefresher, "ThemeChanged")
                or rawget(ThemeRefresher, "Changed")
    
    if typeof(signal) == "RBXScriptSignal" then
        local conn = signal:Connect(function()
            self:_updateThemeCache()
            -- Re-apply non-bound theme props
            for _, fn in ipairs(self._themeUpdaters) do
                pcall(fn)
            end
        end)
        table.insert(self._connections, conn)
    end
    
    -- Initialize container
    self:_initContainer(config)
    
    return self
end

-- Container initialization with standard setup
function BaseTabComponent:_initContainer(config: BaseTabConfig)
    -- Main container (standard across all tabs)
    local container = Instance.new("Frame")
    container.Name = config.name or "TabContainer"
    container.Size = config.size or UDim2.new(1, 0, 0, 0)
    container.Position = config.position or UIx.Common.ORIGIN
    container.AutomaticSize = Enum.AutomaticSize.Y
    container.BackgroundTransparency = 1
    container.Parent = config.parent
    self.container = container
    
    -- Always add right padding to account for scrollbar (add BEFORE layout)
    local padding = Instance.new("UIPadding")
    padding.PaddingRight = UDim.new(0, 12)  -- Scrollbar width + some margin
    padding.Parent = container
    
    -- Only add stack layout if config.stacked ~= false
    if config.stacked ~= false then
        local layout = Instance.new("UIListLayout")
        layout.FillDirection = Enum.FillDirection.Vertical
        layout.Padding = UDim.new(0, UIx.Spacing.MD)
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Parent = container
    end
end

-- === UI Element Creation Methods ===

-- Create a section card with consistent styling
function BaseTabComponent:createSectionCard(parent: Instance, options: {
    name: string?,
    size: UDim2?,
    autoSize: boolean?,
    layoutOrder: number?,
}?): Frame
    local opts = options or {}
    local card = Instance.new("Frame")
    card.Name = opts.name or "Card"
    
    if opts.size then
        card.Size = opts.size
        card.AutomaticSize = Enum.AutomaticSize.None
    else
        card.Size = UDim2.new(1, 0, 0, 0)
        card.AutomaticSize = if opts.autoSize == false then Enum.AutomaticSize.None else Enum.AutomaticSize.Y
    end
    
    card.BackgroundColor3 = self._theme.colors.Surface
    card.BackgroundTransparency = Theme.card.backgroundTransparency
    card.LayoutOrder = opts.layoutOrder or 0
    
    -- Bind to theme refresher
    self:bindToTheme(card, { BackgroundColor3 = "Surface" })
    
    -- Re-apply non-bound props on theme change
    self:_addThemeUpdater(function()
        card.BackgroundTransparency = Theme.card.backgroundTransparency
    end)
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, self._theme.sizes.CornerRadius)
    corner.Parent = card
    
    -- Re-apply corner radius on theme change
    self:_addThemeUpdater(function()
        corner.CornerRadius = UDim.new(0, Theme.sizes.CornerRadius)
    end)
    
    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, UIx.Spacing.MD)
    pad.PaddingBottom = UDim.new(0, UIx.Spacing.MD)
    pad.PaddingLeft = UDim.new(0, UIx.Spacing.MD)
    pad.PaddingRight = UDim.new(0, UIx.Spacing.MD)
    pad.Parent = card
    
    -- Add vertical layout for card contents
    local cardLayout = Instance.new("UIListLayout")
    cardLayout.FillDirection = Enum.FillDirection.Vertical
    cardLayout.Padding = UDim.new(0, UIx.Spacing.SM)
    cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
    cardLayout.Parent = card
    
    -- Set parent at the end (use self.container if parent is self.container)
    card.Parent = parent or self.container
    
    return card
end

-- Create a scrollable section (InventoryTab parity)
function BaseTabComponent:createScrollableSection(titleText: string, minHeight: number): (Frame, ScrollingFrame, UIGridLayout)
    assert(typeof(minHeight) == "number", "minHeight must be a number")
    local card = self:createSectionCard(self.container, { size = UDim2.new(1, 0, 0, minHeight) })
    self:createSectionTitle(card, titleText)
    
    local scroll = Instance.new("ScrollingFrame")
    scroll.Name = "ScrollingFrame"
    scroll.Size = UDim2.new(1, 0, 1, -UIx.Size.BUTTON_SMALL_HEIGHT)
    scroll.Position = UDim2.new(0, 0, 0, UIx.Size.BUTTON_SMALL_HEIGHT)
    scroll.CanvasSize = UIx.Common.ORIGIN
    scroll.ScrollBarThickness = UIx.Spacing.TINY
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarImageColor3 = self._theme.colors.TextDim
    self:bindToTheme(scroll, { ScrollBarImageColor3 = "TextDim" })
    scroll.Parent = card
    
    local layout = Instance.new("UIGridLayout")
    layout.CellPadding = UDim2.new(0, UIx.Spacing.SM, 0, UIx.Spacing.SM)
    layout.CellSize = UDim2.new(0, UIx.Size.BUTTON_WIDTH // 2, 0, UIx.Size.BUTTON_HEIGHT) -- caller can override
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = scroll
    
    -- Auto-fit canvas height
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        scroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 8)
    end)
    
    return card, scroll, layout
end

-- Create a section title label with size override option
function BaseTabComponent:createSectionTitle(parent: Frame, text: string, icon: string?, sizeOverride: number?): TextLabel
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, 0, 0, UIx.Size.ROW_STANDARD)
    title.BackgroundTransparency = 1
    title.Text = (icon and (icon .. " ") or "") .. text
    title.TextColor3 = self._theme.colors.Text
    title.TextXAlignment = Enum.TextXAlignment.Left
    self:bindToTheme(title, { TextColor3 = "Text" })
    title.Font = self._theme.fonts.Primary
    title.TextSize = sizeOverride or self._theme.titleSize
    title.LayoutOrder = 0
    title.Parent = parent
    return title
end

-- Create a label with options
function BaseTabComponent:createLabel(parent: Frame, text: string, options: {
    isDim: boolean?,
    size: UDim2?,
    position: UDim2?,  -- Added position
    textSize: number?,
    align: Enum.TextXAlignment?,
    alignment: Enum.TextXAlignment?,  -- Alias for align
    wrap: boolean?,
    layoutOrder: number?,
}?): TextLabel
    local opts = options or {}
    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.Size = opts.size or UDim2.new(1, 0, 0, 0)
    label.Position = opts.position or UDim2.new(0, 0, 0, 0)  -- Apply position if provided
    label.AutomaticSize = if opts.size then Enum.AutomaticSize.None else Enum.AutomaticSize.Y
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = if opts.isDim then self._theme.colors.TextDim else self._theme.colors.Text
    label.TextXAlignment = opts.align or opts.alignment or Enum.TextXAlignment.Left  -- Support both 'align' and 'alignment'
    self:bindToTheme(label, { TextColor3 = if opts.isDim then "TextDim" else "Text" })
    label.Font = self._theme.fonts.Primary
    label.TextSize = opts.textSize or self._theme.labelSize
    label.TextWrapped = opts.wrap ~= false
    label.LayoutOrder = opts.layoutOrder or 0
    label.Parent = parent
    return label
end

-- Create a button with consistent styling (now supports primary variant)
function BaseTabComponent:createButton(parent: Frame, text: string, onClick: () -> (), options: {
    isDanger: boolean?,
    primary: boolean?,
    variant: ButtonVariant?,
    position: UDim2?,  -- Added position
    size: UDim2?,
    width: number?,
    layoutOrder: number?,
}?): TextButton
    local opts = options or {}
    local button = Instance.new("TextButton")
    button.Name = text:gsub(" ", ""):gsub("[^%w]", "").."Button"
    
    -- Safe fallback for button height
    local btnHeight = (self._theme.sizes and self._theme.sizes.MinButtonHeight) or UIx.Size.BUTTON_HEIGHT
    
    if opts.width then
        button.Size = UDim2.new(0, opts.width, 0, btnHeight)
    else
        button.Size = opts.size or UDim2.new(1, 0, 0, btnHeight)
    end
    
    button.Position = opts.position or UDim2.new(0, 0, 0, 0)  -- Apply position if provided
    
    -- Normalize variant with back-compat for primary/isDanger
    local variant = opts.variant
    if not variant then
        if opts.primary then variant = "primary"
        elseif opts.isDanger then variant = "danger"
        else variant = "surface" end
    end
    
    -- Apply variant styling
    local baseTransparency
    if variant == "primary" then
        button.BackgroundColor3 = self._theme.colors.Primary
        button.TextColor3 = self._theme.colors.Text
        baseTransparency = Theme.button.primaryTransparency or 0
        self:bindToTheme(button, { BackgroundColor3 = "Primary", TextColor3 = "Text" })
    elseif variant == "danger" then
        button.BackgroundColor3 = self._theme.colors.Surface
        button.TextColor3 = self._theme.colors.Error
        baseTransparency = Theme.button.surfaceTransparency
        self:bindToTheme(button, { BackgroundColor3 = "Surface", TextColor3 = "Error" })
    else -- surface (default)
        button.BackgroundColor3 = self._theme.colors.Surface
        button.TextColor3 = self._theme.colors.Text
        baseTransparency = Theme.button.surfaceTransparency
        self:bindToTheme(button, { BackgroundColor3 = "Surface", TextColor3 = "Text" })
    end
    button.BackgroundTransparency = baseTransparency
    
    button.BorderSizePixel = 0
    button.Text = text
    button.TextScaled = false
    button.TextSize = self._theme.buttonSize
    button.Font = self._theme.fonts.Primary
    button.AutoButtonColor = false
    button.LayoutOrder = opts.layoutOrder or 0
    button.Parent = parent
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, self._theme.sizes.CornerRadius)
    corner.Parent = button
    
    -- Re-apply non-bound props on theme change
    self:_addThemeUpdater(function()
        local newBase = if variant == "primary" then (Theme.button.primaryTransparency or 0) else Theme.button.surfaceTransparency
        button.BackgroundTransparency = newBase
        corner.CornerRadius = UDim.new(0, Theme.sizes.CornerRadius)
    end)
    
    -- Hover effects (need to re-evaluate transparencies each time)
    button.MouseEnter:Connect(function()
        local hoverTransparency = if opts.primary then (Theme.button.primaryHoverTransparency or 0.1) else Theme.button.surfaceHoverTransparency
        TweenService:Create(button, TweenInfo.new(UIx.Anim.QUICK), {
            BackgroundTransparency = hoverTransparency
        }):Play()
    end)
    
    button.MouseLeave:Connect(function()
        local baseTransparency = if opts.primary then (Theme.button.primaryTransparency or 0) else Theme.button.surfaceTransparency
        TweenService:Create(button, TweenInfo.new(UIx.Anim.QUICK), {
            BackgroundTransparency = baseTransparency
        }):Play()
    end)
    
    button.Activated:Connect(onClick)
    
    return button
end

-- Create a dropdown with consistent styling
function BaseTabComponent:createDropdown(opts: {
    parent: Instance,
    position: UDim2?,
    size: UDim2?,
    placeholder: string?,
    options: {any}?,
    onSelect: ((any) -> ())?,
    portalParent: Instance?,
})
    local dd = Dropdown.new({
        parent = opts.parent,
        position = opts.position or UDim2.new(0, UIx.Spacing.SM, 0, 0),
        size = opts.size or UDim2.new(1, -UIx.Spacing.LG, 0, UIx.Size.BUTTON_HEIGHT),
        placeholder = opts.placeholder or "Select...",
        options = opts.options or {},
        portalParent = opts.portalParent or self.portalParent,
        onSelect = opts.onSelect,
    })
    table.insert(self._widgets, dd)
    return dd
end

-- Create a field label (for dropdowns and form fields)
function BaseTabComponent:createFieldLabel(parent: Frame, text: string, options: {
    position: UDim2?,
    yOffset: number?,
}?): TextLabel
    local opts = options or {}
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 0, UIx.Size.ROW_STANDARD + UIx.Spacing.TINY)
    lbl.Position = opts.position or UDim2.new(0, 0, 0, opts.yOffset or 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.TextColor3 = self._theme.colors.Text
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Font = self._theme.fonts.Primary
    lbl.TextSize = self._theme.titleSize  -- Bigger for better readability
    lbl.Parent = parent
    self:bindToTheme(lbl, { TextColor3 = "Text" })
    return lbl
end

-- Create a text box with consistent styling
function BaseTabComponent:createTextBox(parent: Frame, placeholder: string, defaultText: string?, options: {
    size: UDim2?,
    width: number?,
}?): TextBox
    local opts = options or {}
    local textBox = Instance.new("TextBox")
    textBox.Name = placeholder:gsub(" ", "").."Box"
    
    if opts.width then
        textBox.Size = UDim2.new(0, opts.width, 0, self._theme.sizes.MinButtonHeight)
    else
        textBox.Size = opts.size or UDim2.new(1, 0, 0, self._theme.sizes.MinButtonHeight)
    end
    
    textBox.ClearTextOnFocus = false
    textBox.Text = defaultText or ""
    textBox.PlaceholderText = placeholder
    textBox.Font = self._theme.fonts.Primary
    textBox.TextSize = self._theme.buttonSize
    textBox.TextColor3 = self._theme.colors.Text
    textBox.PlaceholderColor3 = self._theme.colors.TextDim
    textBox.BackgroundColor3 = self._theme.colors.Surface
    textBox.BackgroundTransparency = Theme.card.backgroundTransparency
    textBox.Parent = parent
    
    self:bindToTheme(textBox, { 
        TextColor3 = "Text",
        PlaceholderColor3 = "TextDim",
        BackgroundColor3 = "Surface"
    })
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, self._theme.sizes.CornerRadius)
    corner.Parent = textBox
    
    -- Re-apply non-bound props on theme change
    self:_addThemeUpdater(function()
        textBox.BackgroundTransparency = Theme.card.backgroundTransparency
        corner.CornerRadius = UDim.new(0, Theme.sizes.CornerRadius)
    end)
    
    return textBox
end

-- Create a row for inline controls (horizontal layout)
function BaseTabComponent:createRow(parent: Instance, height: number?, padding: number?): Frame
    local row = Instance.new("Frame")
    row.Name = "Row"
    row.Size = UDim2.new(1, 0, 0, height or UIx.Size.BUTTON_SMALL_HEIGHT)
    row.BackgroundTransparency = 1
    row.Parent = parent
    
    local rowLayout = Instance.new("UIListLayout")
    rowLayout.FillDirection = Enum.FillDirection.Horizontal
    rowLayout.Padding = UDim.new(0, padding or UIx.Spacing.SM)
    rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
    rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    rowLayout.Parent = row
    
    return row
end

-- Create a field row (for metrics/stats display)
function BaseTabComponent:createFieldRow(parent: Instance, fieldName: string, displayName: string): (Frame, TextLabel, TextLabel)
    local row = Instance.new("Frame")
    row.Name = fieldName
    row.Size = UDim2.new(1, 0, 0, UIx.Size.ROW_TINY)
    row.BackgroundTransparency = 1
    row.Parent = parent
    
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.5, -UIx.Spacing.SM, 1, 0)
    label.Position = UDim2.new(0, UIx.Spacing.LG, 0, 0)  -- Indented
    label.BackgroundTransparency = 1
    label.Text = displayName .. ":"
    label.TextColor3 = self._theme.colors.Text
    label.TextXAlignment = Enum.TextXAlignment.Left
    self:bindToTheme(label, { TextColor3 = "Text" })
    label.Font = self._theme.fonts.Primary
    label.TextSize = self._theme.labelSize
    label.Parent = row
    
    local value = Instance.new("TextLabel")
    value.Size = UDim2.new(0.5, -UIx.Spacing.LG, 1, 0)
    value.Position = UDim2.new(0.5, UIx.Spacing.SM, 0, 0)
    value.BackgroundTransparency = 1
    value.Text = "—"
    value.TextColor3 = self._theme.colors.Text
    value.TextXAlignment = Enum.TextXAlignment.Right
    self:bindToTheme(value, { TextColor3 = "Text" })
    value.Font = self._theme.fonts.Primary
    value.TextSize = self._theme.labelSize
    value.Parent = row
    
    return row, label, value
end

-- Create a status banner (DebugTab parity)
function BaseTabComponent:createStatusBanner(parent: Instance?)
    local card = self:createSectionCard(parent or self.container, { name = "StatusCard", layoutOrder = 0 })
    card.Visible = false
    if parent then
        card.Parent = parent
    end
    
    local lbl = Instance.new("TextLabel")
    lbl.Name = "StatusLabel"
    lbl.Size = UDim2.new(1, 0, 0, UIx.Size.ROW_STANDARD)
    lbl.BackgroundTransparency = 1
    lbl.Font = self._theme.fonts.Primary
    lbl.TextSize = self._theme.labelSize
    lbl.TextXAlignment = Enum.TextXAlignment.Center
    lbl.Parent = card
    
    local timeoutThread = nil
    
    local function show(message: string, isError: boolean?)
        card.Visible = true
        card.BackgroundColor3 = if isError then self._theme.colors.Error else self._theme.colors.Success
        self:bindToTheme(card, { BackgroundColor3 = if isError then "Error" else "Success" })
        lbl.Text = message
        lbl.TextColor3 = self._theme.colors.Text
        self:bindToTheme(lbl, { TextColor3 = "Text" })
        
        -- Cancel previous timeout
        if timeoutThread then
            self:clearTimeout(timeoutThread)
        end
        
        -- Auto-hide after 3 seconds
        timeoutThread = self:setTimeout(UIx.Anim.SMOOTH * 10, function()  -- ~3s display
            if card and lbl.Text == message then 
                card.Visible = false 
            end
            timeoutThread = nil
        end)
    end
    
    return { 
        card = card, 
        label = lbl, 
        show = show 
    }
end

-- === Theme Management ===

-- Update theme cache when theme changes
function BaseTabComponent:_updateThemeCache()
    self._theme.colors = Theme.colors
    self._theme.fonts = Theme.fonts
    self._theme.sizes = Theme.sizes
    -- Text sizes remain constant
end

-- Bind an element to theme with auto-cleanup on destruction
function BaseTabComponent:bindToTheme(element: Instance, bindings: {[string]: string})
    ThemeRefresher.Bind(element, bindings)
    table.insert(self._themeBoundElements, {element = element, bindings = bindings})
    
    local destroyConn
    if (element :: any).Destroying then
        -- Modern, precise signal - only fires on actual destruction
        destroyConn = element.Destroying:Connect(function()
            -- Optional unbind hook if ThemeRefresher supports it
            local unbind = rawget(ThemeRefresher, "Unbind")
            if typeof(unbind) == "function" then
                pcall(unbind, element)
            end
            
            -- Remove from tracking
            for i = #self._themeBoundElements, 1, -1 do
                if self._themeBoundElements[i].element == element then
                    table.remove(self._themeBoundElements, i)
                    break
                end
            end
            
            -- Self-disconnect to avoid keeping dead handle
            if destroyConn and destroyConn.Connected then
                destroyConn:Disconnect()
            end
            
            -- Remove from connections list
            local idx = table.find(self._connections, destroyConn)
            if idx then
                table.remove(self._connections, idx)
            end
        end)
    else
        -- Fallback for older environments: guard against transient nil during reparent
        destroyConn = element.AncestryChanged:Connect(function(_, parent)
            if parent == nil and not element:IsDescendantOf(game) then
                local unbind = rawget(ThemeRefresher, "Unbind")
                if typeof(unbind) == "function" then
                    pcall(unbind, element)
                end
                for i = #self._themeBoundElements, 1, -1 do
                    if self._themeBoundElements[i].element == element then
                        table.remove(self._themeBoundElements, i)
                        break
                    end
                end
                destroyConn:Disconnect()
                -- Remove from connections list
                local idx = table.find(self._connections, destroyConn)
                if idx then
                    table.remove(self._connections, idx)
                end
            end
        end)
    end
    
    table.insert(self._connections, destroyConn)
    
    -- Return a manual disconnect handle if the caller wants to proactively unbind
    return function()
        if destroyConn.Connected then destroyConn:Disconnect() end
        local unbind = rawget(ThemeRefresher, "Unbind")
        if typeof(unbind) == "function" then
            pcall(unbind, element)
        end
        for i = #self._themeBoundElements, 1, -1 do
            if self._themeBoundElements[i].element == element then
                table.remove(self._themeBoundElements, i)
                break
            end
        end
    end
end

-- Register a function to re-apply non-bound theme properties
function BaseTabComponent:_addThemeUpdater(fn: () -> ())
    table.insert(self._themeUpdaters, fn)
end

-- === State Management ===

-- Timer helper with automatic cleanup on destroy
function BaseTabComponent:setTimeout(delay: number, fn: () -> ())
    local th
    th = task.delay(delay, function()
        if not self._destroyed then
            local ok, err = pcall(fn)
            if not ok then
                warn(("[BaseTabComponent] timer error: %s"):format(tostring(err)))
            end
        end
        -- Remove this timer handle to prevent array growth
        for i, h in ipairs(self._timers) do
            if h == th then 
                table.remove(self._timers, i)
                break
            end
        end
    end)
    table.insert(self._timers, th)
    return th
end

-- Optional: Clear a specific timer before it fires
function BaseTabComponent:clearTimeout(handle: thread)
    if not handle then return end
    
    -- Cancel the timer
    pcall(task.cancel, handle)
    
    -- Remove from tracking
    for i, h in ipairs(self._timers) do
        if h == handle then
            table.remove(self._timers, i)
            break
        end
    end
end

-- Hydration helper for loading preferences
function BaseTabComponent:hydrate(fetch: () -> any, apply: (any) -> ())
    self._hydrating = true
    local ok, data = pcall(fetch)
    if ok and data then
        apply(data)
    end
    self._hydrating = false
end

-- Select dropdown option by ID
function BaseTabComponent:selectOptionById(dropdown: any, id: string)
    if not dropdown or not dropdown.options then return end
    for i, opt in ipairs(dropdown.options) do
        if opt.id == id then
            dropdown:select(i)
            break
        end
    end
end

-- Set hydrating state (for preference loading)
function BaseTabComponent:setHydrating(value: boolean)
    self._hydrating = value
end

-- Check if currently hydrating
function BaseTabComponent:isHydrating(): boolean
    return self._hydrating
end

-- Enable/disable the tab
function BaseTabComponent:setEnabled(enabled: boolean)
    if self.container then 
        self.container.Visible = enabled 
    end
end

-- Track a widget for cleanup
function BaseTabComponent:addWidget(widget: any)
    table.insert(self._widgets, widget)
end

-- Track a connection for cleanup
function BaseTabComponent:addConnection(connection: RBXScriptConnection)
    table.insert(self._connections, connection)
end

-- === Update Mechanisms ===

-- Start a periodic update loop (like AccountTab's playtime ticker)
function BaseTabComponent:startPeriodicUpdate(interval: number, updateFunc: () -> ())
    if self._updateTask then
        task.cancel(self._updateTask)
    end
    
    self._updateActive = true
    self._updateTask = task.spawn(function()
        while self._updateActive and self.container and self.container.Parent do
            local ok, err = pcall(updateFunc)
            if not ok then
                warn(("[%s] Periodic update error: %s"):format(self._name or "BaseTabComponent", tostring(err)))
            end
            task.wait(interval)
        end
    end)
end

-- Stop periodic updates
function BaseTabComponent:stopPeriodicUpdate()
    self._updateActive = false
    if self._updateTask then
        task.cancel(self._updateTask)
        self._updateTask = nil
    end
end

-- Wait for player data to be loaded (used by MaterialsTab, ThemeTab)
function BaseTabComponent:waitForDataLoaded(callback: () -> ())
    local Players = game:GetService("Players")
    local player = Players.LocalPlayer
    
    task.spawn(function()
        if not player:GetAttribute("DataLoaded") then
            player:GetAttributeChangedSignal("DataLoaded"):Wait()
        end
        callback()
    end)
end

-- Hook up to a data provider (used by AccountTab, InventoryTab, UpgradeTab)
function BaseTabComponent:connectDataProvider(dataProvider: any, applySnapshot: (any, any?, any?) -> ())
    if not dataProvider then return end
    
    self._dataProvider = dataProvider
    
    -- Get initial snapshot
    local snapshot = dataProvider:getSnapshot()
    if snapshot then
        -- Pass through key/value as nil for initial snapshot for API parity
        applySnapshot(snapshot, nil, nil)
    end
    
    -- Listen for changes
    local conn = dataProvider:onChanged():Connect(function(key, value, snap)
        -- Forward key/value so tabs can handle deltas without full rebuilds
        applySnapshot(snap, key, value)
    end)
    self:addConnection(conn)
end


-- Create a debounced save function (used by ThemeTab for volume slider)
function BaseTabComponent:createDebouncedSave(saveFunc: (any) -> (), delay: number?): (any) -> ()
    local saveTimer = nil
    return function(data)
        if saveTimer then 
            self:clearTimeout(saveTimer)
        end
        saveTimer = self:setTimeout(delay or 0.2, function()
            if not self._hydrating then
                pcall(saveFunc, data)
            end
            saveTimer = nil
        end)
    end
end

-- === Helper Methods ===

-- Format field names consistently (for display)
function BaseTabComponent:formatFieldName(fieldName: string): string
    return fieldName
        :gsub("(%l)(%u)", "%1 %2")  -- Add space before capitals
        :gsub("^%l", string.upper)  -- Capitalize first letter
        :gsub("_", " ")  -- Replace underscores with spaces
        :gsub("Per", " Per")
        :gsub("Sec", " (sec)")
        :gsub("Earned", " Earned")
        :gsub("Spent", " Spent")
end

-- Format duration in seconds to human-readable format
function BaseTabComponent:formatDuration(seconds: number): string
    seconds = MathUtils.nonNegative(math.floor(seconds))
    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    
    if days > 0 then
        return string.format("%dd %dh", days, hours)
    elseif hours > 0 then
        return string.format("%dh %dm", hours, minutes)
    else
        return string.format("%dm", minutes)
    end
end

-- === Cleanup ===

-- Destroy the tab and clean up resources
function BaseTabComponent:destroy()
    -- Mark as destroyed to prevent timer execution
    self._destroyed = true
    
    -- Cancel all pending timers
    if self._timers then
        for _, th in ipairs(self._timers) do
            pcall(task.cancel, th)
        end
        self._timers = {}
    end
    
    -- Stop any periodic updates
    if self.stopPeriodicUpdate then
        self:stopPeriodicUpdate()
    end
    
    -- Unbind all theme elements if supported
    local unbind = rawget(ThemeRefresher, "Unbind")
    if typeof(unbind) == "function" then
        for i = #self._themeBoundElements, 1, -1 do
            local rec = self._themeBoundElements[i]
            if rec and rec.element then
                pcall(unbind, rec.element)
            end
        end
    end
    self._themeBoundElements = {}
    
    -- Clear theme updaters to drop closures
    self._themeUpdaters = {}
    
    -- Clean up widgets
    for _, widget in ipairs(self._widgets) do
        if widget and typeof(widget) == "table" and widget.destroy then
            pcall(widget.destroy, widget)
        elseif widget and typeof(widget) == "Instance" then
            pcall(function() widget:Destroy() end)
        end
    end
    self._widgets = {}
    
    -- Clear labels table to drop references
    self._labels = {}
    
    -- Disconnect all connections
    for _, conn in ipairs(self._connections) do
        if conn and conn.Connected then
            conn:Disconnect()
        end
    end
    self._connections = {}
    
    -- Destroy container last
    if self.container then
        self.container:Destroy()
        self.container = nil
    end
end

-- === Compatibility Methods ===

-- These methods help with gradual migration of existing tabs

-- Get theme reference (for tabs that need direct access)
function BaseTabComponent:getTheme()
    return self._theme
end

-- Get container (some tabs may need direct access)
function BaseTabComponent:getContainer(): Frame?
    return self.container
end

return BaseTabComponent
