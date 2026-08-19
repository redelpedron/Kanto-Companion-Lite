local Component = require("core.Component")
local Colors    = require("util.Colors")
local Helpers   = require("util.Helpers")
local Viewport  = require("util.Viewport")
local TypeColors = require("util.TypeColors")
local ScrollableMixin = require("util.ScrollableMixin")

local PCPopup = setmetatable({}, { __index = Component })
PCPopup.__index = PCPopup
PCPopup.__name = "PCPopup"
PCPopup.needs = { "ConfigService", "FontService", "GameService", "PCService", "SpriteService", "EventBus" }
Helpers.mixin(PCPopup, ScrollableMixin)

function PCPopup.new(locator, props)
    local self = setmetatable(Component.new(locator, props), PCPopup)
    self.tab      = "items"
    self.heldItem = nil
    self.heldMon  = nil
    self.boxView  = 1
    self.status   = nil
    self.statusAt = 0
    self._hit     = {}

    self:_scrollInit()
    return self
end

function PCPopup:init()
    self.bus = self._locator:resolve("EventBus")
    self:_scrollListen()

    self:_listen("pc.open", function(self2) self2:openPopup() end)
    self:_listen("battle.started", function(self2) self2:closePopup() end)
    self:_listen("hud.visibility.changed", function(self2, visible)
        if not visible then self2:closePopup() end
    end)

    self:_listen("input.pressed", function(self2, x, y, consume)
        if not self2:isActive() then return end

        if consume then consume() end
        self2:_handleClick(x, y)
    end)

    self:_listen("input.released", function(self2, x, y, consume)
        if not self2:isActive() then return end
        if self2._scrollDragging then
            self2:_scrollEndDrag()
            if consume then consume() end
        end
    end)
end

function PCPopup:update(dt)
    if not self:isActive() then return end
    local game = self:_service("GameService")

    if not game:getSave() then self:closePopup() end

    self:_scrollUpdateDrag()
end

function PCPopup:openPopup()
    if self:isActive() then return end
    local pc = self:_service("PCService")
    if not pc:canOpen() then return end

    self.tab = "items"
    self.heldItem, self.heldMon = nil, nil
    self.status = nil
    self.boxView = pc:getCurrentBox()

    pc:openModal()
    self:setActive(true)
    self.bus:publish("modal.opened")
end

function PCPopup:closePopup()
    if not self:isActive() then return end
    local pc = self:_service("PCService")
    pc:closeModal()
    self.heldItem, self.heldMon = nil, nil
    self._hit = {}

    self:_scrollReset()
    self:setActive(false)
    self.bus:publish("modal.closed")
end

function PCPopup:_hitRegion(x, y, w, h, tag, data, viewport)
    self._hit[#self._hit + 1] = { x = x, y = y, w = w, h = h, tag = tag, data = data, viewport = viewport }
end

function PCPopup:_topHit(x, y)
    for i = #self._hit, 1, -1 do
        local r = self._hit[i]
        if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
           and (not r.viewport or r.viewport:contains(x, y)) then
            return r.tag, r.data
        end
    end
    return nil, nil
end

function PCPopup:_setStatus(msg)
    self.status = msg
    self.statusAt = (love.timer and love.timer.getTime and love.timer.getTime()) or 0
end

function PCPopup:_handleClick(x, y)

    if self.tab == "items" then
        local L = self:_computeLayout(love.graphics.getDimensions())
        local bx, by, bw, bh = L.wx + 10, L.bodyY, L.ww - 20, L.bodyH
        local p1, p2 = self:_splitPanels(bx, by, bw, bh, L.portrait)

        if self:_scrollTryStartDrag(x, y, { x = p1.x, y = p1.y + 28, w = p1.w, h = p1.h }, "bag") then
            return
        end
        if self:_scrollTryStartDrag(x, y, { x = p2.x, y = p2.y + 28, w = p2.w, h = p2.h }, "pc") then
            return
        end
    end

    local tag, data = self:_topHit(x, y)
    if tag == "close" then
        self:closePopup()
        return
    end
    if tag == "tab" then
        self.tab = data
        self.heldItem, self.heldMon = nil, nil
        return
    end
    if self.tab == "items" then
        self:_handleItemsClick(tag, data)
    else
        self:_handleBoxesClick(tag, data)
    end
end

function PCPopup:_handleItemsClick(tag, data)
    if tag ~= "itemrow" and tag ~= "panel" then return end
    local pc = self:_service("PCService")

    if tag == "itemrow" then
        if self.heldItem and self.heldItem.from == data.side and self.heldItem.id == data.id then
            self.heldItem = nil
            return
        end
        if self.heldItem and self.heldItem.from ~= data.side then
            local ok, err = pc:transferItem(self.heldItem.from, self.heldItem.id, data.side)
            self:_setStatus(ok and nil or err)
            self.heldItem = nil
            return
        end

        local qty = (data.side == "bag") and (pc:getBagItems()[data.id] or 0) or pc:getItemCount(data.id)
        if qty > 0 then
            local dItem = self:_service("GameService"):getItemData()
            local name = (dItem[data.id] and dItem[data.id].name) or data.id
            self.heldItem = { from = data.side, id = data.id, qty = qty, name = name }
        end
        return
    end

    if self.heldItem and self.heldItem.from ~= data.side then
        local ok, err = pc:transferItem(self.heldItem.from, self.heldItem.id, data.side)
        self:_setStatus(ok and nil or err)
    end
    self.heldItem = nil
end

function PCPopup:_handleBoxesClick(tag, data)
    local pc = self:_service("PCService")

    if tag == "monslot" then
        if self.heldMon then
            local src = self.heldMon.src
            if src.loc == data.loc and src.box == data.box and src.index == data.index then
                self.heldMon = nil
                return
            end
            local tgt = { loc = data.loc, box = data.box, index = data.index }
            local ok, err = pc:moveMon(src, tgt)
            self:_setStatus(ok and nil or err)
            self.heldMon = nil
            return
        end
        if data.mon then
            local dPoke = self:_service("GameService"):getPokemonData()
            local def = dPoke[data.mon.species]
            local name = Helpers.sanitizeName(data.mon.nickname or (def and def.name) or data.mon.species)
            self.heldMon = { mon = data.mon, name = name, src = { loc = data.loc, box = data.box, index = data.index } }
        end
        return
    end

    if tag == "boxtab" then
        if self.heldMon then
            local ok, err = pc:moveMon(self.heldMon.src, { loc = "box", box = data.box })
            self:_setStatus(ok and nil or err)
            self.heldMon = nil
        end
        self.boxView = data.box
        return
    end

    if tag == "boxnav" then
        local n = pc:getBoxCount()
        if data.dir > 0 then
            self.boxView = (self.boxView < n) and (self.boxView + 1) or 1
        else
            self.boxView = (self.boxView > 1) and (self.boxView - 1) or n
        end
        return
    end
end

function PCPopup:_computeLayout(W, H)
    local M = 16
    local headerH, footerH = 46, 24
    local ww, wh = W - 2 * M, H - 2 * M
    return {
        wx = M, wy = M, ww = ww, wh = wh,
        headerH = headerH, footerH = footerH,
        bodyY = M + headerH,
        bodyH = wh - headerH - footerH,
        portrait = W < H,
    }
end

function PCPopup:_splitPanels(x, y, w, h, portrait)
    local gap = 10
    if portrait then
        local ph = (h - gap) / 2
        return { x = x, y = y, w = w, h = ph }, { x = x, y = y + ph + gap, w = w, h = ph }
    else
        local pw = (w - gap) / 2
        return { x = x, y = y, w = pw, h = h }, { x = x + pw + gap, y = y, w = pw, h = h }
    end
end

function PCPopup:draw(ctx)
    if not self:isActive() then return end
    local cfg   = self:_service("ConfigService")
    local fonts = self:_service("FontService")
    local W, H  = love.graphics.getDimensions()
    self._hit = {}

    Colors.set({0, 0, 0}, 0.72)
    love.graphics.rectangle("fill", 0, 0, W, H)

    local L = self:_computeLayout(W, H)

    Colors.set(cfg.COL.panel, 0.98)
    love.graphics.rectangle("fill", math.floor(L.wx), math.floor(L.wy), math.floor(L.ww), math.floor(L.wh))
    love.graphics.setLineWidth(1)
    Colors.set(cfg.COL.border, 0.5)
    love.graphics.rectangle("line", math.floor(L.wx) + 0.5, math.floor(L.wy) + 0.5, math.floor(L.ww) - 1, math.floor(L.wh) - 1)

    self:_drawHeader(L, cfg, fonts)
    if self.tab == "items" then
        self:_drawItemsTab(L, cfg, fonts)
    else
        self:_drawBoxesTab(L, cfg, fonts)
    end
    self:_drawFooter(L, cfg, fonts)
end

function PCPopup:_drawHeader(L, cfg, fonts)
    local f20 = fonts:getFont(20)
    love.graphics.setFont(f20)
    Colors.set(cfg.COL.gold, 1)
    love.graphics.print("PC", math.floor(L.wx + 14), math.floor(L.wy + 10))

    local tabW, tabH = 84, 26
    local tx = L.wx + 60
    local ty = L.wy + 12
    local tabs = { { "items", "Items" }, { "boxes", "Boxes" } }
    for _, t in ipairs(tabs) do
        local active = self.tab == t[1]
        self:_hitRegion(tx, ty, tabW, tabH, "tab", t[1])
        Colors.set(active and cfg.COL.tabActive or cfg.COL.tabBg, active and 0.9 or 0.85)
        love.graphics.rectangle("fill", math.floor(tx), math.floor(ty), tabW, tabH)
        local f13 = fonts:getFont(13)
        love.graphics.setFont(f13)
        Colors.set(active and cfg.COL.panel or cfg.COL.dim, 1)
        local tw = f13:getWidth(t[2])
        love.graphics.print(t[2], math.floor(tx + tabW / 2 - tw / 2), math.floor(ty + 6))
        tx = tx + tabW + 6
    end

    local cw = 32
    local cx = L.wx + L.ww - cw - 10
    local cy = L.wy + 8
    self:_hitRegion(cx, cy, cw, cw, "close", nil)
    Colors.set(cfg.COL.lo, 0.85)
    love.graphics.rectangle("fill", math.floor(cx), math.floor(cy), cw, cw)
    Colors.set(cfg.COL.border, 0.5)
    love.graphics.rectangle("line", math.floor(cx) + 0.5, math.floor(cy) + 0.5, cw - 1, cw - 1)
    local f16 = fonts:getFont(16)
    love.graphics.setFont(f16)
    Colors.set(cfg.COL.text, 1)
    local xw = f16:getWidth("X")
    love.graphics.print("X", math.floor(cx + cw / 2 - xw / 2), math.floor(cy + 6))

    Colors.set(cfg.COL.border, 0.35)
    love.graphics.setLineWidth(1)
    love.graphics.line(L.wx, L.wy + L.headerH, L.wx + L.ww, L.wy + L.headerH)
end

function PCPopup:_drawFooter(L, cfg, fonts)
    if self.status and love.timer and love.timer.getTime and (love.timer.getTime() - self.statusAt) > 3 then
        self.status = nil
    end

    local f12 = fonts:getFont(12)
    love.graphics.setFont(f12)
    local msg
    if self.status then
        Colors.set(cfg.COL.lo, 1)
        msg = self.status
    elseif self.heldItem then
        Colors.set(cfg.COL.gold, 1)
        msg = "Holding " .. self.heldItem.name .. " x" .. tostring(self.heldItem.qty)
            .. " -- tap the other list to move it, tap it again to cancel"
    elseif self.heldMon then
        Colors.set(cfg.COL.gold, 1)
        msg = "Holding " .. self.heldMon.name .. " -- tap a slot or box to place it, tap it again to cancel"
    elseif self.tab == "items" then
        Colors.set(cfg.COL.dim, 1)
        msg = "Tap an item, then tap the other list to move it"
    else
        Colors.set(cfg.COL.dim, 1)
        msg = "Tap a Pokemon, then tap a slot or box to move it"
    end
    love.graphics.print(msg, math.floor(L.wx + 14), math.floor(L.wy + L.wh - L.footerH + 4))
end

function PCPopup:_drawItemsTab(L, cfg, fonts)
    local pc = self:_service("PCService")
    local game = self:_service("GameService")
    local dItem = game:getItemData()

    local bx, by, bw, bh = L.wx + 10, L.bodyY, L.ww - 20, L.bodyH
    local p1, p2 = self:_splitPanels(bx, by, bw, bh, L.portrait)

    self:_drawItemList(p1, cfg, fonts, dItem, "bag", "BAG", pc:getBagItems(), pc:bagSlotCount(), pc:bagCapacity())
    self:_drawItemList(p2, cfg, fonts, dItem, "pc", "PC ITEMS", pc:getItems(), pc:pcSlotCount(), pc:pcItemCapacity())
end

function PCPopup:_drawItemList(p, cfg, fonts, dItem, side, title, itemsTable, slotCount, capacity)
    Colors.set(cfg.COL.panelTop, 0.9)
    love.graphics.rectangle("fill", math.floor(p.x), math.floor(p.y), math.floor(p.w), math.floor(p.h))
    Colors.set(cfg.COL.border, 0.3)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", math.floor(p.x) + 0.5, math.floor(p.y) + 0.5, math.floor(p.w) - 1, math.floor(p.h) - 1)

    self:_hitRegion(p.x, p.y, p.w, p.h, "panel", { side = side })

    local f14 = fonts:getFont(14)
    love.graphics.setFont(f14)
    Colors.set(cfg.COL.text, 1)
    love.graphics.print(title, math.floor(p.x + 8), math.floor(p.y + 6))

    local capStr = slotCount .. "/" .. capacity
    local f11 = fonts:getFont(11)
    love.graphics.setFont(f11)
    Colors.set(slotCount >= capacity and cfg.COL.lo or cfg.COL.dim, 1)
    love.graphics.print(capStr, math.floor(p.x + p.w - 8 - f11:getWidth(capStr)), math.floor(p.y + 9))

    local balls, heals, other = Helpers.categorizeItems(dItem, itemsTable)
    if #balls == 0 and #heals == 0 and #other == 0 then
        local f12 = fonts:getFont(12)
        love.graphics.setFont(f12)
        Colors.set(cfg.COL.dim, 1)
        love.graphics.print((side == "bag") and "Bag is empty" or "PC is empty", math.floor(p.x + 8), math.floor(p.y + 30))
        return
    end

    local rowH = 22
    local headerH = 15
    local sections = { { title = "BALLS", rows = balls }, { title = "HEALING", rows = heals }, { title = "OTHER", rows = other } }
    local contentHeight = Helpers.sectionedContentHeight(sections, rowH, headerH, 4)

    local viewportHeight = p.h - 32
    local scroll, maxScroll = self:_scrollClamp(contentHeight, viewportHeight, side)

    local cy = p.y + 30 - scroll
    local maxCy = p.y + p.h - 4

    local viewport = Viewport.new(p.x, p.y + 28, p.w, p.h - 32)
    viewport:clipDraw()

    local function drawSec(secTitle, rows)
        if #rows == 0 then return end
        if cy + 16 > maxCy then return end
        local f10 = fonts:getFont(10)
        love.graphics.setFont(f10)
        Colors.set(cfg.COL.dim, 1)
        love.graphics.print(secTitle, math.floor(p.x + 8), math.floor(cy))
        cy = cy + 15
        for _, row in ipairs(rows) do
            if cy + rowH > maxCy then break end
            local held = self.heldItem and self.heldItem.from == side and self.heldItem.id == row.id
            self:_hitRegion(p.x + 4, cy, p.w - 8, rowH - 2, "itemrow", { side = side, id = row.id }, viewport)
            if held then
                Colors.set(cfg.COL.gold, 0.22)
                love.graphics.rectangle("fill", math.floor(p.x + 4), math.floor(cy), math.floor(p.w - 8), rowH - 2)
            end
            local f12b = fonts:getFont(12)
            love.graphics.setFont(f12b)
            Colors.set(held and cfg.COL.dim or cfg.COL.text, 1)
            love.graphics.print(row.name, math.floor(p.x + 10), math.floor(cy + 3))
            local qtyStr = "x" .. tostring(row.qty)
            Colors.set(cfg.COL.dim, 1)
            love.graphics.print(qtyStr, math.floor(p.x + p.w - 10 - f12b:getWidth(qtyStr)), math.floor(cy + 3))
            cy = cy + rowH
        end
        cy = cy + 4
    end

    drawSec("BALLS", balls)
    drawSec("HEALING", heals)
    drawSec("OTHER", other)

    love.graphics.setScissor()

    self:_scrollDrawBar(
        { x = p.x, y = p.y + 28, w = p.w, h = viewportHeight },
        contentHeight, viewportHeight, maxScroll, scroll,
        { track = cfg.COL.border, thumb = cfg.COL.hi, thumbActive = cfg.COL.gold },
        Colors, side
    )
end

function PCPopup:_drawBoxesTab(L, cfg, fonts)
    local pc = self:_service("PCService")
    local game = self:_service("GameService")
    local sprites = self:_service("SpriteService")
    local dPoke = game:getPokemonData()

    local bx, by, bw, bh = L.wx + 10, L.bodyY, L.ww - 20, L.bodyH
    local p1, p2 = self:_splitPanels(bx, by, bw, bh, L.portrait)

    self:_drawPartyPanel(p1, cfg, fonts, sprites, dPoke, pc)
    self:_drawBoxPanel(p2, cfg, fonts, sprites, dPoke, pc)
end

function PCPopup:_drawPartyPanel(p, cfg, fonts, sprites, dPoke, pc)
    Colors.set(cfg.COL.panelTop, 0.9)
    love.graphics.rectangle("fill", math.floor(p.x), math.floor(p.y), math.floor(p.w), math.floor(p.h))
    Colors.set(cfg.COL.border, 0.3)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", math.floor(p.x) + 0.5, math.floor(p.y) + 0.5, math.floor(p.w) - 1, math.floor(p.h) - 1)

    local party = pc:getParty()
    local game = self:_service("GameService")

    local growth = game:getGrowthSystem()
    local rates = game:getGrowthRates() or {}

    local f14 = fonts:getFont(14)
    love.graphics.setFont(f14)
    Colors.set(cfg.COL.text, 1)
    love.graphics.print("PARTY", math.floor(p.x + 8), math.floor(p.y + 6))
    local countStr = #party .. "/" .. pc:getPartyMax()
    local f11 = fonts:getFont(11)
    love.graphics.setFont(f11)
    Colors.set(cfg.COL.dim, 1)
    love.graphics.print(countStr, math.floor(p.x + p.w - 8 - f11:getWidth(countStr)), math.floor(p.y + 9))

    local ry = p.y + 26
    local rh = 45

    for i = 1, 6 do
        local y = ry + (i - 1) * rh
        if y + rh > p.y + p.h then break end

        local mon = party[i]
        self:_hitRegion(p.x + 4, y, p.w - 8, rh - 2, "monslot", { loc = "party", box = nil, index = i, mon = mon })
        local held = self.heldMon and self.heldMon.src.loc == "party" and self.heldMon.src.index == i
        if held then
            Colors.set(cfg.COL.gold, 0.18)
        elseif mon then
            Colors.set(cfg.COL.border, 0.10)
        else
            Colors.set(cfg.COL.border, 0.04)
        end
        love.graphics.rectangle("fill", math.floor(p.x + 4), math.floor(y), math.floor(p.w - 8), rh - 2)

        if mon then

            local img = sprites:getSprite(mon.species, dPoke)
            local ss = 32
            if img then
                local iw, ih = img:getDimensions()
                local sc = ss / math.max(iw, ih)
                Colors.set(cfg.COL.text, 1)
                love.graphics.draw(img, math.floor(p.x + 6), math.floor(y + 6), 0, sc, sc)
            end

            local nx = p.x + 6 + ss + 6
            local def = dPoke[mon.species]
            local name = Helpers.sanitizeName(mon.nickname or (def and def.name) or mon.species)
            local f11 = fonts:getFont(11)
            love.graphics.setFont(f11)
            Colors.set(held and cfg.COL.dim or cfg.COL.text, 1)
            love.graphics.print(name, math.floor(nx), math.floor(y + 2))

            local lvStr = "Lv" .. (mon.level or 1)
            local lvW = f11:getWidth(lvStr)
            love.graphics.print(lvStr, math.floor(p.x + p.w - 8 - lvW), math.floor(y + 2))

            if mon.status and mon.status ~= "" and mon.status ~= "OK" then
                local statusStr = Helpers.formatStatus(mon.status)
                local f9 = fonts:getFont(9)
                love.graphics.setFont(f9)
                Colors.set(cfg.COL.lo, 1)
                love.graphics.print("[" .. statusStr .. "]", math.floor(nx + f11:getWidth(name) + 4), math.floor(y + 2))
            end

            local xpProg = Helpers.expProgress(growth, def, mon, rates) or 0

            local typeY = y + 14
            local f9 = fonts:getFont(9)
            love.graphics.setFont(f9)
            local typeX = nx
            if def and def.types then
                if type(def.types) == "table" then
                    for idx, t in ipairs(def.types) do
                        local typeName = TypeColors.normalize(tostring(t))
                        local typeColor = TypeColors.getColor(typeName)
                        Colors.set(typeColor, 1)
                        love.graphics.print(typeName, math.floor(typeX), math.floor(typeY))
                        typeX = typeX + f9:getWidth(typeName)
                        if idx < #def.types then
                            Colors.set(cfg.COL.dim, 0.7)
                            love.graphics.print("/", math.floor(typeX), math.floor(typeY))
                            typeX = typeX + f9:getWidth("/")
                        end
                    end
                else
                    local typeName = TypeColors.normalize(tostring(def.types))
                    local typeColor = TypeColors.getColor(typeName)
                    Colors.set(typeColor, 1)
                    love.graphics.print(typeName, math.floor(typeX), math.floor(typeY))
                end
            end

            local mx = (mon.stats and mon.stats.hp) or mon.hp or 1
            local hp = mon.hp or mx
            local frac = mx > 0 and hp / mx or 0

            local hpStr = string.format("%3d/%3d", hp, mx)
            local f9b = fonts:getFont(9)
            love.graphics.setFont(f9b)
            Colors.set(cfg.COL.dim, 1)
            local hpW = f9b:getWidth(hpStr)
            love.graphics.print(hpStr, math.floor(p.x + p.w - 8 - hpW), math.floor(typeY))

            local barW = (p.x + p.w - 8 - hpW - 4) - nx
            local hpBarY = y + 26
            Colors.set({ 0.12, 0.12, 0.14 }, 1)
            love.graphics.rectangle("fill", math.floor(nx), math.floor(hpBarY), math.floor(barW), 3)
            if frac > 0 then
                Colors.set(Colors.hpColor(frac), 1)
                love.graphics.rectangle("fill", math.floor(nx), math.floor(hpBarY), math.floor(barW * frac), 3)
            end

            local expBarY = hpBarY + 4
            Colors.set({ 0.12, 0.12, 0.14 }, 1)
            love.graphics.rectangle("fill", math.floor(nx), math.floor(expBarY), math.floor(barW), 2)
            Colors.set(cfg.COL.xp or { 0.3, 0.5, 0.9 }, 1)
            love.graphics.rectangle("fill", math.floor(nx), math.floor(expBarY), math.floor(barW * xpProg), 2)
        else
            local f10 = fonts:getFont(10)
            love.graphics.setFont(f10)
            Colors.set(cfg.COL.dim, 1)
            love.graphics.print("- empty -", math.floor(p.x + 10), math.floor(y + rh / 2 - 8))
        end
    end
end

function PCPopup:_drawBoxPanel(p, cfg, fonts, sprites, dPoke, pc)
    Colors.set(cfg.COL.panelTop, 0.9)
    love.graphics.rectangle("fill", math.floor(p.x), math.floor(p.y), math.floor(p.w), math.floor(p.h))
    Colors.set(cfg.COL.border, 0.3)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", math.floor(p.x) + 0.5, math.floor(p.y) + 0.5, math.floor(p.w) - 1, math.floor(p.h) - 1)

    local n = pc:getBoxCount()
    local cap = pc:getBoxCapacity()
    if self.boxView < 1 or self.boxView > n then self.boxView = 1 end
    local cur = self.boxView
    local box = pc:getBoxPokemon(cur)

    local f14 = fonts:getFont(14)
    love.graphics.setFont(f14)
    Colors.set(cfg.COL.text, 1)
    love.graphics.print("BOXES", math.floor(p.x + 8), math.floor(p.y + 6))

    local navY = p.y + 6
    local navW = 22
    local label = "Box " .. cur .. "  " .. #box .. "/" .. cap
    local f11 = fonts:getFont(11)
    love.graphics.setFont(f11)
    local labelW = f11:getWidth(label)
    local prevX = p.x + p.w - 8 - navW * 2 - labelW - 12

    self:_hitRegion(prevX, navY, navW, 18, "boxnav", { dir = -1 })
    Colors.set(cfg.COL.tabBg, 0.85)
    love.graphics.rectangle("fill", math.floor(prevX), math.floor(navY), navW, 18)
    local f12 = fonts:getFont(12)
    love.graphics.setFont(f12)
    Colors.set(cfg.COL.text, 1)
    love.graphics.print("<", math.floor(prevX + 8), math.floor(navY + 2))

    love.graphics.setFont(f11)
    Colors.set(#box >= cap and cfg.COL.lo or cfg.COL.dim, 1)
    love.graphics.print(label, math.floor(prevX + navW + 6), math.floor(navY + 3))

    local nextX = prevX + navW + 6 + labelW + 6
    self:_hitRegion(nextX, navY, navW, 18, "boxnav", { dir = 1 })
    Colors.set(cfg.COL.tabBg, 0.85)
    love.graphics.rectangle("fill", math.floor(nextX), math.floor(navY), navW, 18)
    love.graphics.setFont(f12)
    Colors.set(cfg.COL.text, 1)
    love.graphics.print(">", math.floor(nextX + 8), math.floor(navY + 2))

    local railY = p.y + 30
    local railH = 22
    local railGap = 2
    local tabW = (p.w - 16 - (n - 1) * railGap) / n
    local gridTop = railY
    if tabW >= 18 then
        for i = 1, n do
            local tx = p.x + 8 + (i - 1) * (tabW + railGap)
            local cnt = #pc:getBoxPokemon(i)
            local sel = i == cur
            self:_hitRegion(tx, railY, tabW, railH, "boxtab", { box = i })
            Colors.set(sel and cfg.COL.gold or cfg.COL.tabBg, sel and 0.9 or (cnt == 0 and 0.35 or 0.75))
            love.graphics.rectangle("fill", math.floor(tx), math.floor(railY), math.floor(tabW), railH)
            local f10 = fonts:getFont(10)
            love.graphics.setFont(f10)
            Colors.set(sel and cfg.COL.panel or cfg.COL.dim, 1)
            local numStr = tostring(i)
            love.graphics.print(numStr, math.floor(tx + tabW / 2 - f10:getWidth(numStr) / 2), math.floor(railY + 5))
        end
        gridTop = railY + railH + 8
    end

    local cols, rows2, gapG = 4, 5, 6
    local gy0 = gridTop
    local cellW = (p.w - 16 - (cols - 1) * gapG) / cols
    local cellH = math.min((p.y + p.h - gy0 - 8 - (rows2 - 1) * gapG) / rows2, cellW * 1.05)
    for i = 1, cols * rows2 do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local tx = p.x + 8 + col * (cellW + gapG)
        local ty = gy0 + row * (cellH + gapG)
        local mon = box[i]
        self:_hitRegion(tx, ty, cellW, cellH, "monslot", { loc = "box", box = cur, index = i, mon = mon })
        local held = self.heldMon and self.heldMon.src.loc == "box" and self.heldMon.src.box == cur and self.heldMon.src.index == i
        if held then
            Colors.set(cfg.COL.gold, 0.18)
        elseif mon then
            Colors.set(cfg.COL.border, 0.08)
        else
            Colors.set(cfg.COL.border, 0.03)
        end
        love.graphics.rectangle("fill", math.floor(tx), math.floor(ty), math.floor(cellW), math.floor(cellH))

        if mon then
            local img = sprites:getSprite(mon.species, dPoke)
            if img then
                local iw, ih = img:getDimensions()
                local sc = math.min((cellW - 8) / iw, (cellH - 24) / ih)
                Colors.set(cfg.COL.text, 1)
                love.graphics.draw(img, math.floor(tx + cellW / 2), math.floor(ty + (cellH - 20) / 2), 0, sc, sc, iw / 2, ih / 2)
            end
            local def = dPoke[mon.species]
            local nm = Helpers.sanitizeName(mon.nickname or (def and def.name) or mon.species)
            local f9 = fonts:getFont(9)
            love.graphics.setFont(f9)
            Colors.set(held and cfg.COL.dim or cfg.COL.text, 1)
            while #nm > 3 and f9:getWidth(nm) > cellW - 4 do
                nm = nm:sub(1, #nm - 1)
            end
            love.graphics.print(nm, math.floor(tx + cellW / 2 - f9:getWidth(nm) / 2), math.floor(ty + cellH - 18))
            local lvStr = "Lv" .. (mon.level or 1)
            love.graphics.print(lvStr, math.floor(tx + cellW / 2 - f9:getWidth(lvStr) / 2), math.floor(ty + cellH - 9))
        end
    end
end

return PCPopup
