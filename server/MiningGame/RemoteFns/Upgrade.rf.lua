--!strict
-- Upgrade.rf.lua
-- RemoteFunction specs for upgrade operations
-- Contract: top-level { ok, success, ... }. Exceptions: GetServerUnix (scalar), Equipped maps (raw).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

-- Return a factory function that accepts the DI container
return function(container)
	-- Resolve services from the container
	local UpgradeService = container:Get("UpgradeService")

	type RFSpec = {
		name: string,
		handler: (ctx: any, ...any) -> any,
		validate: ((...any) -> boolean)?,
		opts: { requireProfile: boolean?, rateLimitSec: number? }?,
	}

	local specs: { RFSpec } = {
		{
			name = "PurchaseUpgrade",
			handler = function(ctx, upgradeType: string)
				-- ctx.profile is present because requireProfile=true
				local profile = ctx.profile
				if not profile then
					return { ok = false, success = false, err = "NO_PROFILE", reason = "Profile not found" }
				end

				local res = UpgradeService:PurchaseUpgrade(ctx.player, profile, upgradeType)
				if res and res.success then
					-- Return at top level to match client expectations
					return {
						ok = true,
						success = true,
						newLevel = res.newLevel,
						costNext = res.costNext,
					}
				else
					return {
						ok = false,
						success = false,
						err = "PURCHASE_FAILED",
						reason = (res and res.reason) or "Failed to purchase upgrade",
					}
				end
			end,
			validate = function(upgradeType)
				if type(upgradeType) ~= "string" or #upgradeType == 0 or #upgradeType > 64 then
					return false
				end
				-- Whitelist via GameConfig.Upgrades
				return GameConfig.Upgrades and GameConfig.Upgrades[upgradeType] ~= nil
			end,
			opts = { requireProfile = true, rateLimitSec = 0.2 },
		},
	}

	return specs
end -- End of factory function
