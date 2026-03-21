--!strict
-- ServiceValidator.lua - Typed DI helper (no runtime introspection, no any)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MiningGame = ReplicatedStorage:WaitForChild("MiningGame")
local ServiceIndex = require(MiningGame:WaitForChild("ServiceIndex"))

type ServiceName = ServiceIndex.ServiceName
type Services = ServiceIndex.Services

export type ServiceContainer = {
	Get: (self: ServiceContainer, name: ServiceName) -> any,
	tryGet: (self: ServiceContainer, name: ServiceName) -> any,
	get: (self: ServiceContainer, name: ServiceName) -> any,
}

local ServiceValidator = {}

function ServiceValidator.get(
	container: ServiceContainer,
	name: ServiceName,
	_methods: { string }?,
	_properties: { string }?
)
	return container:Get(name)
end

function ServiceValidator.tryGet(
	container: ServiceContainer,
	name: ServiceName,
	_methods: { string }?,
	_properties: { string }?
)
	return container:tryGet(name)
end

return ServiceValidator
