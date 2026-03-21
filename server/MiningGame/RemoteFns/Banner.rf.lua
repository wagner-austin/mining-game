--!strict
-- Banner.rf.lua
-- RemoteFunctions to get/set base banner configuration (Studio-only)

local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("MiningGame")
local Result = require(Shared:WaitForChild("Result"))

return function(_container)
	local BannerConfig = require(ServerScriptService:WaitForChild("Cloth"):WaitForChild("BannerConfig"))

	local function isDev(_player: Player): boolean
		return RunService:IsStudio()
	end

	local function okSchemaZeroArgs(...: any): (boolean, string?)
		return select("#", ...) == 0, "no args expected"
	end

	local function schemaSetConfig(arg: any): (boolean, string?)
		if type(arg) ~= "table" then
			return false, "table expected"
		end
		-- Optional keys with type checks
		local allowed = {
			PITCH_X_DEG = "number",
			YAW_Y_DEG = "number",
			ROLL_Z_DEG = "number",
			LIFT_Y = "number",
			INWARD_X_T = "number",
			INSIDE_Z = "number",
			ALONG_Z_T = "number",
			MATCH_GLOW_TO_BANNER = "boolean",
			COLOR = true, -- special: string hex or {r,g,b}
		}
		for k, v in pairs(arg) do
			if allowed[k] == nil then
				return false, "unknown key: " .. tostring(k)
			end
			if k == "COLOR" then
				if type(v) == "string" then
					-- Expect #RRGGBB
					if not v:match("^#%x%x%x%x%x%x$") and not v:match("^#%x%x%x$") then
						return false, "invalid COLOR hex"
					end
				elseif type(v) == "table" then
					if type(v.r) ~= "number" or type(v.g) ~= "number" or type(v.b) ~= "number" then
						return false, "invalid COLOR rgb"
					end
				else
					return false, "invalid COLOR"
				end
			else
				if allowed[k] ~= type(v) then
					return false, "invalid type for " .. k
				end
			end
		end
		return true, nil
	end

	local function parseColor(c: any): Color3?
		if typeof(c) == "Color3" then
			return c
		end
		if type(c) == "string" then
			if #c == 7 and c:sub(1, 1) == "#" then
				local r = tonumber(c:sub(2, 3), 16)
				local g = tonumber(c:sub(4, 5), 16)
				local b = tonumber(c:sub(6, 7), 16)
				if r and g and b then
					return Color3.fromRGB(r, g, b)
				end
			end
			return nil
		end
		if type(c) == "table" and type(c.r) == "number" and type(c.g) == "number" and type(c.b) == "number" then
			return Color3.fromRGB(c.r, c.g, c.b)
		end
		return nil
	end

	-- Strongly-typed partial update object
	type BannerPartial = {
		PITCH_X_DEG: number?,
		YAW_Y_DEG: number?,
		ROLL_Z_DEG: number?,
		LIFT_Y: number?,
		INWARD_X_T: number?,
		INSIDE_Z: number?,
		ALONG_Z_T: number?,
		MATCH_GLOW_TO_BANNER: boolean?,
		COLOR: Color3?,
	}

	type RFSpec = {
		name: string,
		handler: (ctx: any, ...any) -> any,
		validate: ((...any) -> (boolean, string?))?,
		opts: { requireProfile: boolean?, rateLimitSec: number?, debugOnly: boolean? }?,
	}

	local specs: { RFSpec } = {
		{
			name = "BannerGetConfig",
			handler = function(ctx)
				if not isDev(ctx.player) then
					return Result.err("FORBIDDEN", "Not authorized")
				end
				local t = BannerConfig.get()
				local out = table.clone(t)
				return Result.ok(out)
			end,
			validate = okSchemaZeroArgs,
			opts = { requireProfile = false, rateLimitSec = 0.5, debugOnly = true },
		},
		{
			name = "BannerSetConfig",
			handler = function(ctx, partial: BannerPartial)
				if not isDev(ctx.player) then
					return Result.err("FORBIDDEN", "Not authorized")
				end
				local p = table.clone(partial or {})
				if p.COLOR ~= nil then
					local c = parseColor(p.COLOR)
					if not c then
						return Result.err("INVALID_COLOR", "Invalid color value")
					end
					p.COLOR = c
				end
				BannerConfig.update(p)
				local t = BannerConfig.get()
				local out = table.clone(t)
				return Result.ok(out)
			end,
			validate = schemaSetConfig,
			opts = { requireProfile = false, rateLimitSec = 0.5, debugOnly = true },
		},
	}

	return specs
end
