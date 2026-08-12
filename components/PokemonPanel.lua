local Component = require("core.Component")
local Colors    = require("util.Colors")
local Helpers   = require("util.Helpers")
local Math      = require("util.Math")
local ExpBar    = require("components.ExpBar")
local TypeColors = require("util.TypeColors")

local PokemonPanel = setmetatable({}, { __index = Component })
PokemonPanel.__index = PokemonPanel
PokemonPanel.__name = "PokemonPanel"
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

function PokemonPanel:_drawFullRows(cfg, fonts, sprites, te, x, y, w, h)
    -- showTabHeader means the landscape tab strip above already shows the
    -- title, so this panel draws no inline label (see draw() below) and
    -- doesn't need PARTY_HEADER_H's room reserved for one -- that gap was
    -- pure dead space once the label stopped being drawn there. Same for
    -- the bottom pad: only meaningful as breathing room below a label-less
    -- edge, not a spacing rule the rows themselves need.
    local headerH = self._props.showTabHeader and 0 or cfg.PARTY_HEADER_H
    local padB    = self._props.showTabHeader and 0 or cfg.PARTY_PANEL_PAD_B
    local rowH    = cfg.PARTY_ROW_H
    local cy      = y + headerH
    local maxCy   = y + h - padB

    if #self.party == 0 and self._props.emptyMessage then
        local f11 = fonts:getFont(11)
        love.graphics.setFont(f11)
        Colors.set(cfg.COL.dim, 1)
        love.graphics.print(self._props.emptyMessage, math.floor(x+8), math.floor(cy))
        return
    end

    for _, m in ipairs(self.party) do
        if cy + rowH > maxCy then break end
        local img = sprites:getSprite(m.species, m.pokemonData)
        if img then
            local iw, ih = img:getDimensions()
            local sc = 24 / math.max(iw, ih)
            Colors.set(cfg.COL.text, 1)
            love.graphics.draw(img, math.floor(x+8), math.floor(cy+2), 0, sc, sc)
        end
        local hp, maxhp, status = self:_liveStats(m)

        local nameCol = cfg.COL.text
        if self.enemyTypes and te:hasSuperEffectiveMove(m, self.enemyTypes) then
            nameCol = cfg.COL.se
        end
        local f12 = fonts:getFont(12)
        love.graphics.setFont(f12)
        Colors.set(nameCol, 1)
        local nameStr = Helpers.sanitizeName(m.name)
        love.graphics.print(nameStr, math.floor(x+36), math.floor(cy))
        local tx = x + 36 + f12:getWidth(nameStr)
        if status and status ~= "" and status ~= "OK" then
            local statusStr = " (" .. tostring(status) .. ")"
            Colors.set(cfg.COL.lo, 1)
            love.graphics.print(statusStr, math.floor(tx), math.floor(cy))
            tx = tx + f12:getWidth(statusStr)
        end
        tx = tx + f12:getWidth(" ")
        if m.types then
            local f9 = fonts:getFont(9)
            love.graphics.setFont(f9)
            for _, t2 in ipairs(m.types) do
                local tname = TypeColors.normalize(t2)
                if tname ~= "" then
                    Colors.set(TypeColors.getColor(tname), 1)
                    love.graphics.print(tname, math.floor(tx), math.floor(cy+1))
                    tx = tx + f9:getWidth(tname .. " ")
                end
            end
        end
        local f10b = fonts:getFont(10)
        love.graphics.setFont(f10b)
        Colors.set(cfg.COL.dim, 1)
        local lvStr = "Lv" .. tostring(m.level)
        love.graphics.print(lvStr, math.floor(x+w-8-f10b:getWidth(lvStr)), math.floor(cy))
        -- v2.1.35: maxhp is nil for a benched rival-roster mon (its HP
        -- genuinely isn't known until it's sent into battle -- see
        -- GameDataSystem). The number stays "?" below since we don't know
        -- the real total, but the bar itself can still be drawn full: a
        -- mon that's never been sent out has never taken a hit (Gen 1
        -- doesn't damage benched mons), so it genuinely IS at 100% HP --
        -- this isn't a guess, unlike the old fake-0/1 fill it replaced.
        local known = maxhp ~= nil
        local frac = known and Math.clamp((hp or 0) / math.max(1, maxhp), 0, 1) or 1
        local barW = w - 44 - 50
        local barY = cy + 11
        Colors.set({0.12,0.12,0.14}, 1)
        love.graphics.rectangle("fill", math.floor(x+36), math.floor(barY), math.floor(barW), 4)
        if frac > 0 then
            Colors.set(Colors.hpColor(frac), 1)
            love.graphics.rectangle("fill", math.floor(x+36), math.floor(barY), math.floor(barW*frac), 4)
        end
        local hpStr = known and string.format("%3d/%3d", hp or 0, maxhp) or "?"
        love.graphics.setFont(f10b)
        Colors.set(cfg.COL.dim, 1)
        love.graphics.print(hpStr, math.floor(x+w-8-f10b:getWidth(hpStr)), math.floor(cy+10))
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

function PokemonPanel:_drawCompactStrip(cfg, fonts, sprites, x, y, w, h)
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
                Colors.set(cfg.COL.se, 0.35)
                love.graphics.circle("fill", math.floor(cellCx), math.floor(rowY + iconSz/2), glowR)
            end

            Colors.set(cfg.COL.text, 1)
            love.graphics.draw(img, math.floor(cellCx - (iw*sc)/2), math.floor(rowY), 0, sc, sc)
        end

        local hp, maxhp, status = self:_liveStats(m)
        local frac = Math.clamp((hp or 0) / math.max(1, maxhp or 1), 0, 1)
        local hpStr = tostring(hp or 0) .. "/" .. tostring(maxhp or 0)

        love.graphics.setFont(fHp)
        Colors.set(Colors.hpBarColor(frac), 1)
        love.graphics.print(hpStr, math.floor(cellCx - fHp:getWidth(hpStr)/2), math.floor(rowY + iconSz + 2))

        if status and status ~= "" and status ~= "OK" then
            local statusStr = tostring(status)
            love.graphics.setFont(fStatus)
            Colors.set(cfg.COL.lo, 1)
            love.graphics.print(statusStr, math.floor(cellCx - fStatus:getWidth(statusStr)/2),
                math.floor(rowY + iconSz + 2 + hpLineH))
        end
    end
end

function PokemonPanel:draw(ctx)
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
        local headerH = self._props.showTabHeader and 0 or cfg.PARTY_HEADER_H
        local padB    = self._props.showTabHeader and 0 or cfg.PARTY_PANEL_PAD_B
        local neededH = headerH + rowCount * cfg.PARTY_ROW_H + padB
        drawH = math.min(h, neededH)
    end

    Colors.set(cfg.COL.panel, 0.96)
    love.graphics.rectangle("fill", math.floor(x), math.floor(y), math.floor(w), math.floor(drawH))
    love.graphics.setLineWidth(1)
    Colors.set(cfg.COL.border, 0.3)
    love.graphics.rectangle("line", math.floor(x+0.5), math.floor(y+0.5), math.floor(w-1), math.floor(drawH-1))

    local f14 = fonts:getFont(14)
    love.graphics.setFont(f14)
    Colors.set(cfg.COL.text, 1)
    -- v2.1.40: skip this label whenever the landscape partyTabs strip
    -- above is already showing the same "Party"/trainer-name text as a
    -- tab (see layouts/Landscape.lua's showTabHeader) -- redrawing it
    -- here too was a plain duplicate. Landscape always has that tab strip
    -- now (see AppController:_applyPartyLayout), so this only ever draws
    -- in portrait, which has no tab strip of its own.
    if not self._props.showTabHeader then
        love.graphics.print(self._props.label or "Party", math.floor(x+8), math.floor(y+4))
    end

    if ctx.compact then
        self:_drawCompactStrip(cfg, fonts, sprites, x, y, w, h)
    else
        self:_drawFullRows(cfg, fonts, sprites, te, x, y, w, h)
    end
end

return PokemonPanel
