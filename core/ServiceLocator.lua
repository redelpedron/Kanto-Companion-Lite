local ServiceLocator = {}
ServiceLocator.__index = ServiceLocator

function ServiceLocator.new()
    local self = setmetatable({}, ServiceLocator)
    self._registry = {}
    self._cache = {}
    return self
end

function ServiceLocator:register(name, instance, factory)
    self._registry[name] = { value = instance, factory = factory == true }
    self._cache[name] = nil
end

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

function ServiceLocator:has(name)
    return self._registry[name] ~= nil
end

return ServiceLocator
