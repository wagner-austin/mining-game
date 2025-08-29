--!strict
-- Dropdown.lua
-- Reusable dropdown component with Theme integration and portal system

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Theme = require(MiningGame:WaitForChild("UI"):WaitForChild("Theme"))

-- Track the currently open dropdown globally so only one can be open at a time
local currentOpen = nil -- : Dropdown?

local Dropdown = {}
Dropdown.__index = Dropdown

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

function Dropdown.new(config: DropdownConfig)
    local self = setmetatable({}, Dropdown)
    
    local colors = Theme.colors
    
    -- Store config
    self.options = config.options or {}
    self.onSelect = config.onSelect
    self.connections = {}
    self.optionConns = {} -- Track per-option connections for cleanup
    self.currentIndex = config.initialIndex or 0
    self.portalParent = config.portalParent
    self.zIndexBase = (config.zIndexBase or Theme.z.Modal) + 10
    self.maxHeight = config.maxHeight or 220
    
    -- Main button container
    local container = Instance.new("Frame")
    container.Size = config.size or UDim2.new(1, 0, 0, 36)
    container.Position = config.position or UDim2.new(0, 0, 0, 0)
    container.BackgroundTransparency = 1
    container.Parent = config.parent
    self.container = container
    
    -- Main button
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(1, 0, 1, 0)
    button.BackgroundColor3 = colors.Surface
    button.BackgroundTransparency = 0.2
    button.Text = config.placeholder or "Select..."
    button.TextColor3 = colors.Text
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
    
    local textConstraint = Instance.new("UITextSizeConstraint")
    textConstraint.MinTextSize = Theme.textSizes.Small.Min
    textConstraint.MaxTextSize = Theme.textSizes.Medium.Max
    textConstraint.Parent = button
    
    -- Add padding to avoid text running under arrow
    local padding = Instance.new("UIPadding")
    padding.PaddingRight = UDim.new(0, 30) -- Leave room for the arrow
    padding.PaddingLeft = UDim.new(0, 8)
    padding.Parent = button
    button.TextXAlignment = Enum.TextXAlignment.Left
    
    -- Dropdown arrow indicator
    local arrow = Instance.new("TextLabel")
    arrow.Size = UDim2.new(0, 30, 1, 0)
    arrow.Position = UDim2.new(1, -30, 0, 0)
    arrow.BackgroundTransparency = 1
    arrow.Text = "▼"
    arrow.TextColor3 = colors.TextDim
    arrow.TextScaled = true
    arrow.Font = Theme.fonts.Primary
    arrow.Parent = button
    
    local arrowConstraint = Instance.new("UITextSizeConstraint")
    arrowConstraint.MinTextSize = 8
    arrowConstraint.MaxTextSize = 16
    arrowConstraint.Parent = arrow
    
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
    
    table.insert(self.connections, shield.MouseButton1Click:Connect(function()
        self:close()
    end))
    
    -- Dropdown list container (portaled to root)
    local listContainer = Instance.new("ScrollingFrame")
    listContainer.Visible = false
    listContainer.ZIndex = self.zIndexBase + 1
    listContainer.Size = UDim2.fromOffset(0, self.maxHeight) -- width set on open
    listContainer.Position = UDim2.fromOffset(0, 0)
    listContainer.BackgroundColor3 = colors.Background
    listContainer.BackgroundTransparency = 0 -- fully opaque to block click-through
    listContainer.BorderSizePixel = 0
    listContainer.ScrollBarThickness = 4
    listContainer.ScrollBarImageColor3 = colors.Primary
    listContainer.ScrollBarImageTransparency = 0.5
    listContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
    listContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
    listContainer.Active = true -- absorbs input
    listContainer.ClipsDescendants = true
    listContainer.Parent = rootParent
    self.list = listContainer
    
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
    
    local listLayout = Instance.new("UIListLayout")
    listLayout.Padding = UDim.new(0, 2)
    listLayout.Parent = listContainer
    
    local listPadding = Instance.new("UIPadding")
    listPadding.PaddingTop = UDim.new(0, 4)
    listPadding.PaddingBottom = UDim.new(0, 4)
    listPadding.PaddingLeft = UDim.new(0, 4)
    listPadding.PaddingRight = UDim.new(0, 4)
    listPadding.Parent = listContainer
    
    -- Positioning helper (places list under the button; flips up if needed)
    local function repositionList()
        if not listContainer.Visible then return end
        
        local btnAbs = container.AbsolutePosition
        local btnSize = container.AbsoluteSize
        local rootAbs = rootParent.AbsolutePosition
        local rootSize = rootParent.AbsoluteSize
        
        local x = btnAbs.X - rootAbs.X
        local yBelow = btnAbs.Y - rootAbs.Y + btnSize.Y + 4
        
        listContainer.Size = UDim2.fromOffset(btnSize.X, self.maxHeight)
        listContainer.Position = UDim2.fromOffset(x, yBelow)
        
        -- Flip upward if it would go off-screen
        local listH = math.min(self.maxHeight, listContainer.AbsoluteSize.Y)
        if yBelow + listH > rootSize.Y then
            local yAbove = btnAbs.Y - rootAbs.Y - listH - 4
            listContainer.Position = UDim2.fromOffset(x, math.max(0, yAbove))
        end
    end
    
    -- Reposition when the source button moves/resizes
    table.insert(self.connections, container:GetPropertyChangedSignal("AbsolutePosition"):Connect(repositionList))
    table.insert(self.connections, container:GetPropertyChangedSignal("AbsoluteSize"):Connect(repositionList))
    
    -- Create option buttons
    self.optionButtons = {}
    for i, option in ipairs(self.options) do
        local optBtn = Instance.new("TextButton")
        optBtn.Size = UDim2.new(1, -8, 0, 32)
        optBtn.BackgroundColor3 = colors.Surface
        optBtn.BackgroundTransparency = 0.3 -- Less transparent for better visibility
        optBtn.Text = option.label
        optBtn.TextColor3 = option.color or colors.Text
        optBtn.TextScaled = true
        optBtn.Font = Theme.fonts.Secondary
        optBtn.AutoButtonColor = false
        optBtn.ZIndex = self.zIndexBase + 2 -- Ensure it's above the list container
        optBtn.Parent = listContainer
        
        local optCorner = Instance.new("UICorner")
        optCorner.CornerRadius = UDim.new(0, Theme.sizes.CornerRadius - 2)
        optCorner.Parent = optBtn
        
        local optTextConstraint = Instance.new("UITextSizeConstraint")
        optTextConstraint.MinTextSize = Theme.textSizes.Small.Min
        optTextConstraint.MaxTextSize = Theme.textSizes.Medium.Max
        optTextConstraint.Parent = optBtn
        
        -- Add icon if provided
        if option.icon then
            local icon = Instance.new("TextLabel")
            icon.Size = UDim2.new(0, 24, 1, 0)
            icon.Position = UDim2.new(0, 4, 0, 0)
            icon.BackgroundTransparency = 1
            icon.Text = option.icon
            icon.TextColor3 = option.color or colors.Text
            icon.TextScaled = true
            icon.Font = Theme.fonts.Primary
            icon.Parent = optBtn
            
            -- Adjust text padding for icon
            optBtn.TextXAlignment = Enum.TextXAlignment.Left
            optBtn.Text = "      " .. option.label
        end
        
        -- Hover effect and selection
        local conns = {}
        table.insert(conns, optBtn.MouseEnter:Connect(function()
            optBtn.BackgroundTransparency = 0.2
            optBtn.BackgroundColor3 = colors.Primary
        end))
        
        table.insert(conns, optBtn.MouseLeave:Connect(function()
            optBtn.BackgroundTransparency = 0.3 -- back to initial
            optBtn.BackgroundColor3 = colors.Surface
        end))
        
        table.insert(conns, optBtn.MouseButton1Click:Connect(function()
            self:select(i)
        end))
        
        self.optionConns[i] = conns
        self.optionButtons[i] = optBtn
    end
    
    -- Set initial selection
    if self.currentIndex > 0 and self.options[self.currentIndex] then
        button.Text = self.options[self.currentIndex].label
    end
    
    -- Toggle dropdown
    table.insert(self.connections, button.MouseButton1Click:Connect(function()
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
        optBtn.Size = UDim2.new(1, -8, 0, 32)
        optBtn.BackgroundColor3 = colors.Surface
        optBtn.BackgroundTransparency = 0.3 -- Less transparent for better visibility
        optBtn.Text = option.label
        optBtn.TextColor3 = option.color or colors.Text
        optBtn.TextScaled = true
        optBtn.Font = Theme.fonts.Secondary
        optBtn.AutoButtonColor = false
        optBtn.ZIndex = self.zIndexBase + 2 -- Ensure it's above the list container
        optBtn.Parent = self.list
        
        local optCorner = Instance.new("UICorner")
        optCorner.CornerRadius = UDim.new(0, Theme.sizes.CornerRadius - 2)
        optCorner.Parent = optBtn
        
        local optTextConstraint = Instance.new("UITextSizeConstraint")
        optTextConstraint.MinTextSize = Theme.textSizes.Small.Min
        optTextConstraint.MaxTextSize = Theme.textSizes.Medium.Max
        optTextConstraint.Parent = optBtn
        
        -- Hover effect and selection
        local conns = {}
        table.insert(conns, optBtn.MouseEnter:Connect(function()
            optBtn.BackgroundTransparency = 0.2
            optBtn.BackgroundColor3 = colors.Primary
        end))
        
        table.insert(conns, optBtn.MouseLeave:Connect(function()
            optBtn.BackgroundTransparency = 0.3 -- back to initial
            optBtn.BackgroundColor3 = colors.Surface
        end))
        
        table.insert(conns, optBtn.MouseButton1Click:Connect(function()
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