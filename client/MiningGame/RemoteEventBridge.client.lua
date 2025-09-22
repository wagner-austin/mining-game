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
-- Frequent client updates — skip middleware cost
Bus:markFastPath(EventNames.DIG_FEEDBACK)

-- Wait for the EventBus RemoteEvent with timeout
local RE = Remotes:WaitForChild("EventBus", 10)
if not RE then
    warn("[RemoteEventBridge] EventBus RemoteEvent not found after 10s")
    return
end

-- Server -> Client: Route events into the local bus
-- UI handlers should be non-yielding; use emitDeferred if handlers need to yield
RE.OnClientEvent:Connect(function(eventName: string, payload: any)
    -- Emit synchronously for UI responsiveness
    Bus:emit(eventName, payload)
end)

-- Client -> Server API
type BridgeApi = {
    send: (requestName: string, payload: any) -> (),
    requestSell: (itemId: string, quantity: number) -> (),
    requestEquip: (itemId: string, slot: string?) -> (),
    requestDig: (position: Vector3, toolId: string?) -> (),
    requestUpgrade: (upgradeId: string) -> (),
    requestEquipCosmetic: (cosmeticId: string, slot: string) -> (),
    updateSetting: (key: string, value: any) -> (),
    requestMetrics: () -> (),
}

local Bridge: BridgeApi = {} :: any

-- Whitelisted events that can be sent to server
local SENDABLE_EVENTS: {[string]: boolean} = {
    [RequestNames.INVENTORY_REQUEST_SELL] = true,
    [RequestNames.INVENTORY_REQUEST_EQUIP] = true,
    [RequestNames.UPGRADE_REQUEST_PURCHASE] = true,
    [RequestNames.COSMETIC_REQUEST_EQUIP] = true,
    [RequestNames.SETTINGS_UPDATE] = true,
    [RequestNames.METRICS_REQUEST] = true,
}
table.freeze(SENDABLE_EVENTS)

-- Send an event to the server
function Bridge.send(requestName: string, payload: any)
    -- Client-side validation
    if not SENDABLE_EVENTS[requestName] then
        warn(("[RemoteEventBridge] Attempted to send unregistered request '%s'"):format(requestName))
        return
    end
    
    RE:FireServer(requestName, payload)
end

-- Convenience methods for common events
function Bridge.requestSell(itemId: string, quantity: number)
    Bridge.send(RequestNames.INVENTORY_REQUEST_SELL, {
        itemId = itemId,
        quantity = quantity
    })
end

function Bridge.requestEquip(itemId: string, slot: string?)
    Bridge.send(RequestNames.INVENTORY_REQUEST_EQUIP, {
        itemId = itemId,
        slot = slot
    })
end

-- Note: Digging is handled via ClientRF (RemoteFunction) for immediate feedback

function Bridge.requestUpgrade(upgradeId: string)
    Bridge.send(RequestNames.UPGRADE_REQUEST_PURCHASE, {
        upgradeId = upgradeId
    })
end

function Bridge.requestEquipCosmetic(cosmeticId: string, slot: string)
    Bridge.send(RequestNames.COSMETIC_REQUEST_EQUIP, {
        cosmeticId = cosmeticId,
        slot = slot
    })
end

function Bridge.updateSetting(key: string, value: any)
    Bridge.send(RequestNames.SETTINGS_UPDATE, {
        key = key,
        value = value
    })
end

function Bridge.requestMetrics()
    Bridge.send(RequestNames.METRICS_REQUEST, {})
end

return Bridge
