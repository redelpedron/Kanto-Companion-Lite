
--- Lifecycle: manages creation, initialization, and teardown of components.
-- Ensures deterministic cleanup to avoid memory leaks in long-running mods.
local Lifecycle = {}
Lifecycle.__index = Lifecycle

function Lifecycle.new()
    local self = setmetatable({}, Lifecycle)
    self._components = {}
    self._systems = {}
    return self
end

--- Create and init a component. Returns the instance.
function Lifecycle:createComponent(Class, locator, props)
    local instance = Class.new(locator, props)
    table.insert(self._components, instance)
    instance:_doInit()
    return instance
end

--- Register a system.
function Lifecycle:registerSystem(system)
    table.insert(self._systems, system)
    system:init()
    return system
end

--- Update all active components and systems.
function Lifecycle:update(dt)
    for _, sys in ipairs(self._systems) do
        if sys:isActive() then sys:update(dt) end
    end
    for _, comp in ipairs(self._components) do
        if comp:isActive() then comp:update(dt) end
    end
end

--- Draw all active components via the RenderSystem.
function Lifecycle:draw()
    for _, sys in ipairs(self._systems) do
        if sys:isActive() then sys:draw() end
    end
end

--- Destroy a single component.
function Lifecycle:destroyComponent(instance)
    for i, comp in ipairs(self._components) do
        if comp == instance then
            comp:destroy()
            table.remove(self._components, i)
            return
        end
    end
end

--- Destroy everything.
function Lifecycle:shutdown()
    for _, comp in ipairs(self._components) do
        pcall(function() comp:destroy() end)
    end
    self._components = {}
    for _, sys in ipairs(self._systems) do
        pcall(function() sys:destroy() end)
    end
    self._systems = {}
end

return Lifecycle
