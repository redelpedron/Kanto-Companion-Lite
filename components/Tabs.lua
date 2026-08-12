
--- Tabs: clickable tab bar. Publishes "tab.changed" on selection.
local Component = require("core.Component")
local Colors = require("util.Colors")

local Tabs = setmetatable({}, { __index = Component })
Tabs.__index = Tabs
Tabs.__name = "Tabs"
Tabs.needs = { "ConfigService", "FontService", "EventBus" }

function Tabs.new(locator, props)
    local self = setmetatable(Component.new(locator, props), Tabs)
    self.tabs = props.tabs or {}
    self.activeIdx = props.activeIdx or 1
    self.hitBoxes = {}
    self._modalBlocking = false
    -- Two independent tab strips (party column, right column) share one
    -- EventBus. `changeEvent` lets a second instance publish under its own
    -- event name instead of colliding with "tab.changed"; omit it and this
    -- behaves exactly as before.
    self._changeEvent = props.changeEvent or "tab.changed"
    return self
end

function Tabs:init()
    -- See ItemsPanel.lua: while the PC popup is open it owns all input,
    -- so tab taps underneath it must be ignored.
    self:_listen("modal.opened", function(self2) self2._modalBlocking = true end)
    self:_listen("modal.closed", function(self2) self2._modalBlocking = false end)
    self:_listen("input.pressed", function(self2, x, y, consume)
        if self2._modalBlocking then return end
        for _, box in ipairs(self2.hitBoxes) do
            if x >= box.x and x <= box.x + box.w and y >= box.y and y <= box.y + box.h then
                self2.activeIdx = box.idx
                local bus = self2:_service("EventBus")
                bus:publish(self2._changeEvent, box.idx, self2.tabs[box.idx])
                if consume then consume() end
                return
            end
        end
    end)
end

function Tabs:setTabs(tabs)
    self.tabs = tabs
    if self.activeIdx > #tabs then self.activeIdx = 1 end
end

function Tabs:draw(ctx)
    local cfg = self:_service("ConfigService")
    local fonts = self:_service("FontService")
    local x, y, w = self._props.x, self._props.y, self._props.w
    local h = self._props.h or cfg.TAB_H
    local gap = 0

    self.hitBoxes = {}
    if #self.tabs == 0 then return 0 end

    local tw = math.floor((w - gap * (#self.tabs - 1)) / #self.tabs)
    local tx = x

    for i, label in ipairs(self.tabs) do
        local isActive = i == self.activeIdx
        self.hitBoxes[#self.hitBoxes + 1] = {
            x = tx, y = y, w = tw, h = h, idx = i,
        }

        if isActive then
            Colors.set(cfg.COL.tabActive, 0.9)
        else
            Colors.set(cfg.COL.tabBg, 0.85)
        end
        love.graphics.rectangle("fill", math.floor(tx), math.floor(y), math.floor(tw), math.floor(h))

        local f = fonts:getFont(12)
        love.graphics.setFont(f)
        Colors.set(isActive and cfg.COL.panel or cfg.COL.dim, 1)
        local fw = f:getWidth(label)
        love.graphics.print(label, math.floor(tx + tw/2 - fw/2), math.floor(y + 7))

        tx = tx + tw + gap
    end
    return h
end

return Tabs
