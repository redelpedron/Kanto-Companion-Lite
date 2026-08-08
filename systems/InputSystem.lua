local System = require("core.System")

local InputSystem = setmetatable({}, { __index = System })
InputSystem.__index = InputSystem

function InputSystem.new(locator)
    local self = setmetatable(System.new(locator), InputSystem)
    self.bus = locator:resolve("EventBus")
    self._origTouch = nil
    self._origMouse = nil
    self._wrapped = false
    return self
end

function InputSystem:init()
    if self._wrapped then return end
    if not love then return end

    if love.touchpressed then
        self._origTouch = love.touchpressed
        love.touchpressed = function(id, x, y, dx, dy, pressure)
            local consumed = false
            self.bus:publish("input.pressed", x, y, function() consumed = true end)
            if consumed then return end
            if self._origTouch then return self._origTouch(id, x, y, dx, dy, pressure) end
        end
    end

    if love.touchreleased then
        self._origTouchRelease = love.touchreleased
        love.touchreleased = function(id, x, y, dx, dy, pressure)
            local consumed = false
            self.bus:publish("input.released", x, y, function() consumed = true end)
            if consumed then return end
            if self._origTouchRelease then return self._origTouchRelease(id, x, y, dx, dy, pressure) end
        end
    end

    if love.mousepressed then
        self._origMouse = love.mousepressed
        love.mousepressed = function(x, y, button, istouch, presses)
            -- On touch devices LÖVE fires BOTH love.touchpressed and a
            -- synthesized love.mousepressed (istouch=true) for the same
            -- physical tap. love.touchpressed's wrapper above already
            -- published input.pressed for it, so doing it again here
            -- published two events per tap -- and since picking up an
            -- item/Pokémon in the PC popup is a toggle (tap it -> hold,
            -- tap it again -> cancel), that meant every tap picked
            -- something up and then immediately cancelled it right back.
            -- Only react to a *real* mouse click here.
            if not istouch and button == 1 then
                local consumed = false
                self.bus:publish("input.pressed", x, y, function() consumed = true end)
                if consumed then return end
            end
            if self._origMouse then return self._origMouse(x, y, button, istouch, presses) end
        end
    end

    if love.mousereleased then
        self._origMouseRelease = love.mousereleased
        love.mousereleased = function(x, y, button, istouch, presses)
            -- Only react to real mouse (not synthesized touch events)
            if not istouch and button == 1 then
                local consumed = false
                self.bus:publish("input.released", x, y, function() consumed = true end)
                if consumed then return end
            end
            if self._origMouseRelease then return self._origMouseRelease(x, y, button, istouch, presses) end
        end
    end
    self._wrapped = true
end

function InputSystem:destroy()
    if not self._wrapped then return end
    if not love then return end
    if self._origTouch then love.touchpressed = self._origTouch end
    if self._origTouchRelease then love.touchreleased = self._origTouchRelease end
    if self._origMouse then love.mousepressed = self._origMouse end
    if self._origMouseRelease then love.mousereleased = self._origMouseRelease end
    self._wrapped = false
end

return InputSystem