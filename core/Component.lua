local Component = {}
Component.__index = Component

Component.needs = {}

function Component.new(locator, props)
    local self = setmetatable({}, Component)
    self._locator = locator
    self._props = props or {}
    self._active = true
    self._listeners = {}
    self._initialized = false

    self._layoutKeys = {}
    return self
end

function Component:_service(name)
    return self._locator:resolve(name)
end

function Component:_doInit()
    if self._initialized then return end
    self:init()
    self._initialized = true
end

function Component:init() end

function Component:update(dt) end

function Component:draw(ctx) end

function Component:_listen(eventName, handler)
    local bus = self._locator:resolve("EventBus")
    local unsub = bus:subscribe(eventName, function(...) handler(self, ...) end)
    table.insert(self._listeners, unsub)
end

function Component:setLayout(rect)
    if not rect then return end

    for k, _ in pairs(self._layoutKeys) do
        if rect[k] == nil then
            self._props[k] = nil
        end
    end

    self._layoutKeys = {}
    for k, v in pairs(rect) do
        self._props[k] = v
        self._layoutKeys[k] = true
    end
end

function Component:setActive(active)
    self._active = active
end

function Component:isActive()
    return self._active
end

function Component:destroy()
    for _, unsub in ipairs(self._listeners) do
        pcall(unsub)
    end
    self._listeners = {}
    self._active = false
end

return Component
