--!strict
--[[
    RendererRegistry.lua
    Central registry for cosmetic slot renderers.
    Allows modular, drop-in cosmetic types without editing main controller.
]]

local RendererRegistry = {}
local renderers: {[string]: any} = {}

function RendererRegistry.register(slot: string, renderer: any)
    assert(renderer.apply, "Renderer must have apply function")
    assert(renderer.remove, "Renderer must have remove function")
    renderers[slot] = renderer
end

function RendererRegistry.get(slot: string)
    return renderers[slot]
end

function RendererRegistry.getAll()
    return renderers
end

function RendererRegistry.count()
    local n = 0
    for _ in pairs(renderers) do
        n += 1
    end
    return n
end

return RendererRegistry