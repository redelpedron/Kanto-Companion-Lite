local LayoutSystem = {}
LayoutSystem.__index = LayoutSystem

function LayoutSystem.new(locator)
    local self = setmetatable({}, LayoutSystem)
    self._locator = locator
    self.cfg = locator:resolve("ConfigService")
    self.bus = locator:resolve("EventBus")
    self.saveSvc = locator:resolve("SaveService")
    self.layoutFn = nil
    return self
end

function LayoutSystem:setLayout(layoutFn)
    self.layoutFn = layoutFn
end

function LayoutSystem:update(dt)
    if not self.layoutFn then return end
    local W, H = love.graphics.getDimensions()

    self.cfg.topBarBottom = self.saveSvc:isTopBarBottom()
    local rects = self.layoutFn(W, H, self.cfg)
    if rects then
        self.bus:publish("layout.updated", rects)
    end
end

return LayoutSystem
