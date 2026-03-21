--!strict
-- UIUtils.lua
-- Shared utilities for UI components to avoid duplication

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local UI = MiningGame:WaitForChild("UI")
-- Narrow Theme to the fields we rely on here for strict typing
type AnimSet = { Quick: TweenInfo, Standard: TweenInfo, Smooth: TweenInfo, Bounce: TweenInfo }
type Frosted = {
	backgroundTransparency: number,
	gradientTopT: number,
	gradientBottomT: number,
	noiseColorKey: string,
	noiseLighten: number?,
	noiseTransparency: number,
}
type GlassEdge = {
	thickness: number,
	color: Color3,
	transparency: number,
	applyStrokeMode: Enum.ApplyStrokeMode,
	lineJoinMode: Enum.LineJoinMode,
}
type ThemeLikeTextSizes = { Display: { Min: number, Max: number }, [string]: any }
type ThemeLike = {
	animations: AnimSet,
	colors: { [string]: Color3 },
	effects: { frosted: Frosted },
	glassEdge: GlassEdge,
	textSizes: ThemeLikeTextSizes,
}

local Theme: ThemeLike = require(UI:WaitForChild("Theme"))
local ThemeRefresher = require(UI:WaitForChild("ThemeRefresher"))

-- Try to get PlayerProfileGuard if available (client-side only)
local PlayerProfileGuard = nil
local okPPG, ppg = require(MiningGame:WaitForChild("ClientError")).try("UIUtils.requirePPG", function()
	return require(MiningGame:FindFirstChild("PlayerProfileGuard"))
end)
if okPPG then
	PlayerProfileGuard = ppg
end

local UIUtils = {}

-- Tween helper: create+play a tween for simple property animations
function UIUtils.tweenProps(inst: Instance, goals: { [string]: any }, info: TweenInfo?)
	local tweenInfo: TweenInfo = info or Theme.animations.Quick
	local tween = TweenService:Create(inst, tweenInfo, goals)
	tween:Play()
	return tween
end

-- Registry of frosted backgrounds for live theme refreshing
-- Strongly-typed map (no weak semantics in strict mode)
local _frosted: { [Frame]: { gradient: UIGradient?, noise: ImageLabel? } } = {}

function UIUtils.registerFrosted(background: Frame, gradient: UIGradient?, noise: ImageLabel?)
	_frosted[background] = { gradient = gradient, noise = noise }
	background.AncestryChanged:Connect(function()
		if not background.Parent then
			_frosted[background] = nil
		end
	end)
end

function UIUtils.refreshFrosting()
	local frost = Theme.effects.frosted
	for background, parts in pairs(_frosted) do
		if background and background.Parent then
			background.BackgroundTransparency = frost.backgroundTransparency
			local grad = parts.gradient
			if grad and grad.Parent then
				grad.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, frost.gradientTopT),
					NumberSequenceKeypoint.new(1, frost.gradientBottomT),
				})
			end
			local noise = parts.noise
			if noise and noise.Parent then
				local base = Theme.colors[frost.noiseColorKey] or Theme.colors.Background
				local t = math.clamp(frost.noiseLighten or 0, 0, 1)
				local tinted = t > 0 and base:Lerp(Color3.new(1, 1, 1), t) or base
				noise.ImageColor3 = tinted
				noise.ImageTransparency = frost.noiseTransparency
			end
		else
			if background then
				_frosted[background] = nil
			end
		end
	end
end

-- Format number with K/M/B suffixes
function UIUtils.formatNumber(n: number): string
	local a = math.abs(n)
	if a >= 1e9 then
		return (string.format("%.1fB", n / 1e9)):gsub("%.0B", "B")
	elseif a >= 1e6 then
		return (string.format("%.1fM", n / 1e6)):gsub("%.0M", "M")
	elseif a >= 1e3 then
		return (string.format("%.1fK", n / 1e3)):gsub("%.0K", "K")
	else
		return tostring(n)
	end
end

-- Pulse animation for any GUI element
function UIUtils.pulse(gui: GuiObject, scaleUp: number?)
	local s = gui:FindFirstChildOfClass("UIScale")
	if not s then
		local created = Instance.new("UIScale")
		created.Parent = gui
		s = created
	end

	local scaleObj: UIScale = s :: UIScale

	local Anim: AnimSet = Theme.animations
	local goalsUp: { [string]: any } = { Scale = scaleUp or 1.06 }
	local goalsDown: { [string]: any } = { Scale = 1 }
	local up = TweenService:Create(scaleObj, Anim.Quick, goalsUp)
	local down = TweenService:Create(scaleObj, Anim.Smooth, goalsDown)

	up:Play()
	up.Completed:Connect(function()
		down:Play()
	end)
end

-- Apply consistent glass edge styling
function UIUtils.applyGlassEdge(parent: GuiObject): UIStroke
	local stroke = Instance.new("UIStroke")
	local ge = Theme.glassEdge
	stroke.Thickness = ge.thickness
	stroke.Color = ge.color
	stroke.Transparency = ge.transparency
	stroke.ApplyStrokeMode = ge.applyStrokeMode
	stroke.LineJoinMode = ge.lineJoinMode
	stroke.Parent = parent
	-- Bind to theme so glass edge updates on theme change
	ThemeRefresher.Bind(stroke, { Stroke = "glassEdge" })
	return stroke
end

-- Get profile with retry logic
function UIUtils.getProfileWithRetry(_remotes: any, maxAttempts: number?, delaySec: number?): (any, string?)
	local attempts = maxAttempts or 3
	local delay = delaySec or 1

	local lastErr
	for i = 1, attempts do
		-- Guard-only approach
		if PlayerProfileGuard and type(PlayerProfileGuard.get) == "function" then
			local p, err = PlayerProfileGuard.get()
			if p then
				return p, nil
			end
			lastErr = err
		else
			lastErr = "PlayerProfileGuard unavailable"
		end

		if i < attempts then
			task.wait(delay)
		end
	end

	return nil, lastErr
end

-- Validate scene interface
function UIUtils.validateScene(scene: any)
	assert(type(scene) == "table", "Scene must be a table")
	assert(type(scene.name) == "string", "Scene must have a name property")
	assert(type(scene.init) == "function", "Scene must have init method")
	assert(type(scene.show) == "function", "Scene must have show method")
	assert(type(scene.hide) == "function", "Scene must have hide method")
end

-- Create a button/chip with separated background and content layers
-- Background scales on interaction, content stays stable
function UIUtils.createLayeredButton(props: {
	parent: GuiObject,
	size: UDim2?,
	backgroundProps: {
		color: Color3?,
		transparency: number?,
		cornerRadius: UDim?,
		applyGlassEdge: boolean?,
		gradient: boolean?,
		noise: boolean?,
	}?,
}): (Frame, Frame, Frame)
	local container = Instance.new("Frame")
	container.Name = "LayeredContainer"
	container.Size = props.size or UDim2.fromScale(1, 1)
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.Position = UDim2.fromScale(0.5, 0.5)
	container.BackgroundTransparency = 1
	container.Selectable = false
	container.Parent = props.parent

	-- Background (this is what scales)
	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.fromScale(1, 1)
	background.AnchorPoint = Vector2.new(0.5, 0.5)
	background.Position = UDim2.fromScale(0.5, 0.5)
	background.BackgroundColor3 = (props.backgroundProps and props.backgroundProps.color) or Theme.colors.Surface
	local bgTrans: number = Theme.effects.frosted.backgroundTransparency
	if props.backgroundProps and props.backgroundProps.transparency ~= nil then
		bgTrans = props.backgroundProps.transparency :: number
	end
	background.BackgroundTransparency = bgTrans
	background.ClipsDescendants = true
	background.Parent = container

	if props.backgroundProps and props.backgroundProps.cornerRadius then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = props.backgroundProps.cornerRadius
		corner.Parent = background
	end

	if props.backgroundProps and props.backgroundProps.applyGlassEdge then
		UIUtils.applyGlassEdge(background)
	end

	local gradient: UIGradient? = nil
	if props.backgroundProps and props.backgroundProps.gradient then
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(1, 1, 1))
		local gt: number = Theme.effects.frosted.gradientTopT
		local gb: number = Theme.effects.frosted.gradientBottomT
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, gt),
			NumberSequenceKeypoint.new(1, gb),
		})
		g.Parent = background
		gradient = g
	end

	-- Noise texture for frosted glass effect
	local noise: ImageLabel? = nil
	if props.backgroundProps and props.backgroundProps.noise then
		local n = Instance.new("ImageLabel")
		n.BackgroundTransparency = 1
		n.Image = "rbxasset://textures/ui/GuiImagePlaceholder.png"
		-- Tint the noise toward the active theme color for a colored frost
		local frost = Theme.effects.frosted
		local base = Theme.colors[frost.noiseColorKey] or Theme.colors.Background
		local t = math.clamp(frost.noiseLighten or 0, 0, 1)
		local tinted = t > 0 and base:Lerp(Color3.new(1, 1, 1), t) or base
		n.ImageColor3 = tinted
		n.ImageTransparency = frost.noiseTransparency
		n.ScaleType = Enum.ScaleType.Tile
		n.TileSize = UDim2.fromOffset(64, 64)
		n.Size = UDim2.fromScale(1, 1)
		n.ZIndex = 1
		n.Parent = background
		noise = n
	end

	-- Track frosted elements so we can refresh them on theme flips
	UIUtils.registerFrosted(background, gradient, noise)

	-- Content (never scaled)
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.fromScale(1, 1)
	content.AnchorPoint = Vector2.new(0.5, 0.5)
	content.Position = UDim2.fromScale(0.5, 0.5)
	content.BackgroundTransparency = 1
	content.Selectable = false
	content.ZIndex = 2
	content.Parent = container

	-- scale lives on Background only
	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = background

	return container, background, content
end

-- Press (squish) animation that scales the Background only
function UIUtils.applyPressAnimation(container: Frame, intensity: number?)
	-- Guard against double-binding
	if container:GetAttribute("PressBound") then
		return
	end
	container:SetAttribute("PressBound", true)

	local background = container:FindFirstChild("Background")
	if not background then
		return
	end

	local s = background:FindFirstChildOfClass("UIScale")
	if not s then
		local created = Instance.new("UIScale")
		created.Scale = 1
		created.Parent = background
		s = created
	end
	local scale: UIScale = s :: UIScale

	local squish = intensity or 0.92
	local pressed = false

	-- Helper to reset scale
	local function resetScale()
		if pressed then
			pressed = false
			local Anim2: AnimSet = Theme.animations
			local resetGoals: { [string]: any } = { Scale = 1 }
			TweenService:Create(scale, Anim2.Bounce, resetGoals):Play()
		end
	end

	container.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			pressed = true
			local Anim3: AnimSet = Theme.animations
			local squishGoals: { [string]: any } = { Scale = squish }
			TweenService:Create(scale, Anim3.Quick, squishGoals):Play()
		end
	end)

	container.InputEnded:Connect(function(input)
		if
			(input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch)
			and pressed
		then
			resetScale()
		end
	end)

	-- Reset if mouse/touch leaves the element
	container.MouseLeave:Connect(function()
		resetScale()
	end)

	-- Also reset on global input end (in case pointer is released outside)
	local UserInputService = game:GetService("UserInputService")
	UserInputService.InputEnded:Connect(function(input)
		if
			(input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch)
			and pressed
		then
			resetScale()
		end
	end)
end

-- Pulse (affects Background only)
function UIUtils.pulseLayered(container: Frame, scaleUp: number?)
	local background = container:FindFirstChild("Background")
	if not background then
		UIUtils.pulse(container, scaleUp) -- fallback
		return
	end
	local s = background:FindFirstChildOfClass("UIScale")
	if not s then
		local created = Instance.new("UIScale")
		created.Scale = 1
		created.Parent = background
		s = created
	end
	local scale: UIScale = s :: UIScale

	local Anim4: AnimSet = Theme.animations
	local goalsUp2: { [string]: any } = { Scale = scaleUp or 1.06 }
	local goalsDown2: { [string]: any } = { Scale = 1 }
	local up = TweenService:Create(scale, Anim4.Quick, goalsUp2)
	local down = TweenService:Create(scale, Anim4.Smooth, goalsDown2)

	up:Play()
	up.Completed:Connect(function()
		down:Play()
	end)
end

-- Convert programmer identifiers to human-readable strings
function UIUtils.humanize(s: string): string
	local str = tostring(s or "")
	-- Replace underscores and hyphens with spaces
	str = str:gsub("_", " ")
	str = str:gsub("%-", " ")
	-- Collapse whitespace and trim
	str = str:gsub("%s+", " ")
	str = str:gsub("^%s+", "")
	str = str:gsub("%s+$", "")
	return str
end

-- Optional TitleCase utility (not applied automatically)
function UIUtils.toTitleCase(s: string): string
	local str = UIUtils.humanize(s)
	str = string.gsub(str, "(%w+)", function(word)
		local first = string.sub(word, 1, 1)
		local rest = string.sub(word, 2)
		return string.upper(first) .. string.lower(rest)
	end)
	return str
end

return UIUtils
