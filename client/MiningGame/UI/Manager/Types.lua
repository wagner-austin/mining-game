--!strict
-- Types.lua for UI Manager shared across Scenes/Layers/MiniPopup/Toasts

local Types = {}

-- Import types for MiniPopup handle without introducing runtime anys
-- Avoid tight coupling to BaseChip instance type here; require only destroy method

-- Toasts
export type ToastKind = "info" | "success" | "error" | "warning"
export type CustomToastArgs = {
	labelText: string,
	iconText: string,
	accentColor: Color3,
	richText: boolean,
	duration: number,
	textColor: Color3?,
}
export type ToastQueueItem = {
	message: string?,
	kind: ToastKind?,
	duration: number?,
	rarityData: string?,
	custom: CustomToastArgs?,
}

export type SceneT = {
	name: string,
	frame: Frame?,
	init: (self: SceneT, manager: UIManagerT) -> (),
	show: (self: SceneT) -> (),
	hide: (self: SceneT) -> (),
	cleanup: ((self: SceneT) -> ())?,
	refreshTheme: ((self: SceneT) -> ())?,
}

export type UIManagerT = {
	-- Roots
	screenGui: ScreenGui?,
	overlayGui: ScreenGui?,
	container: Frame?,
	toastStack: Frame?,
	toastLayout: UIListLayout?,
	updateToastPosition: ((self: UIManagerT) -> ())?,

	-- Scenes
	scenes: { [string]: SceneT },
	activeScene: SceneT?,
	sceneStack: { SceneT },

	-- Internals
	_cons: { RBXScriptConnection },
	_transitionUnlockAt: number,
	_watchdogLastVisibleAt: number,
	_isRecovering: boolean,

	-- Optional helpers referenced by MiniPopup
	fullBleedContainer: GuiObject?,
	_miniPopup: { anchor: Frame, chip: { destroy: (self: {}) -> () }, fadeOut: (() -> ())? }?,
	_ensureRootsExist: ((self: UIManagerT) -> ())?,

	-- Toasts subsystem (queue and helpers)
	_toastQueue: { ToastQueueItem },
	_toastActive: number,
	_toastMaxVisible: number,
	_setTimeout: (self: UIManagerT, delay: number, fn: () -> ()) -> thread,
	_clearTimeout: (self: UIManagerT, h: thread?) -> (),
	_durationFor: (self: UIManagerT, message: string) -> number,
}

return Types
