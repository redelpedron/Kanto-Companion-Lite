
--- StatusWidget: displays a status condition label.
local Component = require("core.Component")
local Colors = require("util.Colors")
local FontService = require("services.FontService")

local StatusWidget = setmetatable({}, { __index = Component })
StatusWidget.__index = StatusWidget
StatusWidget.needs = { "ConfigService", "FontService" }

function StatusWidget.new(locator, props)
    local self = setmetatable(Component.new(locator, props), StatusWidget)
    self.status = props.status or ""
    return self
end

function StatusWidget:draw(ctx)
    if not self.status or self.status == "" or self.status == "OK" then return end
    local cfg = self:_service("ConfigService")
    local fonts = self:_service("FontService")
    local x, y = self._props.x, self._props.y
    local size = self._props.size or 9
    local align = self._props.align or "left"

    local f = fonts:getFont(size)
    love.graphics.setFont(f)
    Colors.set(cfg.COL.lo, 1)

    local str = tostring(self.status)
    local X = x
    if align == "center" then
        X = X - f:getWidth(str) / 2
    elseif align == "right" then
        X = X - f:getWidth(str)
    end
    love.graphics.print(str, math.floor(X), math.floor(y))
end

return StatusWidget
