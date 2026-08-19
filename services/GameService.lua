local Helpers = require("util.Helpers")

local GameService = {}
GameService.__index = GameService

function GameService.new(locator)
    local self = setmetatable({}, GameService)
    self._locator = locator
    self._game = nil
    self._data = {}

    self._menuOpenCache = setmetatable({}, { __mode = "k" })

    self._lastSafariMapId = nil
    return self
end

function GameService:setGame(game)
    self._game = game
    if game and game.data then
        self._data = game.data
    end
end

function GameService:getGame()
    if self._game then return self._game end
    local ok, game = pcall(require, "src.core.Game")
    if ok and game and game.save and game.data then
        self:setGame(game)
    end
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

function GameService:getGrowthRates()
    return self._data.growth_rates or {}
end

function GameService:getOverworld()
    local g = self._game
    return g and g.overworld
end

function GameService:getGen2TimeOfDay()
    local g = self._game
    local world = g and g.world
    if type(world) ~= "table" then return nil end
    local v = world.tod or world.daytime
    if type(v) ~= "string" then return nil end
    v = v:upper()
    if v == "MORN" or v == "DAY" or v == "NITE" then return v end
    return nil
end

function GameService:getStack()
    local g = self._game
    return g and g.stack
end

function GameService:getPlayTime()
    local save = self:getSave()
    local v = save and (save.playTime or save.playtime or save.timePlayed)
    if type(v) == "number" then return v end
    if type(v) == "table" then

        local h = tonumber(v.hours) or 0
        local m = tonumber(v.minutes) or 0
        local s = tonumber(v.seconds) or 0
        return h * 3600 + m * 60 + s
    end
    return 0
end

function GameService:getPlayerName()
    local save = self:getSave()
    return (save and save.player and save.player.name) or "Trainer"
end

function GameService:getMoney()
    local save = self:getSave()

    local v = save and (save.money or save.gold
        or (type(save.player) == "table" and save.player.money))
    if type(v) == "number" then return v end
    return 0
end

function GameService:getParty()
    local save = self:getSave()
    return (save and save.party) or {}
end

function GameService:getPokedex()
    local save = self:getSave()
    local dex = save and save.pokedex
    if type(dex) ~= "table" then return { seen = {}, owned = {} } end

    return { seen = dex.seen or {}, owned = dex.owned or dex.caught or {} }
end

function GameService:getInventory()
    local save = self:getSave()
    return (save and save.inventory) or {}
end

function GameService:getRepelSteps()
    local save = self:getSave()
    local v = save and save.repelSteps
    if type(v) == "number" then return v end
    return 0
end

function GameService:_safariDebugEnabled()
    if not self._locator:has("ConfigService") then return false end
    return self._locator:resolve("ConfigService").DEBUG_SAFARI == true
end

function GameService:getSafariSteps()
    local save = self:getSave()
    if not save then return 0 end

    local CONFIRMED_CONTAINER, CONFIRMED_FIELD = nil, nil
    if CONFIRMED_FIELD and type(CONFIRMED_CONTAINER) == "table" then
        local v = CONFIRMED_CONTAINER[CONFIRMED_FIELD]
        if type(v) == "number" then return v end
    end

    local function findByName(t, requireSafariInName)
        if type(t) ~= "table" then return nil end
        for k, v in pairs(t) do
            if type(k) == "string" and type(v) == "number" then
                local lk = k:lower()
                if lk:find("step", 1, true) then
                    if not requireSafariInName or lk:find("safari", 1, true) then
                        return v
                    end
                end
            end
        end
        return nil
    end

    local found = findByName(save, true) or findByName(save.safari, false)
    if found then return found end

    self:_debugSafariCandidates(save)
    return 0
end

function GameService:_debugSafariCandidates(save)
    if not self:_safariDebugEnabled() then return end
    if not self._locator:has("LogService") then return end
    local log = self._locator:resolve("LogService")
    self._safariDumpCount = self._safariDumpCount or 0
    if self._safariDumpCount >= 8 then return end

    local candidates = {}
    local function collect(t, prefix, anyNumericField)
        if type(t) ~= "table" then return end
        for k, v in pairs(t) do
            if type(k) == "string" and type(v) == "number" then
                local lk = k:lower()

                if anyNumericField or lk:find("step", 1, true) or lk:find("safari", 1, true) then
                    candidates[prefix .. k] = v
                end
            end
        end
    end
    collect(save, "save.", false)
    collect(save.safari, "save.safari.", true)
    collect(self:getOverworld(), "overworld.", false)

    local keys = {}
    for k in pairs(candidates) do keys[#keys + 1] = k end
    table.sort(keys)

    local changed = false
    if not self._safariLastSnapshot then
        changed = true
    else
        for _, k in ipairs(keys) do
            if self._safariLastSnapshot[k] ~= candidates[k] then
                changed = true
                break
            end
        end
    end
    self._safariLastSnapshot = candidates
    if not changed then return end

    self._safariDumpCount = self._safariDumpCount + 1
    if #keys == 0 then
        log:info("[Safari debug %d/8] no numeric candidates in save / save.safari / overworld -- the field may live somewhere else entirely", self._safariDumpCount)
        return
    end
    local parts = {}
    for _, k in ipairs(keys) do
        parts[#parts + 1] = string.format("%s=%s", k, tostring(candidates[k]))
    end
    log:info("[Safari debug %d/8] candidates (take a few steps and see which one ticks down): %s", self._safariDumpCount, table.concat(parts, ", "))
end

function GameService:isInSafariZone()
    local mapId = self:getCurrentMapId()
    local hasEncounters = self._data.encounters ~= nil and self._data.encounters[mapId] ~= nil
    local inZone = mapId ~= nil and mapId:match("^SAFARI_ZONE") ~= nil and hasEncounters
    if inZone and mapId ~= self._lastSafariMapId then
        self._lastSafariMapId = mapId
        if self:_safariDebugEnabled() then
            local log = self._locator:resolve("LogService")
            if log then log:info("SafariZone DEBUG: entered mapId=%s", tostring(mapId)) end
        end
    elseif not inZone then
        self._lastSafariMapId = nil
    end
    return inZone
end

function GameService:isGen2()
    if self._isGen2 ~= nil then return self._isGen2 end

    local save = self:getSave()
    if type(save) == "table" and type(save.pokedex) == "table" then
        if save.pokedex.caught ~= nil then
            self._isGen2 = true
            return true
        end
        if save.pokedex.owned ~= nil then
            self._isGen2 = false
            return false
        end
    end

    return Helpers.safeRequire("src.core.Game2") ~= nil
end

function GameService:_isInBattleOverride()
    local ok, result = pcall(function()
        return self._locator:has("BattleService")
            and self._locator:resolve("BattleService"):isInBattle()
    end)
    return ok and result or false
end

function GameService:isInGame()
    if self:_isInBattleOverride() then return true end

    local save = self:getSave()
    if not save then return false end
    local party = save.party
    if not party or #party == 0 then return false end

    local stk = self:getStack()
    if not (stk and stk.states and #stk.states > 0) then

        if self:isGen2() then
            return true
        end
        return false
    end

    for i = #stk.states, 1, -1 do
        local state = stk.states[i]
        if type(state) == "table" then

            if state.map ~= nil or (state.enemy ~= nil and state.player ~= nil) then
                return true
            end
        end
    end
    return false
end

function GameService:isMenuOpen()
    if self:_isInBattleOverride() then return false end

    local stk = self:getStack()
    if not (stk and stk.states and #stk.states > 0) then return false end

    local top = stk.states[#stk.states]
    if type(top) ~= "table" then return false end

    if top.kclSettingsScreen then return false end

    local cached = self._menuOpenCache[top]
    if cached ~= nil then
        return cached
    end

    local isMenuOpen = top.map == nil and not (top.enemy ~= nil and top.player ~= nil)
    self._menuOpenCache[top] = isMenuOpen
    return isMenuOpen
end

function GameService:getCurrentMapId()
    local ov = self:getOverworld()
    local id = ov and ov.map and ov.map.id
    if type(id) == "string" and id ~= "" then return id end

    local g = self:getGame()
    local borderKey = g and g.world and g.world.borderKey
    if type(borderKey) == "string" and borderKey ~= "" then

        local stripped = borderKey:gsub("^%a+|", "")
        if stripped ~= "" then borderKey = stripped end
        return borderKey
    end
    local save = self:getSave()
    local posMap = save and type(save.position) == "table" and save.position.map
    if type(posMap) == "string" and posMap ~= "" then return posMap end
    return nil
end

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

function GameService:getBoxesModule()
    return Helpers.safeRequire("src.pokemon.Boxes")
end

function GameService:getPartyModule()
    return Helpers.safeRequire("src.pokemon.Party")
end

function GameService:getBagModule()
    return Helpers.safeRequire("src.inventory.Bag")
end

function GameService:getOptionRows()
    return Helpers.safeRequire("src.ui.OptionRows")
end

function GameService:getPaletteFX()
    return Helpers.safeRequire("src.render.PaletteFX")
end

return GameService
