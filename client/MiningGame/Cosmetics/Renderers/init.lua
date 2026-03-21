--!strict
-- Renderers/init.lua
-- Static loader that requires all renderer modules so they can self-register

local renderRoot = script

-- Require each renderer explicitly to satisfy analyzer and avoid dynamic scans
require(renderRoot:WaitForChild("Aura"))
require(renderRoot:WaitForChild("Back"))
require(renderRoot:WaitForChild("Hand"))
require(renderRoot:WaitForChild("Head"))
require(renderRoot:WaitForChild("Trail"))

return true
