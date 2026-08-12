
--- ExpBar: reusable experience-progress bar.
local Component = require("core.Component")
local Colors = require("util.Colors")

local ExpBar = setmetatable({}, { __index = Component })
ExpBar.__index = ExpBar
ExpBar.__name = "ExpBar"
-- Colors (imported above) is a plain util module, not a locator service -
-- it belongs in requires, not here. See PokemonPanel.lua for how ExpBar is
-- actually constructed (bypasses Lifecycle, so .needs isn't checked today,
-- but keep this accurate in case that changes).
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

    -- Background
    Colors.set({0.12, 0.12, 0.14}, 1)
    love.graphics.rectangle("fill", math.floor(x), math.floor(y), math.floor(w), math.floor(h))

    -- Fill
    if self.progress > 0 then
        Colors.set(cfg.COL.xp, 1)
        love.graphics.rectangle("fill", math.floor(x), math.floor(y),
            math.floor(w * math.min(1, self.progress)), math.floor(h))
    end
end

return ExpBar
