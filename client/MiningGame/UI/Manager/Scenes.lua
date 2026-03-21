--!strict
-- Scenes.lua: scene registration and navigation for UIManager

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local _Players = game:GetService("Players")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UI = MiningGame:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local UIUtils = require(UI:WaitForChild("UIUtils"))
local UIx = require(UI:WaitForChild("UIConstants"))
local ClientError = require(MiningGame:WaitForChild("ClientError"))
local Time = require(MiningGame:WaitForChild("Time"))
local Logger = require(MiningGame:WaitForChild("Logger"))
local log = Logger.new("UIManager.Scenes")

local Layers = require(script.Parent:WaitForChild("Layers"))
local Types = require(script.Parent:WaitForChild("Types"))
type UIManagerT = Types.UIManagerT
type SceneT = Types.SceneT

local Scenes = {}

local function getCooldownSeconds(): number
	local t1 = Theme.animations.Standard.Time or 0.25
	local t2 = Theme.animations.Quick.Time or 0.15
	local t3 = Theme.animations.Smooth.Time or 0.35
	return math.max(t1, t2, t3) * 0.9
end

function Scenes.registerScene(self: UIManagerT, scene: SceneT)
	UIUtils.validateScene(scene)
	self.scenes[scene.name] = scene
	log:debug("Registered scene: %s", scene.name)
end

function Scenes.showScene(self: UIManagerT, sceneName: string, ...)
	local scene = self.scenes[sceneName]
	if not scene then
		log:warn("Scene not found: %s", sceneName)
		return
	end

	if self.activeScene == scene then
		Scenes.hideScene(self, sceneName)
		return
	end

	if Time.mono() < (self._transitionUnlockAt or 0) then
		return
	end
	self._transitionUnlockAt = Time.mono() + getCooldownSeconds()

	if not scene.frame then
		scene:init(self)
	end

	for i = #self.sceneStack, 1, -1 do
		local s = self.sceneStack[i]
		if s and s.name == scene.name then
			table.remove(self.sceneStack, i)
			break
		end
	end

	if self.activeScene then
		table.insert(self.sceneStack, self.activeScene)
		self.activeScene:hide()
	end

	scene:show(...)
	self.activeScene = scene
	log:info("Showing scene: %s", sceneName)
end

function Scenes.hideScene(self: UIManagerT, sceneName: string)
	local scene = self.scenes[sceneName]
	if not scene then
		return
	end

	scene:hide()

	if self.activeScene == scene then
		self.activeScene = nil
		local prev = table.remove(self.sceneStack)
		if prev then
			prev:show()
			self.activeScene = prev
			log:info("Returning to scene: %s", prev.name)
		elseif self.scenes["MainHUD"] then
			local hud = self.scenes["MainHUD"]
			if not hud.frame then
				hud:init(self)
			end
			hud:show()
			self.activeScene = hud
		end
	else
		for i = #self.sceneStack, 1, -1 do
			local s = self.sceneStack[i]
			if s and s.name == scene.name then
				table.remove(self.sceneStack, i)
				break
			end
		end
	end

	task.defer(function()
		if not Layers.anyUIVisible(self) then
			log:debug("No UI visible after hideScene, recovering immediately")
			Scenes.showMainHUDNow(self)
		end
	end)
end

function Scenes.hideAllScenes(self: UIManagerT)
	for _, s in pairs(self.scenes) do
		if s.frame then
			s:hide()
		end
	end
	self.sceneStack = {}
	self.activeScene = nil
end

function Scenes.showMainHUDNow(self: UIManagerT)
	if self._isRecovering then
		return
	end
	self._isRecovering = true

	Layers.ensureRootsExist(self)

	if self.overlayGui then
		for _, child in ipairs(self.overlayGui:GetChildren()) do
			child:Destroy()
		end
	end

	for _name, scene in pairs(self.scenes) do
		local s = scene
		if s and s.hide then
			ClientError.try("UIManager", function()
				s:hide()
			end)
		end
	end
	self.sceneStack = {}
	self.activeScene = nil

	local hud = self.scenes["MainHUD"]
	if hud then
		if not hud.frame then
			ClientError.try("UIManager", function()
				hud:init(self)
			end)
		end
		ClientError.try("UIManager", function()
			hud:show()
		end)
		self.activeScene = hud
		self._transitionUnlockAt = 0
		local up = self.updateToastPosition
		if up then
			up(self)
		end

		local sg = self.screenGui
		if sg then
			for _, child in ipairs(sg:GetChildren()) do
				if child:IsA("TextButton") and child.Text == "Tap to recover UI" then
					child:Destroy()
				end
			end
		end

		self._watchdogLastVisibleAt = Time.mono() + 2
		log:debug("Watchdog recovered UI by showing MainHUD")
	else
		local btn = Instance.new("TextButton")
		btn.Text = "Tap to recover UI"
		btn.Size = UDim2.fromOffset(UIx.Size.BUTTON_WIDTH, UIx.Size.BUTTON_LARGE_HEIGHT)
		btn.AnchorPoint = Vector2.new(0.5, 0.5)
		btn.Position = UDim2.fromScale(0.5, 0.5)
		btn.BackgroundColor3 = Theme.colors.Surface
		btn.TextColor3 = Theme.colors.Text
		btn.Font = Theme.fonts.Primary
		btn.TextSize = UIx.Visual.TEXT_LARGE
		if self.screenGui then
			btn.Parent = self.screenGui
		end
		btn.Activated:Connect(function()
			btn:Destroy()
			Scenes.showMainHUDNow(self)
		end)
		log:warn("No MainHUD scene registered; showing recovery button")
	end

	task.defer(function()
		self._isRecovering = false
	end)
end

return Scenes
