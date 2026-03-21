--!strict
-- TreeClimbing.client.lua
-- Shows a HUD chip to climb trees when nearby (via ProximityAction)

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(MiningGame:WaitForChild("Logger"))
local ProximityAction = require(script.Parent:WaitForChild("ProximityAction"))
local ClientRegistry = require(MiningGame:WaitForChild("ClientRegistry"))

local log = Logger.new("TreeClimbing")

local player = Players.LocalPlayer

-- Configuration
local DETECTION_RANGE = 25 -- studs from trunk
local TELEPORT_HEIGHT_OFFSET = 10 -- studs above top

-- Helpers
local function getTreeTop(treeModel: Model): Vector3?
	local highestY = -math.huge
	local highestPos: Vector3? = nil
	for _, part in ipairs(treeModel:GetDescendants()) do
		if part:IsA("BasePart") and part.Name:lower():find("leaf") then
			if part.Position.Y > highestY then
				highestY = part.Position.Y
				highestPos = part.Position
			end
		end
	end
	if not highestPos then
		for _, part in ipairs(treeModel:GetDescendants()) do
			if part:IsA("BasePart") then
				if part.Position.Y > highestY then
					highestY = part.Position.Y
					highestPos = part.Position
				end
			end
		end
	end
	return highestPos
end

local function resolveNearbyTree(): Model?
	local character = player.Character or player.CharacterAdded:Wait()
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return nil
	end
	local decorFolder = Workspace:FindFirstChild("BlockDecorations")
	if not decorFolder then
		return nil
	end
	for _, child in ipairs(decorFolder:GetChildren()) do
		if child:IsA("Model") and child.Name:find("Tree") then
			for _, part in ipairs(child:GetDescendants()) do
				if part:IsA("BasePart") and part.Material == Enum.Material.Wood then
					if (part.Position - hrp.Position).Magnitude <= DETECTION_RANGE then
						return child
					end
				end
			end
		end
	end
	return nil
end

local _binding = ProximityAction.bindMainHUD({
	id = "tree_climb",
	resolveTarget = resolveNearbyTree,
	rangeStuds = DETECTION_RANGE,
	label = "Climb",
	icon = "🌳",
	onActivate = function()
		local tree = resolveNearbyTree()
		if not tree then
			return
		end
		local character = player.Character or player.CharacterAdded:Wait()
		local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp then
			return
		end
		local top = getTreeTop(tree)
		if top then
			local targetPos = top + Vector3.new(0, TELEPORT_HEIGHT_OFFSET, 0)
			hrp.CFrame = CFrame.new(targetPos)
			-- Hide the chip immediately; helper will re-show if still in range
			local mgr = ClientRegistry.getUIManager()
			local hud = mgr and mgr.scenes and mgr.scenes.MainHUD
			if hud and hud.hideActionChip then
				hud:hideActionChip()
			end
			log:info("Teleported to tree top at (%.1f, %.1f, %.1f)", targetPos.X, targetPos.Y, targetPos.Z)
		else
			log:warn("Could not find tree top for %s", tree.Name)
		end
	end,
})
