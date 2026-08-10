local System = require("core.System")

local InputSystem = setmetatable({}, { __index = System })
InputSystem.__index = InputSystem

function InputSystem.new(locator)
    local self = setmetatable(System.new(locator), InputSystem)
    self.bus = locator:resolve("EventBus")
    self._origTouch = nil
    self._origTouchRelease = nil
    self._origMouse = nil
    self._origMouseRelease = nil
    -- FIX: store wrapper references so destroy() can check they're still in place
    self._wrappedTouch = nil
    self._wrappedTouchRelease = nil
    self._wrappedMouse = nil
    self._wrappedMouseRelease = nil
    self._origTouchMove = nil
    self._origMouseMove = nil
    self._wrappedTouchMove = nil
    self._wrappedMouseMove = nil
    self._wrapped = false
    return self
end

function InputSystem:init()
    if self._wrapped then return end
    if not love then return end

    if love.touchpressed then
        self._origTouch = love.touchpressed
        self._wrappedTouch = function(id, x, y, dx, dy, pressure)
            local consumed = false
            self.bus:publish("input.pressed", x, y, function() consumed = true end)
            if consumed then return end
            if self._origTouch then return self._origTouch(id, x, y, dx, dy, pressure) end
        end
        love.touchpressed = self._wrappedTouch
    end

    if love.touchreleased then
        self._origTouchRelease = love.touchreleased
        self._wrappedTouchRelease = function(id, x, y, dx, dy, pressure)
            local consumed = false
            self.bus:publish("input.released", x, y, function() consumed = true end)
            if consumed then return end
            if self._origTouchRelease then return self._origTouchRelease(id, x, y, dx, dy, pressure) end
        end
        love.touchreleased = self._wrappedTouchRelease
    end

    if love.mousepressed then
        self._origMouse = love.mousepressed
        self._wrappedMouse = function(x, y, button, istouch, presses)
            if not istouch and button == 1 then
                local consumed = false
                self.bus:publish("input.pressed", x, y, function() consumed = true end)
                if consumed then return end
            end
            if self._origMouse then return self._origMouse(x, y, button, istouch, presses) end
        end
        love.mousepressed = self._wrappedMouse
    end

    if love.mousereleased then
        self._origMouseRelease = love.mousereleased
        self._wrappedMouseRelease = function(x, y, button, istouch, presses)
            if not istouch and button == 1 then
                local consumed = false
                self.bus:publish("input.released", x, y, function() consumed = true end)
                if consumed then return end
            end
            if self._origMouseRelease then return self._origMouseRelease(x, y, button, istouch, presses) end
        end
        love.mousereleased = self._wrappedMouseRelease
    end

    -- Continuous drag position, for scrollbars and anything else that
    -- needs "current pointer position" rather than a press/release edge.
    -- Fires on both touch and mouse so drag-to-scroll works on Android
    -- (touchmoved) as well as desktop LOVE2D testing (mousemoved).
    if love.touchmoved then
        self._origTouchMove = love.touchmoved
        self._wrappedTouchMove = function(id, x, y, dx, dy, pressure)
            self.bus:publish("input.moved", x, y)
            if self._origTouchMove then return self._origTouchMove(id, x, y, dx, dy, pressure) end
        end
        love.touchmoved = self._wrappedTouchMove
    end

    if love.mousemoved then
        self._origMouseMove = love.mousemoved
        self._wrappedMouseMove = function(x, y, dx, dy, istouch)
            if not istouch then
                self.bus:publish("input.moved", x, y)
            end
            if self._origMouseMove then return self._origMouseMove(x, y, dx, dy, istouch) end
        end
        love.mousemoved = self._wrappedMouseMove
    end

    self._wrapped = true
end

function InputSystem:destroy()
    if not self._wrapped then return end
    if not love then return end
    -- FIX: only restore if our wrapper is still in place (defensive)
    if self._wrappedTouch and love.touchpressed == self._wrappedTouch then
        love.touchpressed = self._origTouch
    end
    if self._wrappedTouchRelease and love.touchreleased == self._wrappedTouchRelease then
        love.touchreleased = self._origTouchRelease
    end
    if self._wrappedMouse and love.mousepressed == self._wrappedMouse then
        love.mousepressed = self._origMouse
    end
    if self._wrappedMouseRelease and love.mousereleased == self._wrappedMouseRelease then
        love.mousereleased = self._origMouseRelease
    end
    if self._wrappedTouchMove and love.touchmoved == self._wrappedTouchMove then
        love.touchmoved = self._origTouchMove
    end
    if self._wrappedMouseMove and love.mousemoved == self._wrappedMouseMove then
        love.mousemoved = self._origMouseMove
    end
    self._wrapped = false
end

return InputSystem
