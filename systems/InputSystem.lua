local InputSystem = {}
InputSystem.__index = InputSystem

function InputSystem.new(locator)
    local self = setmetatable({}, InputSystem)
    self._locator = locator
    self.bus = locator:resolve("EventBus")
    -- hookName ("touchpressed", etc.) -> { orig = <original callback or
    -- nil>, wrapped = <our replacement> }. One table instead of six pairs
    -- of named orig/wrapped fields -- init() populates it, destroy() just
    -- walks it back off, and there's exactly one place that knows how
    -- restoration works.
    self._hooks = {}
    self._wrapped = false
    return self
end

-- Wraps an edge-triggered love callback (fires once on press/release) so
-- it publishes an EventBus event first and lets any listener "consume"
-- it (via the 3rd publish arg) to swallow the input before it reaches
-- the underlying game -- e.g. so tapping a HUD button doesn't also
-- register as a tap on the overworld beneath it.
--
--   hookName    -- love callback field to wrap, e.g. "touchpressed"
--   eventName   -- bus event to publish, e.g. "input.pressed"
--   xyFromArgs  -- fn(...) -> x, y, given that hook's own argument list
--   shouldFire  -- optional fn(...) -> bool; omit to always publish.
--                  Used by the mouse hooks to filter out touch-emulated
--                  mouse events and non-left-button clicks, since touch
--                  input already arrives via the touch* hooks and both
--                  firing would double-publish the same tap.
--
-- Whether or not the event fires, the original callback (if one was
-- present) is always invoked afterward -- unless a listener consumed
-- the event, in which case it's swallowed instead.
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

-- Wraps a continuous love callback (fires every frame the pointer moves)
-- so it publishes "input.moved" -- e.g. for scrollbar drag tracking.
-- Unlike _wrapEdge, there's no consume/swallow step: drag position is
-- observed, not claimed, so the original callback always still runs.
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

    -- touchpressed(id, x, y, dx, dy, pressure)
    self:_wrapEdge("touchpressed", "input.pressed",
        function(id, x, y) return x, y end)

    -- touchreleased(id, x, y, dx, dy, pressure)
    self:_wrapEdge("touchreleased", "input.released",
        function(id, x, y) return x, y end)

    -- mousepressed(x, y, button, istouch, presses) -- skip touch-emulated
    -- mouse events (already handled by touchpressed above) and anything
    -- but a left-click.
    self:_wrapEdge("mousepressed", "input.pressed",
        function(x, y) return x, y end,
        function(x, y, button, istouch) return not istouch and button == 1 end)

    -- mousereleased(x, y, button, istouch, presses)
    self:_wrapEdge("mousereleased", "input.released",
        function(x, y) return x, y end,
        function(x, y, button, istouch) return not istouch and button == 1 end)

    -- Continuous drag position, for scrollbars and anything else that
    -- needs "current pointer position" rather than a press/release edge.
    -- Fires on both touch and mouse so drag-to-scroll works on Android
    -- (touchmoved) as well as desktop LOVE2D testing (mousemoved).

    -- touchmoved(id, x, y, dx, dy, pressure)
    self:_wrapMove("touchmoved",
        function(id, x, y) return x, y end)

    -- mousemoved(x, y, dx, dy, istouch) -- skip touch-emulated events,
    -- same reasoning as mousepressed/mousereleased above.
    self:_wrapMove("mousemoved",
        function(x, y) return x, y end,
        function(x, y, dx, dy, istouch) return not istouch end)

    self._wrapped = true
end

function InputSystem:destroy()
    if not self._wrapped then return end
    if not love then return end
    -- Only restore if our wrapper is still in place (defensive -- some
    -- other mod may have wrapped the same hook after us).
    for hookName, hook in pairs(self._hooks) do
        if love[hookName] == hook.wrapped then
            love[hookName] = hook.orig
        end
    end
    self._hooks = {}
    self._wrapped = false
end

return InputSystem
