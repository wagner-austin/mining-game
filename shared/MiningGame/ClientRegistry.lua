--!strict
-- ClientRegistry.lua
-- Minimal client-side registry to avoid `_G` globals.

local ClientRegistry = {}

-- Minimal UIManager interface used by registry callers
export type UIManagerT = {
	container: Frame?,
	fullBleedContainer: GuiObject?,
	overlayGui: ScreenGui?,
	scenes: { [string]: any }?,
	registerScene: ((self: UIManagerT, scene: any) -> ())?,
	showScene: ((self: UIManagerT, name: string, ...any) -> ())?,
	hideScene: ((self: UIManagerT, name: string) -> ())?,
	showNotification: (self: UIManagerT, message: string, kind: string?) -> (),
	showServerAnnouncement: (self: UIManagerT, message: string, color: Color3) -> (),
	showNotificationWithRarity: ((self: UIManagerT, message: string, rarity: string) -> ())?,
	showMiniPopup: ((self: UIManagerT, message: string, icon: string, pos: UDim2) -> ())?,
	hideMiniPopup: ((self: UIManagerT) -> ())?,
	accountDataProvider: (
		{ getSnapshot: (self: any) -> { [string]: any }?, onChanged: (self: any) -> RBXScriptSignal }
	)?,
}

-- Minimal VisualFeedback interface used across client code
export type VisualFeedbackT = {
	-- lifecycle
	Init: (self: VisualFeedbackT) -> (),
	Start: (self: VisualFeedbackT) -> (),
	Destroy: (self: VisualFeedbackT) -> (),
	-- event wiring
	BindToBus: (self: VisualFeedbackT, bus: any) -> () -> (),
	-- mining feedback API (called around digs)
	OnDig: (self: VisualFeedbackT) -> (),
	SetCooldown: (self: VisualFeedbackT, cooldown: number) -> (),
	SetCooldownEndsAt: (self: VisualFeedbackT, timestamp: number) -> (),
	SetCubeOrigin: (self: VisualFeedbackT, origin: CFrame) -> (),
	SetPreviewSize: (self: VisualFeedbackT, size: number) -> (),
	ShowDigResult: (self: VisualFeedbackT, success: boolean, position: Vector3?) -> (),
	SetActiveVolume: (self: VisualFeedbackT, origin: CFrame, sizeStuds: Vector3) -> (),
	-- optional pause/resume hooks used by panels
	Pause: ((self: VisualFeedbackT) -> ())?,
	Resume: ((self: VisualFeedbackT) -> ())?,
}

local _uiManager: UIManagerT? = nil
local _visualFeedback: VisualFeedbackT? = nil

function ClientRegistry.setUIManager(mgr: any)
	_uiManager = mgr
end

function ClientRegistry.getUIManager(): UIManagerT?
	return _uiManager
end

function ClientRegistry.setVisualFeedback(vf: VisualFeedbackT)
	_visualFeedback = vf
end

function ClientRegistry.getVisualFeedback(): VisualFeedbackT?
	return _visualFeedback
end

return ClientRegistry
