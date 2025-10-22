--!strict
-- DebugTab.lua
-- Debug controls for testing and development (Studio-only)
-- Migrated to use BaseTabComponent for consistent UI patterns

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Theme = require(MiningGame:WaitForChild("UI"):WaitForChild("Theme"))
local Logger = require(MiningGame:WaitForChild("Logger"))
local GameConfig = require(MiningGame:WaitForChild("GameConfig"))
local ClientRF = require(MiningGame:WaitForChild("ClientRF"))
local UIConstants = require(MiningGame:WaitForChild("UI"):WaitForChild("UIConstants"))

-- Shorthand
local UIx = UIConstants

local BaseTabComponent = require(script.Parent:WaitForChild("BaseTabComponent"))

-- Client error ring (loaded from PlayerScripts)
local ClientError = require(Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("ClientErrorHandler"))

local log = Logger.new("DebugTab")

local DebugTab = {}
DebugTab.__index = DebugTab
setmetatable(DebugTab, { __index = BaseTabComponent })

-- Helper for cleaner RF status handling with optional message builder
local function rfStatus(self, okMsgOrFn)
    return function(data, err)
        if err then
            self:_showStatus("✗ " .. err, true)
        else
            local msg = type(okMsgOrFn) == "function" and okMsgOrFn(data) or okMsgOrFn
            self:_showStatus("✓ " .. (msg or "Success"), false)
        end
    end
end

type Config = {
    parent: Frame,
    position: UDim2?,
    size: UDim2?,
    portalParent: Frame?,
}

type DebugTabT = typeof(setmetatable({} :: any, DebugTab)) & {
    _resetConfirm: boolean,
    _statusTimeout: thread?,
    _statusCard: Frame?,
    _statusLabel: TextLabel?,
    _statusIsError: boolean?,
    _simCard: Frame?,
    _maxAgentCount: number,
    _currentStrategy: string,
    _strategies: {string},
    _countBox: TextBox?,
    _strategyLabel: TextLabel?,
    _toggleBtn: TextButton?,
    new: (config: Config) -> DebugTabT,
}

function DebugTab.new(config: Config): DebugTabT
    -- Initialize base component
    local self = setmetatable(BaseTabComponent.new({
        parent = config.parent,
        position = config.position,
        size = config.size,
        portalParent = config.portalParent,
        stacked = true,
        name = "DebugTab",
    }), DebugTab)
    
    -- Tab-specific state
    self._resetConfirm = false
    self._statusTimeout = nil
    self._statusCard = nil
    self._statusLabel = nil
    
    -- Build UI
    self:_createStatusSection()
    self:_createCubeSection()
    self:_createCurrencySection()
    self:_createStatsSection()
    self:_createSimAgentsSection()
    
    -- Floating Islands section removed
    
    -- Client Errors section removed (was Studio-only)
    
    -- Setup hotkeys for SimAgents
    self:_setupHotkeys()
    
    return self :: any
end

-- Status feedback system
function DebugTab:_createStatusSection()
    local statusCard = self:createSectionCard(self.container, { layoutOrder = 0 })
    statusCard.Name = "StatusCard"
    statusCard.Visible = false
    
    local statusLabel = self:createLabel(statusCard, "", {
        size = UDim2.new(1, 0, 0, UIx.Size.ROW_STANDARD),
        alignment = Enum.TextXAlignment.Center
    })
    statusLabel.Name = "StatusLabel"
    
    self._statusCard = statusCard
    self._statusLabel = statusLabel
    self._statusIsError = false
    
    -- Register theme updater for dynamic status color
    self:_addThemeUpdater(function()
        if self._statusCard then
            self._statusCard.BackgroundColor3 = self._statusIsError and self._theme.colors.Error or self._theme.colors.Success
        end
    end)
end

function DebugTab:_showStatus(message: string, isError: boolean?)
    if not self._statusCard or not self._statusLabel then return end
    
    self._statusIsError = not not isError -- Convert to boolean
    self._statusCard.Visible = true
    self._statusCard.BackgroundColor3 = isError and self._theme.colors.Error or self._theme.colors.Success
    self._statusLabel.Text = message
    
    -- Cancel previous timeout
    if self._statusTimeout then
        self:clearTimeout(self._statusTimeout)
    end
    
    -- Auto-hide after 3 seconds
    self._statusTimeout = self:setTimeout(3, function()
        if self._statusCard and self._statusLabel.Text == message then
            self._statusCard.Visible = false
        end
        self._statusTimeout = nil
    end)
end

-- Cube Controls Section
function DebugTab:_createCubeSection()
    local card = self:createSectionCard(self.container, { layoutOrder = 1, name = "CubeControlsCard" })
    self:createSectionTitle(card, "Cube Controls")
    
    -- Destructive reset button with danger styling
    self:createButton(card, "Reset Cube (Wipes Progress!)", function()
        if self._resetConfirm then
            -- Second click - actually reset
            local data, err = ClientRF.call("Cube_ResetFull")
            self._resetConfirm = false
            rfStatus(self, "Cube reset to fresh state!")(data, err)
        else
            -- First click - ask for confirmation
            self._resetConfirm = true
            self:_showStatus("⚠️ ?? Click again to confirm WIPE", true)
            self:setTimeout(3, function()
                self._resetConfirm = false
            end)
        end
    end, { variant = "danger", layoutOrder = 2 })
    
    -- Teleport Home button
    self:createButton(card, "Teleport to Spawn", function()
        local data, err = ClientRF.call("TeleportToHome")
        rfStatus(self, "Teleported to spawn!")(data, err)
    end, { layoutOrder = 3 })
end

-- Currency Section
function DebugTab:_createCurrencySection()
    local card = self:createSectionCard(self.container, { layoutOrder = 2 })
    self:createSectionTitle(card, "Currency Cheats")
    
    -- Add Coins button
    self:createButton(card, "Add 1000 Coins", function()
        local data, err = ClientRF.call("DebugAddCurrency", "coins", 1000)
        rfStatus(self, "Added 1000 coins!")(data, err)
    end, { layoutOrder = 1 })
    
    -- Add Gems button
    self:createButton(card, "Add 100 Gems", function()
        local data, err = ClientRF.call("DebugAddCurrency", "gems", 100)
        rfStatus(self, "Added 100 gems!")(data, err)
    end, { layoutOrder = 2 })
end

-- Stats Section
function DebugTab:_createStatsSection()
    local card = self:createSectionCard(self.container, { layoutOrder = 3 })
    self:createSectionTitle(card, "Player Stats")
    
    -- Reset Stats button
    self:createButton(card, "Reset All Stats", function()
        local data, err = ClientRF.call("DebugResetStats")
        rfStatus(self, "Stats reset successfully!")(data, err)
    end, { layoutOrder = 1 })

    -- Reset Inventory (moved here; wipes items and equipped)
    self:createButton(card, "Reset Inventory (Wipes Items)", function()
        local data, err = ClientRF.call("DebugResetInventory")
        rfStatus(self, function(d) return (d and d.message) or "Inventory reset" end)(data, err)
    end, { variant = "danger", layoutOrder = 1 })
end

-- Inventory & Index Section
-- Inventory & Index section removed; Reset Inventory moved under Player Stats

-- SimAgents Section (Studio Only)
function DebugTab:_createSimAgentsSection()
    local card = self:createSectionCard(self.container, { layoutOrder = 99 })
    self:createSectionTitle(card, "Sim Agents (Studio)")
    
    -- Store references for hotkeys
    self._simCard = card
    self._maxAgentCount = 25
    self._currentStrategy = "grid"
    self._strategies = {"grid", "grid_altitude_noise", "grid_terrain_snap"}
    
    -- Row with TextBox + Set button  
    local row = self:createRow(card, UIx.Size.BUTTON_SMALL_HEIGHT)
    row.LayoutOrder = 1  -- After title
    
    -- Count text box
    self._countBox = self:createTextBox(row, "Count", "9", {
        size = UIx.px(80, UIx.Size.BUTTON_SMALL_HEIGHT)
    })
    
    -- Set button
    self:createButton(row, "Set Agents", function()
        local n = tonumber(self._countBox.Text) or 0
        local data, err = ClientRF.call("SimAgents_SetCount", math.clamp(n, 0, self._maxAgentCount))
        if not err and data and data.count then
            self:_showStatus("✓ SimAgents set to " .. tostring(data.count), false)
            self._countBox.Text = tostring(data.count)
        else
            self:_showStatus("✗ Failed to set agents" .. (err and ": " .. err or ""), true)
        end
    end, { width = 120 })
    
    -- Spawn Strategy controls
    self._strategyLabel = self:createLabel(card, "Spawn Strategy: Loading...", {
        isDim = true,
        layoutOrder = 2
    })
    
    -- Load current strategy
    task.spawn(function()
        local listData, listErr = ClientRF.call("SpawnStrategy_List")
        if not listErr and listData and listData.strategies then
            self._strategies = listData.strategies
            log:debug("Loaded spawn strategies: %s", table.concat(listData.strategies, ", "))
        end
        
        local getData, getErr = ClientRF.call("SpawnStrategy_Get")
        if not getErr and getData and getData.current then
            self._currentStrategy = getData.current
            log:debug("Current spawn strategy: %s", getData.current)
        end
        
        self:_updateStrategyDisplay()
    end)
    
    -- Change Strategy button
    self:createButton(card, "Next Spawn Strategy", function()
        self:_cycleSpawnStrategy()
    end, { layoutOrder = 2 })
    
    -- Respawn All button
    self:createButton(card, "Respawn All SimAgents", function()
        local data, err = ClientRF.call("SimAgents_RespawnAll")
        rfStatus(self, "Respawned all SimAgents")(data, err)
    end, { layoutOrder = 4 })
    
    -- Clear button
    self:createButton(card, "Clear SimAgents", function()
        local data, err = ClientRF.call("SimAgents_Clear")
        if not err then
            self._countBox.Text = "0"
        end
        rfStatus(self, "Cleared SimAgents")(data, err)
    end, { layoutOrder = 5 })
    
    -- Toggle terrain cubes button
    self._toggleBtn = self:createButton(card, "Use Terrain Cubes: ...", function()
        self:_toggleTerrainCubes()
    end, { layoutOrder = 6 })
    
    -- Initialize UI from server status
    task.spawn(function()
        local status, err = ClientRF.call("SimAgents_GetStatus")
        if not err and status then
            self._maxAgentCount = status.maxCount or 25
            self._toggleBtn.Text = "Use Terrain Cubes: " .. (status.useTerrainCubes and "On" or "Off")
            self._countBox.Text = tostring(status.count)
            
            -- Display additional status info
            if status.playerCount then
                self:createLabel(card, "Real Players: " .. status.playerCount, { isDim = true })
            end
            
            if not status.enabled then
                self:createLabel(card, "⚠️ SimAgents disabled (not in Studio)")
                card.Visible = false -- Hide the section outside Studio
            end
        else
            card.Visible = false -- Hide if we can't get status
        end
    end)
end

-- Removed _createInlineButton - using BaseTabComponent:createButton instead which already has width support

function DebugTab:_updateStrategyDisplay()
    if self._strategyLabel then
        self._strategyLabel.Text = "Spawn Strategy: " .. self._currentStrategy
    end
end

function DebugTab:_cycleSpawnStrategy()
    local idx = 1
    for i, s in ipairs(self._strategies) do
        if s == self._currentStrategy then
            idx = i
            break
        end
    end
    self._currentStrategy = self._strategies[(idx % #self._strategies) + 1]
    self:_updateStrategyDisplay()
    
    -- Apply to server
    local data, err = ClientRF.call("SpawnStrategy_Set", self._currentStrategy)
    
    if not err and data then
        self:_showStatus("✓ Strategy: " .. (data.current or self._currentStrategy), false)
        
        -- Recompute positions under the new strategy
        task.spawn(function()
            ClientRF.call("SimAgents_RespawnAll")
        end)
    else
        self:_showStatus("✗ Strategy change failed: " .. (err or "Unknown error"), true)
        -- Revert display
        task.spawn(function()
            local getData, getErr = ClientRF.call("SpawnStrategy_Get")
            if not getErr and getData and getData.current then
                self._currentStrategy = getData.current
                self:_updateStrategyDisplay()
            end
        end)
    end
end

function DebugTab:_toggleTerrainCubes()
    local status, err = ClientRF.call("SimAgents_GetStatus")
    if not err and status then
        local want = not status.useTerrainCubes
        local data2, err2 = ClientRF.call("SimAgents_SetTerrainCubes", want)
        if not err2 then
            self._toggleBtn.Text = "Use Terrain Cubes: " .. (want and "On" or "Off")
            self:_showStatus("✓ Terrain cubes " .. (want and "enabled" or "disabled"), false)
        else
            self:_showStatus("✗ Toggle failed: " .. err2, true)
        end
    else
        self:_showStatus("✗ Status unavailable" .. (err and ": " .. err or ""), true)
    end
end

-- Floating Islands Section
-- DebugTab:_createIslandsSection removed
    --[[ legacy islands UI removed
    local card = self:createSectionCard(self.container, { layoutOrder = 5 })
    self:createSectionTitle(card, "🏝️ Floating Islands")
    
    -- Spawn Medium Island button
    self:createButton(card, "Spawn Medium Island", function()
        local data, err = ClientRF.call("Debug_SpawnIsland", { 
            preset = "medium", 
            theme = "underwater_cave" 
        })
        rfStatus(self, "Spawned floating island!")(data, err)
    end, { layoutOrder = 1 })
    
    -- Spawn Large Island button
    self:createButton(card, "Spawn Large Island", function()
        local data, err = ClientRF.call("Debug_SpawnIsland", { 
            preset = "large", 
            theme = "underwater_cave" 
        })
        rfStatus(self, "Spawned large island!")(data, err)
    end, { layoutOrder = 2 })
    ]]

-- Client Errors section removed

-- Setup hotkeys for SimAgents control
function DebugTab:_setupHotkeys()
    local function bumpAgentCount(actionName, state, delta)
        if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
        
        local status, err = ClientRF.call("SimAgents_GetStatus")
        if err or not status or not status.enabled then 
            return Enum.ContextActionResult.Pass
        end
        
        local currentCount = status.count or 0
        local newCount = math.clamp(currentCount + delta, 0, status.maxCount or 25)
        
        local data, err2 = ClientRF.call("SimAgents_SetCount", newCount)
        
        if not err2 and data then
            if self._countBox then
                self._countBox.Text = tostring(data.count or newCount)
            end
            self:_showStatus("SimAgents: " .. tostring(data.count or newCount), false)
        end
        
        return Enum.ContextActionResult.Sink
    end
    
    -- Bind hotkeys: = and ] to increase, - and [ to decrease
    ContextActionService:BindAction(
        "SimAgentsIncrease",
        function(name, state, input)
            return bumpAgentCount(name, state, 1)
        end,
        false,
        Enum.KeyCode.Equals,
        Enum.KeyCode.RightBracket
    )
    
    ContextActionService:BindAction(
        "SimAgentsDecrease",
        function(name, state, input)
            return bumpAgentCount(name, state, -1)
        end,
        false,
        Enum.KeyCode.Minus,
        Enum.KeyCode.LeftBracket
    )
    
    -- Store cleanup action
    self:addConnection({
        Disconnect = function()
            ContextActionService:UnbindAction("SimAgentsIncrease")
            ContextActionService:UnbindAction("SimAgentsDecrease")
        end
    })
end

-- Override destroy for tab-specific cleanup
function DebugTab:destroy()
    -- Cancel status timeout
    if self._statusTimeout then
        task.cancel(self._statusTimeout)
        self._statusTimeout = nil
    end
    
    -- Client errors poll
    if self._clientErrorsConn then
        self._clientErrorsConn:Disconnect()
        self._clientErrorsConn = nil
    end
    
    -- Clear tab-specific references
    self._statusCard = nil
    self._statusLabel = nil
    self._statusIsError = nil
    self._countBox = nil
    self._toggleBtn = nil
    self._strategyLabel = nil
    self._simCard = nil
    
    -- Call base destroy (handles connections, container, theme cleanup)
    BaseTabComponent.destroy(self)
end

return DebugTab

