--!strict
-- ServiceValidator.lua - Helper for validating service interfaces in DI

local ServiceValidator = {}

export type ServiceContainer = {
    Get: (self: any, name: string) -> any,
    tryGet: (self: any, name: string) -> any,
}

local function join(list: {string}, sep: string): string
    local out = ""
    for i, s in ipairs(list) do
        out ..= s .. (i < #list and sep or "")
    end
    return out
end

-- Validate that a service has the expected methods (aggregate errors)
function ServiceValidator.assertInterface(serviceName: string, service: any, methods: {string})
    local errs = {}
    if type(service) ~= "table" then
        table.insert(errs, serviceName .. " is not a table")
    else
        for _, m in ipairs(methods) do
            if type(service[m]) ~= "function" then
                table.insert(errs, string.format("missing method '%s'", m))
            end
        end
    end
    if #errs > 0 then
        error(string.format("%s failed interface check: %s", serviceName, join(errs, "; ")))
    end
end

-- Validate that a service has expected properties (aggregate errors)
function ServiceValidator.assertProperties(serviceName: string, service: any, properties: {string})
    local errs = {}
    if type(service) ~= "table" then
        table.insert(errs, serviceName .. " is not a table")
    else
        for _, p in ipairs(properties) do
            if service[p] == nil then
                table.insert(errs, string.format("missing property '%s'", p))
            end
        end
    end
    if #errs > 0 then
        error(string.format("%s failed property check: %s", serviceName, join(errs, "; ")))
    end
end

-- Convenience: fetch from the container, validate, and return
function ServiceValidator.get(container: ServiceContainer, name: string, methods: {string}?, properties: {string}?)
    local svc = container:Get(name)  -- Will throw if service not found
    if methods and #methods > 0 then
        ServiceValidator.assertInterface(name, svc, methods)
    end
    if properties and #properties > 0 then
        ServiceValidator.assertProperties(name, svc, properties)
    end
    return svc
end

-- Optional: fetch from container without failing if missing (for soft dependencies)
function ServiceValidator.tryGet(container: ServiceContainer, name: string, methods: {string}?, properties: {string}?)
    local svc = container:tryGet(name)
    if not svc then
        return nil
    end
    -- Still validate if we got something
    if methods and #methods > 0 then
        ServiceValidator.assertInterface(name, svc, methods)
    end
    if properties and #properties > 0 then
        ServiceValidator.assertProperties(name, svc, properties)
    end
    return svc
end

-- Batch validation for multiple services
function ServiceValidator.assertInterfaces(interfaces: {{name: string, service: any, methods: {string}}})
    local allErrors = {}
    for _, interface in ipairs(interfaces) do
        local errs = {}
        if type(interface.service) ~= "table" then
            table.insert(errs, interface.name .. " is not a table")
        else
            for _, m in ipairs(interface.methods) do
                if type(interface.service[m]) ~= "function" then
                    table.insert(errs, string.format("%s missing method '%s'", interface.name, m))
                end
            end
        end
        if #errs > 0 then
            table.insert(allErrors, join(errs, "; "))
        end
    end
    if #allErrors > 0 then
        error("Interface validation failed: " .. join(allErrors, " | "))
    end
end

return ServiceValidator
