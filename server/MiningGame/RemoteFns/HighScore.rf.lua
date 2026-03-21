--!strict
-- HighScore.rf.lua
-- RemoteFunctions for fetching server-local high scores (current session)

local Players = game:GetService("Players")
-- No Shared modules needed here
-- Logger removed (unused)

return function(container)
	local DataService = container:Get("DataService")

	type RFSpec = {
		name: string,
		handler: (ctx: any, ...any) -> any,
		validate: ((...any) -> boolean)?,
		opts: { requireProfile: boolean?, rateLimitSec: number? }?,
	}

	local function collectScores(category: string, limit: number): { { name: string, value: number } }
		local list = {}
		for _, plr in ipairs(Players:GetPlayers()) do
			local profile = DataService:GetPlayerData(plr)
			if profile then
				local value = 0
				if category == "blocks" then
					-- Lifetime blocks dug tracked on profile for cross-cube/material consistency
					value = tonumber(profile.totalBlocksDug or 0) or 0
				elseif category == "coins" then
					value = tonumber(profile.coins or 0) or 0
				elseif category == "donator" then
					value = tonumber((profile.robuxSpentDonations or 0)) or 0
				end
				table.insert(list, { name = plr.DisplayName or plr.Name, value = value })
			end
		end
		table.sort(list, function(a, b)
			return a.value > b.value
		end)
		local out = {}
		for i = 1, math.min(limit, #list) do
			out[i] = list[i]
		end
		return out
	end

	local specs: { RFSpec } = {
		{
			name = "GetHighScores",
			validate = function(category: any, limit: any)
				if type(category) ~= "string" then
					return false
				end
				local c = string.lower(category)
				if c ~= "blocks" and c ~= "coins" and c ~= "donator" and c ~= "teleport" then
					return false
				end
				if limit ~= nil and type(limit) ~= "number" then
					return false
				end
				return true
			end,
			handler = function(_ctx, category: string, limit: number?)
				category = string.lower(category)
				local lim: number
				if type(limit) == "number" then
					lim = limit
				else
					lim = 5
				end
				local entries
				if category == "teleport" then
					entries = {
						{ name = "⬆️ Up", value = 0 },
					}
				else
					entries = collectScores(category, lim)
				end
				-- Return entries at top-level to follow RF convention
				return { ok = true, success = true, entries = entries }
			end,
			opts = { requireProfile = true, rateLimitSec = 1.0 },
		},
	}

	return specs
end
