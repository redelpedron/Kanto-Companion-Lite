local Component = require("core.Component")

local CatchRate = setmetatable({}, { __index = Component })
CatchRate.__index = CatchRate
CatchRate.__name = "CatchRate"
CatchRate.needs = { "ConfigService" }

function CatchRate.new(locator, props)
    return setmetatable(Component.new(locator, props), CatchRate)
end

function CatchRate:calculate(enemy, ballId)
    if not enemy then return 0 end
    local cfg = self:_service("ConfigService")
    local rate = enemy.catchRate or 0
    if rate <= 0 then return 0 end
    local ballMult = cfg.BALL_MULT[ballId] or 1
    if ballMult == 255 then return 100 end

    local hpMax = math.max(1, enemy.maxhp or 1)
    local hpCurr = math.max(0, enemy.hp or 0)
    local hpFactor = (3 * hpMax - 2 * hpCurr) / (3 * hpMax)
    local a = rate * ballMult * hpFactor
    if a >= 255 then return 100 end

    local b = 1048560 / math.sqrt(math.sqrt(16711680 / a))
    local shakeProb = b / 65535
    local catchProb = shakeProb * shakeProb * shakeProb * shakeProb
    return math.floor(catchProb * 100 + 0.5)
end

return CatchRate
