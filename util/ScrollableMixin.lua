--- ScrollableMixin: shared vertical-scroll + drag-scrollbar behavior.
-- Extracted from PCPopup, ItemsPanel, and RoutePanel, which each hand-rolled
-- the same offset/drag/clamp/scrollbar math (~70 lines apiece).
--
-- Usage: `Helpers.mixin(MyComponent, ScrollableMixin)` in the class body,
-- then call `self:_scrollInit()` in `.new()`.
--
-- Every method takes an optional `key` (default "default") so a component
-- with more than one independently-scrolling region (PCPopup's bag/pc
-- panels) can drive two scroll states from one mixin instance instead of
-- duplicating the whole thing per side.
local ScrollableMixin = {}

local DEFAULT_KEY = "default"

--- Call from the component's `.new()` (after Component.new / setmetatable).
function ScrollableMixin:_scrollInit()
    self._scroll = {}          -- key -> offset
    self._scrollDragging = false
    self._scrollDragKey = nil
    self._scrollDragStartY = 0
    self._scrollDragStartOffset = 0
    self._scrollLastY = 0      -- updated by input.moved; drives drag without polling love.mouse
end

--- Wire up the input.moved listener that drives drag updates. Call once
-- from the component's `init()`. Requires the component to have a
-- working `self:_listen` (i.e. it's a Component subclass).
function ScrollableMixin:_scrollListen()
    self:_listen("input.moved", function(self2, x, y)
        self2._scrollLastY = y
    end)
end

function ScrollableMixin:_scrollGet(key)
    key = key or DEFAULT_KEY
    return self._scroll[key] or 0
end

function ScrollableMixin:_scrollReset(key)
    if key then
        self._scroll[key] = 0
    else
        self._scroll = {}
    end
    self._scrollDragging = false
    self._scrollDragKey = nil
end

--- Hit-test a scrollbar track and begin a drag if (x,y) is inside it.
-- `rect` is {x, y, w, h} of the *viewport* (not the scrollbar itself);
-- the scrollbar hit zone is derived as the right-edge strip, matching
-- the ±6px hit zone every caller already used.
-- Returns true if a drag was started (caller should treat input as consumed).
function ScrollableMixin:_scrollTryStartDrag(x, y, rect, key)
    key = key or DEFAULT_KEY
    local barX = rect.x + rect.w - 10
    if x >= barX - 6 and x <= barX + 10 and y >= rect.y and y <= rect.y + rect.h then
        self._scrollDragging = true
        self._scrollDragKey = key
        self._scrollDragStartY = y
        self._scrollLastY = y
        self._scrollDragStartOffset = self:_scrollGet(key)
        return true
    end
    return false
end

--- Call every frame (e.g. from `update(dt)`) to continue an active drag.
-- Uses the last position seen via input.moved (touch or mouse) rather
-- than polling love.mouse.getY(), which never fires for touch drags.
function ScrollableMixin:_scrollUpdateDrag()
    if not self._scrollDragging or not self._scrollDragKey then return end
    local dy = self._scrollLastY - self._scrollDragStartY
    self._scroll[self._scrollDragKey] = math.max(0, self._scrollDragStartOffset + dy)
end

--- Call from an `input.released` listener to end any active drag.
function ScrollableMixin:_scrollEndDrag()
    self._scrollDragging = false
    self._scrollDragKey = nil
end

--- Clamp the stored offset to [0, contentHeight - viewportHeight] and
-- return (offset, maxScroll). Call once per draw before computing `cy`.
function ScrollableMixin:_scrollClamp(contentHeight, viewportHeight, key)
    key = key or DEFAULT_KEY
    local maxScroll = math.max(0, contentHeight - viewportHeight)
    local offset = math.max(0, math.min(maxScroll, self:_scrollGet(key)))
    self._scroll[key] = offset
    return offset, maxScroll
end

--- Draw the scrollbar track + thumb. `rect` is the viewport rect this
-- scrollbar belongs to. `colors` = { track, thumb, thumbActive } as
-- {r,g,b} tables (component passes its own cfg.COL.* palette in).
-- `key` identifies which scroll region this bar belongs to, so the
-- "active/dragging" highlight only lights up the thumb actually being
-- dragged when a component has more than one region (e.g. PCPopup's
-- bag/pc side-by-side panels) rather than both at once.
-- No-op if maxScroll <= 0.
function ScrollableMixin:_scrollDrawBar(rect, contentHeight, viewportHeight, maxScroll, offset, colors, Colors, key)
    if maxScroll <= 0 then return end
    key = key or DEFAULT_KEY
    local barX = rect.x + rect.w - 10
    local barW = 4
    local barY = rect.y
    local barH = viewportHeight

    Colors.set(colors.track, colors.trackAlpha or 0.1)
    love.graphics.rectangle("fill", math.floor(barX), math.floor(barY), barW, math.floor(barH))

    local thumbHeight = math.max(20, barH * (viewportHeight / contentHeight))
    local thumbY = barY + (offset / maxScroll) * (barH - thumbHeight)

    local isDragging = self._scrollDragging and self._scrollDragKey == key
    local thumbColor = isDragging and (colors.thumbActive or colors.thumb) or colors.thumb
    Colors.set(thumbColor, isDragging and (colors.thumbActiveAlpha or 0.9) or (colors.thumbAlpha or 0.7))
    love.graphics.rectangle("fill", math.floor(barX), math.floor(thumbY), barW, math.floor(thumbHeight))
end

return ScrollableMixin
