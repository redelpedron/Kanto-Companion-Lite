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
    return self
end

function EnemyPanel:init()
    self:_listen("enemy.updated", function(_, enemy) self.enemy = enemy end)
    self:_listen("active_mon.changed", function(_, mon) self.activeMon = mon end)
    self:_listen("inventory.updated", function(_, inv) self.inventory = inv or {} end)
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
    h = h + 14
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
    h = h + 8
    return h
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

    local cy = y + 6
    local f10 = fonts:getFont(10)
    love.graphics.setFont(f10)
    Colors.set(cfg.COL.dim, 1)
    love.graphics.print("Wild Battle", math.floor(x+8), math.floor(cy))
    cy = cy + 16

    local img = sprites:getSprite(en.species, self._props.pokemonData)
    if img then
        local iw, ih = img:getDimensions()
        local sc = 32 / math.max(iw, ih)
        Colors.set(cfg.COL.text, 1)
        love.graphics.draw(img, math.floor(x+8), math.floor(cy), 0, sc, sc)
    end

    if en.caught then
        local ballRadius = 4
        local ballX = x + 44 - 10
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
        love.graphics.circle("fill", ballX, ballY, 1.5)
        Colors.set({0, 0, 0}, 1)
        love.graphics.circle("line", ballX, ballY, 1.5)
    end

    local f12 = fonts:getFont(12)
    love.graphics.setFont(f12)
    Colors.set(cfg.COL.text, 1)
    local nameStr = Helpers.sanitizeName(en.name)
    love.graphics.print(nameStr, math.floor(x+44), math.floor(cy))
    if en.status and en.status ~= "" and en.status ~= "OK" then
        Colors.set(cfg.COL.lo, 1)
        love.graphics.print(" (" .. tostring(en.status) .. ")", math.floor(x+44+f12:getWidth(nameStr)), math.floor(cy))
    end
    local lvStr = "Lv" .. tostring(en.level or "?")
    love.graphics.setFont(f10)
    Colors.set(cfg.COL.dim, 1)
    love.graphics.print(lvStr, math.floor(x+leftW-8-f10:getWidth(lvStr)), math.floor(cy+2))
    cy = cy + 18

    if en.types then
        local tx = x + 44
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
    cy = cy + 12

    local frac = Math.clamp((en.hp or 0) / math.max(1, en.maxhp or 1), 0, 1)
    local hpStr = string.format("%d/%d", en.hp or 0, en.maxhp or 1)
    local f9b = fonts:getFont(9)
    local hpTextW = f9b:getWidth(hpStr) + 12
    local barW = leftW - 16 - hpTextW
    Colors.set({0.12,0.12,0.14}, 1)
    love.graphics.rectangle("fill", math.floor(x+8), math.floor(cy), math.floor(barW), 5)
    if frac > 0 then
        Colors.set(Colors.hpColor(frac), 1)
        love.graphics.rectangle("fill", math.floor(x+8), math.floor(cy), math.floor(barW*frac), 5)
    end
    love.graphics.setFont(f9b)
    Colors.set(cfg.COL.text, 1)
    love.graphics.print(hpStr, math.floor(x+leftW-8-f9b:getWidth(hpStr)), math.floor(cy))
    cy = cy + 12

    local active = self.activeMon
    if active and active.moves and #active.moves > 0 then
        -- FIX: integer column width prevents fractional pixel misalignment
        local colW = math.floor((leftW - 16) / 2)
        local moveH = 14
        local dMove = self._props.moveData or {}
        local ppSlotW = 36
        for i, mv in ipairs(active.moves) do
            if i > 4 then break end
            local col = (i - 1) % 2
            local row = math.floor((i - 1) / 2)
            -- FIX: integer mx/my prevents subpixel drift
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
            -- FIX: truncate name so it never overlaps PP
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

    local ry = y + 6
    love.graphics.setFont(f10)
    Colors.set(cfg.COL.dim, 1)
    love.graphics.print("CATCH RATE", math.floor(rightX+8), math.floor(ry))
    ry = ry + 16

    local balls = { "POKE_BALL", "GREAT_BALL", "ULTRA_BALL", "MASTER_BALL" }
    local ballNames = { POKE_BALL="Poke", GREAT_BALL="Great", ULTRA_BALL="Ultra", MASTER_BALL="Master" }
    local hasAny = false
    for _, ballId in ipairs(balls) do
        local count = self.inventory[ballId] or 0
        if count > 0 then
            hasAny = true
            local rate = cr:calculate(en, ballId)
            local name = ballNames[ballId] or ballId
            local f11 = fonts:getFont(11)
            love.graphics.setFont(f11)
            Colors.set(cfg.COL.text, 1)
            love.graphics.print(name .. " x" .. count, math.floor(rightX+8), math.floor(ry))
            Colors.set(cfg.COL.catch, 1)
            love.graphics.print(rate .. "%", math.floor(rightX+rightW-8-f11:getWidth(rate.."%")), math.floor(ry))
            ry = ry + 16
        end
    end
    if not hasAny then
        love.graphics.setFont(f10)
        Colors.set(cfg.COL.dim, 1)
        love.graphics.print("No Poke Balls", math.floor(rightX+8), math.floor(ry))
    end
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

    local en = self.enemy
    local cy = y + 6
    local f10 = fonts:getFont(10)
    love.graphics.setFont(f10)
    Colors.set(cfg.COL.dim, 1)
    love.graphics.print("Wild Battle", math.floor(x+8), math.floor(cy))
    cy = cy + 16

    local img = sprites:getSprite(en.species, self._props.pokemonData)
    if img then
        local iw, ih = img:getDimensions()
        local sc = 36 / math.max(iw, ih)
        Colors.set(cfg.COL.text, 1)
        love.graphics.draw(img, math.floor(x+8), math.floor(cy), 0, sc, sc)
    end
    
    if en.caught then
        local ballRadius = 5
        local ballX = x + 48 - 12
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
        love.graphics.circle("fill", ballX, ballY, 2)
        Colors.set({0, 0, 0}, 1)
        love.graphics.circle("line", ballX, ballY, 2)
    end
    
    local f13 = fonts:getFont(13)
    love.graphics.setFont(f13)
    Colors.set(cfg.COL.text, 1)
    local nameStr = Helpers.sanitizeName(en.name)
    love.graphics.print(nameStr, math.floor(x+48), math.floor(cy))
    if en.status and en.status ~= "" and en.status ~= "OK" then
        Colors.set(cfg.COL.lo, 1)
        love.graphics.print(" (" .. tostring(en.status) .. ")", math.floor(x+48+f13:getWidth(nameStr)), math.floor(cy))
    end
    local lvStr = "Lv" .. tostring(en.level or "?")
    love.graphics.setFont(f10)
    Colors.set(cfg.COL.dim, 1)
    love.graphics.print(lvStr, math.floor(x+w-8-f10:getWidth(lvStr)), math.floor(cy+2))
    cy = cy + 20

    if en.types then
        local tx = x + 48
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
    cy = cy + 14

    local frac = Math.clamp((en.hp or 0) / math.max(1, en.maxhp or 1), 0, 1)
    local hpStr = string.format("%d/%d", en.hp or 0, en.maxhp or 1)
    local f9b = fonts:getFont(9)
    local hpTextW = f9b:getWidth(hpStr) + 12
    local barW = w - 16 - hpTextW
    Colors.set({0.12,0.12,0.14}, 1)
    love.graphics.rectangle("fill", math.floor(x+8), math.floor(cy), math.floor(barW), 5)
    if frac > 0 then
        Colors.set(Colors.hpColor(frac), 1)
        love.graphics.rectangle("fill", math.floor(x+8), math.floor(cy), math.floor(barW*frac), 5)
    end
    love.graphics.setFont(f9b)
    Colors.set(cfg.COL.text, 1)
    love.graphics.print(hpStr, math.floor(x+w-8-f9b:getWidth(hpStr)), math.floor(cy))
    cy = cy + 12

    local active = self.activeMon
    if active and active.moves and #active.moves > 0 then
        -- FIX: integer column width prevents fractional pixel misalignment
        local colW = math.floor((w - 16) / 2)
        local moveH = 14
        local dMove = self._props.moveData or {}
        local ppSlotW = 36
        for i, mv in ipairs(active.moves) do
            if i > 4 then break end
            local col = (i - 1) % 2
            local row = math.floor((i - 1) / 2)
            -- FIX: integer mx/my prevents subpixel drift
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
            -- FIX: truncate name so it never overlaps PP
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

    cy = cy + 4
    if cy + 14 > y + drawH - 4 then return end
    love.graphics.setFont(f10)
    Colors.set(cfg.COL.dim, 1)
    love.graphics.print("CATCH RATE", math.floor(x+8), math.floor(cy))
    cy = cy + 14

    local balls = { "POKE_BALL", "GREAT_BALL", "ULTRA_BALL", "MASTER_BALL" }
    local ballNames = { POKE_BALL="Poke", GREAT_BALL="Great", ULTRA_BALL="Ultra", MASTER_BALL="Master" }
    local hasAny = false
    for _, ballId in ipairs(balls) do
        local count = self.inventory[ballId] or 0
        if count > 0 then
            hasAny = true
            if cy + 14 > y + drawH - 4 then break end
            local rate = cr:calculate(en, ballId)
            local name = ballNames[ballId] or ballId
            local f11 = fonts:getFont(11)
            love.graphics.setFont(f11)
            Colors.set(cfg.COL.text, 1)
            love.graphics.print(name .. " x" .. count, math.floor(x+8), math.floor(cy))
            Colors.set(cfg.COL.catch, 1)
            love.graphics.print(rate .. "%", math.floor(x+w-8-f11:getWidth(rate.."%")), math.floor(cy))
            cy = cy + 14
        end
    end
    if not hasAny then
        love.graphics.setFont(f10)
        Colors.set(cfg.COL.dim, 1)
        love.graphics.print("No Poke Balls", math.floor(x+8), math.floor(cy))
    end
end

return EnemyPanel
