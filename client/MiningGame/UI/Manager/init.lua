--!strict
-- Manager init: central export for UIManager submodules

return {
	Animations = require(script:WaitForChild("Animations")),
	Widgets = require(script:WaitForChild("Widgets")),
	Layers = require(script:WaitForChild("Layers")),
	Scenes = require(script:WaitForChild("Scenes")),
	Toasts = require(script:WaitForChild("Toasts")),
	MiniPopup = require(script:WaitForChild("MiniPopup")),
}
