local UISystem = {}
UISystem.__index = UISystem

function UISystem.new(locator)
    local self = setmetatable({}, UISystem)
    self._locator = locator
    self.saveService = locator:resolve("SaveService")
    self.bus = locator:resolve("EventBus")
    self._components = {}
    self._tabbed = {}
    self._wasShouldShow = false
    return self
end

function UISystem:registerComponent(name, comp, isTabbed)
    self._components[name] = comp
    self._tabbed[name] = isTabbed or false
end

function UISystem:update(dt)
    local visible = self.saveService:isVisible()
    local inGame  = self._locator:resolve("GameService"):isInGame()
    local menuOpen= self._locator:resolve("GameService"):isMenuOpen()

    local shouldShow = visible and inGame and not menuOpen
    for name, comp in pairs(self._components) do
        if self._tabbed[name] then
            if not shouldShow then comp:setActive(false) end
        else
            comp:setActive(shouldShow)
        end
    end

    if shouldShow and not self._wasShouldShow then
        self.bus:publish("hud.restored")
    end
    self._wasShouldShow = shouldShow
end

return UISystem
