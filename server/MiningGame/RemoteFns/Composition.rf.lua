--!strict
-- Composition.rf.lua
-- RemoteFunction specs for theme-based composition system
-- Clean, theme-first, no backwards compatibility

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local CubeThemes = require(Shared:WaitForChild("CubeThemes"))

-- Return a factory function that accepts the DI container
return function(container)
	-- Resolve services from the container
	local CompositionService = container:Get("CompositionService")

	type RFSpec = {
		name: string,
		handler: (ctx: any, ...any) -> any,
		validate: ((...any) -> boolean)?,
		opts: { requireProfile: boolean?, rateLimitSec: number?, debugOnly: boolean? }?,
	}

	local specs: { RFSpec } = {
		{
			name = "GetActiveComposition",
			handler = function(ctx)
				local comp = CompositionService:GetActiveComposition(ctx.player)
				if comp then
					return {
						ok = true,
						success = true,
						id = comp.id,
						name = comp.name,
						dropModifiers = comp.dropModifiers, -- { rarityBoost, specificItems?, exclusiveItems? }
					}
				end
				return { ok = true, success = true, id = nil, name = nil, dropModifiers = nil }
			end,
			opts = { requireProfile = true, rateLimitSec = 0.2 },
		},
		{
			name = "ListCompositions",
			handler = function(ctx)
				local payload = CompositionService:ListCompositions(ctx.player) or {}
				-- Return full payload at top level
				local out = table.clone(payload)
				out.ok = true
				out.success = true
				return out
			end,
			opts = { requireProfile = false, rateLimitSec = 1.0 }, -- Light call for early boot
		},

		{
			name = "ApplyComposition",
			handler = function(ctx, themeId: string, preserveAir: boolean?)
				-- Call the new theme-first signature
				local ok, msg = CompositionService:ApplyComposition(ctx.player, themeId, preserveAir)
				if ok then
					return { ok = true, success = true, theme = themeId }
				end
				return {
					ok = false,
					success = false,
					err = "APPLY_FAILED",
					reason = tostring(msg) or "Failed to apply theme",
				}
			end,
			validate = function(themeId, preserveAir)
				if type(themeId) ~= "string" then
					return false
				end
				if not CubeThemes.GetTheme(themeId) then
					return false
				end
				if preserveAir ~= nil and type(preserveAir) ~= "boolean" then
					return false
				end
				return true
			end,
			opts = { requireProfile = true, rateLimitSec = 0.5 },
		},

		{
			name = "RegenerateComposition",
			handler = function(ctx)
				local ok, msg = CompositionService:RegenerateComposition(ctx.player)
				if ok then
					return { ok = true, success = true }
				end
				return {
					ok = false,
					success = false,
					err = "REGENERATE_FAILED",
					reason = tostring(msg) or "Failed to regenerate",
				}
			end,
			opts = { requireProfile = true, rateLimitSec = 2.0 }, -- Higher limit for expensive operation
		},
	}

	return specs
end -- End of factory function
