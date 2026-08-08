local System = require("core.System")

local BattleSystem = setmetatable({}, { __index = System })
BattleSystem.__index = BattleSystem

function BattleSystem.new(locator)
    local self = setmetatable(System.new(locator), BattleSystem)
    self.battleService = locator:resolve("BattleService")
    self.bus = locator:resolve("EventBus")
    self._wasInBattle = false
    self._lastEnemy = nil
    return self
end

function BattleSystem:update(dt)
    local inBattle = self.battleService:isInBattle()
    local enemy = self.battleService:getEnemyData()

    if inBattle and not self._wasInBattle then
        self.bus:publish("battle.started")
    elseif not inBattle and self._wasInBattle then
        self.bus:publish("battle.ended")
    end

    if inBattle then
        if not self._lastEnemy or not enemy
           or self._lastEnemy.species ~= enemy.species
           or self._lastEnemy.hp ~= enemy.hp
           or self._lastEnemy.status ~= enemy.status then
            self.bus:publish("enemy.updated", enemy)
        end
        local activeMon = self.battleService:getPlayerActiveMon()
        if activeMon then
            self.bus:publish("active_mon.changed", activeMon)
        end
    else
        if self._lastEnemy ~= nil then
            self.bus:publish("enemy.updated", nil)
            self._lastEnemy = nil
        end
    end

    self._wasInBattle = inBattle
    self._lastEnemy = enemy
end

return BattleSystem