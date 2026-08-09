--- AppController: orchestrates mod bootstrap, DI wiring, and lifecycle.
-- Extracted from main.lua to eliminate the God Object anti-pattern.
local AppController = {}
AppController.__index = AppController

function AppController.new(mod, registeredPreloads)
    local self = setmetatable({}, AppController)
    self.mod = mod
    self.registeredPreloads = registeredPreloads
    return self
end

function AppController:init()
    self:_createCore()
    self:_createServices()
    self:_createUtilityComponents()
    self:_createSystems()
    self:_createUIComponents()
    self:_registerSystems()
    self:_registerLayouts()
    self:_registerRenderables()
    self:_wireUISystem()
    self:_subscribeEvents()
    self:_wrapHooks()
    self:_installGameHooks()
    self:_registerUnload()
    self.mod.log:info("Kanto Companion Lite (refactored) loaded.")
end

-- =======================================================================
-- Shutdown: clean restoration of all global hooks and lifecycle teardown
-- =======================================================================
function AppController:shutdown()
    self.mod.log:info("Kanto Companion Lite shutting down...")

    -- Restore game.update hook (only if our wrapper is still in place)
    if self._wrappedGame and self._ourUpdate then
        if self._wrappedGame.update == self._ourUpdate then
            self._wrappedGame.update = self._origUpdate
        end
    end

    -- Restore love.draw hook (only if our wrapper is still in place)
    if love and love.draw and self._ourDraw and love.draw == self._ourDraw then
        love.draw = self._origDraw
    end

    -- Teardown all components and systems (calls InputSystem:destroy(), etc.)
    self.life:shutdown()

    -- Cancel any pending scheduler tasks not tied to a system
    if self.sched then
        self.sched._tasks = {}
    end
end

-- =======================================================================
-- Core infrastructure
-- =======================================================================
function AppController:_createCore()
    local ServiceLocator = require("core.ServiceLocator")
    local EventBus       = require("core.EventBus")
    local Lifecycle      = require("core.Lifecycle")
    local Scheduler      = require("core.Scheduler")

    self.locator = ServiceLocator.new()
    self.bus     = EventBus.new()
    self.life    = Lifecycle.new()
    self.sched   = Scheduler.new()

    self.locator:register("EventBus", self.bus)
    self.locator:register("Scheduler", self.sched)
    self.locator:register("Lifecycle", self.life)

    local LogService = require("services.LogService")
    local log = LogService.new(self.locator)
    log:setModLog(self.mod.log)
    self.locator:register("LogService", log)
    self.bus:setLogger(log)
    self.sched:setLogger(log)

    local ConfigService = require("services.ConfigService")
    self.locator:register("ConfigService", ConfigService.new(self.locator))

    -- FIX: register DrawContext so components never touch love.graphics directly
    local DrawContext = require("util.DrawContext")
    self.locator:register("DrawContext", DrawContext.new())
end

-- =======================================================================
-- Services
-- =======================================================================
function AppController:_createServices()
    local GameService   = require("services.GameService")
    local BattleService = require("services.BattleService")
    local SaveService   = require("services.SaveService")
    local PCService     = require("services.PCService")

    self.gameSvc   = GameService.new(self.locator)
    self.battleSvc = BattleService.new(self.locator)
    self.saveSvc   = SaveService.new(self.locator)
    self.pcSvc     = PCService.new(self.locator)

    self.saveSvc:setModSave(self.mod.save)
    self.locator:register("GameService", self.gameSvc)
    self.locator:register("BattleService", self.battleSvc)
    self.locator:register("SaveService", self.saveSvc)
    self.locator:register("PCService", self.pcSvc)

    local SpriteService = require("services.SpriteService")
    local FontService   = require("services.FontService")
    self.locator:register("SpriteService", SpriteService.new(self.locator))
    self.locator:register("FontService", FontService.new(self.locator))
end

-- =======================================================================
-- Stateless utility components (no listeners, safe to register early)
-- =======================================================================
function AppController:_createUtilityComponents()
    local TypeEffectiveness = require("components.TypeEffectiveness")
    local CatchRate         = require("components.CatchRate")
    self.locator:register("TypeEffectiveness", TypeEffectiveness.new(self.locator, {}))
    self.locator:register("CatchRate", CatchRate.new(self.locator, {}))
end

-- =======================================================================
-- Systems
-- =======================================================================
function AppController:_createSystems()
    local RenderSystem   = require("systems.RenderSystem")
    local InputSystem    = require("systems.InputSystem")
    local LayoutSystem   = require("systems.LayoutSystem")
    local BattleSystem   = require("systems.BattleSystem")
    local GameDataSystem = require("systems.GameDataSystem")
    local UISystem       = require("systems.UISystem")

    self.renderSys = RenderSystem.new(self.locator)
    self.inputSys  = InputSystem.new(self.locator)
    self.layoutSys = LayoutSystem.new(self.locator)
    self.battleSys = BattleSystem.new(self.locator)
    self.dataSys   = GameDataSystem.new(self.locator)
    self.uiSys     = UISystem.new(self.locator)
end

function AppController:_registerSystems()
    self.life:registerSystem(self.renderSys)
    self.life:registerSystem(self.inputSys)
    self.life:registerSystem(self.layoutSys)
    self.life:registerSystem(self.battleSys)
    self.life:registerSystem(self.dataSys)
    self.life:registerSystem(self.uiSys)
end

function AppController:_registerLayouts()
    self.layoutSys:registerLayout("portrait", require("layouts.Portrait"))
    self.layoutSys:registerLayout("landscape", require("layouts.Landscape"))
    self.layoutSys:registerLayout("adaptive", require("layouts.Adaptive"))
end

-- =======================================================================
-- UI Components
-- =======================================================================
function AppController:_createUIComponents()
    local TopBar       = require("components.TopBar")
    local PokemonPanel = require("components.PokemonPanel")
    local EnemyPanel   = require("components.EnemyPanel")
    local RoutePanel   = require("components.RoutePanel")
    local ItemsPanel   = require("components.ItemsPanel")
    local Tabs         = require("components.Tabs")
    local PCPopup      = require("components.PCPopup")

    self.topBar   = self.life:createComponent(TopBar, self.locator, {})
    self.topBar2  = self.life:createComponent(TopBar, self.locator, {})  -- portrait stacked
    self.partyPan = self.life:createComponent(PokemonPanel, self.locator, {})
    self.enemyPan = self.life:createComponent(EnemyPanel, self.locator, { pokemonData={}, moveData={} })
    self.routePan = self.life:createComponent(RoutePanel, self.locator, { pokemonData={} })
    self.itemsPan = self.life:createComponent(ItemsPanel, self.locator, {})
    self.tabs     = self.life:createComponent(Tabs, self.locator, { x=0, y=0, w=100, tabs={}, activeIdx=1 })

    -- PCPopup is a full-screen modal, not driven by UISystem
    self.pcPopup  = self.life:createComponent(PCPopup, self.locator, {})
    self.pcPopup:setActive(false)
end

function AppController:_registerRenderables()
    self.renderSys:registerComponent(self.topBar)
    self.renderSys:registerComponent(self.topBar2)
    self.renderSys:registerComponent(self.partyPan)
    self.renderSys:registerComponent(self.enemyPan)
    self.renderSys:registerComponent(self.routePan)
    self.renderSys:registerComponent(self.itemsPan)
    self.renderSys:registerComponent(self.tabs)
    -- Drawn last so it appears on top
    self.renderSys:registerComponent(self.pcPopup)
end

function AppController:_wireUISystem()
    self.uiSys:registerComponent("topBar", self.topBar)
    self.uiSys:registerComponent("topBar2", self.topBar2, true)  -- tabbed
    self.uiSys:registerComponent("party", self.partyPan)
    self.uiSys:registerComponent("enemy", self.enemyPan, true)
    self.uiSys:registerComponent("route", self.routePan, true)
    self.uiSys:registerComponent("items", self.itemsPan, true)
    self.uiSys:registerComponent("tabs", self.tabs)
end

-- =======================================================================
-- Event subscriptions
-- =======================================================================
function AppController:_subscribeEvents()
    local locator = self.locator
    local bus     = self.bus

    -- Layout routing -----------------------------------------------------
    bus:subscribe("layout.updated", function(rects)
        if rects.topBar1 and rects.topBar2 then
            self.topBar:setLayout(rects.topBar1)
            self.topBar2:setLayout(rects.topBar2)
            self.topBar:setActive(true)
            self.topBar2:setActive(true)
        else
            self.topBar:setLayout(rects.topBar)
            self.topBar2:setActive(false)
        end

        self.partyPan:setLayout(rects.party)

        local inBattle = locator:resolve("BattleService"):isInBattle()
        if inBattle and rects.isPortrait then
            self.enemyPan:setLayout({
                x = rects.rightContent.x, y = rects.rightContent.y,
                w = rects.rightContent.w, h = rects.rightContent.h,
                twoColumn = true,
            })
        else
            -- FIX: add wrapHeight so landscape EnemyPanel shrinks to content
            self.enemyPan:setLayout({
                x = rects.rightContent.x, y = rects.rightContent.y,
                w = rects.rightContent.w, h = rects.rightContent.h,
                twoColumn = false,
                wrapHeight = true,
            })
        end
        self.routePan:setLayout(rects.rightContent)
        self.itemsPan:setLayout(rects.rightContent)
        self.tabs:setLayout(rects.rightTabs)
    end)

    -- Tab restoration ----------------------------------------------------
    self.currentTabDrawers = {}

    bus:subscribe("hud.restored", function()
        for i, comp in ipairs(self.currentTabDrawers) do
            comp:setActive(i == self.tabs.activeIdx)
        end
    end)

    bus:subscribe("tab.changed", function(idx)
        for i, comp in ipairs(self.currentTabDrawers) do
            comp:setActive(i == idx)
        end
    end)

    -- Battle lifecycle ---------------------------------------------------
    bus:subscribe("battle.started", function()
        local drawers = { self.enemyPan }
        local labels  = { "Enemy" }
        table.insert(drawers, self.itemsPan)
        table.insert(labels, "Items")
        self.currentTabDrawers = drawers
        self.tabs:setTabs(labels)
        self.tabs.activeIdx = 1
        -- FIX: explicitly hide the encounter list so it doesn't paint over the battle
        self.routePan:setActive(false)
        for i, comp in ipairs(drawers) do
            comp:setActive(i == 1)
        end
    end)

    bus:subscribe("battle.ended", function()
        local drawers = {}
        local labels  = {}
        table.insert(drawers, self.itemsPan)
        table.insert(labels, "Items")
        self.currentTabDrawers = drawers
        self.tabs:setTabs(labels)
        self.tabs.activeIdx = 1
        self.enemyPan:setActive(false)
        self.routePan:setActive(false)
        self.itemsPan:setActive(true)
        local W, H = love.graphics.getDimensions()
        self.topBar:setLayout({ x=0, y=0, w=W, h=locator:resolve("ConfigService").TOP_BAR_H })
    end)

    -- Route updates ------------------------------------------------------
    bus:subscribe("route.updated", function(route)
        local inBattle = locator:resolve("BattleService"):isInBattle()
        if inBattle then return end
        local hasEnc = route and ((route.grass and #route.grass.species>0) or (route.water and #route.water.species>0))
        local drawers = {}
        local labels  = {}
        if hasEnc then
            table.insert(drawers, self.routePan)
            table.insert(labels, "Encounter")
        end
        table.insert(drawers, self.itemsPan)
        table.insert(labels, "Items")
        self.currentTabDrawers = drawers
        self.tabs:setTabs(labels)
        if self.tabs.activeIdx > #labels then self.tabs.activeIdx = 1 end
        for i, comp in ipairs(drawers) do
            comp:setActive(i == self.tabs.activeIdx)
        end
    end)

    -- Data refresh -------------------------------------------------------
    bus:subscribe("party.updated", function(party)
        local dPoke = locator:resolve("GameService"):getPokemonData()
        local dMove = locator:resolve("GameService"):getMoveData()
        self.partyPan._props.pokemonData = dPoke
        self.enemyPan._props.pokemonData = dPoke
        self.enemyPan._props.moveData    = dMove
        self.routePan._props.pokemonData = dPoke
    end)

    -- Engine game.ready --------------------------------------------------
    self.mod.events:on("game.ready", function(p)
        self.gameSvc:setGame((p and p.game) or self.gameSvc:getGame())
        self.battleSvc:setBattleStateClass(self.gameSvc:getBattleStateClass())
    end)
end

-- =======================================================================
-- Hook wrapping
-- =======================================================================
function AppController:_wrapHooks()
    local saveSvc = self.saveSvc

    self.mod.hooks:wrap("ui.options.rows", function(next, game, rows)
        local out = next(game, rows)
        if type(out) ~= "table" then return out end
        out[#out+1] = {
            id = "kanto_companion_lite",
            label = "KANTO COMPANION LITE",
            value = function(g)
                return saveSvc:isVisible() and "ON" or "OFF"
            end,
            step = function(g, dir)
                saveSvc:toggleVisible()
                return true
            end,
        }
        return out
    end)

    local ok, err = pcall(function()
        self.mod.hooks:wrap("ui.start_menu.items", function(original, game)
            local items = original(game)
            table.insert(items, {
                label = saveSvc:isVisible() and "Hide Companion" or "Show Companion",
                action = function() saveSvc:toggleVisible() end
            })
            return items
        end)
    end)
    if not ok then
        self.locator:resolve("LogService"):warning("ui.start_menu.items hook failed: %s", tostring(err))
    end
end

-- =======================================================================
-- Runtime hook installation
-- =======================================================================
function AppController:_installGameHooks()
    self._origUpdate = nil
    self._ourUpdate  = nil
    self._origDraw   = nil
    self._ourDraw    = nil
    self._wrappedGame = nil

    local function install()
        local g = self.gameSvc:getGame()
        if g and g.update then
            if self._wrappedGame ~= g then
                self._origUpdate = g.update
                self._ourUpdate = function(gameSelf, dt)
                    self._origUpdate(gameSelf, dt)
                    self.sched:update(dt)
                    self.life:update(dt)
                end
                g.update = self._ourUpdate
                self._wrappedGame = g
            end
        end
        if love and love.draw and not self._ourDraw then
            self._origDraw = love.draw
            self._ourDraw = function(...)
                if self._origDraw then self._origDraw(...) end
                self.life:draw()
            end
            love.draw = self._ourDraw
        end
    end

    self.mod.events:on("game.ready", install)
    if self.gameSvc:getGame() and self.gameSvc:getGame().save and love then
        install()
    end
end

-- =======================================================================
-- Mod unload registration
-- =======================================================================
function AppController:_registerUnload()
    -- Store reference for external/manual cleanup
    self.mod._kantoCompanionApp = self
    -- Attempt to register an engine unload event if one exists
    local ok = pcall(function()
        self.mod.events:on("mod.unload", function()
            self:shutdown()
        end)
    end)
    if not ok then
        self.locator:resolve("LogService"):info("mod.unload event not available; manual cleanup required")
    end
end

return AppController
