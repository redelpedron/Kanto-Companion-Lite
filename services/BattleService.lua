local Helpers = require("util.Helpers")

local BattleService = {}
BattleService.__index = BattleService

function BattleService.new(locator)
    local self = setmetatable({}, BattleService)
    self._locator = locator
    self._battleState = nil
    self._battleStateClass = nil
    return self
end

function BattleService:setBattleStateClass(cls)
    self._battleStateClass = cls
end

function BattleService:currentBattle()
    local gameService = self._locator:resolve("GameService")
    local g = gameService:getGame()
    local stk = g and g.stack
    if not (stk and stk.states) then return nil end
    for i = #stk.states, 1, -1 do
        local state = stk.states[i]
        if type(state) == "table" then
            if self._battleStateClass and getmetatable(state) == self._battleStateClass then
                return state
            end

            if state.showEnemyHud ~= nil and state.showPlayerHud ~= nil and state.shownMon ~= nil then
                return state
            end
        end
    end
    return nil
end

function BattleService:isInBattle()
    return self:currentBattle() ~= nil
end

local function gen2Battle(battle)
    return battle and type(battle.battle) == "table" and battle.battle or nil
end

function BattleService:getEnemyMon()
    local battle = self:currentBattle()
    local enemy = battle and battle.enemy

    local mon = (type(enemy) == "table") and enemy.mon or nil
    if mon then return mon end

    return battle and battle.shownMon and battle.shownMon.enemy or nil
end

function BattleService:getPlayerActiveMon()
    local battle = self:currentBattle()
    local mon = battle and battle.player and battle.player.mon
    if mon then return mon end

    return battle and battle.shownMon and battle.shownMon.player or nil
end

function BattleService:getEnemyTrainer()
    local battle = self:currentBattle()
    if battle and battle.trainer then return battle.trainer end
    local bb = gen2Battle(battle)
    return bb and bb.trainer or nil
end

function BattleService:getEnemyTrainerClass()
    local battle = self:currentBattle()
    return battle and battle.enemyTrainerClass or nil
end

function BattleService:getEnemyTrainerName()
    local trainer = self:getEnemyTrainer()
    if trainer and trainer.name then
        return Helpers.decodeTrainerName(trainer.name)
    end

    local class = self:getEnemyTrainerClass()
    if class then
        return Helpers.formatMapName(class)
    end
    return nil
end

function BattleService:isTrainerBattle()
    return self:getEnemyTrainer() ~= nil or self:getEnemyTrainerClass() ~= nil
end

function BattleService:getEnemyParty()
    local battle  = self:currentBattle()
    local trainer = self:getEnemyTrainer()
    local enemyRaw = battle and battle.enemy

    local enemy = (type(enemyRaw) == "table") and enemyRaw or nil

    if trainer then
        local parties = trainer.parties
        local roster = type(parties) == "table" and (parties[trainer.index] or parties[1])
        if type(roster) == "table" and #roster > 0 then
            return roster
        end

        roster = trainer.party or trainer.team or trainer.pokemon or trainer.mons
        if type(roster) == "table" and #roster > 0 then
            return roster
        end
    end

    if enemy then
        local roster = enemy.party or enemy.team or enemy.mons or enemy.pokemon
        if type(roster) == "table" and #roster > 0 then
            return roster
        end
    end

    if enemy and enemy.mon then
        return { enemy.mon }
    end

    local bb = gen2Battle(battle)
    if bb then
        local roster = bb.enemyParty or bb.party
        if type(roster) == "table" and #roster > 0 then
            return roster
        end
    end

    local shownEnemy = battle and battle.shownMon and battle.shownMon.enemy
    if shownEnemy then
        return { shownEnemy }
    end
    return {}
end

function BattleService:getEnemyData()
    local eMon = self:getEnemyMon()
    if not eMon then return nil end
    local gameService = self._locator:resolve("GameService")
    local dPoke = gameService:getPokemonData()
    local def = dPoke[eMon.species]

    local dex = gameService:getPokedex()
    local caught = false
    if dex and dex.owned then
        caught = dex.owned[eMon.species] == true
    end

    local types = (eMon.types and #eMon.types > 0) and eMon.types or (def and def.types) or {}

    return {
        name = eMon.nickname or eMon.name or (def and def.name) or tostring(eMon.species),
        species = eMon.species,
        level = eMon.level or 0,
        hp = eMon.hp or 0,
        maxhp = (eMon.stats and eMon.stats.hp) or eMon.maxHp or 1,
        types = Helpers.dedupeTypes(types),
        catchRate = def and def.catchRate or 0,
        status = eMon.status or "",
        caught = caught,
    }
end

return BattleService
