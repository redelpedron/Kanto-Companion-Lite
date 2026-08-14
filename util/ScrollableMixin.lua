local ScrollableMixin = {}

local DEFAULT_KEY = "default"

function ScrollableMixin:_scrollInit()
    self._scroll = {}
    self._scrollDragging = false
    self._scrollDragKey = nil
    self._scrollDragStartY = 0
    self._scrollDragStartOffset = 0
    self._scrollLastY = 0
end

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

function ScrollableMixin:_scrollUpdateDrag()
    if not self._scrollDragging or not self._scrollDragKey then return end
    local dy = self._scrollLastY - self._scrollDragStartY
    self._scroll[self._scrollDragKey] = math.max(0, self._scrollDragStartOffset + dy)
end

function ScrollableMixin:_scrollEndDrag()
    self._scrollDragging = false
    self._scrollDragKey = nil
end

function ScrollableMixin:_scrollClamp(contentHeight, viewportHeight, key)
    key = key or DEFAULT_KEY
    local maxScroll = math.max(0, contentHeight - viewportHeight)
    local offset = math.max(0, math.min(maxScroll, self:_scrollGet(key)))
    self._scroll[key] = offset
    return offset, maxScroll
end

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
