
--- GameService: safe wrapper around the gen1recomp game reference.
-- Abstracts engine internals so components never touch raw game state.
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
    return party and #party > 0
end

function GameService:isMenuOpen()
    local stk = self:getStack()
    if not (stk and stk.states and #stk.states > 0) then return false end
    local top = stk.states[#stk.states]
    return type(top) == "table" and top.items ~= nil and top.index ~= nil
end

function GameService:getCurrentMapId()
    local ov = self:getOverworld()
    return ov and ov.map and ov.map.id
end

return GameService
