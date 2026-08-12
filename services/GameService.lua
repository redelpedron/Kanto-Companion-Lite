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
    -- Weak keys: entries for popped/discarded stack states get collected
    -- automatically instead of pinning them in memory or requiring manual
    -- cleanup. See isMenuOpen below.
    self._menuOpenCache = setmetatable({}, { __mode = "k" })
    -- DEBUG (temporary): logs the raw mapId once per SAFARI_ZONE_* entry
    -- so we can see whether the gate/ticket-booth map shares the same
    -- prefix as the actual zone areas. Remove once confirmed either way.
    self._lastSafariMapId = nil
    return self
end

function GameService:setGame(game)
    self._game = game
    if game and game.data then
        self._data = game.data
    end
end

-- FIX (v2.0.27): game.ready is emitted without a guaranteed payload -- if
-- payload.game is ever missing, self._game stayed nil forever and the
-- love.draw/game.update install in AppController:_installGameHooks() would
-- silently never run, permanently hiding the whole overlay. Other content
-- mods (e.g. quest systems) work around this same engine quirk by falling
-- back to requiring the live Game singleton directly; do the same here so
-- we don't depend on a single event payload ever arriving intact.
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

-- No confirmed field name for the Safari Zone step counter -- the host
-- engine's source isn't available in this sandbox to check against.
-- Once this is confirmed for real (see _debugSafariCandidates below),
-- fill in CONFIRMED_FIELD / CONFIRMED_CONTAINER and delete the search +
-- debug path -- they're scaffolding, not the intended long-term shape.
function GameService:getSafariSteps()
    local save = self:getSave()
    if not save then return 0 end

    -- FILL IN ONCE CONFIRMED (see the log lines described below), e.g.:
    --   local CONFIRMED_CONTAINER, CONFIRMED_FIELD = save, "safariSteps"
    --   local CONFIRMED_CONTAINER, CONFIRMED_FIELD = save.safari, "steps"
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

-- Diagnostic-only: collect every numeric field that could plausibly be
-- the step counter and log the set whenever it changes. A live-updating
-- log while you actually walk around the Safari Zone is far more
-- reliable than a name guess -- the field that ticks down by exactly 1
-- per step you take is unambiguous, name or no name. Only fires while
-- GameService:isInSafariZone() is true (see the one call site in
-- GameDataSystem), and stops logging after 8 changed snapshots so a
-- long test session doesn't spam the mod log forever if the real field
-- turns out to live somewhere none of these three tables cover.
function GameService:_debugSafariCandidates(save)
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
                -- Inside save.safari, "safari" is already implied by the
                -- container, so any number there is worth listing; for
                -- the unscoped tables (save, overworld) only list fields
                -- that look name-relevant, or the dump would be huge.
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

    -- Only re-log when something in the snapshot actually moved --
    -- that's the signal that separates a real, live step counter from
    -- an unrelated static field that merely has a similar-sounding name.
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

-- Safari Zone maps all share a "SAFARI_ZONE_*" mapId prefix (matched on
-- the raw id, not the title-cased display name from formatMapName, so
-- this can't be fooled by some other unrelated map that happens to
-- contain the words "Safari Zone" in its formatted name).
function GameService:isInSafariZone()
    local mapId = self:getCurrentMapId()
    local inZone = mapId ~= nil and mapId:match("^SAFARI_ZONE") ~= nil
    if inZone and mapId ~= self._lastSafariMapId then
        self._lastSafariMapId = mapId
        local log = self._locator:resolve("LogService")
        if log then log:info("SafariZone DEBUG: entered mapId=%s", tostring(mapId)) end
    elseif not inZone then
        self._lastSafariMapId = nil
    end
    return inZone
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

    -- KCL's own settings screen (overlay ON/OFF, topbar position) should
    -- never hide the overlay -- the whole point of those rows is to
    -- preview live while you're on the screen that sets them.
    if top.kclSettingsScreen then return false end

    local cached = self._menuOpenCache[top]
    if cached ~= nil then
        return cached
    end

    -- Anything pushed on top of the overworld/battle state is some kind
    -- of menu -- Start menu list, Pokedex, Party, Bag, Save flow, PC, or
    -- another mod's own screen. Absence of the overworld/battle markers
    -- (same shape isInGame checks above) is the signal, rather than
    -- matching one specific menu's shape, which only ever caught the
    -- flat Start-menu list and missed every screen opened from it.
    local isMenuOpen = top.map == nil and not (top.enemy ~= nil and top.player ~= nil)
    self._menuOpenCache[top] = isMenuOpen
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

-- Added when PCService's and SettingsScreen's own direct requires of these
-- were found to bypass this boundary (see CODE_REVIEW.md). Helpers.safeRequire
-- caches by path, so this is cheap to call repeatedly.
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
