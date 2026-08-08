
--- System: abstract base for engine systems (Render, Input, Layout, etc.).
-- Systems are singleton services managed by the ServiceLocator.
local System = {}
System.__index = System

function System.new(locator)
    local self = setmetatable({}, System)
    self._locator = locator
    self._active = true
    return self
end

function System:_service(name)
    return self._locator:resolve(name)
end

function System:init() end
function System:update(dt) end
function System:draw() end
function System:destroy() end

function System:setActive(active)
    self._active = active
end

function System:isActive()
    return self._active
end

return System
