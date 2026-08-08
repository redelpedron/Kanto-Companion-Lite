--- UISystem: drives overall HUD visibility (save toggle + in-game state).
-- Two kinds of components are registered:
--   * "always" components (TopBar, PokemonPanel, Tabs) mirror shouldShow
--     directly every frame.
--   * "tabbed" components (EnemyPanel, RoutePanel, ItemsPanel) share one
--     screen region and only one may be visible at a time; which one is
--     owned by the tab-switching logic in main.lua (battle/route/tab.changed
--     handlers). This system must only ever turn tabbed components OFF
--     (to hide the whole HUD) and must never force them all ON together,
--     or every tab's content draws stacked on top of each other. When
--     shouldShow flips back on (e.g. a native menu closes), it publishes
--     "hud.restored" so main.lua can turn the *previously* active one back
--     on instead.
local System = require("core.System")

local UISystem = setmetatable({}, { __index = System })
UISystem.__index = UISystem

function UISystem.new(locator)
    local self = setmetatable(System.new(locator), UISystem)
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

    -- We only ever turn tabbed components OFF above, so once a menu that
    -- hid them (e.g. the battle Item list) closes and shouldShow flips
    -- back on, nothing here turns any of them back on -- this system has
    -- no notion of which tab was active. Signal the transition instead and
    -- let main.lua's tab-switching logic (which does know) restore it.
    if shouldShow and not self._wasShouldShow then
        self.bus:publish("hud.restored")
    end
    self._wasShouldShow = shouldShow
end

return UISystem