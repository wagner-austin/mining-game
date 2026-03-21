--!strict
-- PanelReveal.lua
-- Extracted gradient reveal animation and baseline capture for panel-style UIs

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local _UIx = require(MiningGame:WaitForChild("UI"):WaitForChild("UIConstants"))

export type TextRevealT = {
	conn: RBXScriptConnection?,
	progress: NumberValue?,
	tween: Tween?,
	delayThread: thread?,
}

export type BaselineRec = {
	textOrig: number?,
	strokeTextOrig: number?,
	bgOrig: number?,
	imgOrig: number?,
	scrollBarOrig: number?,
	stroke: UIStroke?,
	strokeOrig: number?,
}

export type RevealHost = {
	contentLayer: Frame,
	-- mutable fields managed by this module
	_textReveal: TextRevealT?,
	_revealBaseline: { [GuiObject]: BaselineRec },
	-- used for guards
	isOpen: boolean,
}

local PanelReveal = {}

local function ensureBaseline(host: RevealHost)
	if not host._revealBaseline then
		host._revealBaseline = {}
	end
	local baseline = host._revealBaseline

	-- prune dead instances
	for inst: GuiObject, _ in pairs(baseline) do
		if not inst:IsDescendantOf(host.contentLayer) then
			baseline[inst] = nil
		end
	end

	-- add missing records
	for _, c in ipairs(host.contentLayer:GetDescendants()) do
		if c:IsA("GuiObject") and c.Visible and not c:IsA("UIConstraint") then
			if baseline[c] == nil then
				local rec: BaselineRec = {}
				if c:IsA("TextLabel") or c:IsA("TextButton") or c:IsA("TextBox") then
					rec.textOrig = c.TextTransparency
					rec.strokeTextOrig = c.TextStrokeTransparency
					if rec.textOrig ~= nil and rec.textOrig >= 0.999 then
						rec.textOrig = 0
					end
					if rec.strokeTextOrig ~= nil and rec.strokeTextOrig >= 0.999 then
						rec.strokeTextOrig = 1
					end
				end
				rec.bgOrig = c.BackgroundTransparency
				if c:IsA("ImageLabel") or c:IsA("ImageButton") then
					rec.imgOrig = c.ImageTransparency
					if rec.imgOrig ~= nil and rec.imgOrig >= 0.999 then
						rec.imgOrig = 0
					end
				end
				if c:IsA("ScrollingFrame") then
					rec.scrollBarOrig = c.ScrollBarImageTransparency
				end
				local uiStroke = c:FindFirstChildOfClass("UIStroke")
				if uiStroke then
					rec.stroke = uiStroke
					rec.strokeOrig = uiStroke.Transparency
					if rec.strokeOrig ~= nil and rec.strokeOrig >= 0.999 then
						rec.strokeOrig = 0
					end
				end
				baseline[c] = rec
			end
		end
	end
end

function PanelReveal.refresh(host: RevealHost)
	ensureBaseline(host)
end

function PanelReveal.cancel(host: RevealHost, setTo: number?)
	local tr = host._textReveal
	if tr then
		if tr.tween then
			tr.tween:Cancel()
		end
		if tr.conn then
			tr.conn:Disconnect()
		end
		if tr.progress then
			tr.progress:Destroy()
		end
		if tr.delayThread then
			task.cancel(tr.delayThread)
		end
		host._textReveal = nil
	end
	if setTo ~= nil then
		for _, child in ipairs(host.contentLayer:GetDescendants()) do
			if child:IsA("GuiObject") then
				if child:IsA("TextLabel") then
					local lbl: TextLabel = child
					lbl.TextTransparency = setTo
					lbl.TextStrokeTransparency = setTo
				elseif child:IsA("TextButton") then
					local btn: TextButton = child
					btn.TextTransparency = setTo
					btn.TextStrokeTransparency = setTo
				elseif child:IsA("TextBox") then
					local tb: TextBox = child
					tb.TextTransparency = setTo
					tb.TextStrokeTransparency = setTo
				end
				child.BackgroundTransparency = setTo
				if child:IsA("ImageLabel") then
					local il: ImageLabel = child
					il.ImageTransparency = setTo
				elseif child:IsA("ImageButton") then
					local ib: ImageButton = child
					ib.ImageTransparency = setTo
				end
				local s = child:FindFirstChildOfClass("UIStroke")
				if s then
					s.Transparency = setTo
				end
			end
		end
	end
end

function PanelReveal.start(host: RevealHost, duration: number?, delay: number?, bandPx: number?)
	-- let layout settle for one frame
	RunService.Heartbeat:Wait()
	if not host.isOpen then
		return
	end

	ensureBaseline(host)
	local baseline = host._revealBaseline

	local minY, maxY = math.huge, -math.huge
	local elems: { { el: GuiObject, y: number, rec: BaselineRec } } = {}
	for _, inst in ipairs(host.contentLayer:GetDescendants()) do
		if inst:IsA("GuiObject") and inst.Visible and not inst:IsA("UIConstraint") then
			local rec = baseline[inst]
			if rec then
				local y = inst.AbsolutePosition.Y + inst.AbsoluteSize.Y * 0.5
				table.insert(elems, { el = inst, y = y, rec = rec })
				if y < minY then
					minY = y
				end
				if y > maxY then
					maxY = y
				end

				-- set hidden start state
				if rec.textOrig ~= nil then
					if inst:IsA("TextLabel") then
						local lbl: TextLabel = inst
						lbl.TextTransparency = 1
						lbl.TextStrokeTransparency = 1
					elseif inst:IsA("TextButton") then
						local btn: TextButton = inst
						btn.TextTransparency = 1
						btn.TextStrokeTransparency = 1
					elseif inst:IsA("TextBox") then
						local tb: TextBox = inst
						tb.TextTransparency = 1
						tb.TextStrokeTransparency = 1
					end
				end
				if rec.bgOrig ~= nil and inst.BackgroundTransparency < 0.99 then
					inst.BackgroundTransparency = 1
				end
				if rec.imgOrig ~= nil then
					if inst:IsA("ImageLabel") then
						local img: ImageLabel = inst
						img.ImageTransparency = 1
					elseif inst:IsA("ImageButton") then
						local imgBtn: ImageButton = inst
						imgBtn.ImageTransparency = 1
					end
				end
				if rec.stroke then
					rec.stroke.Transparency = 1
				end
				if rec.scrollBarOrig ~= nil then
					if inst:IsA("ScrollingFrame") then
						local sf: ScrollingFrame = inst
						sf.ScrollBarImageTransparency = 1
					end
				end
			end
		end
	end

	if #elems == 0 or not (maxY > minY) then
		-- fallback: restore from baseline
		for inst: GuiObject, rec in pairs(baseline) do
			if inst:IsDescendantOf(host.contentLayer) then
				if rec.textOrig ~= nil then
					if inst:IsA("TextLabel") then
						local lbl: TextLabel = inst
						lbl.TextTransparency = rec.textOrig
						local strokeT = rec.strokeTextOrig ~= nil and rec.strokeTextOrig or 1
						lbl.TextStrokeTransparency = strokeT
					elseif inst:IsA("TextButton") then
						local btn: TextButton = inst
						btn.TextTransparency = rec.textOrig
						local strokeT2 = rec.strokeTextOrig ~= nil and rec.strokeTextOrig or 1
						btn.TextStrokeTransparency = strokeT2
					elseif inst:IsA("TextBox") then
						local tb: TextBox = inst
						tb.TextTransparency = rec.textOrig
						local strokeT3 = rec.strokeTextOrig ~= nil and rec.strokeTextOrig or 1
						tb.TextStrokeTransparency = strokeT3
					end
				end
				if rec.imgOrig ~= nil then
					if inst:IsA("ImageLabel") then
						local img: ImageLabel = inst
						img.ImageTransparency = rec.imgOrig
					elseif inst:IsA("ImageButton") then
						local imgb: ImageButton = inst
						imgb.ImageTransparency = rec.imgOrig
					end
				end
				if rec.bgOrig ~= nil then
					inst.BackgroundTransparency = rec.bgOrig
				end
				if rec.stroke then
					rec.stroke.Transparency = rec.strokeOrig or 0
				end
				if rec.scrollBarOrig ~= nil then
					if inst:IsA("ScrollingFrame") then
						(inst :: ScrollingFrame).ScrollBarImageTransparency = rec.scrollBarOrig
					end
				end
			end
		end
		return
	end

	-- cancel previous if present
	PanelReveal.cancel(host)

	local progress = Instance.new("NumberValue")
	progress.Value = 0
	local range = maxY - minY
	local band = bandPx or math.clamp(range * 0.06, 16, 72)

	local function lerp(a: number, b: number, t: number): number
		return a + (b - a) * t
	end

	local function update()
		local front = minY + progress.Value * (range + band)
		for _, d in ipairs(elems) do
			local rec = d.rec
			local t = math.clamp((front - d.y) / band, 0, 1)

			if rec.textOrig ~= nil then
				local el = d.el
				if el:IsA("TextLabel") then
					local lbl: TextLabel = el
					lbl.TextTransparency = lerp(1, rec.textOrig, t)
					lbl.TextStrokeTransparency = lerp(1, rec.strokeTextOrig or 1, t)
				elseif el:IsA("TextButton") then
					local btn: TextButton = el
					btn.TextTransparency = lerp(1, rec.textOrig, t)
					btn.TextStrokeTransparency = lerp(1, rec.strokeTextOrig or 1, t)
				elseif el:IsA("TextBox") then
					local tb: TextBox = el
					tb.TextTransparency = lerp(1, rec.textOrig, t)
					tb.TextStrokeTransparency = lerp(1, rec.strokeTextOrig or 1, t)
				end
			end

			if rec.imgOrig ~= nil then
				local el2 = d.el
				if el2:IsA("ImageLabel") then
					local img: ImageLabel = el2
					img.ImageTransparency = lerp(1, rec.imgOrig, t)
				elseif el2:IsA("ImageButton") then
					local imgb: ImageButton = el2
					imgb.ImageTransparency = lerp(1, rec.imgOrig, t)
				end
			end

			if rec.bgOrig ~= nil then
				d.el.BackgroundTransparency = lerp(1, rec.bgOrig, t)
			end

			if rec.stroke then
				rec.stroke.Transparency = lerp(1, rec.strokeOrig or 0, t)
			end

			if rec.scrollBarOrig ~= nil then
				local el3 = d.el
				if el3:IsA("ScrollingFrame") then
					(el3 :: ScrollingFrame).ScrollBarImageTransparency = lerp(1, rec.scrollBarOrig, t)
				end
			end
		end
	end

	local tr: TextRevealT = { progress = progress }
	host._textReveal = tr
	tr.conn = progress.Changed:Connect(update)

	local startTween = function()
		if not host.isOpen or host._textReveal ~= tr then
			progress:Destroy()
			return
		end
		local tween = TweenService:Create(
			progress,
			TweenInfo.new(duration or 0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Value = 1 }
		)
		tr.tween = tween
		tween.Completed:Connect(function()
			update()
			if host._textReveal == tr then
				if tr.conn then
					tr.conn:Disconnect()
				end
				if tr.progress then
					tr.progress:Destroy()
				end
				host._textReveal = nil
			end
		end)
		tween:Play()
	end

	if delay and delay > 0 then
		tr.delayThread = task.delay(delay, startTween)
	else
		startTween()
	end

	update()
end

return PanelReveal
