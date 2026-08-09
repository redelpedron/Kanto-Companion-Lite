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
    -- v1.0.64: compute exact pixel height needed for all battle content
    if not self.enemy then
        return 38  -- header + "Scanning..." + pad
    end
    local h = 6 + 16   -- "Wild Battle" header
    h = h + 20         -- sprite + name + level
    h = h + 14         -- types
    h = h + 12         -- HP bar
    local active = self.activeMon
    if active and active.moves and #active.moves > 0 then
        h = h + 32     -- move grid (2 rows max)
    else
        h = h + 14     -- "No move data"
    end
    h = h + 4          -- spacer
    h = h + 14         -- "CATCH RATE" label
    local balls = { "POKE_BALL", "GREAT_BALL", "ULTRA_BALL", "MASTER_BALL" }
    local hasAny = false
    for _, ballId in ipairs(balls) do
        if (self.inventory[ballId] or 0) > 0 then
            hasAny = true
            h = h + 14
        end
    end
    if not hasAny then
        h = h + 14     -- "No Poke Balls"
    end
    h = h + 8          -- bottom padding
    return h
end

-- v1.0.68: portrait two-column battle layout.
-- Left column: enemy sprite, name, types, HP, moves.
-- Right column: catch rates.
function EnemyPanel:_drawTwoColumn(cfg, fonts, sprites, te, cr, dc, x, y, w, h)
    local en = self.enemy
    if not en then
        dc:setFont(fonts:getFont(12))
        dc:setColor(cfg.COL.dim, 1)
        dc:print("Scanning...", x+8, y+6)
        return
    end

    local leftW = w * 0.55
    local rightX = x + leftW
    local rightW = w - leftW

    -- LEFT COLUMN: enemy info
    local cy = y + 6
    local f10 = fonts:getFont(10)
    dc:setFont(f10)
    dc:setColor(cfg.COL.dim, 1)
    dc:print("Wild Battle", x+8, cy)
    cy = cy + 16

    local img = sprites:getSprite(en.species, self._props.pokemonData)
    if img then
        local iw, ih = img:getDimensions()
        local sc = 32 / math.max(iw, ih)
        dc:setColor(cfg.COL.text, 1)
        dc:draw(img, x+8, cy, 0, sc, sc)
    end

    -- Pokéball indicator (v2.0.1: only show if caught)
    if en.caught then
        local ballRadius = 4
        local ballX = x + 44 - 10
        local ballY = cy + 4
        dc:setColor({1, 0.2, 0.2}, 1)
        dc:rectangle("fill", ballX - ballRadius, ballY - ballRadius,
                               ballRadius * 2, ballRadius)
        dc:setColor({1, 1, 1}, 1)
        dc:rectangle("fill", ballX - ballRadius, ballY,
                               ballRadius * 2, ballRadius)
        dc:setColor({0, 0, 0}, 1)
        dc:setLineWidth(1)
        dc:line(ballX - ballRadius, ballY, ballX + ballRadius, ballY)
        dc:setColor({1, 1, 1}, 1)
        dc:circle("fill", ballX, ballY, 1.5)
        dc:setColor({0, 0, 0}, 1)
        dc:circle("line", ballX, ballY, 1.5)
    end

    local f12 = fonts:getFont(12)
    dc:setFont(f12)
    dc:setColor(cfg.COL.text, 1)
    local nameStr = Helpers.sanitizeName(en.name)
    dc:print(nameStr, x+44, cy)
    if en.status and en.status ~= "" and en.status ~= "OK" then
        dc:setColor(cfg.COL.lo, 1)
        dc:print(" (" .. tostring(en.status) .. ")", x+44+f12:getWidth(nameStr), cy)
    end
    local lvStr = "Lv" .. tostring(en.level or "?")
    dc:setFont(f10)
    dc:setColor(cfg.COL.dim, 1)
    dc:print(lvStr, x+leftW-8-f10:getWidth(lvStr), cy+2)
    cy = cy + 18

    if en.types then
        local tx = x + 44
        local f9 = fonts:getFont(9)
        dc:setFont(f9)
        for _, t2 in ipairs(en.types) do
            local tname = TypeColors.normalize(t2)
            if tname ~= "" then
                dc:setColor(cfg.TYPE[tname] or cfg.COL.dim, 1)
                dc:print(tname, tx, cy)
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
    dc:setColor({0.12,0.12,0.14}, 1)
    dc:rectangle("fill", x+8, cy, barW, 5)
    if frac > 0 then
        dc:setColor(Colors.hpColor(frac), 1)
        dc:rectangle("fill", x+8, cy, barW*frac, 5)
    end
    dc:setFont(f9b)
    dc:setColor(cfg.COL.text, 1)
    dc:print(hpStr, x+leftW-8-f9b:getWidth(hpStr), cy)
    cy = cy + 12

    local active = self.activeMon
    if active and active.moves and #active.moves > 0 then
        local colW = (leftW - 16) / 2
        local moveH = 14
        local dMove = self._props.moveData or {}
        for i, mv in ipairs(active.moves) do
            if i > 4 then break end
            local col = (i - 1) % 2
            local row = (i - 1) / 2
            local mx = x + 8 + col * colW
            local my = cy + row * moveH
            local moveName = mv.name or (dMove[mv.id] and dMove[mv.id].name) or "?"
            local ppCurr = mv.pp or 0
            local ppMax  = mv.maxpp or (dMove[mv.id] and dMove[mv.id].pp) or 0
            local moveCol = cfg.COL.text
            if en.types and te:effectiveness(mv.id, en.types) > 10 then
                moveCol = cfg.COL.se
            end
            local f11 = fonts:getFont(11)
            dc:setFont(f11)
            dc:setColor(moveCol, 1)
            dc:print(moveName, mx, my)
            local ppStr = tostring(ppCurr) .. "/" .. tostring(ppMax)
            dc:setFont(f9b)
            dc:setColor(cfg.COL.dim, 1)
            dc:print(ppStr, mx + colW - 8 - f9b:getWidth(ppStr), my)
        end
        cy = cy + 32
    else
        dc:setFont(f10)
        dc:setColor(cfg.COL.dim, 1)
        dc:print("No move data", x+8, cy)
        cy = cy + 14
    end

    -- RIGHT COLUMN: catch rates
    local ry = y + 6
    dc:setFont(f10)
    dc:setColor(cfg.COL.dim, 1)
    dc:print("CATCH RATE", rightX+8, ry)
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
            dc:setFont(f11)
            dc:setColor(cfg.COL.text, 1)
            dc:print(name .. " x" .. count, rightX+8, ry)
            dc:setColor(cfg.COL.catch, 1)
            dc:print(rate .. "%", rightX+rightW-8-f11:getWidth(rate.."%"), ry)
            ry = ry + 16
        end
    end
    if not hasAny then
        dc:setFont(f10)
        dc:setColor(cfg.COL.dim, 1)
        dc:print("No Poke Balls", rightX+8, ry)
    end
end

function EnemyPanel:draw(ctx)
    local dc     = self:_service("DrawContext")
    local cfg    = self:_service("ConfigService")
    local fonts  = self:_service("FontService")
    local sprites= self:_service("SpriteService")
    local te     = self:_service("TypeEffectiveness")
    local cr     = self:_service("CatchRate")
    local x, y, w, h = ctx.x, ctx.y, ctx.w, ctx.h

    -- v1.0.68: portrait two-column battle mode
    if ctx.twoColumn then
        dc:setColor(cfg.COL.panel, 0.96)
        dc:rectangle("fill", x, y, w, h)
        dc:setLineWidth(1)
        dc:setColor(cfg.COL.border, 0.3)
        dc:rectangle("line", x+0.5, y+0.5, w-1, h-1)
        self:_drawTwoColumn(cfg, fonts, sprites, te, cr, dc, x, y, w, h)
        return
    end

    -- v1.0.64: landscape mode wraps background to content height
    local drawH = h
    if ctx.wrapHeight then
        drawH = math.min(h, self:_contentHeight(w))
    end

    dc:setColor(cfg.COL.panel, 0.96)
    dc:rectangle("fill", x, y, w, drawH)
    dc:setLineWidth(1)
    dc:setColor(cfg.COL.border, 0.3)
    dc:rectangle("line", x+0.5, y+0.5, w-1, drawH-1)

    if not self.enemy then
        local f12 = fonts:getFont(12)
        dc:setFont(f12)
        dc:setColor(cfg.COL.dim, 1)
        dc:print("Scanning...", x+8, y+6)
        return
    end

    local en = self.enemy
    local cy = y + 6
    local f10 = fonts:getFont(10)
    dc:setFont(f10)
    dc:setColor(cfg.COL.dim, 1)
    dc:print("Wild Battle", x+8, cy)
    cy = cy + 16

    local img = sprites:getSprite(en.species, self._props.pokemonData)
    if img then
        local iw, ih = img:getDimensions()
        local sc = 36 / math.max(iw, ih)
        dc:setColor(cfg.COL.text, 1)
        dc:draw(img, x+8, cy, 0, sc, sc)
    end
    
    -- Draw pokéball indicator to the left of the name (v2.0.1: only show if caught)
    if en.caught then
        local ballRadius = 5
        local ballX = x + 48 - 12
        local ballY = cy + 4
        -- Top red half
        dc:setColor({1, 0.2, 0.2}, 1)
        dc:rectangle("fill", ballX - ballRadius, ballY - ballRadius, 
                               ballRadius * 2, ballRadius)
        -- Bottom white half
        dc:setColor({1, 1, 1}, 1)
        dc:rectangle("fill", ballX - ballRadius, ballY, 
                               ballRadius * 2, ballRadius)
        -- Black dividing line
        dc:setColor({0, 0, 0}, 1)
        dc:setLineWidth(1)
        dc:line(ballX - ballRadius, ballY, ballX + ballRadius, ballY)
        -- White center circle
        dc:setColor({1, 1, 1}, 1)
        dc:circle("fill", ballX, ballY, 2)
        dc:setColor({0, 0, 0}, 1)
        dc:circle("line", ballX, ballY, 2)
    end
    
    local f13 = fonts:getFont(13)
    dc:setFont(f13)
    dc:setColor(cfg.COL.text, 1)
    local nameStr = Helpers.sanitizeName(en.name)
    dc:print(nameStr, x+48, cy)
    if en.status and en.status ~= "" and en.status ~= "OK" then
        dc:setColor(cfg.COL.lo, 1)
        dc:print(" (" .. tostring(en.status) .. ")", x+48+f13:getWidth(nameStr), cy)
    end
    local lvStr = "Lv" .. tostring(en.level or "?")
    dc:setFont(f10)
    dc:setColor(cfg.COL.dim, 1)
    dc:print(lvStr, x+w-8-f10:getWidth(lvStr), cy+2)
    cy = cy + 20

    if en.types then
        local tx = x + 48
        local f9 = fonts:getFont(9)
        dc:setFont(f9)
        for _, t2 in ipairs(en.types) do
            local tname = TypeColors.normalize(t2)
            if tname ~= "" then
                dc:setColor(cfg.TYPE[tname] or cfg.COL.dim, 1)
                dc:print(tname, tx, cy)
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
    dc:setColor({0.12,0.12,0.14}, 1)
    dc:rectangle("fill", x+8, cy, barW, 5)
    if frac > 0 then
        dc:setColor(Colors.hpColor(frac), 1)
        dc:rectangle("fill", x+8, cy, barW*frac, 5)
    end
    dc:setFont(f9b)
    dc:setColor(cfg.COL.text, 1)
    dc:print(hpStr, x+w-8-f9b:getWidth(hpStr), cy)
    cy = cy + 12

    local active = self.activeMon
    if active and active.moves and #active.moves > 0 then
        local colW = (w - 16) / 2
        local moveH = 14
        local dMove = self._props.moveData or {}
        for i, mv in ipairs(active.moves) do
            if i > 4 then break end
            local col = (i - 1) % 2
            local row = (i - 1) / 2
            local mx = x + 8 + col * colW
            local my = cy + row * moveH
            local moveName = mv.name or (dMove[mv.id] and dMove[mv.id].name) or "?"
            local ppCurr = mv.pp or 0
            local ppMax  = mv.maxpp or (dMove[mv.id] and dMove[mv.id].pp) or 0
            local moveCol = cfg.COL.text
            if en.types and te:effectiveness(mv.id, en.types) > 10 then
                moveCol = cfg.COL.se
            end
            local f11 = fonts:getFont(11)
            dc:setFont(f11)
            dc:setColor(moveCol, 1)
            dc:print(moveName, mx, my)
            local ppStr = tostring(ppCurr) .. "/" .. tostring(ppMax)
            dc:setFont(f9b)
            dc:setColor(cfg.COL.dim, 1)
            dc:print(ppStr, mx + colW - 8 - f9b:getWidth(ppStr), my)
        end
        cy = cy + 32
    else
        dc:setFont(f10)
        dc:setColor(cfg.COL.dim, 1)
        dc:print("No move data", x+8, cy)
        cy = cy + 14
    end

    cy = cy + 4
    if cy + 14 > y + drawH - 4 then return end
    dc:setFont(f10)
    dc:setColor(cfg.COL.dim, 1)
    dc:print("CATCH RATE", x+8, cy)
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
            dc:setFont(f11)
            dc:setColor(cfg.COL.text, 1)
            dc:print(name .. " x" .. count, x+8, cy)
            dc:setColor(cfg.COL.catch, 1)
            dc:print(rate .. "%", x+w-8-f11:getWidth(rate.."%"), cy)
            cy = cy + 14
        end
    end
    if not hasAny then
        dc:setFont(f10)
        dc:setColor(cfg.COL.dim, 1)
        dc:print("No Poke Balls", x+8, cy)
    end
end

return EnemyPanel
