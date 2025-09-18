--!strict
-- PostProcessingManager.lua
-- Manages post-processing effects with single composite instances and deterministic blending

local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserSettings = UserSettings()
local UserGameSettings = UserSettings:GetService("UserGameSettings")

-- Client-only guard
if RunService:IsServer() then
	error("PostProcessingManager must be required on the client", 0)
end

local PostProcessingConfig = require(script.Parent.PostProcessingConfig)
local PostProcessingSettings = require(script.Parent.PostProcessingSettings)
local Logger = require(script.Parent.Parent.Logger)
local log = Logger.new("PostProcessingManager")

-- Effect class list for composite instances
local EFFECT_CLASSES = {
	"ColorCorrectionEffect",
	"BlurEffect",
	"DepthOfFieldEffect",
	"BloomEffect",
	"SunRaysEffect",
	"Atmosphere"
}

-- Neutral values for each effect type
local NEUTRAL_VALUES = {
	ColorCorrectionEffect = {
		Brightness = 0,
		Contrast = 0,
		Saturation = 0,
		TintColor = Color3.new(1, 1, 1)
	},
	BlurEffect = {
		Size = 0
	},
	BloomEffect = {
		Intensity = 0,
		Size = 24,
		Threshold = 1
	},
	DepthOfFieldEffect = {
		FarIntensity = 0,
		NearIntensity = 0,
		InFocusRadius = 100,
		FocusDistance = 60
	},
	SunRaysEffect = {
		Intensity = 0,
		Spread = 0
	},
	Atmosphere = {
		Density = 0,
		Color = Color3.new(1, 1, 1),
		Decay = Color3.new(1, 1, 1),
		Glare = 0,
		Haze = 0
	}
}

local PostProcessingManager = {}
PostProcessingManager.__index = PostProcessingManager

-- Helper to clamp values
local function clamp(value: number, min: number, max: number): number
	return math.max(min, math.min(max, value))
end

-- Deep clone helper for suspend/resume
local function deepClone(t: any): any
	if typeof(t) ~= "table" then return t end
	local c = {}
	for k, v in pairs(t) do
		c[k] = deepClone(v)
	end
	return c
end

-- Get quality level for performance gating
local function getQualityLevel(): string
	-- Check if debug override is set
	if PostProcessingSettings.Debug.ForceQualityLevel then
		return PostProcessingSettings.Debug.ForceQualityLevel
	end
	
	local quality = UserGameSettings.SavedQualityLevel
	if quality == Enum.SavedQualitySetting.Automatic then
		return "Medium"  -- Safe default for automatic
	end
	local level = tonumber(quality.Value) or 5
	if level <= 3 then
		return "Low"
	elseif level <= 7 then
		return "Medium"
	else
		return "High"
	end
end

function PostProcessingManager.new()
	local self = setmetatable({}, PostProcessingManager)
	
	-- Layer stacks for active effects
	self.layers = {
		THEME = {},
		ENVIRONMENT = {},
		GAMEPLAY = {},
		TRANSITION = {}
	}
	
	-- Single composite instance per effect class
	self.compositeInstances = {}
	
	-- Active tweens for cancellation
	self.activeTweens = {}
	
	-- Current quality level
	self.qualityLevel = getQualityLevel()
	
	-- Auto-react to quality changes
	self._qualityConnection = UserGameSettings:GetPropertyChangedSignal("SavedQualityLevel"):Connect(function()
		self:updateQuality()
	end)
	
	-- Initialize composite instances
	self:_initializeComposites()
	
	log:info("Initialized with quality level: %s", self.qualityLevel)
	
	return self
end

function PostProcessingManager:_initializeComposites()
	-- Warn once about pre-existing effects to avoid log spam
	if not self._warnedLightingScan then
		for _, child in ipairs(Lighting:GetChildren()) do
			local class = child.ClassName
			if (class == "Atmosphere" or class == "BloomEffect" or class == "BlurEffect"
				or class == "ColorCorrectionEffect" or class == "DepthOfFieldEffect" or class == "SunRaysEffect")
				and not tostring(child.Name):match("^PP_") then
				log:warn("Found existing %s '%s' under Lighting. Consider removing to avoid conflicts.", 
					class, child.Name)
			end
		end
		self._warnedLightingScan = true
	end
	
	for _, className in ipairs(EFFECT_CLASSES) do
		local instance = Instance.new(className)
		instance.Name = "PP_" .. className
		instance.Parent = Lighting
		
		-- Atmosphere doesn't have Enabled property
		if className ~= "Atmosphere" then
			instance.Enabled = false
		end
		
		-- Set to neutral values
		for prop, value in pairs(NEUTRAL_VALUES[className]) do
			pcall(function()
				instance[prop] = value
			end)
		end
		
		self.compositeInstances[className] = instance
	end
end

-- Apply an effect with optional overrides
function PostProcessingManager:apply(effectName: string, overrides: any?)
	-- Check if system is enabled
	if not PostProcessingSettings.Enabled then
		if PostProcessingSettings.Debug.VerboseLogging then
			log:debug("Post-processing disabled - ignoring apply(%s)", effectName)
		end
		return
	end
	
	local effectDef = PostProcessingConfig.GetEffect(effectName)
	if not effectDef then
		log:warn("Unknown effect: %s", effectName)
		return
	end
	
	-- Store in appropriate layer
	local layerName = effectDef.layer
	self.layers[layerName][effectName] = {
		definition = effectDef,
		overrides = overrides or {}
	}
	
	-- Update audio reverb if needed
	if effectDef.audio and effectDef.audio.ambientReverb then
		self:_updateAudioReverb()
	end
	
	-- Transition to new composite state
	local transition = effectDef.transition
	self:_transitionToComposite(
		transition and transition.fadeIn or 0,
		transition and transition.easing
	)
	
	log:debug("Applied effect: %s", effectName)
end

-- Remove an effect
function PostProcessingManager:remove(effectName: string)
	local removedDef = nil
	
	-- Find and remove from layers
	for layerName, stack in pairs(self.layers) do
		if stack[effectName] then
			removedDef = stack[effectName].definition
			stack[effectName] = nil
			break
		end
	end
	
	if not removedDef then
		log:debug("Effect not active: %s", effectName)
		return
	end
	
	-- Update audio reverb
	self:_updateAudioReverb()
	
	-- Transition out
	local transition = removedDef.transition
	self:_transitionToComposite(
		transition and transition.fadeOut or 0,
		transition and transition.easing
	)
	
	log:debug("Removed effect: %s", effectName)
end

-- Clear all effects
function PostProcessingManager:clearAll()
	self.layers = {
		THEME = {},
		ENVIRONMENT = {},
		GAMEPLAY = {},
		TRANSITION = {}
	}
	self:_updateAudioReverb()
	self:_transitionToComposite(0.5, Enum.EasingStyle.Quad)
end

-- Compose all active effects into target values
function PostProcessingManager:_composeTargets()
	local targets = {}
	
	-- Initialize with neutral values
	for _, className in ipairs(EFFECT_CLASSES) do
		targets[className] = table.clone(NEUTRAL_VALUES[className])
	end
	
	-- Gather all active effects sorted by priority
	local activeEffects = {}
	for layerName, stack in pairs(self.layers) do
		local layerPriority = PostProcessingConfig.Layers[layerName]
		for effectName, entry in pairs(stack) do
			local totalPriority = layerPriority + (entry.definition.priority or 0)
			table.insert(activeEffects, {
				priority = totalPriority,
				entry = entry
			})
		end
	end
	
	-- Sort by priority (lower first)
	table.sort(activeEffects, function(a, b)
		return a.priority < b.priority
	end)
	
	-- Apply effects in order with blending rules
	for _, item in ipairs(activeEffects) do
		local components = item.entry.definition.components
		local overrides = item.entry.overrides.components or {}
		
		for className, props in pairs(components) do
			-- Merge with overrides if present
			local finalProps = props
			if overrides[className] then
				finalProps = table.clone(props)
				for k, v in pairs(overrides[className]) do
					finalProps[k] = v
				end
			end
			
			-- Apply quality limits
			finalProps = self:_applyQualityLimits(className, finalProps)
			
			-- Blend based on class-specific rules
			self:_blendEffect(className, targets[className], finalProps)
		end
	end
	
	return targets
end

-- Apply quality-based limits to effect properties
function PostProcessingManager:_applyQualityLimits(className: string, props: any)
	local limits = PostProcessingConfig.QualityLimits[self.qualityLevel]
	if not limits or not limits[className] then
		return props
	end
	
	local limited = table.clone(props)
	local classLimits = limits[className]
	
	-- Check if effect should be disabled entirely
	if classLimits.disabled then
		return NEUTRAL_VALUES[className]
	end
	
	-- Apply property limits
	if className == "BlurEffect" and classLimits.maxSize then
		limited.Size = math.min(limited.Size or 0, classLimits.maxSize)
	elseif className == "DepthOfFieldEffect" and classLimits.maxFarIntensity then
		limited.FarIntensity = math.min(limited.FarIntensity or 0, classLimits.maxFarIntensity)
	elseif className == "Atmosphere" and classLimits.maxDensity then
		limited.Density = math.min(limited.Density or 0, classLimits.maxDensity)
	end
	
	return limited
end

-- Blend effect properties based on class-specific rules
function PostProcessingManager:_blendEffect(className: string, target: any, props: any)
	if className == "ColorCorrectionEffect" then
		-- Additive for brightness/contrast/saturation (clamped)
		target.Brightness = clamp(target.Brightness + (props.Brightness or 0), -1, 1)
		target.Contrast = clamp(target.Contrast + (props.Contrast or 0), -1, 1)
		target.Saturation = clamp(target.Saturation + (props.Saturation or 0), -1, 1)
		-- Highest priority non-neutral tint wins (intentionally last-wins by priority sort)
		if props.TintColor and props.TintColor ~= Color3.new(1, 1, 1) then
			target.TintColor = props.TintColor
		end
		
	elseif className == "BlurEffect" then
		-- Maximum wins (clamped to engine limit)
		target.Size = math.min(56, math.max(target.Size, props.Size or 0))
		
	elseif className == "DepthOfFieldEffect" then
		-- Max for intensities, min for radius
		target.FarIntensity = math.max(target.FarIntensity, props.FarIntensity or 0)
		target.NearIntensity = math.max(target.NearIntensity, props.NearIntensity or 0)
		target.InFocusRadius = math.min(target.InFocusRadius, props.InFocusRadius or 100)
		target.FocusDistance = props.FocusDistance or target.FocusDistance
		
	elseif className == "SunRaysEffect" then
		-- Maximum wins for both properties (clamped to engine limits)
		target.Intensity = math.min(1, math.max(target.Intensity, props.Intensity or 0))
		target.Spread = math.min(1, math.max(target.Spread, props.Spread or 0))
		
	elseif className == "BloomEffect" then
		-- Max for intensity/size, min for threshold
		target.Intensity = math.max(target.Intensity, props.Intensity or 0)
		target.Size = math.max(target.Size, props.Size or 24)
		target.Threshold = math.min(target.Threshold, props.Threshold or 1)
		
	elseif className == "Atmosphere" then
		-- Highest priority wins (full override)
		for k, v in pairs(props) do
			target[k] = v
		end
	end
end

-- Apply final bounds clamping to ensure engine-safe values
local function clampFinalProps(className: string, props: any)
	if className == "ColorCorrectionEffect" then
		props.Brightness = clamp(props.Brightness or 0, -1, 1)
		props.Contrast = clamp(props.Contrast or 0, -1, 1)
		props.Saturation = clamp(props.Saturation or 0, -1, 1)
	elseif className == "BlurEffect" then
		props.Size = clamp(props.Size or 0, 0, 56)
	elseif className == "DepthOfFieldEffect" then
		props.FarIntensity = clamp(props.FarIntensity or 0, 0, 1)
		props.NearIntensity = clamp(props.NearIntensity or 0, 0, 1)
		props.InFocusRadius = clamp(props.InFocusRadius or 100, 0, 200)
		props.FocusDistance = clamp(props.FocusDistance or 60, 0, 10000)
	elseif className == "BloomEffect" then
		props.Intensity = clamp(props.Intensity or 0, 0, 2)
		props.Size = clamp(props.Size or 24, 1, 100)
		props.Threshold = clamp(props.Threshold or 1, 0, 1)
	elseif className == "SunRaysEffect" then
		props.Intensity = clamp(props.Intensity or 0, 0, 1)
		props.Spread = clamp(props.Spread or 0, 0, 1)
	elseif className == "Atmosphere" then
		props.Density = clamp(props.Density or 0, 0, 1)
		props.Glare = math.max(props.Glare or 0, 0)
		props.Haze = math.max(props.Haze or 0, 0)
	end
	return props
end

-- Check if values are effectively equal (with tolerance for numbers)
local function valuesEqual(a: any, b: any): boolean
	if typeof(a) == "number" then
		return math.abs((a or 0) - (b or 0)) < 1e-3
	end
	return a == b
end

-- Check if a tween would be a no-op
local function isNoOp(instance: Instance, goalProps: any): boolean
	for propName, goalValue in pairs(goalProps) do
		local ok, currentValue = pcall(function()
			return instance[propName]
		end)
		if ok and not valuesEqual(currentValue, goalValue) then
			return false
		end
	end
	return true
end

-- Transition composite instances to new target values
function PostProcessingManager:_transitionToComposite(duration: number, easing: Enum.EasingStyle?)
	-- Cancel existing tweens
	for _, tween in pairs(self.activeTweens) do
		tween:Cancel()
	end
	self.activeTweens = {}
	
	-- Get target values
	local targets = self:_composeTargets()
	
	-- Apply final safety clamping
	for className, props in pairs(targets) do
		targets[className] = clampFinalProps(className, props)
	end
	
	-- Check if all effects are cleared
	local allClear = self:_isAllClear()
	
	-- Create tweens for each instance
	local tweenInfo = TweenInfo.new(
		duration or 0,
		easing or Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)
	
	for className, targetProps in pairs(targets) do
		local instance = self.compositeInstances[className]
		
		-- Enable if needed (except Atmosphere which has no Enabled)
		if className ~= "Atmosphere" and not allClear then
			instance.Enabled = true
		end
		
		if duration > 0 then
			-- Skip no-op tweens for performance
			if not isNoOp(instance, targetProps) then
				-- Create tween
				local tween = TweenService:Create(instance, tweenInfo, targetProps)
				tween:Play()
				self.activeTweens[className] = tween
				
				-- Disable after transition if clearing (ignore cancelled tweens)
				if allClear and className ~= "Atmosphere" then
					tween.Completed:Connect(function(playbackState)
						if playbackState == Enum.PlaybackState.Cancelled then return end
						instance.Enabled = false
						-- Reset to neutral
						for prop, value in pairs(NEUTRAL_VALUES[className]) do
							pcall(function()
								instance[prop] = value
							end)
						end
					end)
				end
			else
				-- Already at target; if target is neutral, disable the instance
				if className ~= "Atmosphere" and isNoOp(instance, NEUTRAL_VALUES[className]) then
					instance.Enabled = false
				end
			end
		else
			-- Apply immediately
			for prop, value in pairs(targetProps) do
				pcall(function()
					instance[prop] = value
				end)
			end
			
			-- Disable and neutralize if clear; otherwise ensure enabled for immediate apply
			if allClear and className ~= "Atmosphere" then
				for prop, value in pairs(NEUTRAL_VALUES[className]) do
					pcall(function()
						instance[prop] = value
					end)
				end
				instance.Enabled = false
			elseif className ~= "Atmosphere" then
				instance.Enabled = true
			end
		end
	end
end

-- Check if all layers are empty
function PostProcessingManager:_isAllClear(): boolean
	for _, stack in pairs(self.layers) do
		if next(stack) then
			return false
		end
	end
	return true
end

-- Choose the highest priority reverb effect
function PostProcessingManager:_chooseTopReverb()
	local bestReverb = nil
	local bestPriority = nil
	
	for layerName, stack in pairs(self.layers) do
		local layerPriority = PostProcessingConfig.Layers[layerName] or 0
		for _, entry in pairs(stack) do
			local def = entry.definition
			if def.audio and def.audio.ambientReverb then
				local totalPriority = layerPriority + (def.priority or 0)
				if not bestPriority or totalPriority > bestPriority then
					bestPriority = totalPriority
					bestReverb = def.audio.ambientReverb
				end
			end
		end
	end
	
	return bestReverb
end

-- Update ambient reverb based on active effects
function PostProcessingManager:_updateAudioReverb()
	local reverb = self:_chooseTopReverb()
	SoundService.AmbientReverb = reverb or Enum.ReverbType.NoReverb
	
	if reverb then
		log:debug("Set ambient reverb: %s", tostring(reverb))
	end
end

-- Update quality level (call when settings change)
function PostProcessingManager:updateQuality()
	self.qualityLevel = getQualityLevel()
	log:info("Quality level changed to: %s", self.qualityLevel)
	-- Recompose with new limits
	self:_transitionToComposite(0.5, Enum.EasingStyle.Quad)
end

-- Suspend all effects (useful for full-screen menus)
function PostProcessingManager:suspend()
	if self.suspended then return end
	self.suspended = true
	
	-- Store current state (deep clone to preserve references)
	self.suspendedLayers = deepClone(self.layers)
	
	-- Clear all effects
	self.layers = {
		THEME = {},
		ENVIRONMENT = {},
		GAMEPLAY = {},
		TRANSITION = {}
	}
	self:_updateAudioReverb()
	self:_transitionToComposite(0.3, Enum.EasingStyle.Quad)
	
	log:debug("Effects suspended")
end

-- Resume suspended effects
function PostProcessingManager:resume()
	if not self.suspended then return end
	self.suspended = false
	
	-- Restore state
	if self.suspendedLayers then
		self.layers = self.suspendedLayers
		self.suspendedLayers = nil
	end
	
	self:_updateAudioReverb()
	self:_transitionToComposite(0.5, Enum.EasingStyle.Quad)
	
	log:debug("Effects resumed")
end

-- Clean up and destroy the manager
function PostProcessingManager:destroy()
	-- Cancel all tweens
	for _, tween in pairs(self.activeTweens) do
		tween:Cancel()
	end
	self.activeTweens = {}
	
	-- Disconnect quality listener
	if self._qualityConnection then
		self._qualityConnection:Disconnect()
		self._qualityConnection = nil
	end
	
	-- Remove all composite instances
	for _, instance in pairs(self.compositeInstances) do
		instance:Destroy()
	end
	self.compositeInstances = {}
	
	-- Reset audio
	SoundService.AmbientReverb = Enum.ReverbType.NoReverb
	
	-- Clear all data
	self.layers = nil
	
	log:info("Manager destroyed")
end

return PostProcessingManager
