--!strict
-- BannerBillboards.client.lua
-- Mounts billboard UI on banner models tagged via CollectionService

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Logger = require(MiningGame:WaitForChild("Logger"))
-- Strict Theme typing for this module
type ThemeBB = { colors: { [string]: Color3 } }
local Theme: ThemeBB = require(MiningGame:WaitForChild("UI"):WaitForChild("Theme"))
local EventBus = require(MiningGame:WaitForChild("EventBus"))
local EventNames = require(MiningGame:WaitForChild("EventNames"))

local log = Logger.new("BannerBillboards")
local ClientError = require(MiningGame:WaitForChild("ClientError"))

-- Client-side UI components live under StarterPlayerScripts (client tree), not ReplicatedStorage
local ClientRoot = script.Parent:WaitForChild("MiningGame")
local UIComponents = ClientRoot:WaitForChild("UI"):WaitForChild("Components")
local HighScoreBillboard = require(UIComponents:WaitForChild("HighScoreBillboard"))
local _BaseBillboard = require(UIComponents:WaitForChild("BaseBillboard"))

type Mount = { model: Model, destroy: (() -> ())?, ancestryConn: RBXScriptConnection? }
local mounted: { [string]: Mount } = {}
local pending: { [string]: () -> () } = {}

local function getClothId(model: Instance): string?
	local v = model:GetAttribute("ClothId")
	if type(v) == "string" then
		return v :: string
	end
	return nil
end

local function getBannerColor(m: Instance): Color3?
	local v = m:GetAttribute("BannerColor")
	if typeof(v) == "Color3" then
		return v :: Color3
	end
	return nil
end

local function getBannerCategory(m: Instance): string
	local v = m:GetAttribute("BannerCategory")
	if type(v) == "string" then
		return v :: string
	end
	return ""
end

local function getBannerFeature(m: Instance): string
	local v = m:GetAttribute("BannerFeature")
	if type(v) == "string" then
		return v :: string
	end
	return "" -- default: no feature -> no billboard
end

local function getBannerFace(m: Instance): Enum.NormalId
	local v = m:GetAttribute("BannerFace")
	if type(v) == "string" then
		local s = string.lower(v)
		if s == "front" then
			return Enum.NormalId.Front
		end
		if s == "back" then
			return Enum.NormalId.Back
		end
		if s == "left" then
			return Enum.NormalId.Left
		end
		if s == "right" then
			return Enum.NormalId.Right
		end
		if s == "top" then
			return Enum.NormalId.Top
		end
		if s == "bottom" then
			return Enum.NormalId.Bottom
		end
	end
	return Enum.NormalId.Front
end

-- No face auto-mapping: respect BannerFace from server config exactly.

local function findAdornee(model: Model): BasePart?
	-- Require explicitly oriented UI panel created server-side
	local uiPanel = model:FindFirstChild("UIPanel")
	if uiPanel and uiPanel:IsA("BasePart") then
		return uiPanel
	end
	return nil
end
local function mountBanner(model: Model, overrides: any?)
	local id: string? = (overrides and overrides.id) or getClothId(model)
	if not id then
		return
	end
	local mrec = mounted[id]
	if mrec and mrec.model == model then
		return
	end
	local adornee = findAdornee(model)
	if not adornee then
		-- Defer until UIPanel exists using signals (event-driven)
		if pending[id] then
			return
		end
		local conns = {}
		local canceled = false
		local function cleanup()
			canceled = true
			for _, c in ipairs(conns) do
				c:Disconnect()
			end
			pending[id] = nil
		end
		local function tryNow()
			local mm = mounted[id]
			if mm and mm.model == model then
				cleanup()
				return
			end
			local p = findAdornee(model)
			if p then
				cleanup()
				task.defer(function()
					mountBanner(model, overrides)
				end)
			end
		end
		conns[#conns + 1] = model:GetPropertyChangedSignal("PrimaryPart"):Connect(tryNow)
		conns[#conns + 1] = model.DescendantAdded:Connect(function(inst)
			if inst:IsA("BasePart") and inst.Name == "UIPanel" then
				tryNow()
			end
		end)
		conns[#conns + 1] = model.AncestryChanged:Connect(function(_, parent)
			-- Survive stream-out; retry on reparent so mounting is durable
			if parent then
				tryNow()
			end
		end)
		pending[id] = cleanup
		-- Immediate re-check closes race window where adornee appears just before listeners are wired
		tryNow()
		-- Initial deferral is expected during streaming; log at DEBUG.
		log:debug("UIPanel not present yet; deferring billboard mount: %s", model:GetFullName())
		-- Watchdog: warn if UIPanel still missing after timeout
		task.delay(5.0, function()
			if not canceled and not mounted[id] and not findAdornee(model) and model.Parent then
				log:warn("UIPanel still missing after 5s; billboard not mounted: %s", model:GetFullName())
			end
		end)
		return
	end

	local feature = (overrides and overrides.feature) or getBannerFeature(model)
	local accent = (overrides and overrides.color) or getBannerColor(model) or Theme.colors.Primary
	local category = (overrides and overrides.category) or getBannerCategory(model)
	-- Use face: if using UIPanel, mount on Front (vertical aligned by server).
	local face = Enum.NormalId.Front
	if adornee.Name ~= "UIPanel" then
		-- Prefer explicit override when provided; otherwise fall back to model attribute
		local faceOverride = overrides and overrides.face
		if faceOverride ~= nil then
			local resolvedFace: any = nil
			if typeof(faceOverride) == "EnumItem" then
				resolvedFace = faceOverride
			elseif type(faceOverride) == "string" then
				local s = string.lower(faceOverride)
				if s == "front" then
					resolvedFace = Enum.NormalId.Front
				elseif s == "back" then
					resolvedFace = Enum.NormalId.Back
				elseif s == "left" then
					resolvedFace = Enum.NormalId.Left
				elseif s == "right" then
					resolvedFace = Enum.NormalId.Right
				elseif s == "top" then
					resolvedFace = Enum.NormalId.Top
				elseif s == "bottom" then
					resolvedFace = Enum.NormalId.Bottom
				end
			end
			if resolvedFace ~= nil then
				face = resolvedFace
			else
				face = getBannerFace(model)
			end
		else
			face = getBannerFace(model)
		end
	end

	if feature == "HighScore" then
		local ok, hs = ClientError.try("BannerBillboards.HighScoreMount", function()
			return HighScoreBillboard.new({
				adornee = adornee,
				category = category,
				accentColor = accent,
				face = face,
			})
		end)
		if ok and hs then
			-- Handle streaming: if model streams out, destroy and clear; on reparent, remount
			local function destroy()
				ClientError.try("BannerBillboards.Destroy", function()
					hs:destroy()
					return true
				end)
			end
			local conn: RBXScriptConnection
			conn = model.AncestryChanged:Connect(function(_, parent)
				if not parent then
					-- Streamed out: tear down and mark unmounted
					-- Disconnect the connection before clearing to prevent leak
					local rec = mounted[id]
					local c = rec and rec.ancestryConn
					if c then
						c:Disconnect()
					end
					destroy()
					mounted[id] = nil
				else
					-- Streamed back in: attempt to remount if not mounted
					if not mounted[id] then
						task.defer(function()
							mountBanner(model, overrides)
						end)
					end
				end
			end)
			mounted[id] = { model = model, destroy = destroy, ancestryConn = conn }
			log:info(
				"Mounted HighScore billboard on %s (face=%s, category=%s)",
				adornee:GetFullName(),
				tostring(face),
				tostring(category)
			)
		else
			log:error("Failed to create HighScore billboard: %s", tostring(hs))
		end
	elseif feature == "Teleport" or category == "teleport" then
		-- Use HighScore-style billboard with proper header; entries provided by RF (category = "teleport")
		local ok, hs = ClientError.try("BannerBillboards.TeleportMount", function()
			return HighScoreBillboard.new({
				adornee = adornee,
				category = "teleport",
				accentColor = accent,
				face = face,
				title = "🌀 Teleport",
				limit = 5,
			})
		end)
		if ok and hs then
			local function destroy()
				ClientError.try("BannerBillboards.DestroyTeleport", function()
					hs:destroy()
					return true
				end)
			end
			local conn: RBXScriptConnection
			conn = model.AncestryChanged:Connect(function(_, parent)
				if not parent then
					-- Disconnect the connection before clearing to prevent leak
					local rec = mounted[id]
					local c = rec and rec.ancestryConn
					if c then
						c:Disconnect()
					end
					destroy()
					mounted[id] = nil
				else
					if not mounted[id] then
						task.defer(function()
							mountBanner(model, overrides)
						end)
					end
				end
			end)
			mounted[id] = { model = model, destroy = destroy, ancestryConn = conn }
			log:info("Mounted Teleport billboard on %s (face=%s)", adornee:GetFullName(), tostring(face))
		else
			log:error("Failed to create Teleport billboard: %s", tostring(hs))
		end
	else
		-- Scenic/unknown feature: skip logging when empty (expected scenic slot)
		if feature and #feature > 0 then
			log:warn("Unknown banner feature '%s' on %s", tostring(feature), model:GetFullName())
		end
	end
end

local function unmountBanner(model: Model)
	local id = getClothId(model)
	if not id then
		return
	end
	local pend = pending[id]
	if pend then
		ClientError.try("BannerBillboards.Pending", pend)
	end
	local m = mounted[id]
	if m then
		if m.ancestryConn then
			m.ancestryConn:Disconnect()
		end
		if m.destroy then
			ClientError.try("BannerBillboards.DestroyOnUnmount", m.destroy)
		end
	end
	mounted[id] = nil
end

local Bus = EventBus.global()

-- Listen for banner ready events (reliable, after full setup)
Bus:on(EventNames.BANNER_READY, function(evt)
	-- Server bridges only the payload; route is already per-player
	local banners = evt and evt.banners
	if type(banners) ~= "table" then
		return
	end
	for _, b in ipairs(banners) do
		if typeof(b) == "Instance" then
			if b:IsA("Model") then
				mountBanner(b)
			end
		elseif type(b) == "table" then
			local m = b.model
			if typeof(m) == "Instance" and m:IsA("Model") then
				mountBanner(m, b)
			end
		end
	end
end)

-- Keep CollectionService as fallback for existing banners and cleanup
CollectionService:GetInstanceRemovedSignal("Banner"):Connect(function(inst)
	if inst:IsA("Model") then
		unmountBanner(inst)
	end
end)
