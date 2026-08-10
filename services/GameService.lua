--- GameService: safe wrapper around the gen1recomp game reference.
-- Abstracts engine internals so components never touch raw game state.
local Helpers = require("util.Helpers")

local GameService = {}
GameService.__index = GameService

function GameService.new(locator)
    local self = setmetatable({}, GameService)
    self._locator = locator
    self._game = nil
    self._data = {}
    return self
end

function GameService:setGame(game)
    self._game = game
    if game and game.data then
        self._data = game.data
    end
end

function GameService:getGame()
    return self._game
end

function GameService:getSave()
    local g = self._game
    return g and g.save
end

function GameService:getData()
    return self._data
end

function GameService:getPokemonData()
    return self._data.pokemon or {}
end

function GameService:getMoveData()
    return self._data.moves or {}
end

function GameService:getItemData()
    return self._data.items or {}
end

function GameService:getEncounterData()
    return self._data.encounters or {}
end

function GameService:getGrowthRates()
    return self._data.growth_rates or {}
end

function GameService:getConstants()
    return self._data.constants or {}
end

function GameService:getOverworld()
    local g = self._game
    return g and g.overworld
end

function GameService:getStack()
    local g = self._game
    return g and g.stack
end

function GameService:getPlayTime()
    local save = self:getSave()
    return save and (save.playTime or save.playtime or save.timePlayed) or 0
end

function GameService:getPlayerName()
    local save = self:getSave()
    return (save and save.player and save.player.name) or "Trainer"
end

function GameService:getMoney()
    local save = self:getSave()
    return (save and save.money) or 0
end

function GameService:getParty()
    local save = self:getSave()
    return (save and save.party) or {}
end

function GameService:getPokedex()
    local save = self:getSave()
    return (save and save.pokedex) or { seen = {}, owned = {} }
end

function GameService:getInventory()
    local save = self:getSave()
    return (save and save.inventory) or {}
end

function GameService:getRepelSteps()
    local save = self:getSave()
    return (save and save.repelSteps) or 0
end

function GameService:isInGame()
    local save = self:getSave()
    if not save then return false end
    local party = save.party
    if not party or #party == 0 then return false end

    -- FIX: inspect the state stack for an actual overworld or battle state.
    -- The title screen has neither, but may still have save.party loaded.
    local stk = self:getStack()
    if not (stk and stk.states and #stk.states > 0) then return false end

    for i = #stk.states, 1, -1 do
        local state = stk.states[i]
        if type(state) == "table" then
            -- Overworld states carry a 'map' field; battle states carry 'enemy' + 'player'
            if state.map ~= nil or (state.enemy ~= nil and state.player ~= nil) then
                return true
            end
        end
    end
    return false
end

function GameService:isMenuOpen()
    local stk = self:getStack()
    if not (stk and stk.states and #stk.states > 0) then return false end

    local top = stk.states[#stk.states]
    if type(top) ~= "table" then return false end

    if top._isMenuOpen ~= nil then
        return top._isMenuOpen
    end

    local isMenuOpen = top.items ~= nil and top.index ~= nil
    top._isMenuOpen = isMenuOpen
    return isMenuOpen
end

function GameService:getCurrentMapId()
    local ov = self:getOverworld()
    return ov and ov.map and ov.map.id
end

-- =======================================================================
-- Engine abstraction: never let engine src.* paths leak outside GameService
-- =======================================================================
function GameService:getGrowthSystem()
    return Helpers.safeRequire("src.pokemon.Growth")
end

function GameService:getBadgeSystem()
    return Helpers.safeRequire("src.inventory.Badges")
end

function GameService:getBattleStateClass()
    return Helpers.safeRequire("src.battle.BattleState")
end

function GameService:getTypeChart()
    return Helpers.safeRequire("src.battle.TypeChart")
end

return GameService
