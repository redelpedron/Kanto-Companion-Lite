local Math    = require("util.Math")
local Helpers = require("util.Helpers")

local GameDataSystem = {}
GameDataSystem.__index = GameDataSystem

local DEFAULT_ENCOUNTER_BUCKETS = { 51, 102, 141, 166, 191, 216, 229, 242, 253, 256 }

local GEN2_SLOT_WEIGHTS = {
    [7] = { 30, 30, 20, 10, 5, 4, 1 },
    [3] = { 60, 30, 10 },
}

local GEN2_TOD_ORDER  = { "MORN", "DAY", "NITE" }
local GEN2_TOD_LABELS = { MORN = "Morning", DAY = "Day", NITE = "Night" }

function GameDataSystem.new(locator)
    local self = setmetatable({}, GameDataSystem)
    self._locator = locator
    self.gameService = locator:resolve("GameService")
    self.bus = locator:resolve("EventBus")
    self._acc = 0
    self._interval = 0.2

    self._rivalKnown = {}
    return self
end

function GameDataSystem:update(dt)
    self._acc = self._acc + dt
    if self._acc < self._interval then return end
    self._acc = self._acc - self._interval
    self:tick()
end

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
            types = Helpers.dedupeTypes(def and def.types),
            moves = mon.moves or {},
            active = (ctx.activeMon ~= nil and mon == ctx.activeMon),
            xpProgress = xpProg,
            xpToNext = xpNext,
            pokemonData = ctx.dPoke,
            gender = Helpers.normalizeGender(mon.gender),
        }
    end
    return party
end

function GameDataSystem:_buildRival(ctx)
    if not ctx.battleSvc:isTrainerBattle() then

        self._rivalKnown = {}
        return {}
    end

    local rival = {}
    local enemyActiveMon = ctx.battleSvc:getEnemyMon()
    for i, mon in ipairs(ctx.battleSvc:getEnemyParty()) do
        local def = ctx.dPoke[mon.species]

        local isActive = enemyActiveMon ~= nil
            and mon.species == enemyActiveMon.species
            and mon.level == enemyActiveMon.level

        local hp, maxhp, status
        if isActive then
            hp     = enemyActiveMon.hp
            maxhp  = enemyActiveMon.stats and enemyActiveMon.stats.hp
            status = enemyActiveMon.status

            local prev = self._rivalKnown[i]
            if prev and prev.hp == 0 and maxhp ~= nil and hp == maxhp then
                hp, maxhp, status = prev.hp, prev.maxhp, prev.status
            else

                self._rivalKnown[i] = { hp = hp, maxhp = maxhp, status = status }
            end
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
            types = Helpers.dedupeTypes(def and def.types),
            active = isActive,
            pokemonData = ctx.dPoke,
        }
    end
    return rival
end

function GameDataSystem:_buildTrainer(ctx)
    local dex = self.gameService:getPokedex()
    local badgeCount = 0
    if type(ctx.save.player) == "table" and type(ctx.save.player.badges) == "table" then

        for _ in pairs(ctx.save.player.badges) do
            badgeCount = badgeCount + 1
        end
    elseif ctx.badges and ctx.data then
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

    local kantoBadgeCount = 0
    if type(ctx.save.player) == "table" and type(ctx.save.player.kantoBadges) == "table" then
        for _ in pairs(ctx.save.player.kantoBadges) do
            kantoBadgeCount = kantoBadgeCount + 1
        end
    end

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
        kantoBadgeCount = kantoBadgeCount,
        location = location,
        playTime = self.gameService:getPlayTime(),
    }
end

function GameDataSystem:_buildInventory()
    local inv = {}
    for itemId, count in pairs(self.gameService:getInventory()) do
        if type(count) == "number" and count > 0 then
            inv[itemId] = count
        end
    end
    return inv
end

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

function GameDataSystem:_appendGen2Sections(route, part, mapId, dPoke, kindLabel)
    if type(part) ~= "table" then return end
    local entry = part[mapId]
    if type(entry) ~= "table" or type(entry.slots) ~= "table" then return end

    local function aggregate(slotList)
        local weights = GEN2_SLOT_WEIGHTS[#slotList]
        local agg, order = {}, {}
        for i, slot in ipairs(slotList) do
            if slot and slot.species then
                local wt = (weights and weights[i]) or math.floor(100 / #slotList)
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
                pct = a.weight,
                minLevel = a.minL,
                maxLevel = a.maxL,
            }
        end
        table.sort(list, function(x, y) return x.pct > y.pct end)
        return list
    end

    local function rateFor(tod)
        local r = entry.rates
        if type(r) == "table" then
            r = tod and r[tod]
        elseif tod == nil then
            r = entry.rate
        end
        if type(r) == "number" then
            return math.floor(r / 256 * 100 + 0.5)
        end
        return nil
    end

    local sawTod = false
    for _, tod in ipairs(GEN2_TOD_ORDER) do
        local todSlots = entry.slots[tod]
        if type(todSlots) == "table" and #todSlots > 0 then
            sawTod = true
            local list = aggregate(todSlots)
            if #list > 0 then
                route.sections[#route.sections + 1] = {
                    title = kindLabel .. " (" .. (GEN2_TOD_LABELS[tod] or tod) .. ")",
                    tab = { rate = rateFor(tod), species = list },
                }
            end
        end
    end

    if not sawTod and #entry.slots > 0 and type(entry.slots[1]) == "table" then
        local list = aggregate(entry.slots)
        if #list > 0 then
            route.sections[#route.sections + 1] = {
                title = kindLabel,
                tab = { rate = rateFor(nil), species = list },
            }
        end
    end
end

function GameDataSystem:_buildRoute(ctx)
    local mapId = self.gameService:getCurrentMapId()
    if not mapId then return nil end

    local route = {
        id = mapId,
        name = Helpers.formatMapName(mapId),
        grass = nil,
        water = nil,
        sections = {},
    }

    local ge = ctx.data.gen2Encounters
    if type(ge) == "table" then
        self:_appendGen2Sections(route, ge.grass, mapId, ctx.dPoke, "Grass")
        self:_appendGen2Sections(route, ge.water, mapId, ctx.dPoke, "Water")
        return route
    end

    local enc = (ctx.data.encounters or {})[mapId]
    if enc then
        local buckets = (ctx.data.constants and ctx.data.constants.encounterBuckets)
                or DEFAULT_ENCOUNTER_BUCKETS
        route.grass = self:_buildEncounterTable(enc.grass, ctx.dPoke, buckets)
        route.water = self:_buildEncounterTable(enc.water, ctx.dPoke, buckets)
        if route.grass then route.sections[#route.sections + 1] = { title = "Grass", tab = route.grass } end
        if route.water then route.sections[#route.sections + 1] = { title = "Water", tab = route.water } end
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
