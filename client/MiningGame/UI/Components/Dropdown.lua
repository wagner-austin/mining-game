--!strict
-- Dropdown.lua
-- Reusable dropdown component with Theme integration and portal system

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local MathUtils = require(MiningGame:WaitForChild("MathUtils"))
local UIFolder = MiningGame:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))
local ThemeRefresher = require(UIFolder:WaitForChild("ThemeRefresher"))
local UIUtils = require(UIFolder:WaitForChild("UIUtils"))
local UIx = require(UIFolder:WaitForChild("UIConstants"))

-- Track the currently open dropdown globally so only one can be open at a time
local currentOpen = nil -- : Dropdown?

local Dropdown = {}
Dropdown.__index = Dropdown

export type DropdownT = {
    options: {Option},
    onSelect: ((option: Option) -> ())?,
    connections: {RBXScriptConnection},
    optionConns: {{RBXScriptConnection}},
    currentIndex: number,
    portalParent: Instance?,
    zIndexBase: number,
    maxHeight: number,
    container: Frame,
    button: TextButton,
    list: ScrollingFrame?,
    listContent: Frame?,
    shield: TextButton?,
    optionButtons: {TextButton},
    new: (config: DropdownConfig) -> DropdownT,
    setOptions: (self: DropdownT, options: {Option}) -> (),
    getValue: (self: DropdownT) -> Option?,
    destroy: (self: DropdownT) -> (),
}
export type Option = {
    id: string,
    label: string,
    icon: string?, -- Optional icon
    color: Color3?, -- Optional custom color
}

export type DropdownConfig = {
    parent: Instance,
    position: UDim2?,
    size: UDim2?,
    placeholder: string?,
    options: {Option},
    initialIndex: number?,
    onSelect: ((option: Option) -> ())?,
    portalParent: Instance?, -- NEW: lists render here
    zIndexBase: number?, -- NEW: base Z for list/shield (optional)
    maxHeight: number?, -- NEW: list max height (optional)
}

function Dropdown.new(config: DropdownConfig): DropdownT
    local self = setmetatable({}, Dropdown)
    
    -- Don't capture colors here - always use Theme.colors directly
    
    -- Store config
    self.options = config.options or {}
    self.onSelect = config.onSelect
    self.connections = {}
    self.optionConns = {} -- Track per-option connections for cleanup
    self.currentIndex = config.initialIndex or 0
    self.portalParent = config.portalParent
    self.zIndexBase = (config.zIndexBase or Theme.z.Modal) + 10
    self.maxHeight = config.maxHeight or Theme.dropdown.listMaxHeight
    
    -- Main button container
    local container = Instance.new("Frame")
    container.Size = config.size or UDim2.new(1, 0, 0, UIx.Size.BUTTON_HEIGHT)
    container.Position = config.position or UIx.Common.ORIGIN
    container.BackgroundTransparency = 1
    container.Parent = config.parent
    self.container = container
    
    -- Main button
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(1, 0, 1, 0)
    button.BackgroundColor3 = Theme.colors.Surface
    button.BackgroundTransparency = Theme.card.backgroundTransparency
    button.Text = config.placeholder or "Select..."
    button.TextColor3 = Theme.colors.Text
    button.TextScaled = true
    button.Font = Theme.fonts.Primary
    button.AutoButtonColor = true
    button.Parent = container
    self.button = button
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, Theme.sizes.CornerRadius)
    corner.Parent = button
    
    local stroke = Instance.new("UIStroke")
    stroke.Thickness = Theme.glassEdge.thickness
    stroke.Color = Theme.glassEdge.color
    stroke.Transparency = Theme.glassEdge.transparency
    stroke.ApplyStrokeMode = Theme.glassEdge.applyStrokeMode
    stroke.LineJoinMode = Theme.glassEdge.lineJoinMode
    stroke.Parent = button
    
    -- Bind stroke to theme refresher
    ThemeRefresher.Bind(stroke, { Stroke = "glassEdge" })
    
    local textConstraint = Instance.new("UITextSizeConstraint")
    textConstraint.MinTextSize = Theme.textSizes.Small.Min
    textConstraint.MaxTextSize = Theme.textSizes.Medium.Max
    textConstraint.Parent = button
    
    -- Left align text with padding for mobile style
    button.TextXAlignment = Enum.TextXAlignment.Left
    local buttonPadding = Instance.new("UIPadding")
    buttonPadding.PaddingLeft = UDim.new(0, UIx.Spacing.MD)
    buttonPadding.PaddingRight = UDim.new(0, UIx.Spacing.DROPDOWN_ARROW) -- Room for arrow
    buttonPadding.Parent = button
    
    
    -- Dropdown arrow indicator
    local arrow = Instance.new("TextLabel")
    arrow.Size = UDim2.new(0, UIx.Size.ARROW_PX, 1, 0)
    arrow.Position = UDim2.new(1, -UIx.Size.ARROW_PX, 0, 0)
    arrow.BackgroundTransparency = 1
    arrow.Text = "▼"
    arrow.TextColor3 = Theme.colors.TextDim
    arrow.TextScaled = true
    arrow.Font = Theme.fonts.Primary
    arrow.Parent = button
    
    local arrowConstraint = Instance.new("UITextSizeConstraint")
    arrowConstraint.MinTextSize = UIx.Visual.TEXT_MINIMUM
    arrowConstraint.MaxTextSize = UIx.Size.ARROW_PX
    arrowConstraint.Parent = arrow
    
    -- Bind button and arrow to theme refresher
    ThemeRefresher.Bind(button, { BackgroundColor3 = "Surface", TextColor3 = "Text" })
    ThemeRefresher.Bind(arrow, { TextColor3 = "TextDim" })
    
    -- Use portal parent if provided, otherwise use container
    local rootParent = self.portalParent or container
    
    -- Full-screen shield (blocks clicks & closes on click)
    local shield = Instance.new("TextButton")
    shield.Name = "DropdownShield"
    shield.AutoButtonColor = false
    shield.Text = ""
    shield.BackgroundTransparency = 1 -- Invisible
    shield.Size = UDim2.fromScale(1, 1)
    shield.Position = UDim2.fromScale(0, 0)
    shield.Visible = false
    shield.ZIndex = self.zIndexBase
    shield.Modal = true -- grabs input focus while open
    shield.Parent = rootParent
    self.shield = shield
    
    table.insert(self.connections, shield.Activated:Connect(function()
        local SoundManager = require(ReplicatedStorage.MiningGame:WaitForChild("SoundManager"))
        SoundManager.PlayUI("buttonclick")
        self:close()
    end))
    
    -- Dropdown list container (portaled to root)
    local listContainer = Instance.new("ScrollingFrame")
    listContainer.Visible = false
    listContainer.ZIndex = self.zIndexBase + 1
    listContainer.Size = UDim2.fromOffset(0, self.maxHeight) -- width set on open
    listContainer.Position = UDim2.fromOffset(0, 0)
    listContainer.BackgroundColor3 = Theme.colors.Surface  -- Surface color for visibility
    listContainer.BackgroundTransparency = Theme.dropdown.listBackgroundTransparency  -- Less transparent for dropdown
    listContainer.BorderSizePixel = 0
    listContainer.ScrollBarThickness = UIx.Spacing.TINY
    listContainer.ScrollBarImageColor3 = Theme.colors.Primary
    listContainer.ScrollBarImageTransparency = 0.5
    listContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
    listContainer.CanvasSize = UIx.Common.ORIGIN
    listContainer.CanvasPosition = Vector2.new(0, 0) -- Start at top
    listContainer.Active = true -- absorbs input
    listContainer.ClipsDescendants = true
    listContainer.Parent = rootParent
    self.list = listContainer

    -- Add frosted overlays (gradient + tinted noise) and register for live refresh
    local grad = Instance.new("UIGradient")
    grad.Rotation = 90
    grad.Color = ColorSequence.new(Color3.new(1,1,1), Color3.new(1,1,1))
    grad.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, Theme.effects.frosted.gradientTopT),
        NumberSequenceKeypoint.new(1, Theme.effects.frosted.gradientBottomT),
    })
    grad.Parent = listContainer

    local noise = Instance.new("ImageLabel")
    noise.BackgroundTransparency = 1
    noise.Image = "rbxasset://textures/ui/GuiImagePlaceholder.png"
    local frost = Theme.effects.frosted
    local base = Theme.colors[frost.noiseColorKey] or Theme.colors.Background
    local t = math.clamp(frost.noiseLighten or 0, 0, 1)
    local tinted = t > 0 and base:Lerp(Color3.new(1,1,1), t) or base
    noise.ImageColor3 = tinted
    noise.ImageTransparency = frost.noiseTransparency
    noise.ScaleType = Enum.ScaleType.Tile
    noise.TileSize = UDim2.fromOffset(64, 64)
    noise.Size = UDim2.fromScale(1, 1)
    noise.ZIndex = self.zIndexBase -- behind option buttons
    noise.Parent = listContainer

    UIUtils.registerFrosted(listContainer, grad, noise)
    
    local listCorner = Instance.new("UICorner")
    listCorner.CornerRadius = UDim.new(0, Theme.sizes.CornerRadius)
    listCorner.Parent = listContainer
    
    local listStroke = Instance.new("UIStroke")
    listStroke.Thickness = Theme.glassEdge.thickness
    listStroke.Color = Theme.glassEdge.color
    listStroke.Transparency = Theme.glassEdge.transparency
    listStroke.ApplyStrokeMode = Theme.glassEdge.applyStrokeMode
    listStroke.LineJoinMode = Theme.glassEdge.lineJoinMode
    listStroke.ZIndex = self.zIndexBase + 1
    listStroke.Parent = listContainer
    
    -- Bind list stroke to theme refresher
    ThemeRefresher.Bind(listStroke, { Stroke = "glassEdge" })

    -- Content holder so decorative overlays don't interfere with layout
    local contentHolder = Instance.new("Frame")
    contentHolder.Name = "Content"
    contentHolder.BackgroundTransparency = 1
    contentHolder.Size = UDim2.fromScale(1, 1)
    contentHolder.ZIndex = self.zIndexBase + 2
    contentHolder.AutomaticSize = Enum.AutomaticSize.Y
    contentHolder.Parent = listContainer
    self.listContent = contentHolder

    local listPadding = Instance.new("UIPadding")
    listPadding.PaddingTop = UDim.new(0, Theme.dropdown.listPadding)
    listPadding.PaddingBottom = UDim.new(0, Theme.dropdown.listPadding)
    listPadding.PaddingLeft = UDim.new(0, Theme.dropdown.listPadding)
    listPadding.PaddingRight = UDim.new(0, Theme.dropdown.listPadding)
    listPadding.Parent = contentHolder
    
    local listLayout = Instance.new("UIListLayout")
    listLayout.Padding = UDim.new(0, Theme.dropdown.optionGap) -- gap for pill effect
    listLayout.Parent = contentHolder
    
    -- Bind list to theme refresher
    ThemeRefresher.Bind(listContainer, { BackgroundColor3 = "Background", ScrollBarImageColor3 = "Primary" })
    
    -- Positioning helper (places list under the button; flips up if needed)
    local function repositionList()
        if not listContainer.Visible then return end
        
        local btnAbs = container.AbsolutePosition
        local btnSize = container.AbsoluteSize
        local rootAbs = rootParent.AbsolutePosition
        local rootSize = rootParent.AbsoluteSize
        
        -- Mobile style: slightly wider with nice spacing
        local listWidth = math.floor(btnSize.X * Theme.dropdown.listWidthRatio)
        local x = btnAbs.X - rootAbs.X - math.floor((listWidth - btnSize.X) / 2)  -- Center it
        local yBelow = btnAbs.Y - rootAbs.Y + btnSize.Y + Theme.dropdown.listOffset  -- Gap for shadow effect
        
        -- Use the actual content height from AutomaticCanvasSize, capped at maxHeight
        -- AbsoluteCanvasSize.Y gives us the real content height including padding
        local actualContentHeight = listContainer.AbsoluteCanvasSize.Y
        local desiredHeight = math.min(actualContentHeight, self.maxHeight)
        
        -- If we have very few items, use the actual height; otherwise cap it
        if actualContentHeight > 0 then
            listContainer.Size = UDim2.fromOffset(listWidth, desiredHeight)
        else
            -- Fallback for first frame before canvas size is calculated
            listContainer.Size = UDim2.fromOffset(listWidth, self.maxHeight)
        end
        listContainer.Position = UDim2.fromOffset(x, yBelow)
        
        -- Flip upward if it would go off-screen
        local listH = math.min(desiredHeight, listContainer.AbsoluteSize.Y)
        if yBelow + listH > rootSize.Y then
            local listWidth = math.floor(btnSize.X * Theme.dropdown.listWidthRatio)
            local x = btnAbs.X - rootAbs.X - math.floor((listWidth - btnSize.X) / 2)
            local yAbove = btnAbs.Y - rootAbs.Y - listH - Theme.dropdown.listOffset  -- Gap when flipped too
            listContainer.Position = UDim2.fromOffset(x, MathUtils.nonNegative(yAbove))
        end
        
        -- Force scroll to top after repositioning
        listContainer.CanvasPosition = Vector2.new(0, 0)
    end
    
    -- Reposition when the source button moves/resizes
    table.insert(self.connections, container:GetPropertyChangedSignal("AbsolutePosition"):Connect(repositionList))
    table.insert(self.connections, container:GetPropertyChangedSignal("AbsoluteSize"):Connect(repositionList))
    
    -- Also reposition when content size changes (important for dynamic sizing)
    table.insert(self.connections, listContainer:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(repositionList))
    
    -- Create option buttons
    self.optionButtons = {}
    for i, option in ipairs(self.options) do
        local optBtn = Instance.new("TextButton")
        optBtn.Size = UDim2.new(1, 0, 0, Theme.dropdown.optionHeight)
        optBtn.BackgroundColor3 = Theme.colors.Surface
        optBtn.BackgroundTransparency = Theme.dropdown.optionTransparency
        optBtn.Text = option.label
        optBtn.TextColor3 = option.color or Theme.colors.Text
        optBtn.TextScaled = true
        optBtn.Font = Theme.fonts.Primary  -- Use primary font for better readability
        optBtn.AutoButtonColor = false
        optBtn.ZIndex = self.zIndexBase + 2 -- Ensure it's above the list container
        optBtn.Parent = contentHolder

        -- Add a subtle divider line after each option (except last)
        if i < #self.options then
            local divider = Instance.new("Frame")
            divider.Size = UDim2.new(1, -UIx.Spacing.MD, 0, 1)
            divider.Position = UDim2.new(0, UIx.Spacing.SM, 1, -1)
            divider.BackgroundColor3 = Theme.colors.TextDim
            divider.BackgroundTransparency = Theme.ui.dividerTransparency + 0.1  -- Even more subtle
            divider.BorderSizePixel = 0
            divider.Parent = optBtn
            
            -- Bind divider to theme
            ThemeRefresher.Bind(divider, { BackgroundColor3 = "TextDim" })
        end

        local optTextConstraint = Instance.new("UITextSizeConstraint")
        optTextConstraint.MinTextSize = Theme.textSizes.Small.Min
        optTextConstraint.MaxTextSize = Theme.textSizes.Medium.Max
        optTextConstraint.Parent = optBtn
        
        -- Add icon if provided
        if option.icon then
            local icon = Instance.new("TextLabel")
            icon.Size = UDim2.new(0, UIx.Size.ROW_STANDARD, 1, 0)
            icon.Position = UDim2.new(0, UIx.Spacing.TINY, 0, 0)
            icon.BackgroundTransparency = 1
            icon.Text = option.icon
            icon.TextColor3 = option.color or Theme.colors.Text
            icon.TextScaled = true
            icon.Font = Theme.fonts.Primary
            icon.Parent = optBtn
            
            -- Adjust text padding for icon
            optBtn.TextXAlignment = Enum.TextXAlignment.Left
            optBtn.Text = "      " .. option.label
        end
        
        -- Bind option button to theme refresher (conditionally for TextColor3)
        if option.color then
            ThemeRefresher.Bind(optBtn, { BackgroundColor3 = "Surface" })
        else
            ThemeRefresher.Bind(optBtn, { BackgroundColor3 = "Surface", TextColor3 = "Text" })
        end
        
        -- Hover effect and selection
        local conns = {}
        table.insert(conns, optBtn.MouseEnter:Connect(function()
            optBtn.BackgroundTransparency = Theme.dropdown.optionHoverTransparency -- Slightly more solid on hover
        end))
        
        table.insert(conns, optBtn.MouseLeave:Connect(function()
            optBtn.BackgroundTransparency = Theme.dropdown.optionTransparency -- back to initial
        end))
        
        table.insert(conns, optBtn.Activated:Connect(function()
            local SoundManager = require(ReplicatedStorage.MiningGame:WaitForChild("SoundManager"))
            SoundManager.PlayUI("buttonclick")
            self:select(i)
        end))
        
        self.optionConns[i] = conns
        self.optionButtons[i] = optBtn
    end
    
    -- Set initial selection
    if self.currentIndex > 0 and self.options[self.currentIndex] then
        self:select(self.currentIndex)
    end
    
    -- Toggle dropdown
    table.insert(self.connections, button.Activated:Connect(function()
        local SoundManager = require(ReplicatedStorage.MiningGame:WaitForChild("SoundManager"))
        SoundManager.PlayUI("buttonclick")
        self:toggle()
    end))
    
    -- Store repositionList for use in open()
    self.repositionList = repositionList
    
    return self
end

function Dropdown:toggle()
    if self.list.Visible then
        self:close()
    else
        self:open()
    end
end

function Dropdown:open()
    -- Close any other open dropdown
    if currentOpen and currentOpen ~= self then
        currentOpen:close()
    end
    currentOpen = self
    
    -- Show shield and list
    self.shield.Visible = true
    self.shield.Active = true
    self.list.Visible = true
    
    -- Reset scroll position to top
    self.list.CanvasPosition = Vector2.new(0, 0)
    
    -- Position the list
    self.repositionList()
    
    -- Update arrow
    local arrow = self.button:FindFirstChildOfClass("TextLabel")
    if arrow then
        arrow.Text = "▲"
    end
end

function Dropdown:close()
    self.list.Visible = false
    self.shield.Visible = false
    self.shield.Active = false
    
    if currentOpen == self then
        currentOpen = nil
    end
    
    local arrow = self.button:FindFirstChildOfClass("TextLabel")
    if arrow then
        arrow.Text = "▼"
    end
end

function Dropdown:select(index: number)
    if not self.options[index] then return end
    
    self.currentIndex = index
    local option = self.options[index]
    self.button.Text = option.label
    
    -- Update text color if option has a custom color
    if option.color then
        self.button.TextColor3 = option.color
    else
        self.button.TextColor3 = Theme.colors.Text
    end
    
    self:close()
    
    if self.onSelect then
        self.onSelect(option)
    end
end

function Dropdown:setOptions(options: {Option})
    -- Disconnect old option connections
    for _, group in ipairs(self.optionConns) do
        for _, c in ipairs(group) do
            if c and c.Disconnect then c:Disconnect() end
        end
    end
    self.optionConns = {}
    
    -- Clear old option buttons
    for _, btn in ipairs(self.optionButtons) do
        btn:Destroy()
    end
    self.optionButtons = {}
    
    -- Update options
    self.options = options
    self.currentIndex = 0
    self.button.Text = "Select..."
    
    local colors = Theme.colors
    
    -- Create new option buttons
    for i, option in ipairs(self.options) do
        local optBtn = Instance.new("TextButton")
        optBtn.Size = UDim2.new(1, 0, 0, Theme.dropdown.optionHeight)
        optBtn.BackgroundColor3 = Theme.colors.Surface
        optBtn.BackgroundTransparency = Theme.dropdown.optionTransparency
        optBtn.Text = option.label
        optBtn.TextColor3 = option.color or Theme.colors.Text
        optBtn.TextScaled = true
        optBtn.Font = Theme.fonts.Primary
        optBtn.AutoButtonColor = false
        optBtn.ZIndex = self.zIndexBase + 2 -- Ensure it's above the list container
        optBtn.Parent = self.listContent or self.list

        -- Add a subtle divider line after each option (except last)
        if i < #self.options then
            local divider = Instance.new("Frame")
            divider.Size = UDim2.new(1, -UIx.Spacing.MD, 0, 1)
            divider.Position = UDim2.new(0, UIx.Spacing.SM, 1, -1)
            divider.BackgroundColor3 = Theme.colors.TextDim
            divider.BackgroundTransparency = Theme.ui.dividerTransparency + 0.1  -- Even more subtle
            divider.BorderSizePixel = 0
            divider.Parent = optBtn
            
            -- Bind divider to theme
            ThemeRefresher.Bind(divider, { BackgroundColor3 = "TextDim" })
        end

        local optTextConstraint = Instance.new("UITextSizeConstraint")
        optTextConstraint.MinTextSize = Theme.textSizes.Small.Min
        optTextConstraint.MaxTextSize = Theme.textSizes.Medium.Max
        optTextConstraint.Parent = optBtn
        
        -- Bind option button to theme refresher (conditionally for TextColor3)
        if option.color then
            ThemeRefresher.Bind(optBtn, { BackgroundColor3 = "Surface" })
        else
            ThemeRefresher.Bind(optBtn, { BackgroundColor3 = "Surface", TextColor3 = "Text" })
        end
        
        -- Hover effect and selection
        local conns = {}
        table.insert(conns, optBtn.MouseEnter:Connect(function()
            optBtn.BackgroundTransparency = Theme.dropdown.optionHoverTransparency
        end))
        
        table.insert(conns, optBtn.MouseLeave:Connect(function()
            optBtn.BackgroundTransparency = Theme.dropdown.optionTransparency
        end))
        
        table.insert(conns, optBtn.Activated:Connect(function()
            local SoundManager = require(ReplicatedStorage.MiningGame:WaitForChild("SoundManager"))
            SoundManager.PlayUI("buttonclick")
            self:select(i)
        end))
        
        self.optionConns[i] = conns
        self.optionButtons[i] = optBtn
    end
end

function Dropdown:getValue(): Option?
    return self.options[self.currentIndex]
end

function Dropdown:destroy()
    -- Close if open
    if currentOpen == self then
        currentOpen = nil
    end
    
    -- Disconnect global connections
    for _, connection in ipairs(self.connections) do
        connection:Disconnect()
    end
    self.connections = {}
    
    -- Disconnect per-option connections
    for _, group in ipairs(self.optionConns) do
        for _, c in ipairs(group) do
            if c and c.Disconnect then c:Disconnect() end
        end
    end
    self.optionConns = {}
    
    -- Destroy shield
    if self.shield then
        self.shield:Destroy()
        self.shield = nil
    end
    
    -- Destroy list
    if self.list then
        self.list:Destroy()
        self.list = nil
    end
    
    -- Destroy container
    if self.container then
        self.container:Destroy()
    end
end

return Dropdown
