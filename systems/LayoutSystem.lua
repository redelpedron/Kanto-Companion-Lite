local System = require("core.System")

local LayoutSystem = setmetatable({}, { __index = System })
LayoutSystem.__index = LayoutSystem

function LayoutSystem.new(locator)
    local self = setmetatable(System.new(locator), LayoutSystem)
    self.cfg = locator:resolve("ConfigService")
    self.bus = locator:resolve("EventBus")
    self.currentLayout = nil
    self.layouts = {}
    return self
end

function LayoutSystem:registerLayout(name, layoutFn)
    self.layouts[name] = layoutFn
end

function LayoutSystem:update(dt)
    local W, H = love.graphics.getDimensions()
    -- Adaptive.lua owns the portrait/landscape switch (same aspect-ratio
    -- rule); route everything through it instead of duplicating that
    -- decision here, so there's one place that decides which layout wins.
    local layoutFn = self.layouts["adaptive"]
    if layoutFn then
        local rects = layoutFn(W, H, self.cfg)
        if rects then
            self.bus:publish("layout.updated", rects)
        end
    end
end

return LayoutSystem