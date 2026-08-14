local Viewport = {}
Viewport.__index = Viewport

function Viewport.new(x, y, w, h)
    return setmetatable({ x = x, y = y, w = w, h = h }, Viewport)
end

function Viewport:clipDraw()
    love.graphics.setScissor(math.floor(self.x), math.floor(self.y), math.ceil(self.w), math.ceil(self.h))
end

function Viewport:contains(px, py)
    return px >= self.x and px <= self.x + self.w and py >= self.y and py <= self.y + self.h
end

return Viewport
