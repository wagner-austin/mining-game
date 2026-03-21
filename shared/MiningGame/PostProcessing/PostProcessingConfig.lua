--!strict
-- PostProcessingConfig.lua
-- Configuration for post-processing effects with deterministic blending

local PostProcessingConfig = {}

-- Types
export type EffectComponents = {
	ColorCorrectionEffect: { Brightness: number?, Contrast: number?, Saturation: number?, TintColor: Color3? }?,
	BlurEffect: { Size: number? }?,
	DepthOfFieldEffect: {
		FarIntensity: number?,
		NearIntensity: number?,
		InFocusRadius: number?,
		FocusDistance: number?,
	}?,
	BloomEffect: { Intensity: number?, Size: number?, Threshold: number? }?,
	SunRaysEffect: { Intensity: number?, Spread: number? }?,
	Atmosphere: { Density: number?, Color: Color3?, Decay: Color3?, Glare: number?, Haze: number? }?,
}

export type TransitionDef = { fadeIn: number?, fadeOut: number?, easing: Enum.EasingStyle? }
export type AudioDef = { ambientReverb: Enum.ReverbType? }
export type EffectDef = {
	layer: "THEME" | "ENVIRONMENT" | "GAMEPLAY" | "TRANSITION",
	priority: number?,
	components: EffectComponents,
	transition: TransitionDef?,
	audio: AudioDef?,
}

-- Effect layer priorities (higher = renders on top)
PostProcessingConfig.Layers = {
	THEME = 100,
	ENVIRONMENT = 200,
	GAMEPLAY = 300,
	TRANSITION = 400,
}

-- Effect definitions using Roblox class names as keys
PostProcessingConfig.Effects = {
	-- Environmental: Underwater effect when swimming
	underwater = {
		layer = "ENVIRONMENT",
		priority = 100,
		components = {
			ColorCorrectionEffect = {
				TintColor = Color3.fromRGB(120, 180, 220),
				Brightness = -0.15,
				Contrast = -0.25,
				Saturation = -0.40,
			},
			DepthOfFieldEffect = {
				FarIntensity = 0.40,
				InFocusRadius = 12,
				NearIntensity = 0.60,
				FocusDistance = 60,
			},
			BlurEffect = {
				Size = 6,
			},
			SunRaysEffect = {
				Intensity = 0.15,
				Spread = 0.6, -- Subtle underwater light shafts
			},
		},
		transition = {
			fadeIn = 0.8,
			fadeOut = 0.5,
			easing = Enum.EasingStyle.Quad,
		},
		audio = {
			-- Use UnderWater (capital W) - the correct Roblox enum
			ambientReverb = Enum.ReverbType.UnderWater,
		},
	},

	-- Environmental: Cave/Underground atmosphere
	underground = {
		layer = "ENVIRONMENT",
		priority = 90,
		components = {
			ColorCorrectionEffect = {
				TintColor = Color3.fromRGB(180, 170, 160),
				Brightness = -0.2,
				Contrast = 0.1,
				Saturation = -0.2,
			},
			Atmosphere = {
				Density = 0.5,
				Color = Color3.fromRGB(60, 50, 40),
				Decay = Color3.fromRGB(120, 100, 80),
				Glare = 0,
				Haze = 4,
			},
		},
		transition = {
			fadeIn = 1.5,
			fadeOut = 1.0,
			easing = Enum.EasingStyle.Sine,
		},
	},

	-- Theme: Default atmospheric base (overridden by theme packs)
	themeAtmosphere = {
		layer = "THEME",
		priority = 50,
		components = {
			Atmosphere = {
				Density = 0.30,
				Color = Color3.fromRGB(200, 200, 200),
				Decay = Color3.fromRGB(150, 150, 150),
				Glare = 0,
				Haze = 0,
			},
			SunRaysEffect = {
				Intensity = 0.25,
				Spread = 1.0,
			},
		},
		transition = {
			fadeIn = 2.0,
			fadeOut = 2.0,
			easing = Enum.EasingStyle.Sine,
		},
	},

	-- Gameplay: Damage/hurt effect
	damageFlash = {
		layer = "GAMEPLAY",
		priority = 200,
		components = {
			ColorCorrectionEffect = {
				TintColor = Color3.fromRGB(255, 100, 100),
				Brightness = 0.2,
				Contrast = 0.3,
				Saturation = -0.2,
			},
		},
		transition = {
			fadeIn = 0.05,
			fadeOut = 0.30,
			easing = Enum.EasingStyle.Linear,
		},
	},

	-- Gameplay: Heal/powerup effect
	healEffect = {
		layer = "GAMEPLAY",
		priority = 190,
		components = {
			ColorCorrectionEffect = {
				TintColor = Color3.fromRGB(150, 255, 150),
				Brightness = 0.15,
				Saturation = 0.2,
			},
			BloomEffect = {
				Intensity = 0.5,
				Size = 24,
				Threshold = 0.8,
			},
		},
		transition = {
			fadeIn = 0.2,
			fadeOut = 0.8,
			easing = Enum.EasingStyle.Back,
		},
	},

	-- Gameplay: Speed boost effect
	speedBoost = {
		layer = "GAMEPLAY",
		priority = 180,
		components = {
			ColorCorrectionEffect = {
				Contrast = 0.2,
				Saturation = 0.3,
			},
			BlurEffect = {
				Size = 3, -- Reduced for performance
			},
		},
		transition = {
			fadeIn = 0.3,
			fadeOut = 0.5,
			easing = Enum.EasingStyle.Quad,
		},
	},

	-- Transition: Screen fade to black
	screenFade = {
		layer = "TRANSITION",
		priority = 500,
		components = {
			ColorCorrectionEffect = {
				Brightness = -1, -- Full black
			},
		},
		transition = {
			fadeIn = 0.5,
			fadeOut = 0.5,
			easing = Enum.EasingStyle.Linear,
		},
	},

	-- Night time atmospheric override
	nightTime = {
		layer = "ENVIRONMENT",
		priority = 80,
		components = {
			ColorCorrectionEffect = {
				TintColor = Color3.fromRGB(180, 190, 220),
				Brightness = -0.1,
				Contrast = 0.05,
				Saturation = -0.1,
			},
			Atmosphere = {
				Density = 0.4,
				Color = Color3.fromRGB(100, 120, 180),
				Decay = Color3.fromRGB(80, 90, 120),
				Haze = 2,
			},
		},
		transition = {
			fadeIn = 3.0, -- Slow transition for day/night
			fadeOut = 3.0,
			easing = Enum.EasingStyle.Sine,
		},
	},
} :: { [string]: EffectDef }

-- Quality-based limits for mobile/low-end devices
export type ClassLimits = {
	BlurEffect: { maxSize: number? }?,
	DepthOfFieldEffect: { disabled: boolean?, maxFarIntensity: number? }?,
	Atmosphere: { maxDensity: number? }?,
}

PostProcessingConfig.QualityLimits = {
	Low = {
		BlurEffect = { maxSize = 3 },
		DepthOfFieldEffect = { disabled = true },
		Atmosphere = { maxDensity = 0.3 },
	},
	Medium = {
		BlurEffect = { maxSize = 6 },
		DepthOfFieldEffect = { maxFarIntensity = 0.5 },
		Atmosphere = { maxDensity = 0.5 },
	},
	High = {
		-- No limits
	},
} :: { [string]: ClassLimits }

-- Validation helper
function PostProcessingConfig.ValidateEffect(effectName: string): boolean
	return PostProcessingConfig.Effects[effectName] ~= nil
end

-- Get effect configuration
function PostProcessingConfig.GetEffect(effectName: string): EffectDef?
	return PostProcessingConfig.Effects[effectName] :: EffectDef?
end

return PostProcessingConfig
