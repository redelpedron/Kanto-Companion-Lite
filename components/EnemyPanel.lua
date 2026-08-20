local Component = require("core.Component")
local Colors    = require("util.Colors")
local Helpers   = require("util.Helpers")
local Math      = require("util.Math")
local TypeColors = require("util.TypeColors")

local EnemyPanel = setmetatable({}, { __index = Component })
EnemyPanel.__index = EnemyPanel
EnemyPanel.__name = "EnemyPanel"
EnemyPanel.needs = { "ConfigService", "FontService", "SpriteService", "TypeEffectiveness", "CatchRate", "GameService" }

local CAPTION_H  = 16
local HP_ROW_GAP = 12
local MOVE_LABEL_H = 12
local MOVES_H    = 32
local MOVES_H_STACKED = 60
local NO_MOVES_H = 14
local CATCH_GAP  = 4

local SINGLE = {
    nameX         = 48,
    spriteScale   = 36,
    ballRadius    = 5,
    ballOffset    = 12,
    nameFontSize  = 13,
    typeSpacing   = 14,
    levelSpacing  = 20,
    catchRowH     = 14,
}

function EnemyPanel.new(locator, props)
    local self = setmetatable(Component.new(locator, props), EnemyPanel)
    self.enemy = nil
    self.activeMon = nil
    self.inventory = {}

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
    local h = 6 + CAPTION_H
    h = h + SINGLE.levelSpacing
    h = h + SINGLE.typeSpacing
    h = h + HP_ROW_GAP
    local active = self.activeMon
    if active and active.moves and #active.moves > 0 then

        if self.trainerName then
            h = h + MOVE_LABEL_H + MOVES_H_STACKED
        else
            h = h + MOVE_LABEL_H + MOVES_H
        end
    else
        h = h + NO_MOVES_H
    end
    if not self.trainerName then

        h = h + CATCH_GAP
        h = h + SINGLE.catchRowH
        local balls = { "POKE_BALL", "GREAT_BALL", "ULTRA_BALL", "MASTER_BALL" }
        local hasAny = false
        for _, ballId in ipairs(balls) do
            if (self.inventory[ballId] or 0) > 0 then
                hasAny = true
                h = h + SINGLE.catchRowH
            end
        end
        if not hasAny then
            h = h + SINGLE.catchRowH
        end
    end
    h = h + 8
    return h
end

function EnemyPanel:_drawMoveList(cfg, fonts, te, en, x, y, w, stacked)
    local active = self.activeMon
    local f10 = fonts:getFont(10)
    if not (active and active.moves and #active.moves > 0) then
        love.graphics.setFont(f10)
        Colors.set(cfg.COL.dim, 1)
        love.graphics.print("No move data", math.floor(x), math.floor(y))
        return NO_MOVES_H
    end

    love.graphics.setFont(f10)
    Colors.set(cfg.COL.dim, 1)
    love.graphics.print("Your Move", math.floor(x), math.floor(y))
    local cy = y + MOVE_LABEL_H

    local colW = stacked and w or math.floor(w / 2)
    local moveH = 14
    local dMove = self._props.moveData or {}
    local f9b = fonts:getFont(9)
    local ppSlotW = 36

    local stabSlotW = stacked and 14 or 0
    local activeTypes = nil
    if stacked and active.species then
        local pdef = (self._props.pokemonData or {})[active.species]
        if pdef and pdef.types then
            activeTypes = {}
            for _, t in ipairs(pdef.types) do
                activeTypes[TypeColors.normalize(t)] = true
            end
        end
    end
    for i, mv in ipairs(active.moves) do
        if i > 4 then break end
        local col = stacked and 0 or ((i - 1) % 2)
        local row = stacked and (i - 1) or math.floor((i - 1) / 2)

        local mx = math.floor(x + col * colW)
        local my = math.floor(cy + row * moveH)
        local md = dMove[mv.id]
        local moveName = mv.name or (md and md.name) or "?"
        local ppCurr = mv.pp or 0
        local ppMax  = mv.maxpp or (md and md.pp) or 0
        local moveCol = cfg.COL.text
        local noEffect = false
        local quadEffective = false
        if en.types then
            local eff = te:effectiveness(mv.id, en.types)
            if eff <= 0.01 then

                noEffect = true
                moveCol = cfg.COL.dim
            elseif eff < 9.99 then
                moveCol = cfg.COL.lo
            elseif eff > 39.99 then
                quadEffective = true
                moveCol = cfg.COL.se
            elseif eff > 10 then
                moveCol = cfg.COL.se
            end
        end
        local isStab = false
        if activeTypes and md then
            local mvType = TypeColors.normalize(md.type or md.typeName or "")
            isStab = mvType ~= "" and activeTypes[mvType] == true
        end
        local f11 = fonts:getFont(11)
        love.graphics.setFont(f11)
        Colors.set(moveCol, 1)

        local nameMaxW = colW - ppSlotW - stabSlotW - 4
        while f11:getWidth(moveName) > nameMaxW and #moveName > 1 do
            moveName = moveName:sub(1, #moveName - 1)
        end
        love.graphics.print(moveName, mx, my)
        if quadEffective then

            love.graphics.print(moveName, mx + 1, my)
        end
        if noEffect then
            local lineY = math.floor(my + f11:getHeight() * 0.55)
            love.graphics.setLineWidth(1)
            love.graphics.line(mx, lineY, mx + f11:getWidth(moveName), lineY)
        end
        if isStab then
            Colors.set(cfg.COL.se, 1)
            Helpers.drawIcon("bolt", mx + colW - ppSlotW - stabSlotW / 2, my + f11:getHeight() / 2, 12)
        end
        local ppStr = tostring(ppCurr) .. "/" .. tostring(ppMax)
        love.graphics.setFont(f9b)
        Colors.set(cfg.COL.dim, 1)

        love.graphics.print(ppStr, math.floor(mx + colW - 8 - f9b:getWidth(ppStr)), my)
    end
    return MOVE_LABEL_H + (stacked and MOVES_H_STACKED or MOVES_H)
end

function EnemyPanel:_drawContent(cfg, fonts, sprites, te, cr, geom)
    local en = self.enemy
    local x, y = geom.x, geom.y
    local nameColW = geom.nameColW or geom.w

    local cy = y + 6
    local f10 = fonts:getFont(10)
    love.graphics.setFont(f10)
    Colors.set(cfg.COL.dim, 1)

    love.graphics.print(self.trainerName and "Trainer Battle" or "Wild Battle", math.floor(x+8), math.floor(cy))
    cy = cy + CAPTION_H
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
        Colors.set(cfg.COL.hi, 1)
        Helpers.drawIcon("caught", ballX, ballY, ballRadius * 2)
    end

    local fName = fonts:getFont(geom.nameFontSize)
    love.graphics.setFont(fName)
    Colors.set(cfg.COL.text, 1)
    local nameStr = Helpers.sanitizeName(en.name)
    love.graphics.print(nameStr, math.floor(x+geom.nameX), math.floor(cy))

    if (en.hp or 0) > 0 and en.status and en.status ~= "" and en.status ~= "OK" then
        Colors.set(cfg.COL.lo, 1)
        love.graphics.print(" (" .. Helpers.formatStatus(en.status) .. ")", math.floor(x+geom.nameX+fName:getWidth(nameStr)), math.floor(cy))
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
                Colors.set(TypeColors.getColor(tname), 1)
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
    cy = cy + HP_ROW_GAP

    if geom.skipMovesAndCatch then return end

    cy = cy + self:_drawMoveList(cfg, fonts, te, en, x+8, cy, nameColW-16, geom.stackMoves or false)

    if self.trainerName then return end

    local crGeom = geom.catchRate
    local crX, crW = crGeom.x, crGeom.w
    local ry = crGeom.startY or (cy + CATCH_GAP)
    if crGeom.bottomBound and ry + 14 > crGeom.bottomBound then return end

    love.graphics.setFont(f10)
    Colors.set(cfg.COL.dim, 1)
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

    if self.trainerName then
        self:_drawContent(cfg, fonts, sprites, te, cr, {
            x = x, y = y, w = w,
            nameColW = leftW,
            nameX = 44,
            spriteScale = 32,
            ballRadius = 4,
            ballOffset = 10,
            nameFontSize = 12,
            typeSpacing = 12,
            levelSpacing = 18,
            skipMovesAndCatch = true,
        })
        self:_drawMoveList(cfg, fonts, te, en, rightX + 8, y + 6, rightW - 16, true)
        return
    end

    self:_drawContent(cfg, fonts, sprites, te, cr, {
        x = x, y = y, w = w,
        nameColW = leftW,
        nameX = 44,
        spriteScale = 32,
        ballRadius = 4,
        ballOffset = 10,
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
        nameX = SINGLE.nameX,
        spriteScale = SINGLE.spriteScale,
        ballRadius = SINGLE.ballRadius,
        ballOffset = SINGLE.ballOffset,
        nameFontSize = SINGLE.nameFontSize,
        typeSpacing = SINGLE.typeSpacing,
        levelSpacing = SINGLE.levelSpacing,

        stackMoves = self.trainerName ~= nil,
        catchRate = { x = x, w = w, startY = nil, rowH = SINGLE.catchRowH, bottomBound = y + drawH - 4 },
    })
end

return EnemyPanel
