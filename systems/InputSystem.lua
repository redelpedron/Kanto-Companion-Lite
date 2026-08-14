local InputSystem = {}
InputSystem.__index = InputSystem

function InputSystem.new(locator)
    local self = setmetatable({}, InputSystem)
    self._locator = locator
    self.bus = locator:resolve("EventBus")

    self._hooks = {}
    self._wrapped = false
    return self
end

function InputSystem:_wrapEdge(hookName, eventName, xyFromArgs, shouldFire)
    local orig = love[hookName]
    if not orig then return end
    local wrapped = function(...)
        if not shouldFire or shouldFire(...) then
            local x, y = xyFromArgs(...)
            local consumed = false
            self.bus:publish(eventName, x, y, function() consumed = true end)
            if consumed then return end
        end
        return orig(...)
    end
    love[hookName] = wrapped
    self._hooks[hookName] = { orig = orig, wrapped = wrapped }
end

function InputSystem:_wrapMove(hookName, xyFromArgs, shouldFire)
    local orig = love[hookName]
    if not orig then return end
    local wrapped = function(...)
        if not shouldFire or shouldFire(...) then
            local x, y = xyFromArgs(...)
            self.bus:publish("input.moved", x, y)
        end
        return orig(...)
    end
    love[hookName] = wrapped
    self._hooks[hookName] = { orig = orig, wrapped = wrapped }
end

function InputSystem:init()
    if self._wrapped then return end
    if not love then return end

    self:_wrapEdge("touchpressed", "input.pressed",
        function(id, x, y) return x, y end)

    self:_wrapEdge("touchreleased", "input.released",
        function(id, x, y) return x, y end)

    self:_wrapEdge("mousepressed", "input.pressed",
        function(x, y) return x, y end,
        function(x, y, button, istouch) return not istouch and button == 1 end)

    self:_wrapEdge("mousereleased", "input.released",
        function(x, y) return x, y end,
        function(x, y, button, istouch) return not istouch and button == 1 end)

    self:_wrapMove("touchmoved",
        function(id, x, y) return x, y end)

    self:_wrapMove("mousemoved",
        function(x, y) return x, y end,
        function(x, y, dx, dy, istouch) return not istouch end)

    self._wrapped = true
end

function InputSystem:destroy()
    if not self._wrapped then return end
    if not love then return end

    for hookName, hook in pairs(self._hooks) do
        if love[hookName] == hook.wrapped then
            love[hookName] = hook.orig
        end
    end
    self._hooks = {}
    self._wrapped = false
end

return InputSystem
