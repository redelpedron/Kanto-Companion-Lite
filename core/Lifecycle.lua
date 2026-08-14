local Lifecycle = {}
Lifecycle.__index = Lifecycle

function Lifecycle.new()
    local self = setmetatable({}, Lifecycle)
    self._components = {}
    self._systems = {}
    self._locator = nil
    self._log = nil
    return self
end

function Lifecycle:setLocator(locator)
    self._locator = locator
end

function Lifecycle:setLogger(log)
    self._log = log
end

function Lifecycle:createComponent(Class, locator, props)

    if Class.needs and self._locator then
        for _, serviceName in ipairs(Class.needs) do
            if not self._locator:has(serviceName) then
                local msg = ("Component %s requires '%s' but it is not registered"):format(
                    Class.__name or "unknown", serviceName)
                if self._log then
                    self._log:error(msg)
                end
                error(msg, 2)
            end
        end
    end

    local instance = Class.new(locator, props)
    table.insert(self._components, instance)
    instance:_doInit()
    return instance
end

function Lifecycle:registerSystem(system)
    table.insert(self._systems, system)
    if system.init then system:init() end
    return system
end

function Lifecycle:update(dt)
    for _, sys in ipairs(self._systems) do
        if sys.update then sys:update(dt) end
    end
    for _, comp in ipairs(self._components) do
        if comp:isActive() then comp:update(dt) end
    end
end

function Lifecycle:draw()
    for _, sys in ipairs(self._systems) do
        if sys.draw then sys:draw() end
    end
end

function Lifecycle:shutdown()
    for _, comp in ipairs(self._components) do
        pcall(function() comp:destroy() end)
    end
    self._components = {}
    for _, sys in ipairs(self._systems) do
        pcall(function()
            if sys.destroy then sys:destroy() end
        end)
    end
    self._systems = {}
end

return Lifecycle
