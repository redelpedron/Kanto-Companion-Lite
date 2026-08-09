--- DrawContext: abstraction over love.graphics with auto-floor and
-- color-table support. Eliminates math.floor() duplication and the
-- love global dependency across all component draw code.
local DrawContext = {}
DrawContext.__index = DrawContext

function DrawContext.new(graphics)
    local self = setmetatable({}, DrawContext)
    -- Allow injection for headless testing; fall back to love.graphics
    self.g = graphics or (love and love.graphics)
    return self
end

-- -----------------------------------------------------------------------
-- Color
-- -----------------------------------------------------------------------
function DrawContext:setColor(r, g, b, a)
    if type(r) == "table" then
        a = g or 1
        r, g, b = r[1], r[2], r[3]
    end
    self.g.setColor(r, g, b, a)
end

-- -----------------------------------------------------------------------
-- State
-- -----------------------------------------------------------------------
function DrawContext:setFont(font)
    self.g.setFont(font)
end

function DrawContext:getFont()
    return self.g.getFont()
end

function DrawContext:setLineWidth(width)
    self.g.setLineWidth(width)
end

-- -----------------------------------------------------------------------
-- Drawing primitives (all coordinates auto-floored)
-- -----------------------------------------------------------------------
function DrawContext:print(text, x, y, r, sx, sy, ox, oy, kx, ky)
    self.g.print(text, math.floor(x), math.floor(y), r or 0, sx, sy, ox, oy, kx, ky)
end

function DrawContext:rectangle(mode, x, y, w, h, rx, ry, segments)
    self.g.rectangle(mode, math.floor(x), math.floor(y), math.floor(w), math.floor(h), rx, ry, segments)
end

function DrawContext:line(...)
    local args = {...}
    for i, v in ipairs(args) do
        if type(v) == "number" then
            args[i] = math.floor(v)
        end
    end
    self.g.line(unpack(args))
end

function DrawContext:circle(mode, x, y, radius)
    self.g.circle(mode, math.floor(x), math.floor(y), radius)
end

function DrawContext:draw(drawable, x, y, r, sx, sy, ox, oy, kx, ky)
    self.g.draw(drawable, math.floor(x or 0), math.floor(y or 0), r, sx, sy, ox, oy, kx, ky)
end

-- -----------------------------------------------------------------------
-- Stack / scissor
-- -----------------------------------------------------------------------
function DrawContext:push(stack)
    self.g.push(stack)
end

function DrawContext:pop()
    self.g.pop()
end

function DrawContext:origin()
    self.g.origin()
end

function DrawContext:setScissor(...)
    self.g.setScissor(...)
end

-- -----------------------------------------------------------------------
-- Queries
-- -----------------------------------------------------------------------
function DrawContext:getDimensions()
    return self.g.getDimensions()
end

function DrawContext:getWidth(text, font)
    local f = font or self.g.getFont()
    return f:getWidth(text)
end

function DrawContext:getHeight(font)
    local f = font or self.g.getFont()
    return f:getHeight()
end

return DrawContext
