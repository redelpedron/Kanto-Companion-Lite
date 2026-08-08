
--- BadgeWidget: displays badge count (e.g. "3/8").
local Component = require("core.Component")
local Colors = require("util.Colors")

local BadgeWidget = setmetatable({}, { __index = Component })
BadgeWidget.__index = BadgeWidget
BadgeWidget.needs = { "ConfigService", "FontService" }

function BadgeWidget.new(locator, props)
    local self = setmetatable(Component.new(locator, props), BadgeWidget)
    self.count = props.count or 0
    self.max = props.max or 8
    return self
end

function BadgeWidget:draw(ctx)
    local cfg = self:_service("ConfigService")
    local fonts = self:_service("FontService")
    local x, y = self._props.x, self._props.y
    local size = self._props.size or 11
    local label = self._props.label or "Badges"

    local f = fonts:getFont(size)
    love.graphics.setFont(f)

    Colors.set(cfg.COL.dim, 1)
    love.graphics.print(label, math.floor(x), math.floor(y))
    local lw = f:getWidth(label .. " ")

    Colors.set(cfg.COL.gold, 1)
    love.graphics.print(self.count .. "/" .. self.max, math.floor(x + lw), math.floor(y))
end

return BadgeWidget
