local EventBus = {}
EventBus.__index = EventBus

function EventBus.new()
    local self = setmetatable({}, EventBus)
    self._listeners = {}
    return self
end

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

function EventBus:publish(eventName, ...)
    local list = self._listeners[eventName]
    if not list then return end

    local copy = {}
    for i, fn in ipairs(list) do
        if fn then copy[#copy + 1] = fn end
    end
    for _, fn in ipairs(copy) do
        local ok, err = pcall(fn, ...)
        if not ok then

            if self._log then
                self._log:error("EventBus [%s]: %s", eventName, tostring(err))
            end
        end
    end
end

function EventBus:setLogger(log)
    self._log = log
end

return EventBus
