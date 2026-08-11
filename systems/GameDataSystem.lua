local Math    = require("util.Math")
local Helpers = require("util.Helpers")

local GameDataSystem = {}
GameDataSystem.__index = GameDataSystem

-- Default encounter-rate buckets (percent-of-256 breakpoints for a
-- 10-slot grass/water table), used whenever a map's own data doesn't
-- carry its own `constants.encounterBuckets` override.
local DEFAULT_ENCOUNTER_BUCKETS = { 51, 102, 141, 166, 191, 216, 229, 242, 253, 256 }

function GameDataSystem.new(locator)
    local self = setmetatable({}, GameDataSystem)
    self._locator = locator
    self.gameService = locator:resolve("GameService")
    self.bus = locator:resolve("EventBus")
    self._acc = 0
    self._interval = 0.2 -- throttled: full snapshot + bus publish is too heavy for every frame
    -- v2.1.38: last known hp/maxhp/status per rival roster slot, keyed by
    -- index. Once a mon has been sent out at least once we've genuinely
    -- seen its stats -- including 0 HP if it fainted -- so that should
    -- stick even after it's benched again (see _buildRival below).
    -- Cleared whenever we're not in a trainer battle so a new trainer's
    -- roster never inherits a previous battle's reveals.
    self._rivalKnown = {}
    return self
end

--- Runs every frame via Lifecycle, but only does real work every 0.2s.
function GameDataSystem:update(dt)
    self._acc = self._acc + dt
    if self._acc < self._interval then return end
    self._acc = self._acc - self._interval
    self:tick()
end

-- Resolves and bundles the services/data this tick's builders share, so
-- each builder takes one `ctx` table instead of a long, easy-to-misorder
-- positional argument list, and nothing gets re-resolved per section.
function GameDataSystem:_buildContext()
    local battleSvc = self._locator:resolve("BattleService")
    local battle = battleSvc:currentBattle()
    return {
        save    = self.gameService:getSave(),
        data    = self.gameService:getData(),
        dPoke   = self.gameService:getPokemonData(),
        rates   = self.gameService:getGrowthRates(),
        growth  = self.gameService:getGrowthSystem(),
        badges  = self.gameService:getBadgeSystem(),
        battleSvc = battleSvc,
        activeMon = battle and battle.player and battle.player.mon or nil,
    }
end

-- The player's own party (both HUD party panels).
function GameDataSystem:_buildParty(ctx)
    local party = {}
    for i, mon in ipairs(self.gameService:getParty()) do
        local def = ctx.dPoke[mon.species]
        local xpProg, xpNext = Helpers.expProgress(ctx.growth, def, mon, ctx.rates)
        party[i] = {
            name = mon.nickname or (def and def.name) or tostring(mon.species),
            species = mon.species,
            level = mon.level or 0,
            hp = mon.hp or 0,
            maxhp = (mon.stats and mon.stats.hp) or 1,
            status = mon.status or "",
            types = def and def.types or {},
            moves = mon.moves or {},
            active = (ctx.activeMon ~= nil and mon == ctx.activeMon),
            xpProgress = xpProg,
            xpToNext = xpNext,
            pokemonData = ctx.dPoke,
        }
    end
    return party
end

-- Landscape-only Rival tab: the opposing trainer's full roster, built
-- the same way as the player's party above but with no xpProgress
-- field, so PokemonPanel's existing "only draw the xp bar if the row
-- has one" check already leaves it off without any extra flag. Wild
-- encounters have no trainer, so this stays empty and the Rival panel
-- shows its "no trainer battle" placeholder instead.
function GameDataSystem:_buildRival(ctx)
    if not ctx.battleSvc:isTrainerBattle() then
        -- Not (or no longer) in a trainer battle -- drop any reveals so
        -- the next trainer's roster starts fresh instead of inheriting
        -- stale hp/maxhp from whoever we last fought.
        self._rivalKnown = {}
        return {}
    end

    local rival = {}
    local enemyActiveMon = ctx.battleSvc:getEnemyMon()
    for i, mon in ipairs(ctx.battleSvc:getEnemyParty()) do
        local def = ctx.dPoke[mon.species]
        -- trainer.parties entries only ever carry {level, species} -- no
        -- hp/stats/moves/status. That data doesn't exist until the mon
        -- is actually sent into battle, at which point it lives in a
        -- *separate* live object (battle.enemy.mon, i.e. enemyActiveMon
        -- here). Matches how Gen 1 trainer data has always worked: a
        -- trainer's remaining roster is genuinely just species+level
        -- until it's sent out.
        --
        -- FIX: `active` used to compare `mon == enemyActiveMon` -- table
        -- identity between two different tables that can never be the
        -- same object, so it was always false, for every row, every
        -- battle. That's also why the live-HP override already built
        -- into PokemonPanel:_liveStats() never engaged even for the mon
        -- actually on the field. Match by species+level instead.
        -- hp/maxhp/status are left nil for benched mons (PokemonPanel
        -- now renders that as "unknown" rather than a misleading 0/1)
        -- since we genuinely don't know them yet.
        local isActive = enemyActiveMon ~= nil
            and mon.species == enemyActiveMon.species
            and mon.level == enemyActiveMon.level

        local hp, maxhp, status
        if isActive then
            hp     = enemyActiveMon.hp
            maxhp  = enemyActiveMon.stats and enemyActiveMon.stats.hp
            status = enemyActiveMon.status
            -- v2.1.38: remember what we just saw for this slot, so it
            -- doesn't fall back to "unknown" once the mon is benched
            -- again -- most importantly when it's benched *because it
            -- just fainted*, which used to redraw as "?" instead of
            -- staying at 0/maxhp.
            self._rivalKnown[i] = { hp = hp, maxhp = maxhp, status = status }
        else
            local known = self._rivalKnown[i]
            hp     = known and known.hp
            maxhp  = known and known.maxhp
            status = known and known.status
        end

        rival[i] = {
            name = def and def.name or tostring(mon.species),
            species = mon.species,
            level = mon.level or 0,
            hp = hp,
            maxhp = maxhp,
            status = status,
            types = def and def.types or {},
            active = isActive,
            pokemonData = ctx.dPoke,
        }
    end
    return rival
end

-- Trainer/HUD summary strip: name, money, dex counts, badge count,
-- location, play time.
function GameDataSystem:_buildTrainer(ctx)
    local dex = self.gameService:getPokedex()
    local badgeCount = 0
    if ctx.badges and ctx.data then
        local ok, list = pcall(ctx.badges.list, ctx.data)
        if ok and list then
            for _, e in ipairs(list) do
                local itemId = ctx.badges.itemFor and ctx.badges.itemFor(e)
                if itemId and ctx.save.inventory and ctx.save.inventory[itemId] and ctx.save.inventory[itemId] > 0 then
                    badgeCount = badgeCount + 1
                end
            end
        end
    end

    -- Safari Zone edge case: the location the HUD shows everywhere else
    -- (TopBar's location chip, both its wide and compact render paths)
    -- also carries the remaining step count while inside the zone, since
    -- running out of steps there ends the visit -- same reason a repel's
    -- remaining steps are surfaced (see repel.updated) rather than left
    -- for the player to track themselves.
    local location = Helpers.formatMapName(self.gameService:getCurrentMapId())
    if self.gameService:isInSafariZone() then
        location = location .. " - " .. self.gameService:getSafariSteps() .. " steps"
    end

    return {
        name = self.gameService:getPlayerName(),
        money = self.gameService:getMoney(),
        dexSeen = Math.countTrue(dex.seen),
        dexOwned = Math.countTrue(dex.owned),
        badgeCount = badgeCount,
        location = location,
        playTime = self.gameService:getPlayTime(),
    }
end

-- Bag contents: {itemId -> count}, positive counts only.
function GameDataSystem:_buildInventory()
    local inv = {}
    for itemId, count in pairs(self.gameService:getInventory()) do
        if type(count) == "number" and count > 0 then
            inv[itemId] = count
        end
    end
    return inv
end

-- Aggregates one grass/water encounter table (species -> weighted slots)
-- into the sorted, percentage-labeled list the Route panel displays.
-- `part` is `data.encounters[mapId].grass` or `.water`; nil/zero-rate
-- returns nil so the panel can tell "no water here" from "0% water".
function GameDataSystem:_buildEncounterTable(part, dPoke, buckets)
    if not part or not part.slots or (part.rate or 0) == 0 then return nil end
    local bk = part.buckets or buckets
    local agg, order, prev = {}, {}, 0
    for i, slot in ipairs(part.slots) do
        local top = bk[i] or 256
        local wt = top - prev
        prev = top
        if slot and slot.species then
            local a = agg[slot.species]
            if not a then
                a = { species = slot.species, weight = 0, minL = slot.level, maxL = slot.level }
                agg[slot.species] = a
                order[#order + 1] = a
            end
            a.weight = a.weight + wt
            a.minL = math.min(a.minL, slot.level)
            a.maxL = math.max(a.maxL, slot.level)
        end
    end
    local list = {}
    for _, a in ipairs(order) do
        local d = dPoke[a.species]
        list[#list + 1] = {
            name = (d and d.name) or tostring(a.species),
            species = a.species,
            pct = math.floor(a.weight / 256 * 100 + 0.5),
            minLevel = a.minL,
            maxLevel = a.maxL,
        }
    end
    table.sort(list, function(x, y) return x.pct > y.pct end)
    return { rate = math.floor((part.rate or 0) / 256 * 100 + 0.5), species = list }
end

-- Current map: name plus grass/water encounter breakdowns, or nil if
-- the engine doesn't currently have a resolved map id.
function GameDataSystem:_buildRoute(ctx)
    local mapId = self.gameService:getCurrentMapId()
    if not mapId then return nil end

    local route = {
        id = mapId,
        name = Helpers.formatMapName(mapId),
        grass = nil,
        water = nil,
    }
    local enc = (ctx.data.encounters or {})[mapId]
    if enc then
        local buckets = (ctx.data.constants and ctx.data.constants.encounterBuckets)
                or DEFAULT_ENCOUNTER_BUCKETS
        route.grass = self:_buildEncounterTable(enc.grass, ctx.dPoke, buckets)
        route.water = self:_buildEncounterTable(enc.water, ctx.dPoke, buckets)
    end
    return route
end

function GameDataSystem:tick()
    local game = self.gameService:getGame()
    if not game then return end
    if not self.gameService:isInGame() then return end
    if self.gameService:isMenuOpen() then return end

    local ctx = self:_buildContext()

    self.bus:publish("party.updated", self:_buildParty(ctx))
    self.bus:publish("rival.updated", self:_buildRival(ctx))
    self.bus:publish("trainer.updated", self:_buildTrainer(ctx))
    self.bus:publish("repel.updated", self.gameService:getRepelSteps())
    self.bus:publish("inventory.updated", self:_buildInventory())
    self.bus:publish("route.updated", self:_buildRoute(ctx))
end

return GameDataSystem
