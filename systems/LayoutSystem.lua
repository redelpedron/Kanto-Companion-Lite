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

--- Set the top-level layout function. Adaptive.lua owns the
-- portrait/landscape switch internally (it requires Portrait/Landscape
-- directly), so there's exactly one layout function to drive here --
-- a name-keyed registry would only ever have one live key.
function LayoutSystem:setLayout(layoutFn)
    self.layoutFn = layoutFn
end

function LayoutSystem:update(dt)
    if not self.layoutFn then return end
    local W, H = love.graphics.getDimensions()
    -- Forward the persisted "Bottom Topbar" setting onto cfg each frame
    -- so Landscape.lua can read cfg.topBarBottom the same way it already
    -- reads every other layout constant. Portrait.lua never looks at
    -- this field, so it stays unaffected regardless of the setting's
    -- value.
    self.cfg.topBarBottom = self.saveSvc:isTopBarBottom()
    local rects = self.layoutFn(W, H, self.cfg)
    if rects then
        self.bus:publish("layout.updated", rects)
    end
end

return LayoutSystem