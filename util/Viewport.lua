--- Viewport: a clipped rect that both drawing and hit-testing read from,
-- so a scrolled-off element can never be visually hidden by
-- love.graphics.setScissor() while still being tappable. Before this,
-- draw clipping and input clipping were two separate, hand-written
-- rects that could (and did) drift apart -- see PCPopup's item lists.
local Viewport = {}
Viewport.__index = Viewport

function Viewport.new(x, y, w, h)
    return setmetatable({ x = x, y = y, w = w, h = h }, Viewport)
end

--- Applies love.graphics.setScissor for this viewport's rect. Caller is
-- responsible for clearing it afterwards with love.graphics.setScissor()
-- (no args).
function Viewport:clipDraw()
    love.graphics.setScissor(math.floor(self.x), math.floor(self.y), math.ceil(self.w), math.ceil(self.h))
end

--- True if (px, py) falls inside this viewport's rect -- the exact same
-- rect clipDraw() used, so a hit-test built on this can never disagree
-- with what's actually visible on screen.
function Viewport:contains(px, py)
    return px >= self.x and px <= self.x + self.w and py >= self.y and py <= self.y + self.h
end

return Viewport
