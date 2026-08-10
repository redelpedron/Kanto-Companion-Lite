local Component = require("core.Component")
local Colors    = require("util.Colors")
local Helpers   = require("util.Helpers")
local ScrollableMixin = require("util.ScrollableMixin")

local RoutePanel = setmetatable({}, { __index = Component })
RoutePanel.__index = RoutePanel
RoutePanel.needs = { "ConfigService", "FontService", "SpriteService", "EventBus" }
Helpers.mixin(RoutePanel, ScrollableMixin)

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

    -- v1.0.65: input handling for scrollbar drag
    self:_listen("input.pressed", function(self2, x, y, consume)
        if not self2._active then return end
        self2:_handleClick(x, y, consume)
    end)
    self:_listen("input.released", function(self2, x, y)
        self2:_scrollEndDrag()
    end)
end

-- v1.0.65: count total encounter entries across all sections
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

-- v1.0.65: compute wrapped height (capped at 9 visible entries)
function RoutePanel:_wrappedHeight(w, h)
    local cfg = self:_service("ConfigService")
    local MAX_VISIBLE = 5
    local ENTRY_H = 18
    local SEC_HEADER_H = 16
    local SEC_SPACING = 4
    local TOP_PAD = 8
    local BOT_PAD = 4

    local totalEntries = self:_countEntries()
    local sections = 0
    if self.route then
        if self.route.grass and self.route.grass.species and #self.route.grass.species > 0 then sections = sections + 1 end
        if self.route.water and self.route.water.species and #self.route.water.species > 0 then sections = sections + 1 end
    end

    local visibleEntries = math.min(totalEntries, MAX_VISIBLE)
    local neededH = TOP_PAD + (sections * SEC_HEADER_H) + (visibleEntries * ENTRY_H) + (sections * SEC_SPACING) + BOT_PAD

    -- If no encounters, show "No wild encounters" row
    if totalEntries == 0 then
        neededH = TOP_PAD + 14 + BOT_PAD
    end

    return math.min(h, neededH)
end

-- v1.0.65: total content height for scroll calculation
function RoutePanel:_contentHeight()
    local SEC_HEADER_H = 16
    local ENTRY_H = 18
    local SEC_SPACING = 4
    local TOP_PAD = 8

    local totalEntries = self:_countEntries()
    local sections = 0
    if self.route then
        if self.route.grass and self.route.grass.species and #self.route.grass.species > 0 then sections = sections + 1 end
        if self.route.water and self.route.water.species and #self.route.water.species > 0 then sections = sections + 1 end
    end

    return TOP_PAD + (sections * SEC_HEADER_H) + (totalEntries * ENTRY_H) + (sections * SEC_SPACING)
end

function RoutePanel:_handleClick(x, y, consume)
    if not self._props then return end
    local px, py, pw, ph = self._props.x, self._props.y, self._props.w, self._props.h

    -- Hit zone: scrollbar track area
    local viewportHeight = ph - 12
    if self:_scrollTryStartDrag(x, y, { x = px, y = py + 8, w = pw, h = viewportHeight }) then
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

    -- v1.0.65: landscape mode wraps background to content height (max 9 entries)
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

    -- Scroll metrics
    local contentHeight = self:_contentHeight()
    local viewportHeight = drawH - 12
    local scrollOffset, maxScroll = self:_scrollClamp(contentHeight, viewportHeight)

    -- Apply scissor
    love.graphics.setScissor(
        math.floor(x),
        math.floor(y + 8),
        math.ceil(w),
        math.ceil(viewportHeight)
    )

    local cy = y + 8 - scrollOffset
    local maxCy = y + drawH - 4

    local f9 = fonts:getFont(9)
    love.graphics.setFont(f9)
    -- Fixed column widths sized to the widest realistic value, not to any
    -- one row's actual string -- keeps both columns lined up straight down
    -- the list instead of wobbling with digit count.
    local COL_PCT_W = f9:getWidth("100%")
    local COL_GAP   = 6
    local pctColRight = x + w - 8
    local lvColRight  = pctColRight - COL_PCT_W - COL_GAP

    local function drawSec(title, tab)
        if not tab or not tab.species or #tab.species == 0 then return end
        if cy + 18 > maxCy then return end
        local f10 = fonts:getFont(10)
        love.graphics.setFont(f10)
        Colors.set(cfg.COL.dim, 1)
        love.graphics.print(title .. " " .. tab.rate .. "%", math.floor(x+8), math.floor(cy))
        cy = cy + 16
        for _, sp in ipairs(tab.species) do
            if cy + 16 > maxCy then break end
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
            -- v2.1.38: every other name-printing site (PokemonPanel,
            -- EnemyPanel, PCPopup) runs species names through
            -- sanitizeName first so the ♀/♂ glyphs -- absent from LÖVE's
            -- default font -- get swapped for "(F)"/"(M)" instead of
            -- rendering as a missing-glyph box. This was the one spot
            -- that printed the raw name, so gender-locked species with a
            -- symbol in their name (e.g. Nidorino/Nidorina) showed a
            -- blank/garbled glyph here instead of the gender tag.
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
            cy = cy + 18
        end
        cy = cy + 4
    end

    drawSec("Grass", self.route.grass)
    drawSec("Water", self.route.water)

    local hasAny = (self.route.grass and self.route.grass.species and #self.route.grass.species > 0)
                or (self.route.water and self.route.water.species and #self.route.water.species > 0)
    if not hasAny then
        if cy + 14 <= maxCy then
            local f10 = fonts:getFont(10)
            love.graphics.setFont(f10)
            Colors.set(cfg.COL.dim, 1)
            love.graphics.print("No wild encounters", math.floor(x+8), math.floor(cy))
        end
    end

    -- Clear scissor
    love.graphics.setScissor()

    self:_scrollDrawBar(
        { x = x, y = y + 8, w = w, h = viewportHeight },
        contentHeight, viewportHeight, maxScroll, scrollOffset,
        { track = cfg.COL.border, thumb = cfg.COL.hi, thumbActive = cfg.COL.gold },
        Colors
    )
end

return RoutePanel
