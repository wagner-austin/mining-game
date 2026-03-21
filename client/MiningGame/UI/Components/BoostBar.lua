--!strict
-- BoostBar.lua
-- Bottom-right dynamic group of boost badges (chips) showing active effects

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UIx = require(MiningGame:WaitForChild("UI"):WaitForChild("UIConstants"))
local BaseChip = require(script.Parent:WaitForChild("BaseChip"))
local BoostDefs = require(MiningGame:WaitForChild("BoostDefs"))
local _Time = require(MiningGame:WaitForChild("Time"))
local CharacterStateClient = require(MiningGame:WaitForChild("Character"):WaitForChild("CharacterStateClient"))
local ClientRegistry = require(MiningGame:WaitForChild("ClientRegistry"))
local ClientError = require(MiningGame:WaitForChild("ClientError"))

type Chip = {
	container: GuiObject,
	setIcon: (self: Chip, icon: string) -> (),
	setText: (self: Chip, text: string) -> (),
	destroy: (self: Chip) -> (),
}

type State = {
	frame: Frame?,
	chips: { [string]: Chip },
	conn: RBXScriptConnection?,
	timerConn: RBXScriptConnection?,
}

local state: State = {
	frame = nil,
	chips = {},
	conn = nil,
	timerConn = nil,
}

local function ensureUI(parent: GuiObject)
	if state.frame and state.frame.Parent then
		return
	end
	local frame = Instance.new("Frame")
	frame.Name = "BoostBar"
	frame.BackgroundTransparency = 1
	frame.AnchorPoint = Vector2.new(1, 1)
	frame.Size = UDim2.new(0, 420, 0, 52)
	frame.Position = UDim2.new(1, -UIx.Spacing.XL, 1, -UIx.Spacing.XL)
	frame.ZIndex = 2
	frame.Parent = parent
	state.frame = frame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Padding = UDim.new(0, UIx.Spacing.SM)
	layout.Parent = frame
end

local function refresh()
	local frame = state.frame
	if not frame then
		return
	end
	local effects = CharacterStateClient.getEffects()
	local seen: { [string]: boolean } = {}

	for id, _ in pairs(effects) do
		local sid = tostring(id)
		local def = BoostDefs.get(sid)
		if def then
			seen[sid] = true
			local chip = state.chips[sid]
			if not chip then
				local newChipInst = BaseChip.new({
					parent = frame,
					icon = def.icon,
					iconSize = UIx.Size.ROW_MEDIUM - UIx.Spacing.XS,
					iconPaddingTop = 1,
					text = "",
					align = "center",
					pulseOnUpdate = false,
					innerPadding = UIx.Spacing.NONE,
					size = UDim2.new(0, UIx.Size.ROW_MEDIUM + UIx.Spacing.SM, 0, UIx.Size.ROW_MEDIUM),
				})
				local newChip: Chip = {
					container = newChipInst.container,
					setIcon = function(_self: Chip, icon: string)
						newChipInst:setIcon(icon)
					end,
					setText = function(_self: Chip, text: string)
						newChipInst:setText(text)
					end,
					destroy = function(_self: Chip)
						newChipInst:destroy()
					end,
				}
				state.chips[sid] = newChip
				chip = newChip

				local chipGui = newChip.container
				if chipGui and not chipGui:GetAttribute("HoverInfoBound") then
					chipGui:SetAttribute("HoverInfoBound", true)
					chipGui.MouseEnter:Connect(function()
						local mgr = ClientRegistry.getUIManager()
						local fn = mgr and mgr.showMiniPopup
						if fn then
							local defB = BoostDefs.get(sid)
							local msg = (BoostDefs.label and BoostDefs.label(sid))
								or (defB and defB.baseLabel)
								or "Boost"
							local pos = UDim2.fromOffset(chipGui.AbsolutePosition.X, chipGui.AbsolutePosition.Y)
							fn(mgr :: any, msg, defB and defB.icon or "", pos)
						end
					end)
					chipGui.MouseLeave:Connect(function()
						local mgr = ClientRegistry.getUIManager()
						local fn = mgr and mgr.hideMiniPopup
						if fn then
							fn(mgr :: any)
						end
					end)
				end
			else
				chip:setIcon(def.icon)
				chip:setText("")
			end
		end
	end

	for sid, chip in pairs(state.chips) do
		if not seen[sid] then
			ClientError.try("BoostBar.ChipDestroy", function()
				chip:destroy()
			end)
			state.chips[sid] = nil
		end
	end
end

local function mount(parent: GuiObject)
	ensureUI(parent)
	if state.conn then
		state.conn:Disconnect()
		state.conn = nil
	end
	state.conn = CharacterStateClient.changed():Connect(refresh)
	refresh()
	if state.timerConn then
		state.timerConn:Disconnect()
		state.timerConn = nil
	end
	state.timerConn = RunService.Heartbeat:Connect(function() end)
end

local function unmount()
	if state.conn then
		state.conn:Disconnect()
		state.conn = nil
	end
	if state.timerConn then
		state.timerConn:Disconnect()
		state.timerConn = nil
	end
	for _, chip in pairs(state.chips) do
		ClientError.try("BoostBar.ChipDestroy", function()
			chip:destroy()
		end)
	end
	state.chips = {}
	if state.frame then
		state.frame:Destroy()
		state.frame = nil
	end
end

export type BoostBarAPI = { mount: (parent: GuiObject) -> (), unmount: () -> () }

return {
	mount = mount,
	unmount = unmount,
} :: BoostBarAPI
