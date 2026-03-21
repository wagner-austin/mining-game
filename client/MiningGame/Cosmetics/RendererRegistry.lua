--!strict
--[[
    RendererRegistry.lua
    Central registry for cosmetic slot renderers.
    Allows modular, drop-in cosmetic types without editing main controller.
]]

local RendererRegistry = {}

export type CosmeticDef = {
	id: string?,
	color: Color3?,
	tint: Color3?,
	transparency: number?,
	material: Enum.Material?,
	materialPreset: string?,
	variant: string?,

	-- Trail renderer optional fields
	itemId: string?,
	effect: string?,
	bandCount: number?,
	bandSeparation: number?,
	bandOffset: number?,
	bandAxis: string?,
	minLength: number?,
	faceCamera: boolean?,
	lightEmission: number?,
	widthScaleSequence: NumberSequence | { number }?,
	texture: string?,
	textureLength: number?,
	textureMode: Enum.TextureMode?,
	colorSequence: ColorSequence | { Color3 }?,
	transparencySequence: NumberSequence | { number }?,

	-- Aura renderer optional fields
	particleTexture: string?,
	emissionRate: number?,
	lifetime: number? | NumberRange?,
	lifetimeRange: { number }?,
	speed: number? | NumberRange?,
	speedRange: { number }?,
	spreadAngle: Vector2 | { number }?,
	lightInfluence: number?,
	acceleration: Vector3?,
	rotSpeed: number? | NumberRange?,
	velInheritance: number?,
	lightBrightness: number?,
	lightRange: number?,
	sizeSequence: NumberSequence | { number }?,

	-- Hand/Head procedural hints (unified)
	kind: ("pickaxe" | "sword" | "warhammer" | "horns" | "halo" | "crown" | "charm" | "sunglasses")?,
	procedural: { kind: "pickaxe" | "sword" | "warhammer" | "horns" | "halo" | "crown" | "charm" | "sunglasses" }?,
	headHighlight: boolean?,
	headPulse: boolean?,
	headTint: Color3?,
	headPulseColor2: Color3?,
	headPulseSpeed: number?,
	bladeTint: Color3?,
	bladeHighlight: boolean?,
	pulse: boolean?,
	pulseSpeed: number?,
	handleMaterial: Enum.Material?,
	headMaterial: Enum.Material?,
	-- shared dims
	handleLength: number?,
	handleRadius: number?,
	gripOffset: number?,
	gripHandOffsetY: number?,
	gripTiltDeg: number?,
	gripYawDeg: number?,
	gripRollDeg: number?,
	headLength: number?,
	headWidth: number?,
	headHeight: number?,
	headAttachOffsetZ: number?,
	bladeLength: number?,
	bladeWidth: number?,
	bladeThickness: number?,
	guardRingRadius: number?,
	guardRingThickness: number?,
	guardRingSegments: number?,
	handleTint: Color3?,

	-- Head (procedural) optional fields
	scale: number?,
	glows: boolean?,
	segments: number?,
	-- horns
	hornLength: number?,
	hornRadius: number?,
	hornSeparation: number?,
	hornTiltDeg: number?,
	hornHeightOffset: number?,
	-- halo
	haloThickness: number?,
	thickness: number?,
	haloRadius: number?,
	radius: number?,
	haloHeightOffset: number?,
	heightOffset: number?,
	haloRingOffset: number?,
	-- crown
	crownRadius: number?,
	bandHeight: number?,
	height: number?,
	bandThickness: number?,
	crownHeightOffset: number?,
	spikeCount: number?,
	spikeHeight: number?,
	spikeRadius: number?,
	spikeTiltDeg: number?,
	spikeSegments: number?,
	-- charm
	charmCoreRadius: number?,
	coreRadius: number?,
	charmRingRadius: number?,
	ringRadius: number?,
	charmRingThickness: number?,
	ringThickness: number?,
	charmHeightOffset: number?,
	charmForwardOffset: number?,
	forwardOffset: number?,
	charmPlacement: string?,
	placement: string?,
	charmOrbRing: boolean?,
	orbRing: boolean?,
	charmOrbCount: number?,
	orbCount: number?,
	charmOrbSmallRadius: number?,
	orbSmallRadius: number?,
	charmOrbMediumRadius: number?,
	orbMediumRadius: number?,
	charmOrbRadius: number?,
	orbRadius: number?,
	charmSpinHz: number?,
	spinHz: number?,
	-- sunglasses
	glassesForwardOffset: number?,
	glassesHeightOffset: number?,
	lensWidth: number?,
	lensHeight: number?,
	lensThickness: number?,
	bridgeWidth: number?,
	frameThickness: number?,
	templeLength: number?,
	templeThickness: number?,
	lensTint: Color3?,
	lensColor: Color3?,
	lensTransparency: number?,
	frameColor: Color3?,

	-- Head renderer routing hints
	shape: ("horns" | "halo" | "crown" | "charm" | "sunglasses" | "helmet")?,

	-- Back renderer optional fields
	spanStuds: number?,
	wingHeight: number?,
	wingThickness: number?,
	mountX: number?,
	mountY: number?,
	mountZ: number?,
	highlight: boolean?,
	highlightColor: Color3?,
	highlightFillT: number?,
	highlightOutlineT: number?,
	colorMode: string?,
	hueSpeedHz: number?,
	colorSpeedHz: number?,
	animates: boolean?,
	animSpec: { speedHz: number?, freqHz: number?, amplitudeDeg: number?, axis: string? }?,
	lightColor: Color3?,
}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Types = require(Shared:WaitForChild("Types"))

export type RendererCtx = {
	instances: { Instance }?,
	connections: { RBXScriptConnection }?,
	-- renderer-specific optional state container (JSON-like to avoid anys)
	state: { [string]: Types.JsonValue }?,
}

export type Renderer = {
	priority: number?,
	apply: (character: Model, def: CosmeticDef) -> RendererCtx?,
	remove: (ctx: RendererCtx) -> (),
	preload: ((def: CosmeticDef, character: Model) -> { Instance })?,
	showPlaceholder: ((character: Model, def: CosmeticDef) -> ())?,
	hidePlaceholder: ((character: Model) -> ())?,
}

local renderers: { [string]: Renderer } = {}

function RendererRegistry.register(slot: string, renderer: Renderer)
	assert(renderer.apply, "Renderer must have apply function")
	assert(renderer.remove, "Renderer must have remove function")
	renderers[slot] = renderer
end

function RendererRegistry.get(slot: string): Renderer?
	return renderers[slot]
end

function RendererRegistry.getAll(): { [string]: Renderer }
	return renderers
end

function RendererRegistry.count()
	local n = 0
	for _ in pairs(renderers) do
		n += 1
	end
	return n
end

return RendererRegistry
