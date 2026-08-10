local Math    = require("util.Math")
local Helpers = require("util.Helpers")

local GameDataSystem = {}
GameDataSystem.__index = GameDataSystem

function GameDataSystem.new(locator)
    local self = setmetatable({}, GameDataSystem)
    self._locator = locator
    self.gameService = locator:resolve("GameService")
    self.bus = locator:resolve("EventBus")
    self._acc = 0
    self._interval = 0.2 -- throttled: full snapshot + bus publish is too heavy for every frame
    return self
end

--- Runs every frame via Lifecycle, but only does real work every 0.2s.
function GameDataSystem:update(dt)
    self._acc = self._acc + dt
    if self._acc < self._interval then return end
    self._acc = self._acc - self._interval
    self:tick()
end

function GameDataSystem:tick()
    local game = self.gameService:getGame()
    if not game then return end
    if not self.gameService:isInGame() then return end
    if self.gameService:isMenuOpen() then return end

    local save   = self.gameService:getSave()
    local data   = self.gameService:getData()
    local dPoke  = self.gameService:getPokemonData()
    local dMove  = self.gameService:getMoveData()
    local rates  = self.gameService:getGrowthRates()
    -- FIX: engine internals accessed through GameService abstraction
    local growth = self.gameService:getGrowthSystem()
    local badges = self.gameService:getBadgeSystem()
    local battle = self._locator:resolve("BattleService"):currentBattle()
    local activeMon = battle and battle.player and battle.player.mon or nil

    local party = {}
    for i, mon in ipairs(self.gameService:getParty()) do
        local def = dPoke[mon.species]
        local xpProg, xpNext
        if growth and def and def.growthRate and mon.exp and mon.level then
            local cur = growth.expForLevel(def.growthRate, mon.level, rates)
            local nxt = growth.expForLevel(def.growthRate, mon.level + 1, rates)
            if mon.level >= 100 or nxt <= cur then
                xpProg, xpNext = 1, 0
            else
                xpProg = math.max(0, math.min(1, (mon.exp - cur) / (nxt - cur)))
                xpNext = math.max(0, nxt - cur)
            end
        end
        party[i] = {
            name = mon.nickname or (def and def.name) or tostring(mon.species),
            species = mon.species,
            level = mon.level or 0,
            hp = mon.hp or 0,
            maxhp = (mon.stats and mon.stats.hp) or 1,
            status = mon.status or "",
            types = def and def.types or {},
            moves = mon.moves or {},
            active = (activeMon ~= nil and mon == activeMon),
            xpProgress = xpProg,
            xpToNext = xpNext,
            pokemonData = dPoke,
        }
    end
    self.bus:publish("party.updated", party)

    local dex = self.gameService:getPokedex()
    local badgeCount = 0
    if badges and data then
        local ok, list = pcall(badges.list, data)
        if ok and list then
            for _, e in ipairs(list) do
                local itemId = badges.itemFor and badges.itemFor(e)
                if itemId and save.inventory and save.inventory[itemId] and save.inventory[itemId] > 0 then
                    badgeCount = badgeCount + 1
                end
            end
        end
    end

    self.bus:publish("trainer.updated", {
        name = self.gameService:getPlayerName(),
        money = self.gameService:getMoney(),
        dexSeen = Math.countTrue(dex.seen),
        dexOwned = Math.countTrue(dex.owned),
        badgeCount = badgeCount,
        location = Helpers.formatMapName(self.gameService:getCurrentMapId()),
        playTime = self.gameService:getPlayTime(),
    })

    self.bus:publish("repel.updated", self.gameService:getRepelSteps())

    local inv = {}
    for itemId, count in pairs(self.gameService:getInventory()) do
        if type(count) == "number" and count > 0 then
            inv[itemId] = count
        end
    end
    self.bus:publish("inventory.updated", inv)

    local mapId = self.gameService:getCurrentMapId()
    if mapId then
        local route = {
            id = mapId,
            name = Helpers.formatMapName(mapId),
            grass = nil,
            water = nil,
        }
        local enc = (data.encounters or {})[mapId]
        if enc then
            local BK = (data.constants and data.constants.encounterBuckets)
                    or { 51, 102, 141, 166, 191, 216, 229, 242, 253, 256 }
            local function buildEncTable(part)
                if not part or not part.slots or (part.rate or 0) == 0 then return nil end
                local bk = part.buckets or BK
                local agg, order, prev = {}, {}, 0
                for i2, slot in ipairs(part.slots) do
                    local top = bk[i2] or 256
                    local wt = top - prev
                    prev = top
                    if slot and slot.species then
                        local a = agg[slot.species]
                        if not a then
                            a = { species=slot.species, weight=0, minL=slot.level, maxL=slot.level }
                            agg[slot.species] = a
                            order[#order+1] = a
                        end
                        a.weight = a.weight + wt
                        a.minL = math.min(a.minL, slot.level)
                        a.maxL = math.max(a.maxL, slot.level)
                    end
                end
                local list = {}
                for _, a in ipairs(order) do
                    local d = dPoke[a.species]
                    list[#list+1] = {
                        name = (d and d.name) or tostring(a.species),
                        species = a.species,
                        pct = math.floor(a.weight/256*100+0.5),
                        minLevel = a.minL,
                        maxLevel = a.maxL,
                    }
                end
                table.sort(list, function(x,y) return x.pct > y.pct end)
                return { rate = math.floor((part.rate or 0)/256*100+0.5), species = list }
            end
            route.grass = buildEncTable(enc.grass)
            route.water = buildEncTable(enc.water)
        end
        self.bus:publish("route.updated", route)
    else
        self.bus:publish("route.updated", nil)
    end
end

return GameDataSystem
