local Component = require("core.Component")
local Colors    = require("util.Colors")
local Helpers   = require("util.Helpers")
local ScrollableMixin = require("util.ScrollableMixin")

local ItemsPanel = setmetatable({}, { __index = Component })
ItemsPanel.__index = ItemsPanel
ItemsPanel.needs = { "ConfigService", "FontService", "GameService", "EventBus" }
Helpers.mixin(ItemsPanel, ScrollableMixin)

function ItemsPanel.new(locator, props)
    local self = setmetatable(Component.new(locator, props), ItemsPanel)
    self.inventory = {}
    self._modalBlocking = false
    self:_scrollInit()
    return self
end

function ItemsPanel:init()
    self.bus = self._locator:resolve("EventBus")
    self:_scrollListen()
    self:_listen("inventory.updated", function(_, inv) self.inventory = inv or {} end)

    self:_listen("modal.opened", function(self2) self2._modalBlocking = true end)
    self:_listen("modal.closed", function(self2) self2._modalBlocking = false end)

    self:_listen("input.pressed", function(self2, x, y, consume)
        if not self2._active or self2._modalBlocking then return end
        self2:_handleClick(x, y, consume)
    end)
    
    -- Listen for mouse release to end scrollbar drag
    self:_listen("input.released", function(self2, x, y)
        self2:_scrollEndDrag()
    end)
end

function ItemsPanel:_handleClick(x, y, consume)
    if not self._props or not self._active then return end
    local px, py, pw, ph = self._props.x, self._props.y, self._props.w, self._props.h

    -- Handle PC button (top-right)
    local btnW, btnH = 60, 20
    local btnX = px + pw - btnW - 8
    local btnY = py + 4

    if x >= btnX and x <= btnX + btnW and y >= btnY and y <= btnY + btnH then
        self.bus:publish("pc.open")
        if consume then consume() end
        return true
    end
    
    -- Scrollbar drag hit zone
    local viewportHeight = ph - 28
    if self:_scrollTryStartDrag(x, y, { x = px, y = py + 24, w = pw, h = viewportHeight }) then
        if consume then consume() end
        return true
    end

    return false
end

function ItemsPanel:_categorize(dItem)
    local balls, heals, other = {}, {}, {}
    for id, count in pairs(self.inventory) do
        if type(count) == "number" and count > 0 then
            local name = (dItem[id] and dItem[id].name) or id
            local row = { name = name, qty = count }
            if Helpers.isBallItem(id) then
                balls[#balls + 1] = row
            elseif Helpers.isHealItem(id) then
                heals[#heals + 1] = row
            else
                other[#other + 1] = row
            end
        end
    end
    local function byName(a, b) return a.name < b.name end
    table.sort(balls, byName)
    table.sort(heals, byName)
    table.sort(other, byName)
    return balls, heals, other
end

function ItemsPanel:update(dt)
    self:_scrollUpdateDrag()
end

function ItemsPanel:draw(ctx)
    local cfg   = self:_service("ConfigService")
    local fonts = self:_service("FontService")
    local game  = self:_service("GameService")
    local x, y, w, h = ctx.x, ctx.y, ctx.w, ctx.h

    -- v1.0.65: cap max height to ~9 items worth (landscape wrap mode)
    local drawH = h
    if ctx.wrapHeight then
        local itemHeight = 14
        local headerHeight = 16
        local maxItems = 9
        -- Count total items
        local totalItems = 0
        for _, count in pairs(self.inventory) do
            if type(count) == "number" and count > 0 then
                totalItems = totalItems + 1
            end
        end
        local sections = 0
        local dItem = game:getItemData()
        local balls, heals, other = self:_categorize(dItem)
        if #balls > 0 then sections = sections + 1 end
        if #heals > 0 then sections = sections + 1 end
        if #other > 0 then sections = sections + 1 end
        local neededH = 24 + (sections * headerHeight) + (math.min(totalItems, maxItems) * itemHeight) + (sections * 4) + 8
        if totalItems == 0 then
            neededH = 24 + 14 + 8
        end
        drawH = math.min(h, neededH)
    end

    Colors.set(cfg.COL.panel, 0.96)
    love.graphics.rectangle("fill", math.floor(x), math.floor(y), math.floor(w), math.floor(drawH))
    love.graphics.setLineWidth(1)
    Colors.set(cfg.COL.border, 0.3)
    love.graphics.rectangle("line", math.floor(x)+0.5, math.floor(y)+0.5, math.floor(w)-1, math.floor(drawH)-1)

    local f13 = fonts:getFont(13)
    love.graphics.setFont(f13)
    Colors.set(cfg.COL.text, 1)
    love.graphics.print("Bag", math.floor(x+8), math.floor(y+6))

    local btnW, btnH = 60, 20
    local btnX = x + w - btnW - 8
    local btnY = y + 4

    local dItem = game:getItemData()
    local balls, heals, other = self:_categorize(dItem)

    Colors.set(cfg.COL.hi, 0.6)
    love.graphics.rectangle("fill", math.floor(btnX), math.floor(btnY), btnW, btnH)
    Colors.set(cfg.COL.border, 0.3)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", math.floor(btnX)+0.5, math.floor(btnY)+0.5, btnW-1, btnH-1)

    local f10 = fonts:getFont(10)
    love.graphics.setFont(f10)
    Colors.set(cfg.COL.text, 1)
    local btnLabel = "PC"
    local btnTextW = f10:getWidth(btnLabel)
    love.graphics.print(btnLabel, math.floor(btnX + (btnW - btnTextW) / 2), math.floor(btnY + 3))

    if #balls == 0 and #heals == 0 and #other == 0 then
        local f10b = fonts:getFont(10)
        love.graphics.setFont(f10b)
        Colors.set(cfg.COL.dim, 1)
        love.graphics.print("Bag is empty", math.floor(x+8), math.floor(y+24))
        return
    end

    -- ADDED: Calculate content and scroll metrics
    local itemHeight = 14
    local headerHeight = 16
    local startY = y + 24
    local viewportHeight = drawH - 28
    
    local contentHeight = 0
    local sections = {
        { name = "BALLS", rows = balls },
        { name = "HEALING", rows = heals },
        { name = "OTHER", rows = other }
    }
    
    for _, sec in ipairs(sections) do
        if #sec.rows > 0 then
            contentHeight = contentHeight + headerHeight + (#sec.rows * itemHeight) + 4
        end
    end
    
    -- Clamp scroll to valid range
    local scrollOffset, maxScroll = self:_scrollClamp(contentHeight, viewportHeight)

    -- Apply scissor to clip overflowing content
    love.graphics.setScissor(
        math.floor(x),
        math.floor(y + 24),
        math.ceil(w),
        math.ceil(viewportHeight)
    )

    local cy = y + 24 - scrollOffset
    local maxCy = y + drawH - 4

    local function drawSec(title, rows)
        if #rows == 0 then return end
        if cy + 16 > maxCy then return end
        local f10c = fonts:getFont(10)
        love.graphics.setFont(f10c)
        Colors.set(cfg.COL.dim, 1)
        love.graphics.print(title, math.floor(x+8), math.floor(cy))
        cy = cy + 16
        for _, row in ipairs(rows) do
            if cy + 14 > maxCy then break end
            local f11 = fonts:getFont(11)
            love.graphics.setFont(f11)
            Colors.set(cfg.COL.text, 1)
            love.graphics.print(row.name, math.floor(x+8), math.floor(cy))
            local qtyStr = "x" .. tostring(row.qty)
            Colors.set(cfg.COL.dim, 1)
            love.graphics.print(qtyStr, math.floor(x+w-8-f11:getWidth(qtyStr)), math.floor(cy))
            cy = cy + 14
        end
        cy = cy + 4
    end

    drawSec("BALLS", balls)
    drawSec("HEALING", heals)
    drawSec("OTHER", other)
    
    -- Clear scissor
    love.graphics.setScissor()

    self:_scrollDrawBar(
        { x = x, y = y + 24, w = w, h = viewportHeight },
        contentHeight, viewportHeight, maxScroll, scrollOffset,
        { track = cfg.COL.border, thumb = cfg.COL.hi, thumbActive = cfg.COL.gold },
        Colors
    )
end

return ItemsPanel
