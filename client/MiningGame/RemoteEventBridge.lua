--!strict
--[[
    RemoteEventBridge.client.lua
    Client-side bridge between EventBus and RemoteEvents.
    
    Features:
    - Receives server events and routes to local EventBus
    - Provides safe API for sending events to server
    - Optional event validation
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local Remotes = MiningGame:WaitForChild("Remotes")
local EventBus = require(MiningGame.EventBus)
local EventNames = require(MiningGame.EventNames)
local RequestNames = require(MiningGame.RequestNames)
local Bus = EventBus.global()
-- Frequent client updates �?" skip middleware cost
Bus:markFastPath(EventNames.DIG_FEEDBACK)
Bus:markFastPath(EventNames.INVENTORY_DELTA)

-- Wait for the EventBus RemoteEvent with timeout
-- Client -> Server API (declare early for fallback typing)
type BridgeApi = {
	send: (requestName: string, payload: any) -> (),
	requestSell: (itemId: string, quantity: number) -> (),
	requestEquip: (itemId: string, slot: string?) -> (),
	requestDig: (position: Vector3, toolId: string?) -> (),
	requestUpgrade: (upgradeId: string) -> (),
	requestEquipCosmetic: (cosmeticId: string, slot: string) -> (),
	updateSetting: (key: string, value: any) -> (),
	requestMetrics: () -> (),
	requestServerMetrics: () -> (),
}

local RE = Remotes:WaitForChild("EventBus", 10)
if not RE then
	warn("[RemoteEventBridge] EventBus RemoteEvent not found after 10s")
	local function _noop(...: any)
		local _ = ...
	end
	local fallback: BridgeApi = {
		send = _noop,
		requestSell = _noop,
		requestEquip = _noop,
		requestDig = _noop,
		requestUpgrade = _noop,
		requestEquipCosmetic = _noop,
		updateSetting = _noop,
		requestMetrics = _noop,
		requestServerMetrics = _noop,
	}
	return fallback
end

-- Server -> Client: Route events into the local bus
-- UI handlers should be non-yielding; use emitDeferred if handlers need to yield
RE.OnClientEvent:Connect(function(eventName: string, payload: any)
	-- Emit synchronously for UI responsiveness
	Bus:emit(eventName, payload)
end)

-- Whitelisted events that can be sent to server
local SENDABLE_EVENTS: { [string]: boolean } = {
	[RequestNames.INVENTORY_REQUEST_SELL] = true,
	[RequestNames.INVENTORY_REQUEST_EQUIP] = true,
	[RequestNames.UPGRADE_REQUEST_PURCHASE] = true,
	[RequestNames.COSMETIC_REQUEST_EQUIP] = true,
	[RequestNames.SETTINGS_UPDATE] = true,
	[RequestNames.METRICS_REQUEST] = true,
	[RequestNames.SERVER_METRICS_REQUEST] = true,
	[RequestNames.TELEPORT_RANDOM_SKY] = true,
}
table.freeze(SENDABLE_EVENTS)

local function sendImpl(requestName: string, payload: any)
	if not SENDABLE_EVENTS[requestName] then
		warn(("[RemoteEventBridge] Attempted to send unregistered request '%s'"):format(requestName))
		return
	end
	RE:FireServer(requestName, payload)
end

local Bridge: BridgeApi = {
	send = sendImpl,
	requestSell = function(itemId: string, quantity: number)
		sendImpl(RequestNames.INVENTORY_REQUEST_SELL, { itemId = itemId, quantity = quantity })
	end,
	requestEquip = function(itemId: string, slot: string?)
		sendImpl(RequestNames.INVENTORY_REQUEST_EQUIP, { itemId = itemId, slot = slot })
	end,
	requestDig = function(position: Vector3, toolId: string?)
		sendImpl(RequestNames.DIG_REQUEST, { position = position, toolId = toolId })
	end,
	requestUpgrade = function(upgradeId: string)
		sendImpl(RequestNames.UPGRADE_REQUEST_PURCHASE, { upgradeId = upgradeId })
	end,
	requestEquipCosmetic = function(cosmeticId: string, slot: string)
		sendImpl(RequestNames.COSMETIC_REQUEST_EQUIP, { cosmeticId = cosmeticId, slot = slot })
	end,
	updateSetting = function(key: string, value: any)
		sendImpl(RequestNames.SETTINGS_UPDATE, { key = key, value = value })
	end,
	requestMetrics = function()
		sendImpl(RequestNames.METRICS_REQUEST, {})
	end,
	requestServerMetrics = function()
		sendImpl(RequestNames.SERVER_METRICS_REQUEST, {})
	end,
}

-- Whitelisted events that can be sent to server
-- moved up

-- Send an event to the server
-- Note: Digging is also available via ClientRF in some flows, but event exists for parity

return Bridge
