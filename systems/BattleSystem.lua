local BattleSystem = {}
BattleSystem.__index = BattleSystem

function BattleSystem.new(locator)
    local self = setmetatable({}, BattleSystem)
    self._locator = locator
    self.battleService = locator:resolve("BattleService")
    self.bus = locator:resolve("EventBus")
    self._wasInBattle = false
    self._lastEnemy = nil
    self._lastTrainerName = nil
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

        -- Rival tab: live per-frame HP/status for whichever enemy mon is
        -- currently out, same as active_mon.changed does for the player.
        local enemyActiveMon = self.battleService:getEnemyMon()
        if enemyActiveMon then
            self.bus:publish("enemy_active_mon.changed", enemyActiveMon)
        end

        -- Rival tab label: update as soon as a trainer battle starts
        -- (or a wild encounter begins with no trainer) rather than
        -- waiting on GameDataSystem's slower 0.2s roster snapshot.
        local trainerName = self.battleService:getEnemyTrainerName()
        if trainerName ~= self._lastTrainerName then
            self.bus:publish("rival_trainer.updated", trainerName)
            self._lastTrainerName = trainerName
        end
    else
        if self._lastEnemy ~= nil then
            self.bus:publish("enemy.updated", nil)
            self._lastEnemy = nil
        end
        if self._lastTrainerName ~= nil then
            self.bus:publish("rival_trainer.updated", nil)
            self._lastTrainerName = nil
        end
    end

    self._wasInBattle = inBattle
    self._lastEnemy = enemy
end

return BattleSystem