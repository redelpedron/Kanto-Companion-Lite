local Component = require("core.Component")
local Colors    = require("util.Colors")
local Helpers   = require("util.Helpers")
local Math      = require("util.Math")
local TypeColors = require("util.TypeColors")

local EnemyPanel = setmetatable({}, { __index = Component })
EnemyPanel.__index = EnemyPanel
EnemyPanel.needs = { "ConfigService", "FontService", "SpriteService", "TypeEffectiveness", "CatchRate", "GameService" }

function EnemyPanel.new(locator, props)
    local self = setmetatable(Component.new(locator, props), EnemyPanel)
    self.enemy = nil
    self.activeMon = nil
    self.inventory = {}
    -- Caption text (see _drawContent): nil outside of trainer battles, so
    -- the panel reads "Wild Battle"; set to the trainer's name whenever
    -- one is fighting, same event the Rival tab label already uses.
    self.trainerName = nil
    return self
end

function EnemyPanel:init()
    self:_listen("enemy.updated", function(_, enemy) self.enemy = enemy end)
    self:_listen("active_mon.changed", function(_, mon) self.activeMon = mon end)
    self:_listen("inventory.updated", function(_, inv) self.inventory = inv or {} end)
    self:_listen("rival_trainer.updated", function(_, name) self.trainerName = name end)
end

function EnemyPanel:_contentHeight(w)
    if not self.enemy then
        return 38
    end
    local h = 6 + 16
    h = h + 20
    h = h + 14
    h = h + 12
    local active = self.activeMon
    if active and active.moves and #active.moves > 0 then
        h = h + 32
    else
        h = h + 14
    end
    h = h + 4
    h = h + 14 -- catch-rate section header row ("CATCH RATE" or "Can't be caught")
    if not self.trainerName then
        -- Trainer's mons can never be caught (Gen 1 rule), so in a
        -- trainer battle we only ever draw the one header-row note above
        -- and skip the ball-by-ball odds list entirely.
        local balls = { "POKE_BALL", "GREAT_BALL", "ULTRA_BALL", "MASTER_BALL" }
        local hasAny = false
        for _, ballId in ipairs(balls) do
            if (self.inventory[ballId] or 0) > 0 then
                hasAny = true
                h = h + 14
            end
        end
        if not hasAny then
            h = h + 14
        end
    end
    h = h + 8
    return h
end

-- Shared enemy-info renderer. `geom` describes the differences between
-- the two-column battle-HUD layout and the single-panel wrap-height
-- layout so this body runs once instead of being duplicated ~165 lines
-- across draw() and _drawTwoColumn().
--
-- geom = {
--   x, y, w,            -- panel origin/width (name column uses w unless nameColW given)
--   nameColW,            -- width of the name/HP/moves column (defaults to w)
--   nameX,               -- x-offset of name/type text from sprite (44 in two-col, 48 in single)
--   spriteScale,         -- target sprite size in px (32 two-col, 36 single)
--   ballRadius,          -- caught-icon radius (4 two-col, 5 single)
--   ballOffset,          -- caught-icon x-offset back from nameX (10 two-col, 12 single)
--   ballDotRadius,       -- caught-icon center-dot radius (1.5 two-col, 2 single)
--   nameFontSize,        -- 12 two-col, 13 single
--   typeSpacing,         -- vertical gap after type row (12 / 14)
--   levelSpacing,        -- vertical gap after name/level row (18 / 20)
--   catchRate = {
--     x, w,               -- catch-rate column origin/width (rightX/rightW, or x/w)
--     startY,             -- fixed y to start at (two-col: y+6) or nil to continue from cy
--     rowH,                -- 16 two-col, 14 single
--     bottomBound,         -- y beyond which drawing stops (nil = unbounded, two-col case)
--   },
-- }
function EnemyPanel:_drawContent(cfg, fonts, sprites, te, cr, geom)
    local en = self.enemy
    local x, y = geom.x, geom.y
    local nameColW = geom.nameColW or geom.w

    local cy = y + 6
    local f10 = fonts:getFont(10)
    love.graphics.setFont(f10)
    Colors.set(cfg.COL.dim, 1)
    -- FIX v2.1.30: was hardcoded "Wild Battle" even for trainer fights.
    love.graphics.print(self.trainerName and "Trainer Battle" or "Wild Battle", math.floor(x+8), math.floor(cy))
    cy = cy + 16

    local img = sprites:getSprite(en.species, self._props.pokemonData)
    if img then
        local iw, ih = img:getDimensions()
        local sc = geom.spriteScale / math.max(iw, ih)
        Colors.set(cfg.COL.text, 1)
        love.graphics.draw(img, math.floor(x+8), math.floor(cy), 0, sc, sc)
    end

    if en.caught then
        local ballRadius = geom.ballRadius
        local ballX = x + geom.nameX - geom.ballOffset
        local ballY = cy + 4
        Colors.set({1, 0.2, 0.2}, 1)
        love.graphics.rectangle("fill", math.floor(ballX - ballRadius), math.floor(ballY - ballRadius),
                               math.floor(ballRadius * 2), math.floor(ballRadius))
        Colors.set({1, 1, 1}, 1)
        love.graphics.rectangle("fill", math.floor(ballX - ballRadius), math.floor(ballY),
                               math.floor(ballRadius * 2), math.floor(ballRadius))
        Colors.set({0, 0, 0}, 1)
        love.graphics.setLineWidth(1)
        love.graphics.line(ballX - ballRadius, ballY, ballX + ballRadius, ballY)
        Colors.set({1, 1, 1}, 1)
        love.graphics.circle("fill", ballX, ballY, geom.ballDotRadius)
        Colors.set({0, 0, 0}, 1)
        love.graphics.circle("line", ballX, ballY, geom.ballDotRadius)
    end

    local fName = fonts:getFont(geom.nameFontSize)
    love.graphics.setFont(fName)
    Colors.set(cfg.COL.text, 1)
    local nameStr = Helpers.sanitizeName(en.name)
    love.graphics.print(nameStr, math.floor(x+geom.nameX), math.floor(cy))
    if en.status and en.status ~= "" and en.status ~= "OK" then
        Colors.set(cfg.COL.lo, 1)
        love.graphics.print(" (" .. tostring(en.status) .. ")", math.floor(x+geom.nameX+fName:getWidth(nameStr)), math.floor(cy))
    end
    local lvStr = "Lv" .. tostring(en.level or "?")
    love.graphics.setFont(f10)
    Colors.set(cfg.COL.dim, 1)
    love.graphics.print(lvStr, math.floor(x+nameColW-8-f10:getWidth(lvStr)), math.floor(cy+2))
    cy = cy + geom.levelSpacing

    if en.types then
        local tx = x + geom.nameX
        local f9 = fonts:getFont(9)
        love.graphics.setFont(f9)
        for _, t2 in ipairs(en.types) do
            local tname = TypeColors.normalize(t2)
            if tname ~= "" then
                Colors.set(cfg.TYPE[tname] or cfg.COL.dim, 1)
                love.graphics.print(tname, math.floor(tx), math.floor(cy))
                tx = tx + f9:getWidth(tname .. " ")
            end
        end
    end
    cy = cy + geom.typeSpacing

    local frac = Math.clamp((en.hp or 0) / math.max(1, en.maxhp or 1), 0, 1)
    local hpStr = string.format("%d/%d", en.hp or 0, en.maxhp or 1)
    local f9b = fonts:getFont(9)
    local hpTextW = f9b:getWidth(hpStr) + 12
    local barW = nameColW - 16 - hpTextW
    Colors.set({0.12,0.12,0.14}, 1)
    love.graphics.rectangle("fill", math.floor(x+8), math.floor(cy), math.floor(barW), 5)
    if frac > 0 then
        Colors.set(Colors.hpColor(frac), 1)
        love.graphics.rectangle("fill", math.floor(x+8), math.floor(cy), math.floor(barW*frac), 5)
    end
    love.graphics.setFont(f9b)
    Colors.set(cfg.COL.text, 1)
    love.graphics.print(hpStr, math.floor(x+nameColW-8-f9b:getWidth(hpStr)), math.floor(cy))
    cy = cy + 12

    local active = self.activeMon
    if active and active.moves and #active.moves > 0 then
        -- integer column width prevents fractional pixel misalignment
        local colW = math.floor((nameColW - 16) / 2)
        local moveH = 14
        local dMove = self._props.moveData or {}
        local ppSlotW = 36
        for i, mv in ipairs(active.moves) do
            if i > 4 then break end
            local col = (i - 1) % 2
            local row = math.floor((i - 1) / 2)
            -- integer mx/my prevents subpixel drift
            local mx = math.floor(x + 8 + col * colW)
            local my = math.floor(cy + row * moveH)
            local moveName = mv.name or (dMove[mv.id] and dMove[mv.id].name) or "?"
            local ppCurr = mv.pp or 0
            local ppMax  = mv.maxpp or (dMove[mv.id] and dMove[mv.id].pp) or 0
            local moveCol = cfg.COL.text
            if en.types and te:effectiveness(mv.id, en.types) > 10 then
                moveCol = cfg.COL.se
            end
            local f11 = fonts:getFont(11)
            love.graphics.setFont(f11)
            Colors.set(moveCol, 1)
            -- truncate name so it never overlaps PP
            local nameMaxW = colW - ppSlotW - 4
            while f11:getWidth(moveName) > nameMaxW and #moveName > 1 do
                moveName = moveName:sub(1, #moveName - 1)
            end
            love.graphics.print(moveName, mx, my)
            local ppStr = tostring(ppCurr) .. "/" .. tostring(ppMax)
            love.graphics.setFont(f9b)
            Colors.set(cfg.COL.dim, 1)
            -- PP right-aligned to consistent column edge
            love.graphics.print(ppStr, math.floor(mx + colW - 8 - f9b:getWidth(ppStr)), my)
        end
        cy = cy + 32
    else
        love.graphics.setFont(f10)
        Colors.set(cfg.COL.dim, 1)
        love.graphics.print("No move data", math.floor(x+8), math.floor(cy))
        cy = cy + 14
    end

    -- ---- Catch rate section ----
    local crGeom = geom.catchRate
    local crX, crW = crGeom.x, crGeom.w
    local ry = crGeom.startY or (cy + 4)
    if crGeom.bottomBound and ry + 14 > crGeom.bottomBound then return end

    love.graphics.setFont(f10)
    Colors.set(cfg.COL.dim, 1)

    -- v2.1.38: trainer mons can never be caught (Gen 1 rule) -- showing
    -- catch odds for them is meaningless at best, misleading at worst.
    -- Swap the whole section for a one-line note instead of the ball
    -- list once we know it's a trainer battle (self.trainerName is only
    -- set then -- see the "Wild Battle"/"Trainer Battle" caption above).
    if self.trainerName then
        love.graphics.print("Can't be caught", math.floor(crX+8), math.floor(ry))
        return
    end

    love.graphics.print("CATCH RATE", math.floor(crX+8), math.floor(ry))
    ry = ry + crGeom.rowH

    local balls = { "POKE_BALL", "GREAT_BALL", "ULTRA_BALL", "MASTER_BALL" }
    local ballNames = { POKE_BALL="Poke", GREAT_BALL="Great", ULTRA_BALL="Ultra", MASTER_BALL="Master" }
    local hasAny = false
    for _, ballId in ipairs(balls) do
        local count = self.inventory[ballId] or 0
        if count > 0 then
            hasAny = true
            if crGeom.bottomBound and ry + 14 > crGeom.bottomBound then break end
            local rate = cr:calculate(en, ballId)
            local name = ballNames[ballId] or ballId
            local f11 = fonts:getFont(11)
            love.graphics.setFont(f11)
            Colors.set(cfg.COL.text, 1)
            love.graphics.print(name .. " x" .. count, math.floor(crX+8), math.floor(ry))
            Colors.set(cfg.COL.catch, 1)
            love.graphics.print(rate .. "%", math.floor(crX+crW-8-f11:getWidth(rate.."%")), math.floor(ry))
            ry = ry + crGeom.rowH
        end
    end
    if not hasAny then
        love.graphics.setFont(f10)
        Colors.set(cfg.COL.dim, 1)
        love.graphics.print("No Poke Balls", math.floor(crX+8), math.floor(ry))
    end
end

function EnemyPanel:_drawTwoColumn(cfg, fonts, sprites, te, cr, x, y, w, h)
    local en = self.enemy
    if not en then
        love.graphics.setFont(fonts:getFont(12))
        Colors.set(cfg.COL.dim, 1)
        love.graphics.print("Scanning...", math.floor(x+8), math.floor(y+6))
        return
    end

    local leftW = math.floor(w * 0.55)
    local rightX = x + leftW
    local rightW = w - leftW

    self:_drawContent(cfg, fonts, sprites, te, cr, {
        x = x, y = y, w = w,
        nameColW = leftW,
        nameX = 44,
        spriteScale = 32,
        ballRadius = 4,
        ballOffset = 10,
        ballDotRadius = 1.5,
        nameFontSize = 12,
        typeSpacing = 12,
        levelSpacing = 18,
        catchRate = { x = rightX, w = rightW, startY = y + 6, rowH = 16, bottomBound = nil },
    })
end

function EnemyPanel:draw(ctx)
    local cfg    = self:_service("ConfigService")
    local fonts  = self:_service("FontService")
    local sprites= self:_service("SpriteService")
    local te     = self:_service("TypeEffectiveness")
    local cr     = self:_service("CatchRate")
    local x, y, w, h = ctx.x, ctx.y, ctx.w, ctx.h

    if ctx.twoColumn then
        Colors.set(cfg.COL.panel, 0.96)
        love.graphics.rectangle("fill", math.floor(x), math.floor(y), math.floor(w), math.floor(h))
        love.graphics.setLineWidth(1)
        Colors.set(cfg.COL.border, 0.3)
        love.graphics.rectangle("line", math.floor(x)+0.5, math.floor(y)+0.5, math.floor(w)-1, math.floor(h)-1)
        self:_drawTwoColumn(cfg, fonts, sprites, te, cr, x, y, w, h)
        return
    end

    local drawH = h
    if ctx.wrapHeight then
        drawH = math.min(h, self:_contentHeight(w))
    end

    Colors.set(cfg.COL.panel, 0.96)
    love.graphics.rectangle("fill", math.floor(x), math.floor(y), math.floor(w), math.floor(drawH))
    love.graphics.setLineWidth(1)
    Colors.set(cfg.COL.border, 0.3)
    love.graphics.rectangle("line", math.floor(x)+0.5, math.floor(y)+0.5, math.floor(w)-1, math.floor(drawH)-1)

    if not self.enemy then
        local f12 = fonts:getFont(12)
        love.graphics.setFont(f12)
        Colors.set(cfg.COL.dim, 1)
        love.graphics.print("Scanning...", math.floor(x+8), math.floor(y+6))
        return
    end

    self:_drawContent(cfg, fonts, sprites, te, cr, {
        x = x, y = y, w = w,
        nameX = 48,
        spriteScale = 36,
        ballRadius = 5,
        ballOffset = 12,
        ballDotRadius = 2,
        nameFontSize = 13,
        typeSpacing = 14,
        levelSpacing = 20,
        catchRate = { x = x, w = w, startY = nil, rowH = 14, bottomBound = y + drawH - 4 },
    })
end

return EnemyPanel
