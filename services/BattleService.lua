
--- BattleService: detects battle state and extracts enemy / player mon data.
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
    if not (stk and stk.states and self._battleStateClass) then return nil end
    for i = #stk.states, 1, -1 do
        if getmetatable(stk.states[i]) == self._battleStateClass then
            return stk.states[i]
        end
    end
    return nil
end

function BattleService:isInBattle()
    return self:currentBattle() ~= nil
end

function BattleService:getEnemyMon()
    local battle = self:currentBattle()
    return battle and battle.enemy and battle.enemy.mon
end

function BattleService:getPlayerActiveMon()
    local battle = self:currentBattle()
    return battle and battle.player and battle.player.mon
end

function BattleService:getEnemyData()
    local eMon = self:getEnemyMon()
    if not eMon then return nil end
    local gameService = self._locator:resolve("GameService")
    local dPoke = gameService:getPokemonData()
    local def = dPoke[eMon.species]
    return {
        name = eMon.nickname or (def and def.name) or tostring(eMon.species),
        species = eMon.species,
        level = eMon.level or 0,
        hp = eMon.hp or 0,
        maxhp = (eMon.stats and eMon.stats.hp) or 1,
        types = def and def.types or {},
        catchRate = def and def.catchRate or 0,
        status = eMon.status or "",
    }
end

return BattleService
