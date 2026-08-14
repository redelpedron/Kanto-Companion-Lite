local Component = require("core.Component")
local Colors = require("util.Colors")

local ExpBar = setmetatable({}, { __index = Component })
ExpBar.__index = ExpBar
ExpBar.__name = "ExpBar"

ExpBar.needs = { "ConfigService" }

function ExpBar.new(locator, props)
    local self = setmetatable(Component.new(locator, props), ExpBar)
    self.progress = props.progress or 0
    return self
end

function ExpBar:draw(ctx)
    if self.progress == nil then return end
    local cfg = self:_service("ConfigService")
    local x, y, w = self._props.x, self._props.y, self._props.w
    local h = self._props.h or 2

    Colors.set({0.12, 0.12, 0.14}, 1)
    love.graphics.rectangle("fill", math.floor(x), math.floor(y), math.floor(w), math.floor(h))

    if self.progress > 0 then
        Colors.set(cfg.COL.xp, 1)
        love.graphics.rectangle("fill", math.floor(x), math.floor(y),
            math.floor(w * math.min(1, self.progress)), math.floor(h))
    end
end

return ExpBar
