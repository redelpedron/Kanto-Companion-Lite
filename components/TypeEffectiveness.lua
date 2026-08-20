local Component = require("core.Component")
local TypeColors = require("util.TypeColors")
local Helpers = require("util.Helpers")

local TypeEffectiveness = setmetatable({}, { __index = Component })
TypeEffectiveness.__index = TypeEffectiveness
TypeEffectiveness.__name = "TypeEffectiveness"
TypeEffectiveness.needs = { "GameService", "EventBus" }

function TypeEffectiveness.new(locator, props)
    local self = setmetatable(Component.new(locator, props), TypeEffectiveness)
    self._typeChart = nil
    self._typeChartReady = false
    return self
end

function TypeEffectiveness:_ensureTypeChart()
    if self._typeChartReady then return true end
    local gameService = self:_service("GameService")
    local tc = gameService:getTypeChart()
    if not tc then return false end
    self._typeChart = tc
    local data = gameService:getData()
    self._typeChartReady = pcall(tc.load, data)
    return self._typeChartReady
end

function TypeEffectiveness:effectiveness(moveId, defenderTypes)
    if not self:_ensureTypeChart() then return 10 end
    local gameService = self:_service("GameService")
    local dMove = gameService:getMoveData()
    local moveData = dMove[moveId]
    if not moveData then return 10 end

    local atkType = TypeColors.normalize(moveData.type or moveData.typeName or "")
    if atkType == "" then return 10 end

    defenderTypes = TypeColors.dedupe(defenderTypes)

    local ok, mult = pcall(self._typeChart.effectiveness, atkType, defenderTypes)
    if ok and type(mult) == "number" then
        return mult
    end

    local mult = 10
    for _, defType in ipairs(defenderTypes or {}) do
        local def = TypeColors.normalize(defType)
        if def ~= "" then
            local eff = 10
            if self._typeChart[atkType] then
                local t = self._typeChart[atkType]
                if type(t) == "table" and type(t[def]) == "number" then
                    eff = t[def]
                end
            end
            mult = mult * eff / 10
        end
    end
    return mult
end

function TypeEffectiveness:hasSuperEffectiveMove(mon, enemyTypes)
    if not mon or not mon.moves then return false end
    for _, mv in ipairs(mon.moves) do
        if self:effectiveness(mv.id, enemyTypes) > 10 then
            return true
        end
    end
    return false
end

return TypeEffectiveness
