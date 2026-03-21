--!strict
-- AccountDataProvider.lua
-- Centralized client-side data management for account/profile information

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Use EventBus for events
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Ready = require(MiningGame:WaitForChild("Ready"))
local Time = require(MiningGame:WaitForChild("Time"))
local EventBus = require(MiningGame:WaitForChild("EventBus"))
local EventNames = require(MiningGame:WaitForChild("EventNames"))
local PlayerProfileGuard = require(MiningGame:WaitForChild("PlayerProfileGuard"))
local ClientError = require(MiningGame:WaitForChild("ClientError"))
local Bus = EventBus.global()

local AccountDataProvider = {}
AccountDataProvider.__index = AccountDataProvider

local Types = require(MiningGame:WaitForChild("Types"))

export type Profile = {
	coins: number,
	gems: number?,
	totalBlocksDug: number?,
	sessionStartTime: number?,
	username: string?,
	displayName: string?,
	userId: number?,
	-- Extended data (typed)
	inventory: { [string]: number }?,
	settings: { [string]: Types.JsonValue }?,
	statistics: { [string]: number }?,
	upgrades: { [string]: number }?,
	equipped: Types.EquippedItems?,
	cubeStats: { totalChunks: number, dugCells: number, compressedSize: number }?,
	boosts: { [string]: number }?,
}

export type AccountSnapshot = {
	profile: Profile,
	cubeStats: { totalChunks: number, dugCells: number, compressedSize: number }?,
	sessionStartTime: number,
	lastUpdated: number,
	isLoading: boolean,
}

function AccountDataProvider.new()
	local self = setmetatable({}, AccountDataProvider)

	-- no external dependencies required
	self._profile = nil :: Profile?
	self._cubeStats = nil :: { totalChunks: number, dugCells: number, compressedSize: number }?
	self._sessionStartTime = nil :: number? -- Will be set from server
	self._lastUpdated = 0
	self._isLoading = false
	self._connections = {} :: { RBXScriptConnection }
	self._busUnsubs = {} :: { () -> () }

	-- Event for changes
	self._changed = Instance.new("BindableEvent")

	-- Initialize
	self:_fetchInitialData()
	self:_setupEventListeners()

	return self
end

-- Public API

function AccountDataProvider:getProfile(): Profile?
	return self._profile
end

function AccountDataProvider:getSnapshot(): AccountSnapshot
	return {
		profile = self._profile or self:_getDefaultProfile(),
		cubeStats = self._cubeStats,
		sessionStartTime = self._sessionStartTime or Time.unix(), -- Safe fallback
		lastUpdated = self._lastUpdated,
		isLoading = self._isLoading,
	}
end

function AccountDataProvider:onChanged(): RBXScriptSignal
	return self._changed.Event
end

function AccountDataProvider:refresh()
	self:_fetchInitialData()
end

function AccountDataProvider:destroy()
	-- Clean up EventBus subscriptions
	if self._busUnsubs then
		for _, unsub in ipairs(self._busUnsubs) do
			ClientError.try("AccountDataProvider.unsubscribe", unsub)
		end
		self._busUnsubs = {}
	end

	-- Clean up RBXScriptConnections
	if self._connections then
		for _, conn in ipairs(self._connections) do
			if typeof(conn) == "RBXScriptConnection" then
				ClientError.try("AccountDataProvider.Disconnect", function()
					conn:Disconnect()
				end)
			end
		end
		self._connections = {}
	end

	local changed = self._changed
	self._changed = nil
	if changed then
		changed:Destroy()
	end
end

-- Private Methods

function AccountDataProvider:_getDefaultProfile(): Profile
	return {
		coins = 0,
		gems = 0,
		totalBlocksDug = 0,
		currentDepth = 0,
		maxDepth = 0,
		joinTime = Time.unix(),
		playTime = 0,
		username = "Loading...",
		displayName = "Loading...",
		userId = 0,
		upgrades = { speed = 0, size = 0 },
		inventory = {},
		equipped = {},
	}
end

function AccountDataProvider:_fetchInitialData()
	if self._isLoading then
		return
	end

	-- Defensive check: if server isn't ready yet, defer until it is
	if not Ready.wait(0) then
		-- Server not ready, set up deferred fetch
		local conn
		conn = MiningGame:GetAttributeChangedSignal("ServerReady"):Connect(function()
			if MiningGame:GetAttribute("ServerReady") then
				conn:Disconnect()
				self:_fetchInitialData() -- Retry when ready
			end
		end)
		return
	end

	self._isLoading = true
	self:_notifyChange()

	task.spawn(function()
		-- Use PlayerProfileGuard for centralized profile access
		local profile, err = PlayerProfileGuard.get()

		self._isLoading = false

		if profile then
			-- Cast to shared PlayerStats shape for update routine
			self:_updateProfile(profile :: any)
			-- Prefer server-authored session start time (profile shape varies)
			local pp: any = profile
			self._sessionStartTime = pp.sessionStartTime or pp.joinTime or self._sessionStartTime or Time.unix()

			-- Cube stats may be included in the GetProfile response
			if pp.cubeStats then
				self._cubeStats = pp.cubeStats
			end
		elseif err then
			-- Log error but don't crash
			warn("[AccountDataProvider] Failed to fetch profile:", err)
		end
	end)
end

function AccountDataProvider:_updateProfile(newData: Types.PlayerStats)
	if not self._profile then
		self._profile = self:_getDefaultProfile()
	end

	-- Copy only the fields we use on the client
	local p = self._profile :: Profile
	p.coins = newData.coins or p.coins
	p.gems = newData.gems or p.gems
	p.totalBlocksDug = newData.totalBlocksDug or p.totalBlocksDug
	p.sessionStartTime = newData.sessionStartTime or p.sessionStartTime
	if newData.upgrades then
		p.upgrades = newData.upgrades
	end
	if newData.inventory then
		local inv: { [string]: number } = {}
		for k, v in pairs(newData.inventory) do
			inv[k] = tonumber(v) or 0
		end
		p.inventory = inv
	end
	if newData.equipped then
		p.equipped = newData.equipped
	end
	if newData.boosts then
		local b: { [string]: number } = {}
		for k, v in pairs(newData.boosts) do
			b[k] = tonumber(v) or 0
		end
		p.boosts = b
	end

	self._lastUpdated = Time.unix()
	self:_notifyChange()
end

function AccountDataProvider:_updateField(key: string, value: Types.JsonValue)
	if not self._profile then
		self._profile = self:_getDefaultProfile()
	end
	-- Apply only known keys for strict typing
	if key == "upgrades" and type(value) == "table" then
		self._profile.upgrades = value :: any -- validated above
	elseif key == "coins" and type(value) == "number" then
		self._profile.coins = value
	elseif key == "gems" and type(value) == "number" then
		self._profile.gems = value
	end
	self._lastUpdated = Time.unix()
	self:_notifyChange(key, value)
end

function AccountDataProvider:_notifyChange(key: string?, value: Types.JsonValue?)
	local snapshot = self:getSnapshot()
	self._changed:Fire(key, value, snapshot)
	-- Broadcast cross-module snapshot updates for client-local listeners
	local Contracts = require(MiningGame:WaitForChild("EventContracts"))
	Bus:emit(EventNames.ACCOUNT_SNAPSHOT_UPDATED, Contracts.ACCOUNT_SNAPSHOT_UPDATED(snapshot))
end

function AccountDataProvider:_setupEventListeners()
	-- Store unsubscribe functions for cleanup
	self._busUnsubs = {}

	-- Profile updates (full snapshot from server)
	table.insert(
		self._busUnsubs,
		Bus:on(EventNames.PROFILE_UPDATED, function(profile)
			self._profile = profile
			self:_notifyChange()
		end)
	)

	-- Currency changes
	table.insert(
		self._busUnsubs,
		Bus:on(EventNames.CURRENCY_CHANGED, function(currencyData)
			local p = self._profile or self:_getDefaultProfile()
			local c = currencyData
			if c then
				if c.currency == "coins" then
					p.coins = c.balance
				end
				if c.currency == "gems" then
					p.gems = c.balance
				end
			end
			self._profile = p
			self:_notifyChange()
		end)
	)

	-- Inventory changes (full snapshot)
	table.insert(
		self._busUnsubs,
		Bus:on(EventNames.INVENTORY_CHANGED, function(inventory)
			local p = self._profile or self:_getDefaultProfile()
			p.inventory = inventory
			self._profile = p
			self:_notifyChange()
		end)
	)

	-- Inventory deltas (incremental updates)
	table.insert(
		self._busUnsubs,
		Bus:on(EventNames.INVENTORY_DELTA, function(delta)
			local p = self._profile or self:_getDefaultProfile()
			local inv = (p.inventory or {}) :: { [string]: number }
			p.inventory = inv
			for itemId, inc in pairs(delta) do
				local current = inv[itemId] or 0
				inv[itemId] = current + (inc or 0)
			end
			self._profile = p
			self:_notifyChange("inventoryDelta", delta)
		end)
	)

	-- Debug reset via EventBus - refresh entire profile
	table.insert(
		self._busUnsubs,
		Bus:on(EventNames.DEBUG_RESET, function()
			-- Refetch entire profile from server
			self:_fetchInitialData()
		end)
	)

	-- Boosts changes via EventBus (keeping for compatibility)
	table.insert(
		self._busUnsubs,
		Bus:on(EventNames.BOOSTS_CHANGED, function(boosts)
			local prof = self._profile or self:_getDefaultProfile()
			prof.boosts = boosts
			self:_notifyChange("boosts", boosts)
		end)
	)

	-- Upgrades changes via EventBus
	table.insert(
		self._busUnsubs,
		Bus:on(EventNames.UPGRADES_CHANGED, function(upgrades)
			self:_updateField("upgrades", upgrades)
		end)
	)
end

return AccountDataProvider
