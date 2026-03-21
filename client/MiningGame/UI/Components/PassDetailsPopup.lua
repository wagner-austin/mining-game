--!strict
-- PassDetailsPopup.lua
-- Compact details popup for Gamepasses (permanent upgrades via Robux)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MG = ReplicatedStorage:WaitForChild("MiningGame")
local UI = MG:WaitForChild("UI")
-- Strict Theme typing mirrors actual Theme.lua
local _Theme = require(UI:WaitForChild("Theme"))
type ThemePDP = typeof(_Theme)
local Theme: ThemePDP = _Theme
local UIx = require(UI:WaitForChild("UIConstants"))
local ThemeRefresher = require(UI:WaitForChild("ThemeRefresher"))
local UIFactory = require(UI:WaitForChild("Factory"))
local BaseInfoPopup = require(script.Parent:WaitForChild("BaseInfoPopup"))
local UIUtils = require(UI:WaitForChild("UIUtils"))
local ClientRF = require(MG:WaitForChild("ClientRF"))
local GameConfig = require(MG:WaitForChild("GameConfig"))
local ClientError = require(MG:WaitForChild("ClientError"))
local Types = require(MG:WaitForChild("Types"))

-- Class table must be defined before type uses it
local PassDetailsPopup = {}
PassDetailsPopup.__index = PassDetailsPopup

type Props = { parent: Instance, passId: string }
type PassDef = { id: string, name: string?, robux: number?, effects: { [string]: Types.JsonValue }? }

export type PassDetailsPopupT = {
	_scrim: Instance?,
	_card: Frame?,
	new: (props: Props) -> PassDetailsPopupT,
	destroy: (self: PassDetailsPopupT) -> (),
}

local function findPass(passId: string): PassDef?
	local list = (GameConfig.Monetization and GameConfig.Monetization.GAMEPASSES) or {}
	for _, p in ipairs(list) do
		if p.id == passId then
			return p
		end
	end
	return nil
end

local function isAssetString(s: Types.JsonValue): boolean
	if typeof(s) ~= "string" then
		return false
	end
	if s == "" then
		return false
	end
	return s:match("^rbxassetid://%d+$") ~= nil
		or s:match("^rbxasset://") ~= nil
		or s:match("^https?://") ~= nil
		or s:match("^%d+$") ~= nil
end

local function row(parent: Instance, label: string, value: string)
	local r = Instance.new("Frame")
	r.BackgroundTransparency = 1
	r.Size = UDim2.new(1, 0, 0, UIx.Size.ROW_SMALL)
	r.Parent = parent

	local l = UIFactory.label({
		parent = r,
		text = label,
		size = UDim2.new(0.4, -UIx.Spacing.MD, 1, 0),
		alignment = Enum.TextXAlignment.Left,
		textSize = UIx.Visual.TEXT_MEDIUM,
		isDim = true,
	})
	l.Font = Theme.fonts.Secondary

	UIFactory.label({
		parent = r,
		text = value,
		size = UDim2.new(0.6, 0, 1, 0),
		position = UDim2.new(0.4, UIx.Spacing.MD, 0, 0),
		alignment = Enum.TextXAlignment.Left,
		textSize = UIx.Visual.TEXT_MEDIUM,
		isDim = false,
	})
end

function PassDetailsPopup.new(props: Props): PassDetailsPopupT
	local self: PassDetailsPopupT = setmetatable({} :: any, PassDetailsPopup)
	local pass: PassDef? = findPass(props.passId)
	if not pass then
		return self
	end

	local base = BaseInfoPopup.new({ parent = props.parent, size = UDim2.new(0, 360, 0, 220) })
	local card = base.card :: Frame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, UIx.Spacing.SM)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = card

	-- Header with icon + name
	local header = Instance.new("Frame")
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 56)
	header.LayoutOrder = 1
	header.Parent = card
	local title = pass.name or pass.id or "Gamepass"

	-- Get official icon from GetGamepasses
	local iconStr: string? = nil
	do
		local ok, res = ClientError.try("PassDetailsPopup.GetGamepassesIcon", function()
			return ClientRF.call("GetGamepasses")
		end)
		if ok and res and res.list then
			for _, entry in ipairs(res.list) do
				if entry.id == pass.id and typeof(entry.icon) == "string" and entry.icon ~= "" then
					iconStr = entry.icon
					break
				end
			end
		end
	end

	if (typeof(iconStr) == "string") and isAssetString(iconStr) then
		local s = iconStr or ""
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Size = UDim2.new(0, 48, 0, 48)
		img.Position = UDim2.new(0, 0, 0.5, -24)
		img.Image = s:match("^%d+$") and ("rbxassetid://" .. s) or s
		img.ScaleType = Enum.ScaleType.Fit
		img.Parent = header
	else
		local lbl = UIFactory.label({
			parent = header,
			text = "PASS",
			size = UDim2.new(0, 48, 0, 48),
			position = UDim2.new(0, 0, 0.5, -24),
			alignment = Enum.TextXAlignment.Center,
			textSize = UIx.Visual.TEXT_TITLE,
		})
		lbl.TextYAlignment = Enum.TextYAlignment.Center
		lbl.Font = Theme.fonts.Display
		ThemeRefresher.Bind(lbl, { TextColor3 = "Text" })
	end

	local nameLabel = UIFactory.label({
		parent = header,
		text = title,
		size = UDim2.new(1, -56, 1, 0),
		position = UDim2.new(0, 56, 0, 0),
		alignment = Enum.TextXAlignment.Left,
		textSize = UIx.Visual.TEXT_TITLE,
	})
	nameLabel.TextYAlignment = Enum.TextYAlignment.Center
	nameLabel.TextWrapped = true
	nameLabel.Font = Theme.fonts.Display
	ThemeRefresher.Bind(nameLabel, { TextColor3 = "Text" })

	-- Owned status (query RF; tolerate failure)
	local ownedText = "Checking..."
	local ok, res = ClientError.try("PassDetailsPopup.GetGamepassesOwned", function()
		return ClientRF.call("GetGamepasses")
	end)
	if ok and res and res.list then
		local owned = false
		for _, entry in ipairs(res.list) do
			if entry.id == pass.id then
				owned = entry.owned == true
				break
			end
		end
		ownedText = owned and "Owned" or "Unowned"
	else
		ownedText = "Unknown"
	end
	row(card, "Status", ownedText)

	-- Price (Robux)
	do
		local rbx = tonumber(pass.robux)
		if rbx then
			row(card, "Price", string.format("R$ %s", UIUtils.formatNumber(rbx)))
		end
	end

	-- Effects summary
	local effects = pass.effects
	if type(effects) == "table" then
		local parts = {}
		for k, v in pairs(effects) do
			local key = tostring(k)
			if key == "loot_multiplier" and typeof(v) == "number" then
				table.insert(parts, string.format("Loot x%.2f", v))
			elseif key == "size_bonus" and typeof(v) == "number" then
				table.insert(parts, string.format("Tool Size +%d", v))
			else
				table.insert(parts, string.format("%s: %s", key, tostring(v)))
			end
		end
		if #parts > 0 then
			row(card, "Effects", table.concat(parts, "; "))
		end
	else
		row(card, "Type", "Permanent upgrade")
	end

	self._scrim = base.scrim
	self._card = card
	return self
end

function PassDetailsPopup.destroy(self: PassDetailsPopupT)
	local s = self._scrim
	if s then
		s:Destroy()
	end
	self._scrim = nil
	self._card = nil
end

return PassDetailsPopup
