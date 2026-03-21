--!strict
-- Pets.rf.lua
-- Stub RemoteFunction specs for future pet system

-- Return a factory function that accepts the DI container
return function(_container)
	-- No services needed yet for this stub

	type RFSpec = {
		name: string,
		handler: (ctx: any, ...any) -> any,
		validate: ((...any) -> boolean)?,
		opts: { requireProfile: boolean?, rateLimitSec: number?, debugOnly: boolean? }?,
	}

	-- Stub handlers for future implementation
	local specs: { RFSpec } = {
		{
			name = "EquipPet",
			handler = function(_ctx, _petId: string)
				-- TODO: Implement when pet system is ready
				return {
					ok = false,
					success = false,
					err = "NOT_IMPLEMENTED",
					reason = "Pet system coming soon",
				}
			end,
			validate = function(petId)
				return type(petId) == "string" and #petId > 0 and #petId < 100
			end,
			opts = { requireProfile = true, rateLimitSec = 0.5 },
		},

		{
			name = "UnequipPet",
			handler = function(_ctx, _petId: string)
				-- TODO: Implement when pet system is ready
				return {
					ok = false,
					success = false,
					err = "NOT_IMPLEMENTED",
					reason = "Pet system coming soon",
				}
			end,
			validate = function(petId)
				return type(petId) == "string" and #petId > 0 and #petId < 100
			end,
			opts = { requireProfile = true, rateLimitSec = 0.5 },
		},

		{
			name = "UpgradePet",
			handler = function(_ctx, _petId: string, _upgradeType: string)
				-- TODO: Implement when pet system is ready
				return {
					ok = false,
					success = false,
					err = "NOT_IMPLEMENTED",
					reason = "Pet system coming soon",
				}
			end,
			validate = function(petId, upgradeType)
				if type(petId) ~= "string" or #petId == 0 or #petId > 100 then
					return false
				end
				if type(upgradeType) ~= "string" or #upgradeType == 0 or #upgradeType > 50 then
					return false
				end
				return true
			end,
			opts = { requireProfile = true, rateLimitSec = 1.0 },
		},
	}

	return specs
end -- End of factory function
