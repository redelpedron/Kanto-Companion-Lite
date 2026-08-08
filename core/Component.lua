
--- Component: abstract base for all HUD widgets.
-- Lifecycle: init -> update -> draw -> onEvent -> destroy
-- Components receive only the services they declare via `needs`.
local Component = {}
Component.__index = Component

--- `needs` is a table of service names this component requires.
Component.needs = {}

function Component.new(locator, props)
    local self = setmetatable({}, Component)
    self._locator = locator
    self._props = props or {}
    self._active = true
    self._listeners = {}   -- list of unsubscribe functions
    self._initialized = false
    return self
end

--- Resolve a required service.
function Component:_service(name)
    return self._locator:resolve(name)
end

--- Internal init wrapper.
function Component:_doInit()
    if self._initialized then return end
    self:init()
    self._initialized = true
end

--- Override in subclass. Subscribe to events here.
function Component:init() end

--- Override in subclass. Called every frame with dt.
function Component:update(dt) end

--- Override in subclass. Called with a DrawContext.
function Component:draw(ctx) end

--- Override in subclass. Handle EventBus events here.
function Component:onEvent(eventName, ...) end

--- Register an EventBus listener that auto-cleans on destroy.
function Component:_listen(eventName, handler)
    local bus = self._locator:resolve("EventBus")
    local unsub = bus:subscribe(eventName, function(...) handler(self, ...) end)
    table.insert(self._listeners, unsub)
end

--- Merge a layout rect (x, y, w, h, and any layout-specific extras like
-- isPortrait/section/stackMode) into this component's props. Only the
-- keys present in `rect` are touched, so other props a component holds
-- (e.g. data props like pokemonData set by a separate data-refresh
-- handler) are left alone. This is the one sanctioned way for outside
-- code to push layout geometry into a component -- callers should never
-- assign to `_props` directly.
function Component:setLayout(rect)
    if not rect then return end
    for k, v in pairs(rect) do
        self._props[k] = v
    end
end

--- Deactivate this component (stops updates/draws).
function Component:setActive(active)
    self._active = active
end

function Component:isActive()
    return self._active
end

--- Clean up all listeners and resources.
function Component:destroy()
    for _, unsub in ipairs(self._listeners) do
        pcall(unsub)
    end
    self._listeners = {}
    self._active = false
end

return Component
