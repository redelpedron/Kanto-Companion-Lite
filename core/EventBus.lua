
--- EventBus: decoupled pub/sub with automatic cleanup.
-- Listeners are stored per-event with plain strong references.
-- Cleanup is explicit: Component:_listen records each subscription's
-- unsubscribe function and Component:destroy() calls them all, so nothing
-- needs to rely on the garbage collector to drop a listener. (A weak-value
-- list here would be a bug: the EventBus is the *only* place these bare
-- closures are referenced, so the GC would be free to collect them the
-- moment it runs -- often before they ever fire once -- silently turning
-- every subscribe() into a no-op with no error anywhere.)
local EventBus = {}
EventBus.__index = EventBus

function EventBus.new()
    local self = setmetatable({}, EventBus)
    self._listeners = {}      -- eventName -> { listener1, listener2, ... }
    self._once = {}           -- eventName -> { [listener]=true }
    return self
end

--- Subscribe to an event. Returns an unsubscribe function.
function EventBus:subscribe(eventName, listener)
    if type(eventName) ~= "string" or type(listener) ~= "function" then
        return function() end
    end
    local list = self._listeners[eventName]
    if not list then
        list = {}
        self._listeners[eventName] = list
    end
    table.insert(list, listener)

    return function()
        for i, fn in ipairs(list) do
            if fn == listener then
                table.remove(list, i)
                break
            end
        end
    end
end

--- Subscribe once; auto-unsubscribes after first fire.
function EventBus:once(eventName, listener)
    local unsub
    local wrapper = function(...)
        unsub()
        listener(...)
    end
    unsub = self:subscribe(eventName, wrapper)
    return unsub
end

--- Publish an event to all subscribers.
function EventBus:publish(eventName, ...)
    local list = self._listeners[eventName]
    if not list then return end
    -- Copy list to avoid mutation issues during iteration
    local copy = {}
    for i, fn in ipairs(list) do
        if fn then copy[#copy + 1] = fn end
    end
    for _, fn in ipairs(copy) do
        local ok, err = pcall(fn, ...)
        if not ok then
            -- Log but don't crash the bus
            if self._log then
                self._log:error("EventBus [%s]: %s", eventName, tostring(err))
            end
        end
    end
end

--- Remove all listeners for a given event, or all events if nil.
function EventBus:clear(eventName)
    if eventName then
        self._listeners[eventName] = nil
    else
        self._listeners = {}
    end
end

--- Attach a logger for error reporting.
function EventBus:setLogger(log)
    self._log = log
end

return EventBus
