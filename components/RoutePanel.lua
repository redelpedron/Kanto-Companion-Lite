local Component = require("core.Component")
local Colors    = require("util.Colors")
local Helpers   = require("util.Helpers")
local ScrollableMixin = require("util.ScrollableMixin")

local RoutePanel = setmetatable({}, { __index = Component })
RoutePanel.__index = RoutePanel
RoutePanel.__name = "RoutePanel"
RoutePanel.needs = { "ConfigService", "FontService", "SpriteService", "EventBus" }
Helpers.mixin(RoutePanel, ScrollableMixin)

local MAX_VISIBLE_ENTRIES = 5
local ENTRY_H = 18
local SEC_HEADER_H = 16
local SEC_SPACING = 4
local TOP_PAD = 8
local BOT_PAD = 4
local NO_ENCOUNTERS_ROW_H = 14

function RoutePanel.new(locator, props)
    local self = setmetatable(Component.new(locator, props), RoutePanel)
    self.route = nil
    self:_scrollInit()
    return self
end

function RoutePanel:init()
    self.bus = self._locator:resolve("EventBus")
    self:_scrollListen()
    self:_listen("route.updated", function(_, route) self.route = route end)

    self:_listen("input.pressed", function(self2, x, y, consume)
        if not self2._active then return end
        self2:_handleClick(x, y, consume)
    end)
    self:_listen("input.released", function(self2, x, y)
        self2:_scrollEndDrag()
    end)
end

function RoutePanel:_countEntries()
    if not self.route then return 0 end
    local n = 0
    if self.route.grass and self.route.grass.species then
        n = n + #self.route.grass.species
    end
    if self.route.water and self.route.water.species then
        n = n + #self.route.water.species
    end
    return n
end

function RoutePanel:_sectionCount()
    if not self.route then return 0 end
    local sections = 0
    if self.route.grass and self.route.grass.species and #self.route.grass.species > 0 then sections = sections + 1 end
    if self.route.water and self.route.water.species and #self.route.water.species > 0 then sections = sections + 1 end
    return sections
end

function RoutePanel:_wrappedHeight(w, h)
    local totalEntries = self:_countEntries()
    local sections = self:_sectionCount()

    local visibleEntries = math.min(totalEntries, MAX_VISIBLE_ENTRIES)
    local neededH = TOP_PAD + (sections * SEC_HEADER_H) + (visibleEntries * ENTRY_H) + (sections * SEC_SPACING) + BOT_PAD

    if totalEntries == 0 then
        neededH = TOP_PAD + NO_ENCOUNTERS_ROW_H + BOT_PAD
    end

    return math.min(h, neededH)
end

function RoutePanel:_contentHeight()
    local totalEntries = self:_countEntries()
    local sections = self:_sectionCount()

    return TOP_PAD + (sections * SEC_HEADER_H) + (totalEntries * ENTRY_H) + (sections * SEC_SPACING)
end

function RoutePanel:_handleClick(x, y, consume)
    if not self._props then return end
    local px, py, pw, ph = self._props.x, self._props.y, self._props.w, self._props.h

    local viewportHeight = ph - (TOP_PAD + BOT_PAD)
    if self:_scrollTryStartDrag(x, y, { x = px, y = py + TOP_PAD, w = pw, h = viewportHeight }) then
        if consume then consume() end
        return true
    end
    return false
end

function RoutePanel:update(dt)
    self:_scrollUpdateDrag()
end

function RoutePanel:draw(ctx)
    local cfg    = self:_service("ConfigService")
    local fonts  = self:_service("FontService")
    local sprites= self:_service("SpriteService")
    local x, y, w, h = ctx.x, ctx.y, ctx.w, ctx.h

    local drawH = h
    if ctx.wrapHeight then
        drawH = self:_wrappedHeight(w, h)
    end

    Colors.set(cfg.COL.panel, 0.96)
    love.graphics.rectangle("fill", math.floor(x), math.floor(y), math.floor(w), math.floor(drawH))
    love.graphics.setLineWidth(1)
    Colors.set(cfg.COL.border, 0.3)
    love.graphics.rectangle("line", math.floor(x)+0.5, math.floor(y)+0.5, math.floor(w)-1, math.floor(drawH)-1)

    if not self.route then
        local f12 = fonts:getFont(12)
        love.graphics.setFont(f12)
        Colors.set(cfg.COL.dim, 1)
        love.graphics.print("No location data", math.floor(x+8), math.floor(y+6))
        return
    end

    local contentHeight = self:_contentHeight()
    local viewportHeight = drawH - (TOP_PAD + BOT_PAD)
    local scrollOffset, maxScroll = self:_scrollClamp(contentHeight, viewportHeight)

    love.graphics.setScissor(
        math.floor(x),
        math.floor(y + TOP_PAD),
        math.ceil(w),
        math.ceil(viewportHeight)
    )

    local cy = y + TOP_PAD - scrollOffset
    local maxCy = y + drawH - BOT_PAD

    local f9 = fonts:getFont(9)
    love.graphics.setFont(f9)

    local COL_PCT_W = f9:getWidth("100%")
    local COL_GAP   = 6
    local pctColRight = x + w - 8
    local lvColRight  = pctColRight - COL_PCT_W - COL_GAP

    local function drawSec(title, tab)
        if not tab or not tab.species or #tab.species == 0 then return end
        if cy + ENTRY_H > maxCy then return end
        local f10 = fonts:getFont(10)
        love.graphics.setFont(f10)
        Colors.set(cfg.COL.dim, 1)
        local periodSuffix = tab.period and (" (" .. tab.period .. ")") or ""
        love.graphics.print(title .. periodSuffix .. " " .. tab.rate .. "%", math.floor(x+8), math.floor(cy))
        cy = cy + SEC_HEADER_H
        for _, sp in ipairs(tab.species) do
            if cy + SEC_HEADER_H > maxCy then break end
            local img = sprites:getSprite(sp.species, self._props.pokemonData)
            if img then
                local iw, ih = img:getDimensions()
                local sc = 20 / math.max(iw, ih)
                Colors.set(cfg.COL.text, 1)
                love.graphics.draw(img, math.floor(x+8), math.floor(cy-2), 0, sc, sc)
            end
            local f11 = fonts:getFont(11)
            love.graphics.setFont(f11)
            Colors.set(cfg.COL.text, 1)

            love.graphics.print(Helpers.sanitizeName(sp.name), math.floor(x+32), math.floor(cy))
            local lv
            if sp.minLevel == sp.maxLevel then
                lv = "Lv" .. sp.minLevel
            else
                lv = "Lv" .. sp.minLevel .. "-" .. sp.maxLevel
            end
            love.graphics.setFont(f9)
            Colors.set(cfg.COL.text, 1)
            love.graphics.print(sp.pct .. "%", math.floor(pctColRight - f9:getWidth(sp.pct.."%")), math.floor(cy))
            Colors.set(cfg.COL.dim, 1)
            love.graphics.print(lv, math.floor(lvColRight - f9:getWidth(lv)), math.floor(cy))
            cy = cy + ENTRY_H
        end
        cy = cy + SEC_SPACING
    end

    drawSec("Grass", self.route.grass)
    drawSec("Water", self.route.water)

    local hasAny = (self.route.grass and self.route.grass.species and #self.route.grass.species > 0)
                or (self.route.water and self.route.water.species and #self.route.water.species > 0)
    if not hasAny then
        if cy + NO_ENCOUNTERS_ROW_H <= maxCy then
            local f10 = fonts:getFont(10)
            love.graphics.setFont(f10)
            Colors.set(cfg.COL.dim, 1)
            love.graphics.print("No wild encounters", math.floor(x+8), math.floor(cy))
        end
    end

    love.graphics.setScissor()

    self:_scrollDrawBar(
        { x = x, y = y + TOP_PAD, w = w, h = viewportHeight },
        contentHeight, viewportHeight, maxScroll, scrollOffset,
        { track = cfg.COL.border, thumb = cfg.COL.hi, thumbActive = cfg.COL.gold },
        Colors
    )
end

return RoutePanel
