local Component = require("core.Component")
local Colors    = require("util.Colors")
local Helpers   = require("util.Helpers")

local RoutePanel = setmetatable({}, { __index = Component })
RoutePanel.__index = RoutePanel
RoutePanel.needs = { "ConfigService", "FontService", "SpriteService", "EventBus" }

function RoutePanel.new(locator, props)
    local self = setmetatable(Component.new(locator, props), RoutePanel)
    self.route = nil
    -- v1.0.65: scroll state for encounter lists
    self.scrollOffset = 0
    self.scrollDragging = false
    self.scrollDragStartY = 0
    self.scrollDragStartOffset = 0
    return self
end

function RoutePanel:init()
    self.bus = self._locator:resolve("EventBus")
    self:_listen("route.updated", function(_, route) self.route = route end)

    -- v1.0.65: input handling for scrollbar drag
    self:_listen("input.pressed", function(self2, x, y, consume)
        if not self2._active then return end
        self2:_handleClick(x, y, consume)
    end)
    self:_listen("input.released", function(self2, x, y)
        if self2.scrollDragging then
            self2.scrollDragging = false
        end
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
    local scrollbarX = px + pw - 10
    local scrollbarY = py + 8
    local viewportHeight = ph - 12

    if x >= scrollbarX - 6 and x <= scrollbarX + 10 and
       y >= scrollbarY and y <= scrollbarY + viewportHeight then
        self.scrollDragging = true
        self.scrollDragStartY = y
        self.scrollDragStartOffset = self.scrollOffset
        if consume then consume() end
        return true
    end
    return false
end

function RoutePanel:update(dt)
    if self.scrollDragging then
        local currentY = love.mouse.getY()
        local dy = currentY - self.scrollDragStartY
        self.scrollOffset = math.max(0, self.scrollDragStartOffset + dy)
    end
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
    local maxScroll = math.max(0, contentHeight - viewportHeight)
    self.scrollOffset = math.max(0, math.min(maxScroll, self.scrollOffset))

    -- Apply scissor
    love.graphics.setScissor(
        math.floor(x),
        math.floor(y + 8),
        math.ceil(w),
        math.ceil(viewportHeight)
    )

    local cy = y + 8 - self.scrollOffset
    local maxCy = y + drawH - 4

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
            love.graphics.print(sp.name, math.floor(x+32), math.floor(cy))
            local lv
            if sp.minLevel == sp.maxLevel then
                lv = "Lv" .. sp.minLevel
            else
                lv = "Lv" .. sp.minLevel .. "-" .. sp.maxLevel
            end
            local f9 = fonts:getFont(9)
            love.graphics.setFont(f9)
            Colors.set(cfg.COL.dim, 1)
            love.graphics.print(lv, math.floor(x+w-8-f9:getWidth(lv)), math.floor(cy))
            Colors.set(cfg.COL.text, 1)
            love.graphics.print(sp.pct .. "%", math.floor(x+w-8-f9:getWidth(lv.."  ")-f9:getWidth(sp.pct.."%")), math.floor(cy))
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

    -- v1.0.65: draw scrollbar if content exceeds viewport
    if maxScroll > 0 then
        local scrollbarX = x + w - 10
        local scrollbarW = 4
        local scrollbarY = y + 8
        local scrollbarH = viewportHeight

        Colors.set(cfg.COL.border, 0.1)
        love.graphics.rectangle("fill", math.floor(scrollbarX), math.floor(scrollbarY), scrollbarW, math.floor(scrollbarH))

        local thumbHeight = math.max(20, scrollbarH * (viewportHeight / contentHeight))
        local thumbY = scrollbarY + (self.scrollOffset / maxScroll) * (scrollbarH - thumbHeight)

        local isDragging = self.scrollDragging
        Colors.set(isDragging and cfg.COL.gold or cfg.COL.hi, isDragging and 0.9 or 0.7)
        love.graphics.rectangle("fill", math.floor(scrollbarX), math.floor(thumbY), scrollbarW, math.floor(thumbHeight))
    end
end

return RoutePanel
