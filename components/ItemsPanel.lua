local Component = require("core.Component")
local Colors    = require("util.Colors")
local Helpers   = require("util.Helpers")

local ItemsPanel = setmetatable({}, { __index = Component })
ItemsPanel.__index = ItemsPanel
ItemsPanel.needs = { "ConfigService", "FontService", "GameService", "EventBus" }

function ItemsPanel.new(locator, props)
    local self = setmetatable(Component.new(locator, props), ItemsPanel)
    self.inventory = {}
    self._modalBlocking = false
    -- ADDED: Scroll state
    self.scrollOffset = 0
    self.scrollDragging = false
    self.scrollDragStartY = 0
    self.scrollDragStartOffset = 0
    return self
end

function ItemsPanel:init()
    self.bus = self._locator:resolve("EventBus")
    self:_listen("inventory.updated", function(_, inv) self.inventory = inv or {} end)

    self:_listen("modal.opened", function(self2) self2._modalBlocking = true end)
    self:_listen("modal.closed", function(self2) self2._modalBlocking = false end)

    self:_listen("input.pressed", function(self2, x, y, consume)
        if not self2._active or self2._modalBlocking then return end
        self2:_handleClick(x, y, consume)
    end)
    
    -- ADDED: Listen for mouse release to end scrollbar drag
    self:_listen("input.released", function(self2, x, y)
        if self2.scrollDragging then
            self2.scrollDragging = false
        end
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
    
    -- ADDED: Handle scrollbar drag (hit zone: ±8px around scrollbar)
    local scrollbarX = px + pw - 10  -- Center of scrollbar within right margin
    local scrollbarY = py + 24
    local scrollbarW = 4
    local viewportHeight = ph - 28
    
    if x >= scrollbarX - 6 and x <= scrollbarX + scrollbarW + 6 and
       y >= scrollbarY and y <= scrollbarY + viewportHeight then
        self.scrollDragging = true
        self.scrollDragStartY = y
        self.scrollDragStartOffset = self.scrollOffset
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

-- ADDED: Handle continuous scroll drag
function ItemsPanel:update(dt)
    if self.scrollDragging then
        local currentY = love.mouse.getY()
        local dy = currentY - self.scrollDragStartY
        self.scrollOffset = math.max(0, self.scrollDragStartOffset + dy)
    end
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
    local maxScroll = math.max(0, contentHeight - viewportHeight)
    self.scrollOffset = math.max(0, math.min(maxScroll, self.scrollOffset))

    -- Apply scissor to clip overflowing content
    love.graphics.setScissor(
        math.floor(x),
        math.floor(y + 24),
        math.ceil(w),
        math.ceil(viewportHeight)
    )

    -- MODIFIED: cy now includes scroll offset
    local cy = y + 24 - self.scrollOffset
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

    -- ADDED: Draw scrollbar if content exceeds viewport
    if maxScroll > 0 then
        local scrollbarX = x + w - 10  -- Centered in the hit zone
        local scrollbarW = 4
        local scrollbarY = y + 24
        local scrollbarH = viewportHeight
        
        -- Scrollbar track (background)
        Colors.set(cfg.COL.border, 0.1)
        love.graphics.rectangle("fill", math.floor(scrollbarX), math.floor(scrollbarY), 
                                scrollbarW, math.floor(scrollbarH))
        
        -- Thumb height proportional to content vs viewport
        local thumbHeight = math.max(20, scrollbarH * (viewportHeight / contentHeight))
        
        -- Thumb position based on scroll offset
        local thumbY = scrollbarY + (self.scrollOffset / maxScroll) * (scrollbarH - thumbHeight)
        
        -- Thumb appearance (highlight if dragging)
        local isDragging = self.scrollDragging
        Colors.set(isDragging and cfg.COL.gold or cfg.COL.hi, isDragging and 0.9 or 0.7)
        love.graphics.rectangle("fill", math.floor(scrollbarX), math.floor(thumbY), 
                                scrollbarW, math.floor(thumbHeight))
    end
end

return ItemsPanel
