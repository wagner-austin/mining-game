--!strict
-- ProximityAction.lua
-- Small helper to bind a proximity-based MainHUD action chip with E-key support.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(MiningGame:WaitForChild("Logger"))
local ClientRegistry = require(MiningGame:WaitForChild("ClientRegistry"))

local _log = Logger.new("ProximityAction")

export type BindOpts = {
	id: string,
	resolveTarget: () -> (Model | BasePart)?,
	rangeStuds: number,
	label: string,
	icon: string?,
	widthPx: number?,
	key: Enum.KeyCode?,
	canActivate: (() -> boolean)?,
	onActivate: () -> (),
}

local ProximityAction = {}

local function getMainHUD()
	local mgr = ClientRegistry.getUIManager()
	if mgr and mgr.scenes then
		return mgr.scenes.MainHUD
	end
	return nil
end

function ProximityAction.bindMainHUD(opts: BindOpts)
	assert(type(opts) == "table", "opts required")
	assert(type(opts.id) == "string" and #opts.id > 0, "id required")
	assert(type(opts.resolveTarget) == "function", "resolveTarget function required")
	assert(type(opts.rangeStuds) == "number" and opts.rangeStuds > 0, "rangeStuds > 0 required")
	assert(type(opts.label) == "string" and #opts.label > 0, "label required")
	assert(type(opts.onActivate) == "function", "onActivate required")

	local player = Players.LocalPlayer
	local character = player.Character or player.CharacterAdded:Wait()
	local hrp = character:WaitForChild("HumanoidRootPart") :: BasePart

	local mainHUD
	-- Wait for MainHUD asynchronously without blocking
	task.spawn(function()
		while not mainHUD do
			mainHUD = getMainHUD()
			if mainHUD then
				break
			end
			task.wait(0.1)
		end
	end)

	local shown = false
	local hbConn

	local function hide()
		if shown and mainHUD and mainHUD.hideActionChip then
			mainHUD:hideActionChip()
		end
		shown = false
	end

	hbConn = RunService.Heartbeat:Connect(function()
		if not hrp.Parent then
			return
		end
		local target = opts.resolveTarget()
		if not target then
			if shown then
				hide()
			end
			return
		end

		local pos: Vector3
		if target:IsA("Model") then
			local pp = target.PrimaryPart
			if not pp then
				-- Derive from model center
				local cf = target:GetPivot()
				pos = cf.Position
			else
				pos = pp.Position
			end
		else
			pos = target.Position
		end

		local dist = (pos - hrp.Position).Magnitude
		if dist <= opts.rangeStuds then
			if not shown and mainHUD and mainHUD.showActionChip then
				shown = true
				mainHUD:showActionChip(opts.label, opts.icon, function()
					if opts.canActivate and not opts.canActivate() then
						return
					end
					opts.onActivate()
				end, opts.widthPx)
			end
		else
			if shown then
				hide()
			end
		end
	end)

	-- Clean up on character respawn
	local charConn
	charConn = player.CharacterAdded:Connect(function(newChar)
		character = newChar
		hrp = character:WaitForChild("HumanoidRootPart") :: BasePart
	end)

	return {
		unbind = function()
			hide()
			if hbConn then
				hbConn:Disconnect()
			end
			if charConn then
				charConn:Disconnect()
			end
		end,
	}
end

return ProximityAction
