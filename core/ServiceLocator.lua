
--- ServiceLocator: lightweight dependency-injection container.
-- Services are registered by name and lazily resolved.
local ServiceLocator = {}
ServiceLocator.__index = ServiceLocator

function ServiceLocator.new()
    local self = setmetatable({}, ServiceLocator)
    self._registry = {}
    self._cache = {}
    return self
end

--- Register a service instance or factory.
-- If `factory` is true, `instance` is called on first resolve.
function ServiceLocator:register(name, instance, factory)
    self._registry[name] = { value = instance, factory = factory == true }
    self._cache[name] = nil
end

--- Resolve a service by name.
function ServiceLocator:resolve(name)
    local cached = self._cache[name]
    if cached ~= nil then return cached end

    local entry = self._registry[name]
    if not entry then
        error("Service not registered: " .. tostring(name))
    end

    local value
    if entry.factory then
        value = entry.value(self)
    else
        value = entry.value
    end

    self._cache[name] = value
    return value
end

--- Check if a service is registered.
function ServiceLocator:has(name)
    return self._registry[name] ~= nil
end

--- Unregister a service (useful for testing / hot-reload).
function ServiceLocator:unregister(name)
    self._registry[name] = nil
    self._cache[name] = nil
end

--- Invalidate a cached service. Next resolve() will re-create it (for factories).
function ServiceLocator:invalidate(name)
    self._cache[name] = nil
end

--- Invalidate all cached services. Useful on game reset.
function ServiceLocator:invalidateAll()
    self._cache = {}
end

return ServiceLocator
