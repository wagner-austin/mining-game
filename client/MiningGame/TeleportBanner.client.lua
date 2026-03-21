--!strict
-- TeleportBanner.client.lua
-- Shows an ActionChip near the Teleport banner to teleport the player to a random sky position.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(MiningGame:WaitForChild("Logger"))
local EventBus = require(MiningGame:WaitForChild("EventBus"))
local EventNames = require(MiningGame:WaitForChild("EventNames"))
local RequestNames = require(MiningGame:WaitForChild("RequestNames"))
-- Client RemoteEventBridge lives under PlayerScripts.MiningGame
local RemoteEventBridge = require(script.Parent:WaitForChild("RemoteEventBridge"))
-- Strict Theme typing mirrors actual Theme.lua shape
local _Theme = require(MiningGame:WaitForChild("UI"):WaitForChild("Theme"))
type ThemeTB = typeof(_Theme)
local Theme: ThemeTB = _Theme
local ProximityAction = require(script.Parent:WaitForChild("ProximityAction"))
local ClientError = require(MiningGame:WaitForChild("ClientError"))

local log = Logger.new("TeleportBannerAction")
local Bus = EventBus.global()

-- Track bindings so we don't bind twice for the same model
local bindings: { [Instance]: { unbind: () -> () } } = {}

local function bindForBanner(model: Model)
	if bindings[model] then
		return
	end
	local rangeStuds = 16
	local binding = ProximityAction.bindMainHUD({
		id = "teleport_banner",
		resolveTarget = function()
			if not model or not model.Parent then
				return nil
			end
			local panel = model:FindFirstChild("UIPanel")
			if panel and panel:IsA("BasePart") then
				return panel
			end
			return (model.PrimaryPart or model)
		end,
		widthPx = (Theme.homeButton.width + 50),
		rangeStuds = rangeStuds,
		label = "Teleport",
		icon = Theme.icons.home or "🧭",
		onActivate = function()
			RemoteEventBridge.send(RequestNames.TELEPORT_RANDOM_SKY, {})
		end,
	})
	bindings[model] = binding
	model.Destroying:Connect(function()
		local b = bindings[model]
		bindings[model] = nil
		if b and b.unbind then
			ClientError.try("TeleportBanner.unbind", b.unbind)
		end
	end)
	log:info("Bound teleport action to %s", model:GetFullName())
end

-- Listen for banner ready events, bind for feature = "Teleport" or category = "teleport"
Bus:on(EventNames.BANNER_READY, function(evt)
	local banners = evt and evt.banners
	if type(banners) ~= "table" then
		return
	end
	for _, b in ipairs(banners) do
		local m = (typeof(b) == "Instance" and b) or (type(b) == "table" and b.model) or nil
		if typeof(m) == "Instance" and m:IsA("Model") then
			local feature = (type(b) == "table" and b.feature) or (m:GetAttribute("BannerFeature") or "")
			local category = (type(b) == "table" and b.category) or (m:GetAttribute("BannerCategory") or "")
			feature = tostring(feature)
			category = tostring(category)
			if feature == "Teleport" or category == "teleport" then
				bindForBanner(m)
			end
		end
	end
end)
