local Component = require("core.Component")
local Colors    = require("util.Colors")
local Helpers   = require("util.Helpers")
local Math      = require("util.Math")
local ExpBar    = require("components.ExpBar")
local TypeColors = require("util.TypeColors")

local PokemonPanel = setmetatable({}, { __index = Component })
PokemonPanel.__index = PokemonPanel
PokemonPanel.needs = { "ConfigService", "FontService", "SpriteService", "TypeEffectiveness" }

function PokemonPanel.new(locator, props)
    local self = setmetatable(Component.new(locator, props), PokemonPanel)
    self.party = {}
    self.enemyTypes = nil
    -- Raw battle.player.mon reference, refreshed every frame via
    -- active_mon.changed (see BattleSystem:update). party.updated only
    -- ticks every 0.2s (GameDataSystem), which reads as a visible lag on
    -- HP/status for whichever party member is actively fighting, so we
    -- override that one row's hp/maxhp/status with this live data instead
    -- of waiting on the next poll.
    self.activeMon = nil
    -- One shared, reused instance per row rather than one per party slot:
    -- pure-render (no listeners, nothing to leak), so re-pointing its
    -- props/state before each row's draw() call is safe and avoids
    -- creating garbage components every frame.
    self._expBar = ExpBar.new(locator, {})
    self._expBar:_doInit()
    return self
end

-- Reused for both the player's party (default event names) and the
-- landscape-only Rival tab (partyEvent="rival.updated",
-- activeMonEvent="enemy_active_mon.changed", trackEnemyTypes=false --
-- matchup highlighting is about the player's own mons, not the rival's).
function PokemonPanel:init()
    local partyEvent     = self._props.partyEvent or "party.updated"
    local activeMonEvent = self._props.activeMonEvent or "active_mon.changed"
    self:_listen(partyEvent, function(_, party) self.party = party or {} end)
    if self._props.trackEnemyTypes ~= false then
        self:_listen("enemy.updated", function(_, enemy) self.enemyTypes = enemy and enemy.types or nil end)
    end
    self:_listen(activeMonEvent, function(_, mon) self.activeMon = mon end)
    self:_listen("battle.ended", function() self.activeMon = nil end)
end

--- While a row's mon is the active battler, prefer the live mon table
-- (updated every frame) over the party snapshot (updated every 0.2s) so
-- HP and status don't lag behind the actual battle. Shared by both the
-- full and compact row renderers.
function PokemonPanel:_liveStats(m)
    local hp, maxhp, status = m.hp, m.maxhp, m.status
    if m.active and self.activeMon then
        hp     = self.activeMon.hp or hp
        maxhp  = (self.activeMon.stats and self.activeMon.stats.hp) or maxhp
        status = self.activeMon.status or status
    end
    return hp, maxhp, status
end

-- =======================================================================
-- FULL rows (landscape): name, status, types, level, numeric HP, xp bar.
-- =======================================================================

function PokemonPanel:_drawFullRows(cfg, fonts, sprites, te, dc, x, y, w, h)
    local headerH = cfg.PARTY_HEADER_H
    local rowH    = cfg.PARTY_ROW_H
    local cy      = y + headerH
    local maxCy   = y + h - cfg.PARTY_PANEL_PAD_B

    if #self.party == 0 and self._props.emptyMessage then
        local f11 = fonts:getFont(11)
        dc:setFont(f11)
        dc:setColor(cfg.COL.dim, 1)
        dc:print(self._props.emptyMessage, x+8, cy)
        return
    end

    for _, m in ipairs(self.party) do
        if cy + rowH > maxCy then break end
        local img = sprites:getSprite(m.species, m.pokemonData)
        if img then
            local iw, ih = img:getDimensions()
            local sc = 24 / math.max(iw, ih)
            dc:setColor(cfg.COL.text, 1)
            dc:draw(img, x+8, cy+2, 0, sc, sc)
        end
        local hp, maxhp, status = self:_liveStats(m)

        local nameCol = cfg.COL.text
        if self.enemyTypes and te:hasSuperEffectiveMove(m, self.enemyTypes) then
            nameCol = cfg.COL.se
        end
        local f12 = fonts:getFont(12)
        dc:setFont(f12)
        dc:setColor(nameCol, 1)
        local nameStr = Helpers.sanitizeName(m.name)
        dc:print(nameStr, x+36, cy)
        local tx = x + 36 + f12:getWidth(nameStr)
        if status and status ~= "" and status ~= "OK" then
            local statusStr = " (" .. tostring(status) .. ")"
            dc:setColor(cfg.COL.lo, 1)
            dc:print(statusStr, tx, cy)
            tx = tx + f12:getWidth(statusStr)
        end
        tx = tx + f12:getWidth(" ")
        if m.types then
            local f9 = fonts:getFont(9)
            dc:setFont(f9)
            for _, t2 in ipairs(m.types) do
                local tname = TypeColors.normalize(t2)
                if tname ~= "" then
                    dc:setColor(cfg.TYPE[tname] or cfg.COL.dim, 1)
                    dc:print(tname, tx, cy+1)
                    tx = tx + f9:getWidth(tname .. " ")
                end
            end
        end
        local f10b = fonts:getFont(10)
        dc:setFont(f10b)
        dc:setColor(cfg.COL.dim, 1)
        local lvStr = "Lv" .. tostring(m.level)
        dc:print(lvStr, x+w-8-f10b:getWidth(lvStr), cy)
        -- v2.1.35: maxhp is nil for a benched rival-roster mon (its HP
        -- genuinely isn't known until it's sent into battle -- see
        -- GameDataSystem). Render that as "unknown" instead of a fake
        -- 0/1, which read as the Pokemon being nearly fainted.
        local known = maxhp ~= nil
        local frac = known and Math.clamp((hp or 0) / math.max(1, maxhp), 0, 1) or 0
        local barW = w - 44 - 50
        local barY = cy + 11
        dc:setColor({0.12,0.12,0.14}, 1)
        dc:rectangle("fill", x+36, barY, barW, 4)
        if known and frac > 0 then
            dc:setColor(Colors.hpColor(frac), 1)
            dc:rectangle("fill", x+36, barY, barW*frac, 4)
        end
        local hpStr = known and string.format("%3d/%3d", hp or 0, maxhp) or "?"
        dc:setFont(f10b)
        dc:setColor(cfg.COL.dim, 1)
        dc:print(hpStr, x+w-8-f10b:getWidth(hpStr), cy+10)
        if m.xpProgress ~= nil then
            self._expBar.progress = m.xpProgress
            self._expBar._props = { x = x+36, y = cy+16, w = barW, h = 2 }
            self._expBar:draw()
        end
        cy = cy + rowH
    end
end

-- =======================================================================
-- COMPACT strip (portrait): every party member sits in its own column
-- of one single horizontal row -- icon on top, current HP as a colored
-- number ("80/80", green/yellow/red by percentage, gray if fainted)
-- beneath it, and a status abbreviation (e.g. "PSN") beneath that when
-- present. Name/level/types/xp all dropped so the whole party fits in
-- one slim, wrap-height strip above the right panel.
-- =======================================================================

function PokemonPanel:_drawCompactStrip(cfg, fonts, sprites, dc, x, y, w, h)
    local n = #self.party
    if n == 0 then return end

    local headerH = cfg.PARTY_HEADER_H
    local rowY    = y + headerH
    local rowH    = math.min(cfg.PARTY_ROW_H_COMPACT, (y + h - cfg.PARTY_PANEL_PAD_B) - rowY)
    if rowH <= 0 then return end

    local fHp     = fonts:getFont(10)
    local fStatus = fonts:getFont(9)
    local hpLineH     = fHp:getHeight() + 2
    local statusLineH = fStatus:getHeight() + 2

    local cellW  = w / n
    -- Icon gets whatever vertical room is left after reserving fixed
    -- bands for the HP and status lines beneath it, clamped so it never
    -- overflows a narrow cell (a full party of 6) or looks oversized in
    -- a wide one (1-2 mons).
    local iconSz = math.max(14, math.min(cellW - 8, rowH - hpLineH - statusLineH))

    -- v1.0.66: get TypeEffectiveness service for super-effective glow
    local te = self:_service("TypeEffectiveness")

    for i, m in ipairs(self.party) do
        local cellX  = x + (i - 1) * cellW
        local cellCx = cellX + cellW / 2

        local img = sprites:getSprite(m.species, m.pokemonData)
        if img then
            local iw, ih = img:getDimensions()
            local sc = iconSz / math.max(iw, ih)

            -- v1.0.66: portrait-only green glow if this mon has a
            -- super-effective move against the current enemy/wild Pokémon
            if self.enemyTypes and te:hasSuperEffectiveMove(m, self.enemyTypes) then
                local glowR = iconSz * 0.55
                dc:setColor(cfg.COL.se, 0.35)
                dc:circle("fill", cellCx, rowY + iconSz/2, glowR)
            end

            dc:setColor(cfg.COL.text, 1)
            dc:draw(img, cellCx - (iw*sc)/2, rowY, 0, sc, sc)
        end

        local hp, maxhp, status = self:_liveStats(m)
        local frac = Math.clamp((hp or 0) / math.max(1, maxhp or 1), 0, 1)
        local hpStr = tostring(hp or 0) .. "/" .. tostring(maxhp or 0)

        dc:setFont(fHp)
        dc:setColor(Colors.hpBarColor(frac), 1)
        dc:print(hpStr, cellCx - fHp:getWidth(hpStr)/2, rowY + iconSz + 2)

        if status and status ~= "" and status ~= "OK" then
            local statusStr = tostring(status)
            dc:setFont(fStatus)
            dc:setColor(cfg.COL.lo, 1)
            dc:print(statusStr, cellCx - fStatus:getWidth(statusStr)/2,
                rowY + iconSz + 2 + hpLineH)
        end
    end
end

function PokemonPanel:draw(ctx)
    local dc     = self:_service("DrawContext")
    local cfg    = self:_service("ConfigService")
    local fonts  = self:_service("FontService")
    local sprites= self:_service("SpriteService")
    local te     = self:_service("TypeEffectiveness")
    local x, y, w, h = ctx.x, ctx.y, ctx.w, ctx.h

    -- v1.0.63: Landscape mode wraps background to actual content height
    -- instead of stretching to fill the entire allocated rect.
    local drawH = h
    if not ctx.compact then
        local rowCount = math.max(1, math.min(#self.party, cfg.PARTY_MAX))
        local neededH = cfg.PARTY_HEADER_H + rowCount * cfg.PARTY_ROW_H + cfg.PARTY_PANEL_PAD_B
        drawH = math.min(h, neededH)
    end

    dc:setColor(cfg.COL.panel, 0.96)
    dc:rectangle("fill", x, y, w, drawH)
    dc:setLineWidth(1)
    dc:setColor(cfg.COL.border, 0.3)
    dc:rectangle("line", x+0.5, y+0.5, w-1, drawH-1)

    local f14 = fonts:getFont(14)
    dc:setFont(f14)
    dc:setColor(cfg.COL.text, 1)
    dc:print(self._props.label or "Party", x+8, y+4)

    if ctx.compact then
        self:_drawCompactStrip(cfg, fonts, sprites, dc, x, y, w, h)
    else
        self:_drawFullRows(cfg, fonts, sprites, te, dc, x, y, w, h)
    end
end

return PokemonPanel
