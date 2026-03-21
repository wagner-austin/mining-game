--!strict
-- ServiceRegistry.lua
-- Server-side registry to expose the ServiceContainer for Studio debugging

local ServiceRegistry = {}

local _container: any? = nil

function ServiceRegistry.setContainer(container: any)
	_container = container
end

function ServiceRegistry.getContainer(): any?
	return _container
end

return ServiceRegistry
